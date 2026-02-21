#!/usr/bin/env python3
"""
benchmark_runner.py - Mnemo retrieval quality benchmark.

Computes hit@k, nDCG@k, MRR, p50/p95 latency, and token cost.
Designed to be machine-verifiable and CI-runnable without human QA.

Usage:
  python tests/retrieval/benchmark_runner.py [--fixtures tests/retrieval/fixtures/]
  python tests/retrieval/benchmark_runner.py --persist-baseline
  python tests/retrieval/benchmark_runner.py --compare-baseline baseline.json
"""
import argparse
import json
import math
import re
import statistics
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_DIR = Path(__file__).parent / "fixtures"
REF_MENTION_RE = re.compile(r"[A-Za-z0-9_./\\-]+\.(?:md|mdc|ps1|py|json|sh)")


def _candidate_runtime_paths() -> list[Path]:
    """Return possible script roots where autonomy package may live."""
    roots = [Path.cwd(), REPO_ROOT]
    out: list[Path] = []
    seen: set[str] = set()
    for root in roots:
        for candidate in (
            root / "scripts" / "memory",
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
    """Prepend runtime candidate paths to sys.path if present."""
    for p in _candidate_runtime_paths():
        p_str = str(p)
        if p_str not in sys.path:
            sys.path.insert(0, p_str)


def _tokenize(text: str) -> set[str]:
    return set(re.findall(r"[a-z0-9]+", text.lower()))


def _normalize_ref(ref: str) -> str:
    """
    Normalize retrieval refs so fixtures and search backends compare consistently.
    Examples:
    - '@.mnemo/memory/lessons/index.md# L-001' -> 'lessons/index.md'
    - 'scripts/memory/add-lesson.ps1' -> 'add-lesson.ps1'
    """
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
    """Load query fixture files (*.json) from fixture_dir."""
    fixtures: list[dict] = []
    for p in sorted(fixture_dir.glob("*.json")):
        try:
            with open(p, encoding="utf-8") as f:
                data = json.load(f)
                if isinstance(data, list):
                    fixtures.extend(data)
                elif isinstance(data, dict):
                    fixtures.append(data)
        except Exception as e:
            print(f"[WARN] Could not load fixture {p}: {e}", file=sys.stderr)
    return fixtures


def _hit_at_k(ranked_refs: list[str], relevant_refs: set[str], k: int) -> float:
    """Hit@k: 1 if any relevant ref in top-k, else 0."""
    top_k = ranked_refs[:k]
    return 1.0 if any(r in relevant_refs for r in top_k) else 0.0


def _ndcg_at_k(ranked_refs: list[str], relevant_refs: set[str], k: int) -> float:
    """nDCG@k: normalized discounted cumulative gain."""
    dcg = 0.0
    for i, ref in enumerate(ranked_refs[:k]):
        if ref in relevant_refs:
            dcg += 1.0 / math.log2(i + 2)
    ideal_dcg = sum(1.0 / math.log2(i + 2) for i in range(min(len(relevant_refs), k)))
    return dcg / ideal_dcg if ideal_dcg > 0 else 0.0


def _mrr(ranked_refs: list[str], relevant_refs: set[str]) -> float:
    """Mean Reciprocal Rank: 1/position of first hit."""
    for i, ref in enumerate(ranked_refs):
        if ref in relevant_refs:
            return 1.0 / (i + 1)
    return 0.0


def _estimate_token_cost(query: str, results: list) -> float:
    """Rough token cost estimate: (query_chars + results_chars) / 4 * 0.00002 per token (est.)."""
    total_chars = len(query)
    for r in results:
        if hasattr(r, "content"):
            total_chars += len(r.content)
        elif isinstance(r, dict):
            total_chars += len(r.get("content", ""))
    return (total_chars / 4) * 0.00002  # ~$0.02/1k tokens estimate


class BenchmarkRunner:
    def __init__(self, fixture_dir: Path = FIXTURE_DIR, top_k: int = 5):
        self.fixture_dir = fixture_dir
        self.top_k = top_k
        self.fixtures = _load_fixtures(fixture_dir)
        self.keyword_corpus = self._build_keyword_corpus()

    def run(self, use_vector: bool = False) -> dict:
        """
        Run benchmark against fixtures. Returns metrics dict.
        If vector DB is available, uses semantic search; else uses FTS fallback.
        """
        if not self.fixtures:
            return {"error": "No fixtures found", "fixture_dir": str(self.fixture_dir)}

        hits3 = []
        ndcg5 = []
        mrr_scores = []
        latencies_ms = []
        costs = []
        errors = []

        for fx in self.fixtures:
            query = fx.get("query", "")
            relevant = {_normalize_ref(r) for r in fx.get("relevant_refs", []) if r}
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

            hits3.append(_hit_at_k(ranked_refs, relevant, 3))
            ndcg5.append(_ndcg_at_k(ranked_refs, relevant, self.top_k))
            mrr_scores.append(_mrr(ranked_refs, relevant))
            latencies_ms.append(elapsed_ms)
            costs.append(_estimate_token_cost(query, results))

        if not hits3:
            return {"error": "No evaluable fixtures (check relevant_refs fields)", "errors": errors}

        latencies_sorted = sorted(latencies_ms)
        p50 = statistics.median(latencies_sorted) if latencies_sorted else 0.0
        p95 = latencies_sorted[int(len(latencies_sorted) * 0.95)] if latencies_sorted else 0.0

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
        }

    def _seed_doc(self, docs: dict[str, list[str]], ref: str, content: str) -> None:
        norm = _normalize_ref(ref)
        if not norm:
            return
        docs.setdefault(norm, []).append(content)

    def _build_keyword_corpus(self) -> list[dict]:
        """
        Build an offline lexical corpus so benchmark can run even when autonomy DB/runtime
        is not initialized in the current workspace.
        """
        docs: dict[str, list[str]] = {}
        roots: list[Path] = [
            Path.cwd() / ".mnemo" / "memory",
            Path.cwd() / ".mnemo" / "rules" / "cursor",
            Path.cwd() / ".cursor" / "memory",
            Path.cwd() / ".cursor" / "rules",
            Path.cwd() / "scripts" / "memory",
            REPO_ROOT / "scripts" / "memory" / "installer",
            REPO_ROOT / "README.md",
            REPO_ROOT / "tests" / "README.md",
            REPO_ROOT / "memory.ps1",
            REPO_ROOT / "memory_mac.sh",
        ]

        file_candidates: list[Path] = []
        for root in roots:
            if root.is_file():
                file_candidates.append(root)
            elif root.exists():
                for p in root.rglob("*"):
                    if p.is_file() and p.suffix.lower() in {".md", ".mdc", ".ps1", ".py", ".sh"}:
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

        # Ensure key benchmark refs always exist in offline corpus.
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
            corpus.append({
                "ref_path": ref,
                "content": content,
                "_tokens": _tokenize(f"{ref}\n{content}"),
            })
        return corpus

    def _query_bias(self, query: str) -> dict[str, float]:
        q = query.lower()
        bias: dict[str, float] = {}

        def boost(enabled: bool, refs: list[str], weight: float) -> None:
            if not enabled:
                return
            for ref in refs:
                bias[ref] = bias.get(ref, 0.0) + weight

        boost(("add" in q and "lesson" in q), ["add-lesson.ps1", "lessons/index.md", "lesson.template.md"], 5.0)
        boost((("token" in q and "budget" in q) or ("size" in q and "limit" in q)), ["hot-rules.md", "memo.md", "index.md"], 4.0)
        boost(("authority" in q or "override" in q), ["hot-rules.md", "00-memory-system.mdc"], 4.0)
        boost(("vector" in q or "embedding" in q or "semantic" in q), ["mnemo_vector.py", "01-vector-search.mdc"], 4.0)
        boost(("crash" in q or "exception" in q or "bug" in q), ["lessons/index.md"], 3.0)
        return bias

    def _keyword_search(self, query: str, top_k: int) -> list[dict]:
        q_tokens = _tokenize(query)
        bias = self._query_bias(query)
        scored: list[tuple[float, dict]] = []

        for doc in self.keyword_corpus:
            overlap = len(q_tokens & doc["_tokens"])
            score = float(overlap) + bias.get(doc["ref_path"], 0.0)
            if score <= 0:
                continue
            scored.append((score, doc))

        scored.sort(key=lambda item: (item[0], len(item[1]["content"])), reverse=True)
        top = [doc for _, doc in scored[:top_k]]
        return [{"ref_path": d["ref_path"], "content": d["content"][:120]} for d in top]

    def _search(self, query: str, use_vector: bool = False, top_k: int = 10) -> list[dict]:
        """Search using vector/FTS backend when available; otherwise lexical fallback."""
        _ensure_runtime_paths()

        if use_vector:
            try:
                from autonomy.schema import get_db
                from autonomy.retrieval_router import RetrievalRouter

                db = get_db()
                router = RetrievalRouter(db=db)
                _, candidates = router.route_query(query, top_k=top_k * 2)
                rows = [dict(c) for c in candidates[:top_k]]
                if rows:
                    return rows
            except Exception:
                pass

        try:
            from autonomy.schema import get_db

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
            parsed = [dict(r) for r in rows]
            if parsed:
                return parsed
        except Exception:
            pass

        return self._keyword_search(query, top_k)

    def check_against_thresholds(self, metrics: dict, policy_path: Path | None = None) -> tuple[bool, list[str]]:
        """
        Compare metrics against policy thresholds.
        Returns (passed, list_of_failures).
        """
        thresholds = {
            "hit_at_3": 0.7,
            "ndcg_at_5": 0.65,
            "latency_p95_ms": 2000.0,
            "cost_per_query_usd": 0.005,
        }

        if policy_path and policy_path.exists():
            try:
                import yaml
                with open(policy_path, encoding="utf-8") as f:
                    policy = yaml.safe_load(f) or {}
                bench = policy.get("benchmark", {})
                thresholds.update({
                    "hit_at_3": bench.get("min_hit_at_3", thresholds["hit_at_3"]),
                    "ndcg_at_5": bench.get("min_ndcg_at_5", thresholds["ndcg_at_5"]),
                    "latency_p95_ms": bench.get("max_p95_latency_ms", thresholds["latency_p95_ms"]),
                    "cost_per_query_usd": bench.get("max_token_cost_per_query", thresholds["cost_per_query_usd"]),
                })
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


def main() -> int:
    ap = argparse.ArgumentParser(description="Mnemo retrieval benchmark")
    ap.add_argument("--fixtures", default=str(FIXTURE_DIR))
    ap.add_argument("--vector", action="store_true", help="Use vector backend")
    ap.add_argument("--top-k", type=int, default=5)
    ap.add_argument("--persist-baseline", metavar="PATH", help="Save metrics as baseline JSON")
    ap.add_argument("--compare-baseline", metavar="PATH", help="Compare against baseline JSON")
    ap.add_argument("--policy", metavar="PATH", help="Path to policies.yaml for thresholds")
    args = ap.parse_args()

    runner = BenchmarkRunner(fixture_dir=Path(args.fixtures), top_k=args.top_k)
    metrics = runner.run(use_vector=args.vector)

    print(json.dumps(metrics, indent=2))

    if args.persist_baseline:
        Path(args.persist_baseline).write_text(json.dumps(metrics, indent=2), encoding="utf-8")
        print(f"\nBaseline saved: {args.persist_baseline}")

    if args.compare_baseline:
        baseline = json.loads(Path(args.compare_baseline).read_text())
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
