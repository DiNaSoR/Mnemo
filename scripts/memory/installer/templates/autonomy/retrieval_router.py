#!/usr/bin/env python3
"""
retrieval_router.py - Active retrieval router with intent/topic classification.

Routes queries to appropriate memory classes based on detected intent.
Falls back to global search when confidence is low.

Memory class routing:
  - procedural → lessons/ (how to do things, rules)
  - episodic   → journal/, active-context (recent events, history)
  - core       → hot-rules.md, memo.md (invariants, ownership)
  - semantic   → digests/ (summaries, concepts)
  - global     → all classes (fallback)
"""
import re
import sqlite3
from dataclasses import dataclass
from typing import Optional

from autonomy.schema import get_db

# Intent → memory_type routing table
_INTENT_PATTERNS: list[tuple[str, list[str], str]] = [
    # (label, patterns, memory_type)
    ("error", [r"\b(error|crash|fail|bug|exception|broke|broken)\b"], "procedural"),
    ("lesson", [r"\b(lesson|rule|pattern|pitfall|don.t|avoid|never|always)\b"], "procedural"),
    ("history", [r"\b(when|yesterday|last\s+week|last\s+month|what\s+happened|journal)\b"], "episodic"),
    ("recent", [r"\b(recent|latest|today|current\s+session|currently\s+working)\b"], "episodic"),
    ("ownership", [r"\b(who\s+owns|owner|responsible\s+for|which\s+(file|module|class))\b"], "core"),
    ("invariant", [r"\b(invariant|constraint|rule|must\s+not|forbidden|allowed)\b"], "core"),
    ("architecture", [r"\b(architecture|design|structure|module|component)\b"], "semantic"),
    ("summary", [r"\b(summary|overview|digest|what\s+is|describe)\b"], "semantic"),
]

CONFIDENCE_THRESHOLD = 0.5


@dataclass
class RouteDecision:
    intent: str
    memory_types: list[str]  # ordered by priority
    confidence: float
    fallback: bool  # True if routing to global fallback


def classify_intent(query: str) -> RouteDecision:
    """
    Classify query intent and route to memory class(es).
    Returns RouteDecision with ordered memory types to search.
    """
    q_lower = query.lower()
    scores: dict[str, float] = {}

    for label, patterns, mem_type in _INTENT_PATTERNS:
        for pattern in patterns:
            if re.search(pattern, q_lower, re.IGNORECASE):
                scores[mem_type] = scores.get(mem_type, 0.0) + 1.0

    if not scores:
        return RouteDecision(
            intent="global", memory_types=["core", "procedural", "episodic", "semantic"],
            confidence=0.0, fallback=True
        )

    # Normalize
    total = sum(scores.values())
    normed = {k: v / total for k, v in scores.items()}

    best_type = max(normed, key=lambda k: normed[k])
    best_conf = normed[best_type]

    if best_conf < CONFIDENCE_THRESHOLD:
        # Include all types but prioritize best match
        all_types = list(normed.keys()) + [t for t in ["core", "procedural", "episodic", "semantic"] if t not in normed]
        return RouteDecision(intent="mixed", memory_types=all_types, confidence=best_conf, fallback=True)

    # Include secondary routes
    ordered = sorted(normed, key=lambda k: normed[k], reverse=True)
    # Always include global fallback types not in primary route
    for t in ["core", "procedural", "episodic", "semantic"]:
        if t not in ordered:
            ordered.append(t)

    return RouteDecision(
        intent=best_type, memory_types=ordered, confidence=best_conf, fallback=False
    )


class RetrievalRouter:
    def __init__(self, db: Optional[sqlite3.Connection] = None):
        self.db = db or get_db()

    def route_query(self, query: str, top_k: int = 5) -> tuple[RouteDecision, list[dict]]:
        """
        Route query to appropriate memory classes, return (decision, candidates).
        Candidates are dict with {ref_path, content, source_ref, memory_type,
        authority, time_scope, entity_tags}.
        """
        decision = classify_intent(query)
        candidates: list[dict] = []

        # Primary: search by memory_type priority
        for mem_type in decision.memory_types:
            rows = self.db.execute(
                """
                SELECT mu.unit_id, mu.source_ref, mu.memory_type, mu.authority,
                       mu.time_scope, mu.entity_tags, mu.sensitivity
                FROM memory_units mu
                WHERE mu.memory_type = ? AND mu.sensitivity != 'secret'
                ORDER BY mu.authority DESC, mu.updated_at DESC
                LIMIT ?
                """,
                (mem_type, top_k),
            ).fetchall()
            for row in rows:
                candidates.append(dict(row))
            if len(candidates) >= top_k:
                break

        # Fallback: add any missing from global pool
        if len(candidates) < top_k:
            existing_ids = {c["unit_id"] for c in candidates}
            remaining = top_k - len(candidates)
            if existing_ids:
                placeholders = ",".join("?" * len(existing_ids))
                extra = self.db.execute(
                    f"""
                    SELECT mu.unit_id, mu.source_ref, mu.memory_type, mu.authority,
                           mu.time_scope, mu.entity_tags, mu.sensitivity
                    FROM memory_units mu
                    WHERE mu.unit_id NOT IN ({placeholders})
                      AND mu.sensitivity != 'secret'
                    ORDER BY mu.authority DESC, mu.updated_at DESC
                    LIMIT ?
                    """,
                    (*existing_ids, remaining),
                ).fetchall()
            else:
                extra = self.db.execute(
                    """
                    SELECT mu.unit_id, mu.source_ref, mu.memory_type, mu.authority,
                           mu.time_scope, mu.entity_tags, mu.sensitivity
                    FROM memory_units mu
                    WHERE mu.sensitivity != 'secret'
                    ORDER BY mu.authority DESC, mu.updated_at DESC
                    LIMIT ?
                    """,
                    (remaining,),
                ).fetchall()
            for row in extra:
                candidates.append(dict(row))

        return decision, candidates

    def get_route_metadata(self, query: str) -> dict:
        """Return routing metadata as dict (for logging/debugging)."""
        decision = classify_intent(query)
        return {
            "intent": decision.intent,
            "memory_types": decision.memory_types,
            "confidence": round(decision.confidence, 3),
            "fallback": decision.fallback,
        }
