#!/usr/bin/env python3
"""
benchmark_runner.py - Mnemo retrieval quality benchmark.

Computes hit@k, nDCG@k, MRR, p50/p95 latency, and token-aware cost.
Supports:
  - Multi-file fixtures
  - Category-level metrics
  - Weight overrides for score fusion
  - Ablation mode over fusion signals
"""
from __future__ import annotations

import argparse
import json
import math
import re
import statistics
import sys
import time
from pathlib import Path
from typing import Any, Optional

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_DIR = Path(__file__).parent / "fixtures"
REF_MENTION_RE = re.compile(r"[A-Za-z0-9_./\\-]+\.(?:md|mdc|ps1|py|json|sh)")

DEFAULT_WEIGHTS = {
    "semantic": 0.55,
    "authority": 0.25,
    "temporal": 0.10,
    "entity": 0.10,
}

FALLBACK_AUTHORITY_WEIGHTS = {
    "core": 1.0,
    "procedural": 0.9,
    "semantic": 0.8,
    "episodic": 0.7,
    "resource": 0.5,
    "vault": 0.0,
}

TIME_WORDS = frozenset(
    {
        "today",
        "yesterday",
        "last week",
        "last month",
        "recent",
        "latest",
        "currently",
        "now",
    }
)


def _candidate_runtime_paths() -> list[Path]:
    roots = [Path.cwd(), REPO_ROOT]
    out: list[Path] = []
    seen: set[str] = set()
    for root in roots:
        for candidate in (
            root / "scripts" / "memory",
            root / "scripts" / "memory" / "installer" / "templates",
            root / ".mnemo" / "memory" / "scripts",
            root / ".cursor" / "memory" / "scripts",
        ):
            key = str(candidate.resolve()) if candidate.exists() else str(candidate)
            if key in seen:
                continue
            seen.add(key)
            if candidate.exists():
                out.append(candidate)
    return out


def _ensure_runtime_paths() -> None:
    for p in _candidate_runtime_paths():
        p_str = str(p)
        if p_str not in sys.path:
            sys.path.insert(0, p_str)


def _tokenize(text: str) -> set[str]:
    return set(re.findall(r"[a-z0-9_./-]+", text.lower()))


def _normalize_ref(ref: str) -> str:
    if not ref:
        return ""
    s = ref.strip().replace("\\", "/").lstrip("@")
    s = s.split("#", 1)[0].strip().strip("`'\"")
    for marker in (
        ".mnemo/memory/",
        ".cursor/memory/",
        ".mnemo/rules/cursor/",
        ".cursor/rules/",
        "scripts/memory/installer/templates/",
        "scripts/memory/",
    ):
        idx = s.lower().find(marker)
        if idx >= 0:
            s = s[idx + len(marker) :]
            break
    while s.startswith("./"):
        s = s[2:]
    parts = [p for p in s.split("/") if p]
    if len(parts) >= 2 and parts[-2] == "lessons":
        return f"lessons/{parts[-1]}"
    if len(parts) > 1:
        return parts[-1]
    return s


def _load_fixtures(fixture_dir: Path) -> list[dict]:
    fixtures: list[dict] = []
    for p in sorted(fixture_dir.glob("*.json")):
        try:
            data = json.loads(p.read_text(encoding="utf-8"))
            if isinstance(data, list):
                for item in data:
                    if isinstance(item, dict) and "query" in item and "relevant_refs" in item:
                        fixtures.append(item)
            elif isinstance(data, dict):
                if "query" in data and "relevant_refs" in data:
                    fixtures.append(data)
        except Exception as e:
            print(f"[WARN] Could not load fixture {p}: {e}", file=sys.stderr)
    return fixtures


def _hit_at_k(ranked_refs: list[str], relevant_refs: set[str], k: int) -> float:
    return 1.0 if any(r in relevant_refs for r in ranked_refs[:k]) else 0.0


def _ndcg_at_k(ranked_refs: list[str], relevant_refs: set[str], k: int) -> float:
    dcg = 0.0
    for i, ref in enumerate(ranked_refs[:k]):
        if ref in relevant_refs:
            dcg += 1.0 / math.log2(i + 2)
    ideal_dcg = sum(1.0 / math.log2(i + 2) for i in range(min(len(relevant_refs), k)))
    return dcg / ideal_dcg if ideal_dcg > 0 else 0.0


def _mrr(ranked_refs: list[str], relevant_refs: set[str]) -> float:
    for i, ref in enumerate(ranked_refs):
        if ref in relevant_refs:
            return 1.0 / (i + 1)
    return 0.0


def _normalize_weights(raw: Optional[dict[str, float]]) -> dict[str, float]:
    merged = dict(DEFAULT_WEIGHTS)
    if raw:
        for key in ("semantic", "authority", "temporal", "entity"):
            if key in raw:
                merged[key] = float(raw[key])
    total = sum(max(0.0, v) for v in merged.values())
    if total <= 0:
        raise ValueError("weights must sum to positive value")
    return {k: max(0.0, v) / total for k, v in merged.items()}


def _parse_weights_arg(raw: str) -> dict[str, float]:
    parts = [p.strip() for p in raw.split(",") if p.strip()]
    if len(parts) != 4:
        raise ValueError("--weights must be four comma-separated values: semantic,authority,temporal,entity")
    sem, auth, temp, ent = (float(x) for x in parts)
    return {"semantic": sem, "authority": auth, "temporal": temp, "entity": ent}


def _ablation_weight_sets(base: dict[str, float]) -> dict[str, dict[str, float]]:
    no_auth = _normalize_weights({**base, "authority": 0.0})
    no_temp = _normalize_weights({**base, "temporal": 0.0})
    no_entity = _normalize_weights({**base, "entity": 0.0})
    sem_auth = _normalize_weights({"semantic": base["semantic"], "authority": base["authority"], "temporal": 0.0, "entity": 0.0})
    return {
        "full": _normalize_weights(base),
        "semantic_only": {"semantic": 1.0, "authority": 0.0, "temporal": 0.0, "entity": 0.0},
        "no_authority": no_auth,
        "no_temporal": no_temp,
        "no_entity": no_entity,
        "semantic_authority": sem_auth,
    }


def _safe_read_preview(path_str: str, max_chars: int = 3000) -> str:
    if not path_str:
        return ""
    normalized = path_str.lstrip("@").split("#", 1)[0].strip()
    p = Path(normalized)
    candidates = [p]
    if not p.is_absolute():
        candidates.extend([Path.cwd() / p, REPO_ROOT / p])
    for candidate in candidates:
        if candidate.exists() and candidate.is_file():
            try:
                return candidate.read_text(encoding="utf-8", errors="ignore")[:max_chars]
            except Exception:
                continue
    return ""


def _infer_memory_type(path_str: str) -> str:
    _ensure_runtime_paths()
    try:
        from autonomy.common import infer_memory_type as runtime_infer_memory_type  # type: ignore

        return runtime_infer_memory_type(path_str)
    except Exception:
        p = path_str.lower().replace("\\", "/")
        if "hot-rules" in p or "memo.md" in p:
            return "core"
        if "/lessons/" in p or "lesson" in p:
            return "procedural"
        if "/journal/" in p or "active-context" in p:
            return "episodic"
        if "/vault/" in p:
            return "vault"
        return "semantic"


def _authority_weight(mem_type: str) -> float:
    _ensure_runtime_paths()
    try:
        from autonomy.common import AUTHORITY_WEIGHTS as runtime_weights  # type: ignore

        return float(runtime_weights.get(mem_type, 0.5))
    except Exception:
        return float(FALLBACK_AUTHORITY_WEIGHTS.get(mem_type, 0.5))


def _temporal_score(query: str, mem_type: str) -> float:
    q = query.lower()
    has_time_query = any(w in q for w in TIME_WORDS)
    if mem_type == "episodic":
        return 1.0 if has_time_query else 0.65
    if mem_type in {"core", "procedural"}:
        return 0.8
    return 0.6


def _entity_score(query_tokens: set[str], ref_path: str, content: str) -> float:
    ref_tokens = _tokenize(ref_path)
    if query_tokens & ref_tokens:
        return 1.0
    # Fallback: lightweight scan of leading snippet to avoid large scans.
    snippet_tokens = _tokenize(content[:300])
    return 0.6 if query_tokens & snippet_tokens else 0.0


class _FallbackTokenCounter:
    mode = "chars/4"

    def count(self, text: str) -> int:
        return max(1, math.ceil(len(text or "") / 4))


def _make_token_counter():
    _ensure_runtime_paths()
    try:
        from autonomy.token_counter import TokenCounter  # type: ignore

        return TokenCounter(provider="auto", model="gpt-4o-mini")
    except Exception:
        return _FallbackTokenCounter()


class BenchmarkRunner:
    def __init__(self, fixture_dir: Path = FIXTURE_DIR, top_k: int = 5, weights: Optional[dict[str, float]] = None):
        self.fixture_dir = fixture_dir
        self.top_k = top_k
        self.fixtures = _load_fixtures(fixture_dir)
        self.keyword_corpus = self._build_keyword_corpus()
        self.weights = _normalize_weights(weights)
        self.token_counter = _make_token_counter()

    def _estimate_token_cost(self, query: str, results: list[Any]) -> float:
        total_tokens = self.token_counter.count(query)
        for r in results:
            if hasattr(r, "content"):
                total_tokens += self.token_counter.count(getattr(r, "content", ""))
            elif isinstance(r, dict):
                total_tokens += self.token_counter.count(str(r.get("content", "")))
        return total_tokens * 0.00002  # rough estimate at ~$0.02 per 1k tokens

    def run(self, use_vector: bool = False) -> dict:
        if not self.fixtures:
            return {"error": "No fixtures found", "fixture_dir": str(self.fixture_dir)}

        hits3: list[float] = []
        ndcg5: list[float] = []
        mrr_scores: list[float] = []
        latencies_ms: list[float] = []
        costs: list[float] = []
        errors: list[str] = []
        category_rows: dict[str, dict[str, list[float] | int]] = {}

        for fx in self.fixtures:
            query = str(fx.get("query", "")).strip()
            relevant = {_normalize_ref(r) for r in fx.get("relevant_refs", []) if r}
            category = str(fx.get("category", "uncategorized")).strip() or "uncategorized"
            if not query or not relevant:
                continue

            t0 = time.perf_counter()
            try:
                results = self._search(query, use_vector=use_vector, top_k=self.top_k)
            except Exception as e:
                errors.append(f"{query[:40]}: {e}")
                continue
            elapsed_ms = (time.perf_counter() - t0) * 1000

            ranked_refs = [
                _normalize_ref(r.get("ref_path", "") if isinstance(r, dict) else getattr(r, "ref_path", ""))
                for r in results
            ]

            hit3 = _hit_at_k(ranked_refs, relevant, 3)
            ndcg = _ndcg_at_k(ranked_refs, relevant, self.top_k)
            mrr = _mrr(ranked_refs, relevant)
            cost = self._estimate_token_cost(query, results)

            hits3.append(hit3)
            ndcg5.append(ndcg)
            mrr_scores.append(mrr)
            latencies_ms.append(elapsed_ms)
            costs.append(cost)

            row = category_rows.setdefault(
                category,
                {"evaluated": 0, "hit_at_3": [], "ndcg_at_5": [], "mrr": []},
            )
            row["evaluated"] = int(row["evaluated"]) + 1
            row["hit_at_3"].append(hit3)  # type: ignore[index]
            row["ndcg_at_5"].append(ndcg)  # type: ignore[index]
            row["mrr"].append(mrr)  # type: ignore[index]

        if not hits3:
            return {"error": "No evaluable fixtures (check relevant_refs fields)", "errors": errors}

        latencies_sorted = sorted(latencies_ms)
        p50 = statistics.median(latencies_sorted) if latencies_sorted else 0.0
        p95 = latencies_sorted[int(len(latencies_sorted) * 0.95)] if latencies_sorted else 0.0

        category_metrics: dict[str, dict[str, float | int]] = {}
        for cat, row in sorted(category_rows.items()):
            cat_hit = row["hit_at_3"]  # type: ignore[assignment]
            cat_ndcg = row["ndcg_at_5"]  # type: ignore[assignment]
            cat_mrr = row["mrr"]  # type: ignore[assignment]
            category_metrics[cat] = {
                "evaluated": int(row["evaluated"]),
                "hit_at_3": round(statistics.mean(cat_hit), 4) if cat_hit else 0.0,
                "ndcg_at_5": round(statistics.mean(cat_ndcg), 4) if cat_ndcg else 0.0,
                "mrr": round(statistics.mean(cat_mrr), 4) if cat_mrr else 0.0,
            }

        return {
            "fixture_count": len(self.fixtures),
            "evaluated": len(hits3),
            "hit_at_3": round(statistics.mean(hits3), 4),
            "ndcg_at_5": round(statistics.mean(ndcg5), 4),
            "mrr": round(statistics.mean(mrr_scores), 4),
            "latency_p50_ms": round(p50, 2),
            "latency_p95_ms": round(p95, 2),
            "cost_per_query_usd": round(statistics.mean(costs), 6),
            "errors": errors,
            "mode": "vector" if use_vector else "fts",
            "weights": {k: round(v, 4) for k, v in self.weights.items()},
            "tokenizer_mode": getattr(self.token_counter, "mode", "chars/4"),
            "category_metrics": category_metrics,
        }

    def _seed_doc(self, docs: dict[str, list[str]], ref: str, content: str) -> None:
        norm = _normalize_ref(ref)
        if not norm:
            return
        docs.setdefault(norm, []).append(content)

    def _build_keyword_corpus(self) -> list[dict]:
        docs: dict[str, list[str]] = {}
        roots: list[Path] = [
            Path.cwd() / ".mnemo" / "memory",
            Path.cwd() / ".mnemo" / "rules" / "cursor",
            Path.cwd() / ".cursor" / "memory",
            Path.cwd() / ".cursor" / "rules",
            Path.cwd() / "scripts" / "memory",
            REPO_ROOT / "bin",
            REPO_ROOT / "scripts" / "memory" / "installer",
            REPO_ROOT / "tests",
            REPO_ROOT / ".github" / "workflows",
            REPO_ROOT / "README.md",
            REPO_ROOT / "tests" / "README.md",
            REPO_ROOT / "package.json",
        ]

        file_candidates: list[Path] = []
        for root in roots:
            if root.is_file():
                file_candidates.append(root)
            elif root.exists():
                for p in root.rglob("*"):
                    if p.is_file() and p.suffix.lower() in {".md", ".mdc", ".ps1", ".py", ".sh", ".yml", ".yaml"}:
                        file_candidates.append(p)

        for p in file_candidates:
            try:
                text = p.read_text(encoding="utf-8", errors="ignore")
            except Exception:
                continue

            self._seed_doc(docs, str(p), text[:12000])
            lines = text.splitlines()
            for i, line in enumerate(lines):
                for ref_mention in REF_MENTION_RE.findall(line):
                    start = max(0, i - 1)
                    end = min(len(lines), i + 2)
                    self._seed_doc(docs, ref_mention, "\n".join(lines[start:end]))

        for ref in (
            "add-lesson.ps1",
            "lessons/index.md",
            "lesson.template.md",
            "hot-rules.md",
            "memo.md",
            "index.md",
            "00-memory-system.mdc",
            "01-vector-search.mdc",
            "mnemo_vector.py",
        ):
            docs.setdefault(ref, [ref])

        corpus: list[dict] = []
        for ref, chunks in docs.items():
            content = "\n".join(chunks)[:16000]
            corpus.append(
                {
                    "ref_path": ref,
                    "content": content,
                    "_tokens": _tokenize(f"{ref}\n{content}"),
                }
            )
        return corpus

    def _keyword_search(self, query: str, top_k: int) -> list[dict]:
        q_tokens = _tokenize(query)
        scored: list[tuple[float, dict]] = []

        for doc in self.keyword_corpus:
            ref = str(doc["ref_path"])
            content = str(doc["content"])
            overlap = len(q_tokens & doc["_tokens"])
            semantic = overlap / max(1, len(q_tokens))
            if semantic <= 0:
                continue

            mem_type = _infer_memory_type(ref)
            authority = _authority_weight(mem_type)
            temporal = _temporal_score(query, mem_type)
            entity = _entity_score(q_tokens, ref, content)

            final = (
                self.weights["semantic"] * semantic
                + self.weights["authority"] * authority
                + self.weights["temporal"] * temporal
                + self.weights["entity"] * entity
            )
            scored.append(
                (
                    final,
                    {
                        "ref_path": ref,
                        "content": content[:120],
                        "semantic": round(semantic, 4),
                        "authority": round(authority, 4),
                        "temporal": round(temporal, 4),
                        "entity": round(entity, 4),
                        "final_score": round(final, 4),
                    },
                )
            )

        scored.sort(key=lambda item: (item[0], len(item[1]["content"])), reverse=True)
        return [doc for _, doc in scored[:top_k]]

    def _search(self, query: str, use_vector: bool = False, top_k: int = 10) -> list[dict]:
        _ensure_runtime_paths()

        if use_vector:
            try:
                from autonomy.retrieval_router import RetrievalRouter  # type: ignore
                from autonomy.reranker import ScoreFusionReranker  # type: ignore
                from autonomy.schema import get_db  # type: ignore

                db = get_db()
                router = RetrievalRouter(db=db)
                decision, candidates = router.route_query(query, top_k=top_k * 2)
                raw_results: list[dict] = []
                q_tokens = _tokenize(query)
                for c in candidates:
                    ref = str(c.get("source_ref", "") or c.get("ref_path", ""))
                    content = _safe_read_preview(ref)
                    sem = len(q_tokens & _tokenize(f"{ref}\n{content[:500]}")) / max(1, len(q_tokens))
                    raw_results.append(
                        {
                            "ref_path": ref,
                            "content": content[:1200],
                            "source_file": ref,
                            "distance": max(0.0, 1.0 - sem),
                            "memory_type": c.get("memory_type"),
                            "time_scope": c.get("time_scope"),
                            "entity_tags": c.get("entity_tags"),
                        }
                    )
                reranker = ScoreFusionReranker(db=db, weights=self.weights)
                ranked = reranker.rerank(query=query, raw_results=raw_results, top_k=top_k, route_intent=decision.intent)
                db.close()
                if ranked:
                    return [
                        {
                            "ref_path": r.ref_path,
                            "content": r.content,
                            "final_score": r.final_score,
                            "semantic": r.semantic_score,
                            "authority": r.authority_score,
                            "temporal": r.temporal_score,
                            "entity": r.entity_score,
                        }
                        for r in ranked
                    ]
            except Exception:
                pass

        try:
            from autonomy.schema import get_db  # type: ignore

            db = get_db()
            try:
                rows = db.execute(
                    "SELECT path as ref_path, content FROM memory_fts WHERE memory_fts MATCH ? LIMIT ?",
                    (query, top_k),
                ).fetchall()
            except Exception:
                rows = db.execute(
                    "SELECT source_ref as ref_path, '' as content FROM memory_units LIMIT ?",
                    (top_k,),
                ).fetchall()
            db.close()
            parsed = [dict(r) for r in rows]
            if parsed:
                for item in parsed:
                    item["content"] = str(item.get("content", ""))[:120]
                return parsed
        except Exception:
            pass

        return self._keyword_search(query, top_k)

    def check_against_thresholds(self, metrics: dict, policy_path: Path | None = None) -> tuple[bool, list[str]]:
        thresholds = {
            "hit_at_3": 0.75,
            "ndcg_at_5": 0.68,
            "latency_p95_ms": 2000.0,
            "cost_per_query_usd": 0.005,
        }
        if policy_path and policy_path.exists():
            try:
                import yaml  # type: ignore

                policy = yaml.safe_load(policy_path.read_text(encoding="utf-8")) or {}
                bench = policy.get("benchmark", {})
                thresholds.update(
                    {
                        "hit_at_3": bench.get("min_hit_at_3", thresholds["hit_at_3"]),
                        "ndcg_at_5": bench.get("min_ndcg_at_5", thresholds["ndcg_at_5"]),
                        "latency_p95_ms": bench.get("max_p95_latency_ms", thresholds["latency_p95_ms"]),
                        "cost_per_query_usd": bench.get("max_token_cost_per_query", thresholds["cost_per_query_usd"]),
                    }
                )
            except Exception:
                pass

        failures: list[str] = []
        if "error" in metrics:
            return False, [metrics["error"]]

        if metrics.get("hit_at_3", 0) < thresholds["hit_at_3"]:
            failures.append(f"hit@3={metrics['hit_at_3']} < {thresholds['hit_at_3']}")
        if metrics.get("ndcg_at_5", 0) < thresholds["ndcg_at_5"]:
            failures.append(f"nDCG@5={metrics['ndcg_at_5']} < {thresholds['ndcg_at_5']}")
        if metrics.get("latency_p95_ms", 0) > thresholds["latency_p95_ms"]:
            failures.append(f"p95={metrics['latency_p95_ms']}ms > {thresholds['latency_p95_ms']}ms")
        if metrics.get("cost_per_query_usd", 0) > thresholds["cost_per_query_usd"]:
            failures.append(f"cost={metrics['cost_per_query_usd']} > {thresholds['cost_per_query_usd']}")
        return len(failures) == 0, failures


def _run_ablation(args: argparse.Namespace, base_weights: dict[str, float]) -> tuple[dict, int]:
    configs = _ablation_weight_sets(base_weights)
    results: list[dict] = []
    exit_code = 0

    for label, weights in configs.items():
        runner = BenchmarkRunner(fixture_dir=Path(args.fixtures), top_k=args.top_k, weights=weights)
        metrics = runner.run(use_vector=args.vector)
        results.append({"config": label, "weights": weights, "metrics": metrics})

    full_metrics = next((r["metrics"] for r in results if r["config"] == "full"), {})
    policy_path = Path(args.policy) if args.policy else None
    full_runner = BenchmarkRunner(fixture_dir=Path(args.fixtures), top_k=args.top_k, weights=base_weights)
    passed, failures = full_runner.check_against_thresholds(full_metrics, policy_path)

    payload = {
        "ablation": results,
        "quality_gate_passed": passed,
        "quality_gate_failures": failures,
        "mode": "vector" if args.vector else "fts",
    }
    if not passed:
        exit_code = 1
    return payload, exit_code


def main() -> int:
    ap = argparse.ArgumentParser(description="Mnemo retrieval benchmark")
    ap.add_argument("--fixtures", default=str(FIXTURE_DIR))
    ap.add_argument("--vector", action="store_true", help="Use vector/backend path where available")
    ap.add_argument("--top-k", type=int, default=5)
    ap.add_argument("--weights", help="Comma-separated semantic,authority,temporal,entity weights")
    ap.add_argument("--ablation", action="store_true", help="Run ablation matrix over score-fusion signals")
    ap.add_argument("--persist-baseline", metavar="PATH", help="Save metrics as baseline JSON")
    ap.add_argument("--compare-baseline", metavar="PATH", help="Compare against baseline JSON")
    ap.add_argument("--policy", metavar="PATH", help="Path to policies.yaml for thresholds")
    args = ap.parse_args()

    base_weights = dict(DEFAULT_WEIGHTS)
    if args.weights:
        base_weights = _normalize_weights(_parse_weights_arg(args.weights))

    if args.ablation:
        payload, exit_code = _run_ablation(args, base_weights)
        print(json.dumps(payload, indent=2))
        if args.persist_baseline:
            Path(args.persist_baseline).write_text(json.dumps(payload, indent=2), encoding="utf-8")
            print(f"\nBaseline saved: {args.persist_baseline}")
        return exit_code

    runner = BenchmarkRunner(fixture_dir=Path(args.fixtures), top_k=args.top_k, weights=base_weights)
    metrics = runner.run(use_vector=args.vector)
    print(json.dumps(metrics, indent=2))

    if args.persist_baseline:
        Path(args.persist_baseline).write_text(json.dumps(metrics, indent=2), encoding="utf-8")
        print(f"\nBaseline saved: {args.persist_baseline}")

    if args.compare_baseline:
        baseline = json.loads(Path(args.compare_baseline).read_text(encoding="utf-8"))
        print("\nDrift vs baseline:")
        for key in ("hit_at_3", "ndcg_at_5", "mrr", "latency_p95_ms", "cost_per_query_usd"):
            old = baseline.get(key, 0)
            new = metrics.get(key, 0)
            delta = new - old
            symbol = "▲" if delta > 0 else "▼" if delta < 0 else "="
            print(f"  {key}: {old:.4f} → {new:.4f} {symbol}{abs(delta):.4f}")

    policy_path = Path(args.policy) if args.policy else None
    passed, failures = runner.check_against_thresholds(metrics, policy_path)
    if not passed:
        print("\nQUALITY GATE FAILED:")
        for f in failures:
            print(f"  FAIL: {f}")
        return 1

    print("\nQuality gate PASSED" if not metrics.get("error") else "\n(Skipped: no fixtures)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
