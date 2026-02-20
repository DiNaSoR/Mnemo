#!/usr/bin/env python3
"""
drift_check.py - Benchmark drift detection and trend analysis.

Compares current metrics against a persisted baseline to detect quality regression.
Designed for CI/nightly automation.

Usage:
  python tests/retrieval/drift_check.py --current metrics.json --baseline baseline.json
  python tests/retrieval/drift_check.py --current metrics.json --baseline baseline.json --fail-on-regression
"""
import argparse
import json
import sys
from pathlib import Path

# Max allowed regression per metric
REGRESSION_THRESHOLDS = {
    "hit_at_3":          -0.05,   # max 5pp drop
    "ndcg_at_5":         -0.05,
    "mrr":               -0.05,
    "latency_p95_ms":     200.0,  # max 200ms increase
    "cost_per_query_usd": 0.001,  # max $0.001 increase
}


def _load(path: str) -> dict:
    return json.loads(Path(path).read_text(encoding="utf-8"))


def compare(current: dict, baseline: dict) -> tuple[bool, list[dict]]:
    """
    Compare current metrics against baseline.
    Returns (is_regression, list_of_drift_items).
    """
    drifts: list[dict] = []
    regression = False

    for metric, max_regression in REGRESSION_THRESHOLDS.items():
        cur_val = current.get(metric)
        base_val = baseline.get(metric)
        if cur_val is None or base_val is None:
            continue

        delta = cur_val - base_val
        is_latency_or_cost = "latency" in metric or "cost" in metric
        threshold_exceeded = (
            delta > max_regression if is_latency_or_cost else delta < max_regression
        )

        drifts.append({
            "metric": metric,
            "baseline": round(base_val, 4),
            "current": round(cur_val, 4),
            "delta": round(delta, 4),
            "regression": threshold_exceeded,
        })

        if threshold_exceeded:
            regression = True

    return regression, drifts


def main() -> int:
    ap = argparse.ArgumentParser(description="Mnemo benchmark drift check")
    ap.add_argument("--current", required=True, help="Current metrics JSON path")
    ap.add_argument("--baseline", required=True, help="Baseline metrics JSON path")
    ap.add_argument("--fail-on-regression", action="store_true",
                    help="Exit 1 if any regression detected")
    ap.add_argument("--output", help="Write drift report to JSON file")
    args = ap.parse_args()

    current = _load(args.current)
    baseline = _load(args.baseline)

    regression, drifts = compare(current, baseline)

    print("Drift Report:")
    print(f"  Baseline: {args.baseline}")
    print(f"  Current:  {args.current}")
    print("")

    for d in drifts:
        direction = "▲" if d["delta"] > 0 else "▼" if d["delta"] < 0 else "="
        status = " ← REGRESSION" if d["regression"] else ""
        print(f"  {d['metric']:30s}  {d['baseline']:.4f} → {d['current']:.4f}  {direction}{abs(d['delta']):.4f}{status}")

    if args.output:
        report = {
            "regression": regression,
            "baseline": args.baseline,
            "current": args.current,
            "drifts": drifts,
        }
        Path(args.output).write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"\nReport written: {args.output}")

    if regression:
        print("\nDRIFT DETECTED: quality regression found.")
        if args.fail_on_regression:
            return 1
    else:
        print("\nNo regression detected.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
