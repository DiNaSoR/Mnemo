#!/usr/bin/env python3
"""
token_cost_simulation.py - Deep token-cost simulation for Mnemo retrieval.

Purpose:
  Estimate token usage during search/retrieval and context-pack construction
  across multiple top-k and token-budget scenarios.

What it simulates per query:
  1) Query tokenization cost
  2) Retrieved candidate token volume (top-k)
  3) Packed context tokens after budget truncation
  4) Prompt + completion token estimate
  5) Optional USD estimate (if prices are provided)

Usage:
  python tests/retrieval/token_cost_simulation.py
  python tests/retrieval/token_cost_simulation.py --vector --show-per-query
  python tests/retrieval/token_cost_simulation.py --output /tmp/token-sim.json
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import statistics
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

from benchmark_runner import BenchmarkRunner


REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_DIR = Path(__file__).parent / "fixtures"
DEFAULT_TOPK_GRID = [3, 5, 8, 12]
DEFAULT_SYSTEM_TOKENS = 240
DEFAULT_COMPLETION_TOKENS = 500


def _ensure_runtime_paths() -> None:
    roots = [Path.cwd(), REPO_ROOT]
    candidates: list[Path] = []
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
                candidates.append(candidate)
    for p in candidates:
        p_str = str(p)
        if p_str not in sys.path:
            sys.path.insert(0, p_str)


def _safe_import_yaml():
    try:
        import yaml  # type: ignore
        return yaml
    except Exception:
        return None


def _load_policy_budgets() -> dict[str, int]:
    """
    Load token budgets from policy file.
    Falls back to defaults if policy or parser is unavailable.
    """
    policy_path = REPO_ROOT / "scripts" / "memory" / "installer" / "templates" / "autonomy" / "policies.yaml"
    defaults = {"default": 1500, "extended": 3000}

    _ensure_runtime_paths()
    try:
        from autonomy.token_counter import load_token_budget_config  # type: ignore

        cfg = load_token_budget_config(policy_path=policy_path)
        return {"default": int(cfg.default_tokens), "extended": int(cfg.extended_tokens)}
    except Exception:
        pass

    if not policy_path.exists():
        return defaults

    yaml = _safe_import_yaml()
    if yaml is None:
        return defaults

    try:
        data = yaml.safe_load(policy_path.read_text(encoding="utf-8")) or {}
        d = data.get("token_budget_default_tokens")
        e = data.get("token_budget_extended_tokens")
        if d is None or e is None:
            # Legacy char budget support.
            d = int(math.ceil(int(data.get("token_budget_default", defaults["default"] * 4)) / 4))
            e = int(math.ceil(int(data.get("token_budget_extended", defaults["extended"] * 4)) / 4))
        else:
            d = int(d)
            e = int(e)
        return {"default": d, "extended": e}
    except Exception:
        return defaults

class TokenCounter:
    """
    Token counter with provider-aware fallbacks:
      - tiktoken when available for OpenAI-style tokenization
      - Google LocalTokenizer when available for Gemini
      - chars/4 approximation fallback
    """

    def __init__(self, provider: str, model: str):
        _ensure_runtime_paths()
        self._delegate = None
        try:
            from autonomy.token_counter import TokenCounter as SharedTokenCounter  # type: ignore

            self._delegate = SharedTokenCounter(provider=provider, model=model)
            self.provider = provider.lower().strip()
            self.model = model
            self.mode = self._delegate.mode
            self._tiktoken_enc = None
            self._gemini_tokenizer = None
            return
        except Exception:
            pass

        self.provider = provider.lower().strip()
        self.model = model
        self.mode = "chars/4"
        self._tiktoken_enc = None
        self._gemini_tokenizer = None

        if self.provider == "openai":
            self._try_init_tiktoken()
        elif self.provider == "gemini":
            self._try_init_gemini_local()
        else:
            self._try_init_tiktoken()
            if self._tiktoken_enc is None:
                self._try_init_gemini_local()

    def _try_init_tiktoken(self) -> None:
        try:
            import tiktoken  # type: ignore

            self._tiktoken_enc = tiktoken.encoding_for_model(self.model)
            self.mode = f"tiktoken:{self.model}"
        except Exception:
            self._tiktoken_enc = None

    def _try_init_gemini_local(self) -> None:
        try:
            from google import genai  # type: ignore

            self._gemini_tokenizer = genai.LocalTokenizer(model_name=self.model)
            self.mode = f"gemini-local:{self.model}"
        except Exception:
            self._gemini_tokenizer = None

    def count(self, text: str) -> int:
        if self._delegate is not None:
            return int(self._delegate.count(text))
        if not text:
            return 0

        if self._tiktoken_enc is not None:
            try:
                return len(self._tiktoken_enc.encode(text))
            except Exception:
                pass

        if self._gemini_tokenizer is not None:
            try:
                result = self._gemini_tokenizer.count_tokens(text)
                if isinstance(result, int):
                    return result
                if hasattr(result, "total_tokens"):
                    return int(result.total_tokens)
                return int(result)
            except Exception:
                pass

        # Conservative heuristic fallback.
        return max(1, math.ceil(len(text) / 4))


@dataclass
class ScenarioResult:
    top_k: int
    budget_name: str
    budget_tokens: int
    queries_evaluated: int
    tokenizer_mode: str
    avg_query_tokens: float
    avg_candidate_tokens: float
    avg_packed_tokens: float
    avg_prompt_tokens: float
    p95_prompt_tokens: float
    avg_total_tokens: float
    p95_total_tokens: float
    avg_snippets_included: float
    avg_snippets_dropped: float
    avg_estimated_usd: float
    p95_estimated_usd: float

    def to_dict(self) -> dict:
        return {
            "top_k": self.top_k,
            "budget_name": self.budget_name,
            "budget_tokens": self.budget_tokens,
            "queries_evaluated": self.queries_evaluated,
            "tokenizer_mode": self.tokenizer_mode,
            "avg_query_tokens": round(self.avg_query_tokens, 2),
            "avg_candidate_tokens": round(self.avg_candidate_tokens, 2),
            "avg_packed_tokens": round(self.avg_packed_tokens, 2),
            "avg_prompt_tokens": round(self.avg_prompt_tokens, 2),
            "p95_prompt_tokens": round(self.p95_prompt_tokens, 2),
            "avg_total_tokens": round(self.avg_total_tokens, 2),
            "p95_total_tokens": round(self.p95_total_tokens, 2),
            "avg_snippets_included": round(self.avg_snippets_included, 2),
            "avg_snippets_dropped": round(self.avg_snippets_dropped, 2),
            "avg_estimated_usd": round(self.avg_estimated_usd, 6),
            "p95_estimated_usd": round(self.p95_estimated_usd, 6),
        }


def _percentile(values: list[float], pct: float) -> float:
    if not values:
        return 0.0
    v = sorted(values)
    idx = min(len(v) - 1, max(0, int(round((pct / 100.0) * (len(v) - 1)))))
    return v[idx]


def _parse_topk_grid(raw: str) -> list[int]:
    out: list[int] = []
    for part in raw.split(","):
        p = part.strip()
        if not p:
            continue
        v = int(p)
        if v <= 0:
            continue
        out.append(v)
    return sorted(set(out)) or DEFAULT_TOPK_GRID


def _pack_with_budget(results: list[dict], token_counter: TokenCounter, budget_tokens: int) -> tuple[str, int, int]:
    """
    Build packed retrieval context with budget truncation.
    Returns: (packed_text, included_count, dropped_count)
    """
    used_tokens = 0
    included = 0
    blocks: list[str] = []

    for r in results:
        ref = str(r.get("ref_path", "")).strip() or "<unknown>"
        content = str(r.get("content", "")).strip()
        if not content:
            continue
        block = f"<!-- {ref} -->\n{content}\n"
        block_tokens = token_counter.count(block)
        if used_tokens + block_tokens > budget_tokens:
            continue
        blocks.append(block)
        used_tokens += block_tokens
        included += 1

    dropped = max(0, len(results) - included)
    return "\n".join(blocks).strip(), included, dropped


def _estimate_usd(
    prompt_tokens: int,
    completion_tokens: int,
    input_price_per_1m: float,
    output_price_per_1m: float,
) -> float:
    input_cost = (prompt_tokens / 1_000_000.0) * input_price_per_1m
    output_cost = (completion_tokens / 1_000_000.0) * output_price_per_1m
    return input_cost + output_cost


def _hydrate_content(result: dict) -> str:
    """
    Ensure we have snippet content for token simulation.
    Some retrieval paths return metadata-only rows (e.g., memory_units without content).
    """
    content = str(result.get("content", "") or "")
    if content.strip():
        return content

    candidates: list[str] = []
    for key in ("source_ref", "source_file", "ref_path"):
        raw = str(result.get(key, "") or "").strip()
        if not raw:
            continue
        normalized = raw.lstrip("@").split("#", 1)[0].strip().replace("\\", "/")
        candidates.append(normalized)

    for c in candidates:
        p = Path(c)
        possible: list[Path] = [p]
        if not p.is_absolute():
            possible.extend([Path.cwd() / p, REPO_ROOT / p])
        for path in possible:
            if path.exists() and path.is_file():
                try:
                    return path.read_text(encoding="utf-8", errors="ignore")[:3000]
                except Exception:
                    continue
    return ""


def simulate(args: argparse.Namespace) -> dict:
    budgets = _load_policy_budgets()
    topk_grid = _parse_topk_grid(args.topk_grid)
    runner = BenchmarkRunner(fixture_dir=Path(args.fixtures), top_k=max(topk_grid))
    token_counter = TokenCounter(provider=args.provider, model=args.model)

    # Query dataset from benchmark fixtures.
    fixtures = runner.fixtures
    if not fixtures:
        raise RuntimeError(f"No fixtures found under: {args.fixtures}")

    scenarios: list[ScenarioResult] = []
    per_query_rows: list[dict] = []

    for top_k in topk_grid:
        for budget_name, budget_tokens in budgets.items():
            query_tokens_arr: list[float] = []
            candidate_tokens_arr: list[float] = []
            packed_tokens_arr: list[float] = []
            prompt_tokens_arr: list[float] = []
            total_tokens_arr: list[float] = []
            included_arr: list[float] = []
            dropped_arr: list[float] = []
            usd_arr: list[float] = []

            for fx in fixtures:
                query = str(fx.get("query", "")).strip()
                if not query:
                    continue

                # Use benchmark runner search to mirror current retrieval behavior.
                raw_results = runner._search(query, use_vector=args.vector, top_k=top_k)  # noqa: SLF001
                if not raw_results:
                    continue

                candidate_results = []
                for r in raw_results[:top_k]:
                    item = dict(r)
                    item["content"] = _hydrate_content(item)
                    candidate_results.append(item)

                candidate_tokens = sum(token_counter.count(str(r.get("content", ""))) for r in candidate_results)

                packed_text, included, dropped = _pack_with_budget(
                    candidate_results, token_counter=token_counter, budget_tokens=budget_tokens
                )
                query_tokens = token_counter.count(query)
                packed_tokens = token_counter.count(packed_text)
                prompt_tokens = args.system_tokens + query_tokens + packed_tokens
                total_tokens = prompt_tokens + args.completion_tokens
                usd = _estimate_usd(
                    prompt_tokens=prompt_tokens,
                    completion_tokens=args.completion_tokens,
                    input_price_per_1m=args.input_price_per_1m,
                    output_price_per_1m=args.output_price_per_1m,
                )

                query_tokens_arr.append(query_tokens)
                candidate_tokens_arr.append(candidate_tokens)
                packed_tokens_arr.append(packed_tokens)
                prompt_tokens_arr.append(prompt_tokens)
                total_tokens_arr.append(total_tokens)
                included_arr.append(included)
                dropped_arr.append(dropped)
                usd_arr.append(usd)

                if args.show_per_query:
                    per_query_rows.append({
                        "query": query,
                        "top_k": top_k,
                        "budget_name": budget_name,
                        "budget_tokens": budget_tokens,
                        "query_tokens": query_tokens,
                        "candidate_tokens": candidate_tokens,
                        "packed_tokens": packed_tokens,
                        "prompt_tokens": prompt_tokens,
                        "completion_tokens": args.completion_tokens,
                        "total_tokens": total_tokens,
                        "snippets_included": included,
                        "snippets_dropped": dropped,
                        "estimated_usd": round(usd, 6),
                    })

            if not prompt_tokens_arr:
                continue

            scenarios.append(ScenarioResult(
                top_k=top_k,
                budget_name=budget_name,
                budget_tokens=budget_tokens,
                queries_evaluated=len(prompt_tokens_arr),
                tokenizer_mode=token_counter.mode,
                avg_query_tokens=statistics.mean(query_tokens_arr),
                avg_candidate_tokens=statistics.mean(candidate_tokens_arr),
                avg_packed_tokens=statistics.mean(packed_tokens_arr),
                avg_prompt_tokens=statistics.mean(prompt_tokens_arr),
                p95_prompt_tokens=_percentile(prompt_tokens_arr, 95),
                avg_total_tokens=statistics.mean(total_tokens_arr),
                p95_total_tokens=_percentile(total_tokens_arr, 95),
                avg_snippets_included=statistics.mean(included_arr),
                avg_snippets_dropped=statistics.mean(dropped_arr),
                avg_estimated_usd=statistics.mean(usd_arr),
                p95_estimated_usd=_percentile(usd_arr, 95),
            ))

    scenarios_sorted = sorted(scenarios, key=lambda s: (s.top_k, s.budget_tokens))
    payload = {
        "config": {
            "fixtures": str(args.fixtures),
            "vector": args.vector,
            "provider": args.provider,
            "model": args.model,
            "tokenizer_mode": token_counter.mode,
            "topk_grid": topk_grid,
            "budgets_tokens": budgets,
            "system_tokens": args.system_tokens,
            "completion_tokens": args.completion_tokens,
            "input_price_per_1m": args.input_price_per_1m,
            "output_price_per_1m": args.output_price_per_1m,
        },
        "scenario_summary": [s.to_dict() for s in scenarios_sorted],
    }
    if args.show_per_query:
        payload["per_query"] = per_query_rows
    return payload


def _print_table(report: dict) -> None:
    cfg = report["config"]
    print("Token Cost Simulation")
    print("=====================")
    print(f"retrieval_mode: {'vector' if cfg['vector'] else 'fts'}")
    print(f"provider/model: {cfg['provider']} / {cfg['model']}")
    print(f"tokenizer: {cfg['tokenizer_mode']}")
    print(f"fixtures: {cfg['fixtures']}")
    print("")
    print(
        "top_k  budget    avg_prompt  p95_prompt  avg_total  p95_total  "
        "avg_pack  avg_cand  kept  drop  avg_usd"
    )
    print("-" * 112)
    for row in report["scenario_summary"]:
        print(
            f"{row['top_k']:>4}  "
            f"{row['budget_name']:<8}  "
            f"{row['avg_prompt_tokens']:>10.1f}  "
            f"{row['p95_prompt_tokens']:>10.1f}  "
            f"{row['avg_total_tokens']:>9.1f}  "
            f"{row['p95_total_tokens']:>9.1f}  "
            f"{row['avg_packed_tokens']:>8.1f}  "
            f"{row['avg_candidate_tokens']:>8.1f}  "
            f"{row['avg_snippets_included']:>4.1f}  "
            f"{row['avg_snippets_dropped']:>4.1f}  "
            f"{row['avg_estimated_usd']:>7.5f}"
        )

    if report.get("per_query"):
        print("\nPer-query rows included in JSON output.")


def main() -> int:
    ap = argparse.ArgumentParser(description="Mnemo deep token-cost simulation")
    ap.add_argument("--fixtures", default=str(FIXTURE_DIR), help="Fixture directory with query JSON files")
    ap.add_argument("--vector", action="store_true", help="Try vector retrieval path first")
    ap.add_argument("--provider", default="openai", choices=["openai", "gemini", "auto"])
    ap.add_argument("--model", default="gpt-4o-mini", help="Tokenizer model name")
    ap.add_argument("--topk-grid", default="3,5,8,12", help="Comma-separated top-k values")
    ap.add_argument("--system-tokens", type=int, default=DEFAULT_SYSTEM_TOKENS, help="Fixed system/instruction token overhead")
    ap.add_argument("--completion-tokens", type=int, default=DEFAULT_COMPLETION_TOKENS, help="Estimated completion tokens")
    ap.add_argument("--input-price-per-1m", type=float, default=0.0, help="Input token price per 1M tokens (USD)")
    ap.add_argument("--output-price-per-1m", type=float, default=0.0, help="Output token price per 1M tokens (USD)")
    ap.add_argument("--output", help="Write full simulation JSON report")
    ap.add_argument("--show-per-query", action="store_true", help="Include per-query details in output JSON")
    args = ap.parse_args()

    report = simulate(args)
    _print_table(report)

    if args.output:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"\nReport written: {out}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
