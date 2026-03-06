#!/usr/bin/env python3
"""
eval_contradiction.py - Evaluate contradiction detection quality.

Reports precision/recall/F1 for:
  1) legacy Jaccard+keyword baseline
  2) shared contradiction detector (predicate/hybrid/heuristic modes)
"""
from __future__ import annotations

import argparse
import csv
import json
import re
import sys
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
FIXTURE_PATH = Path(__file__).parent / "fixtures" / "contradiction_pairs.json"


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


def _jaccard(a: str, b: str) -> float:
    ta = set(re.findall(r"\w+", a.lower()))
    tb = set(re.findall(r"\w+", b.lower()))
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def _legacy_predict(a: str, b: str) -> bool:
    if _jaccard(a, b) < 0.85:
        return False
    pairs = [
        ("do not", "always"),
        ("never", "must"),
        ("disabled", "enabled"),
        ("false", "true"),
        ("forbidden", "required"),
    ]
    al = a.lower()
    bl = b.lower()
    for neg, pos in pairs:
        if (neg in al and pos in bl) or (pos in al and neg in bl):
            return True
    return False


def _compute_metrics(rows: list[dict[str, Any]]) -> dict[str, float | int]:
    tp = sum(1 for r in rows if r["label"] and r["pred"])
    fp = sum(1 for r in rows if not r["label"] and r["pred"])
    tn = sum(1 for r in rows if not r["label"] and not r["pred"])
    fn = sum(1 for r in rows if r["label"] and not r["pred"])

    precision = tp / (tp + fp) if (tp + fp) else 0.0
    recall = tp / (tp + fn) if (tp + fn) else 0.0
    f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) else 0.0
    acc = (tp + tn) / max(1, len(rows))

    return {
        "count": len(rows),
        "tp": tp,
        "fp": fp,
        "tn": tn,
        "fn": fn,
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "f1": round(f1, 4),
        "accuracy": round(acc, 4),
    }


def _fixture_category(fx: dict[str, Any]) -> str:
    cat = str(fx.get("category", "")).strip().lower()
    if cat:
        return cat
    tag = str(fx.get("tag", "")).strip().lower()
    return tag or "uncategorized"


def evaluate(
    fixtures: list[dict[str, Any]],
    use_embeddings: bool = False,
    anchor_threshold: float = 0.45,
    embed_threshold: float = 0.72,
    mode: str = "hybrid",
    min_frame_confidence: float = 0.55,
    require_embedding_confirmation: bool = False,
    by_category: bool = False,
) -> dict[str, Any]:
    _ensure_runtime_paths()
    from autonomy.contradiction import compare_texts  # type: ignore

    legacy_rows: list[dict[str, Any]] = []
    detector_rows: list[dict[str, Any]] = []
    legacy_by_cat: dict[str, list[dict[str, Any]]] = {}
    detector_by_cat: dict[str, list[dict[str, Any]]] = {}

    for fx in fixtures:
        a = str(fx.get("a", "")).strip()
        b = str(fx.get("b", "")).strip()
        label = bool(fx.get("is_contradiction", False))
        if not a or not b:
            continue
        category = _fixture_category(fx)

        legacy_pred = _legacy_predict(a, b)
        legacy_row = {"label": label, "pred": legacy_pred}
        legacy_rows.append(legacy_row)
        legacy_by_cat.setdefault(category, []).append(legacy_row)

        match = compare_texts(
            a,
            b,
            use_embeddings=use_embeddings,
            anchor_threshold=anchor_threshold,
            embed_threshold=embed_threshold,
            mode=mode,
            min_frame_confidence=min_frame_confidence,
            require_embedding_confirmation=require_embedding_confirmation,
        )
        detector_pred = match is not None
        detector_row = {
            "label": label,
            "pred": detector_pred,
            "method": getattr(match, "method", "") if match else "",
        }
        detector_rows.append(detector_row)
        detector_by_cat.setdefault(category, []).append(detector_row)

    legacy = _compute_metrics(legacy_rows)
    detector = _compute_metrics(detector_rows)
    report: dict[str, Any] = {
        "legacy_jaccard": legacy,
        "detector_v2": detector,
        "improvement_f1": round(float(detector["f1"]) - float(legacy["f1"]), 4),
        "improvement_precision": round(float(detector["precision"]) - float(legacy["precision"]), 4),
        "config": {
            "mode": mode,
            "use_embeddings": use_embeddings,
            "anchor_threshold": anchor_threshold,
            "embed_threshold": embed_threshold,
            "min_frame_confidence": min_frame_confidence,
            "require_embedding_confirmation": require_embedding_confirmation,
        },
    }

    if by_category:
        categories = sorted(set(legacy_by_cat.keys()) | set(detector_by_cat.keys()))
        report["by_category"] = {
            "legacy_jaccard": {cat: _compute_metrics(legacy_by_cat.get(cat, [])) for cat in categories},
            "detector_v2": {cat: _compute_metrics(detector_by_cat.get(cat, [])) for cat in categories},
        }

    return report


def _write_report_json(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2), encoding="utf-8")


def _write_report_csv(path: Path, report: dict[str, Any], include_by_category: bool) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    rows: list[dict[str, Any]] = []
    for detector_key in ("legacy_jaccard", "detector_v2"):
        m = report.get(detector_key, {})
        rows.append(
            {
                "scope": "overall",
                "detector": detector_key,
                "category": "all",
                "count": m.get("count", 0),
                "tp": m.get("tp", 0),
                "fp": m.get("fp", 0),
                "tn": m.get("tn", 0),
                "fn": m.get("fn", 0),
                "precision": m.get("precision", 0.0),
                "recall": m.get("recall", 0.0),
                "f1": m.get("f1", 0.0),
                "accuracy": m.get("accuracy", 0.0),
            }
        )

    if include_by_category:
        by_cat = report.get("by_category", {})
        for detector_key in ("legacy_jaccard", "detector_v2"):
            category_map = by_cat.get(detector_key, {})
            for category in sorted(category_map.keys()):
                m = category_map.get(category, {})
                rows.append(
                    {
                        "scope": "category",
                        "detector": detector_key,
                        "category": category,
                        "count": m.get("count", 0),
                        "tp": m.get("tp", 0),
                        "fp": m.get("fp", 0),
                        "tn": m.get("tn", 0),
                        "fn": m.get("fn", 0),
                        "precision": m.get("precision", 0.0),
                        "recall": m.get("recall", 0.0),
                        "f1": m.get("f1", 0.0),
                        "accuracy": m.get("accuracy", 0.0),
                    }
                )

    with path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(
            f,
            fieldnames=[
                "scope",
                "detector",
                "category",
                "count",
                "tp",
                "fp",
                "tn",
                "fn",
                "precision",
                "recall",
                "f1",
                "accuracy",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    ap = argparse.ArgumentParser(description="Evaluate contradiction detector quality")
    ap.add_argument("--fixtures", default=str(FIXTURE_PATH))
    ap.add_argument("--mode", choices=["predicate", "hybrid", "heuristic"], default="hybrid")
    ap.add_argument("--use-embeddings", action="store_true", help="Enable optional embedding-enhanced contradiction checks")
    ap.add_argument("--anchor-threshold", type=float, default=0.45)
    ap.add_argument("--embed-threshold", type=float, default=0.72)
    ap.add_argument("--min-frame-confidence", type=float, default=0.55)
    ap.add_argument("--require-embedding-confirmation", action="store_true")
    ap.add_argument("--min-precision", type=float, default=0.75)
    ap.add_argument("--min-recall", type=float, default=0.70)
    ap.add_argument("--min-f1", type=float, default=0.72)
    ap.add_argument("--by-category", action="store_true", help="Include per-category metric breakdown")
    ap.add_argument("--report-json", help="Optional path to write full JSON report")
    ap.add_argument("--report-csv", help="Optional path to write CSV summary report")
    args = ap.parse_args()

    fixtures = json.loads(Path(args.fixtures).read_text(encoding="utf-8"))
    if not isinstance(fixtures, list):
        raise SystemExit("Fixture file must contain a JSON array")

    report = evaluate(
        fixtures=fixtures,
        use_embeddings=args.use_embeddings,
        anchor_threshold=args.anchor_threshold,
        embed_threshold=args.embed_threshold,
        mode=args.mode,
        min_frame_confidence=args.min_frame_confidence,
        require_embedding_confirmation=args.require_embedding_confirmation,
        by_category=args.by_category,
    )
    print(json.dumps(report, indent=2))

    if args.report_json:
        _write_report_json(Path(args.report_json), report)
        print(f"\nWrote JSON report: {args.report_json}")
    if args.report_csv:
        _write_report_csv(Path(args.report_csv), report, include_by_category=args.by_category)
        print(f"Wrote CSV report: {args.report_csv}")

    detector = report["detector_v2"]
    precision = float(detector["precision"])
    recall = float(detector["recall"])
    f1 = float(detector["f1"])

    failed: list[str] = []
    if precision < args.min_precision:
        failed.append(f"precision={precision:.4f} < {args.min_precision:.4f}")
    if recall < args.min_recall:
        failed.append(f"recall={recall:.4f} < {args.min_recall:.4f}")
    if f1 < args.min_f1:
        failed.append(f"f1={f1:.4f} < {args.min_f1:.4f}")

    if failed:
        print("\nCONTRADICTION QUALITY GATE FAILED:")
        for f in failed:
            print(f"  FAIL: {f}")
        return 1

    print("\nContradiction quality gate PASSED")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
