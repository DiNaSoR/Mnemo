#!/usr/bin/env python3
"""
weight_sweep.py - Score-fusion weight sensitivity analysis.

Grid-searches semantic/authority/temporal/entity weights and reports:
  - best configuration by composite quality score
  - top-N configs
  - sensitivity curve (score vs distance from default weights)
"""
from __future__ import annotations

import argparse
import csv
import itertools
import json
import statistics
from pathlib import Path
from typing import Any

from benchmark_runner import BenchmarkRunner, DEFAULT_WEIGHTS

FIXTURE_DIR = Path(__file__).parent / "fixtures"
WEIGHT_KEYS = ("semantic", "authority", "temporal", "entity")


def _composite_score(metrics: dict[str, Any]) -> float:
    # Prioritize ranking quality, then retrieval hit rate.
    return (0.5 * float(metrics.get("ndcg_at_5", 0.0))) + (0.3 * float(metrics.get("mrr", 0.0))) + (
        0.2 * float(metrics.get("hit_at_3", 0.0))
    )


def _normalize_weights(weights: dict[str, float]) -> dict[str, float]:
    raw = {k: max(0.0, float(weights.get(k, 0.0))) for k in WEIGHT_KEYS}
    total = sum(raw.values())
    if total <= 0:
        raise ValueError("Weights must sum to a positive value")
    return {k: round(v / total, 6) for k, v in raw.items()}


def _parse_weights_arg(value: str) -> dict[str, float]:
    parts = [p.strip() for p in value.split(",")]
    if len(parts) != 4:
        raise ValueError("--default-weights must be four comma-separated values: semantic,authority,temporal,entity")
    nums = [float(p) for p in parts]
    return _normalize_weights(dict(zip(WEIGHT_KEYS, nums)))


def _weight_tuple(weights: dict[str, float]) -> tuple[float, float, float, float]:
    return tuple(float(weights[k]) for k in WEIGHT_KEYS)


def _weight_distance(weights: dict[str, float], default_weights: dict[str, float]) -> float:
    return round(sum(abs(float(weights[k]) - float(default_weights[k])) for k in WEIGHT_KEYS), 6)


def _weight_grid(step: float) -> list[dict[str, float]]:
    # Enumerate simplex with configurable granularity.
    ints = list(range(0, int(round(1.0 / step)) + 1))
    out: list[dict[str, float]] = []
    for s, a, t in itertools.product(ints, repeat=3):
        e = int(round(1.0 / step)) - s - a - t
        if e < 0:
            continue
        sem = round(s * step, 6)
        auth = round(a * step, 6)
        temp = round(t * step, 6)
        ent = round(e * step, 6)
        if sem == auth == temp == ent == 0:
            continue
        out.append({"semantic": sem, "authority": auth, "temporal": temp, "entity": ent})
    # Deterministic order before execution.
    out.sort(key=_weight_tuple)
    return out


def _curve_points(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    by_distance: dict[float, list[dict[str, Any]]] = {}
    for row in rows:
        dist = float(row["distance_from_default"])
        by_distance.setdefault(dist, []).append(row)

    points: list[dict[str, Any]] = []
    for dist in sorted(by_distance.keys()):
        group = by_distance[dist]
        scores = [float(r["score"]) for r in group]
        best = sorted(
            group,
            key=lambda r: (
                -float(r["score"]),
                -float(r["metrics"].get("ndcg_at_5", 0.0)),
                -float(r["metrics"].get("mrr", 0.0)),
                -float(r["metrics"].get("hit_at_3", 0.0)),
                _weight_tuple(r["weights"]),
            ),
        )[0]
        points.append(
            {
                "distance": dist,
                "count": len(group),
                "avg_score": round(statistics.mean(scores), 6),
                "max_score": round(max(scores), 6),
                "best_weights": best["weights"],
            }
        )
    return points


def _write_curve_json(path: Path, default_weights: dict[str, float], points: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "default_weights": default_weights,
        "points": points,
    }
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _write_curve_csv(path: Path, points: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "distance",
                "count",
                "avg_score",
                "max_score",
                "best_semantic",
                "best_authority",
                "best_temporal",
                "best_entity",
            ],
        )
        writer.writeheader()
        for p in points:
            w = p["best_weights"]
            writer.writerow(
                {
                    "distance": p["distance"],
                    "count": p["count"],
                    "avg_score": p["avg_score"],
                    "max_score": p["max_score"],
                    "best_semantic": w["semantic"],
                    "best_authority": w["authority"],
                    "best_temporal": w["temporal"],
                    "best_entity": w["entity"],
                }
            )


def main() -> int:
    ap = argparse.ArgumentParser(description="Weight sweep for Mnemo benchmark reranking")
    ap.add_argument("--fixtures", default=str(FIXTURE_DIR))
    ap.add_argument("--top-k", type=int, default=5)
    ap.add_argument("--step", type=float, default=0.25, help="Grid step for weights (e.g. 0.25 or 0.1)")
    ap.add_argument("--vector", action="store_true", help="Use vector retrieval path when available")
    ap.add_argument("--top-n", type=int, default=10, help="Number of top configs to print")
    ap.add_argument("--default-weights", help="Comma-separated semantic,authority,temporal,entity defaults")
    ap.add_argument("--curve-json", help="Optional JSON path for sensitivity curve output")
    ap.add_argument("--curve-csv", help="Optional CSV path for sensitivity curve output")
    args = ap.parse_args()

    default_weights = dict(DEFAULT_WEIGHTS)
    if args.default_weights:
        default_weights = _parse_weights_arg(args.default_weights)

    weights_grid = _weight_grid(args.step)
    runner = BenchmarkRunner(fixture_dir=Path(args.fixtures), top_k=args.top_k, weights=default_weights)
    rows: list[dict[str, Any]] = []
    for weights in weights_grid:
        runner.weights = dict(weights)
        metrics = runner.run(use_vector=args.vector)
        if "error" in metrics:
            continue
        score = round(_composite_score(metrics), 6)
        rows.append(
            {
                "weights": weights,
                "metrics": metrics,
                "score": score,
                "distance_from_default": _weight_distance(weights, default_weights),
            }
        )

    if not rows:
        print(json.dumps({"error": "No successful sweep runs"}, indent=2))
        return 1

    # Deterministic ranking with explicit tie-breaks.
    rows.sort(
        key=lambda r: (
            -float(r["score"]),
            float(r["distance_from_default"]),
            -float(r["metrics"].get("ndcg_at_5", 0.0)),
            -float(r["metrics"].get("mrr", 0.0)),
            -float(r["metrics"].get("hit_at_3", 0.0)),
            _weight_tuple(r["weights"]),
        )
    )
    best = rows[0]

    runner.weights = dict(default_weights)
    default_metrics = runner.run(use_vector=args.vector)
    default_score = _composite_score(default_metrics) if "error" not in default_metrics else 0.0
    points = _curve_points(rows)

    report = {
        "config": {
            "fixtures": str(args.fixtures),
            "top_k": args.top_k,
            "step": args.step,
            "vector": args.vector,
            "grid_size": len(weights_grid),
            "runs_evaluated": len(rows),
        },
        "default": {
            "weights": default_weights,
            "score": round(default_score, 6),
            "metrics": default_metrics,
        },
        "best": best,
        "top_configs": rows[: max(1, args.top_n)],
        "sensitivity_curve": points,
    }
    print(json.dumps(report, indent=2))

    if args.curve_json:
        _write_curve_json(Path(args.curve_json), default_weights=default_weights, points=points)
        print(f"\nWrote curve JSON: {args.curve_json}")
    if args.curve_csv:
        _write_curve_csv(Path(args.curve_csv), points=points)
        print(f"Wrote curve CSV: {args.curve_csv}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
