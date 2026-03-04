#!/usr/bin/env python3
"""
reranker.py - Score-fusion reranker for Mnemo retrieval.

Combines four signals into a final relevance score:
  1. Semantic similarity (cosine distance from vector search)
  2. Authority weight  (memory_type hierarchy)
  3. Temporal relevance (recency decay for episodic, boost for time queries)
  4. Entity consistency (bonus when queried entity found in unit's entity_tags)

Output is a sorted list of RankedResult objects ready for context packing.
"""
import re
import time
import sqlite3
from dataclasses import dataclass
from typing import Optional

from autonomy.schema import get_db
from autonomy.common import AUTHORITY_WEIGHTS, infer_memory_type as _infer_memory_type, infer_time_scope as _infer_time_scope

# Score fusion weights (must sum to 1.0)
W_SEMANTIC   = 0.55
W_AUTHORITY  = 0.25
W_TEMPORAL   = 0.10
W_ENTITY     = 0.10

# Temporal decay half-life in days for episodic memory
EPISODIC_HALF_LIFE_DAYS = 30.0

# Time-sensitive query keywords
TIME_WORDS = frozenset({
    "today", "yesterday", "last week", "last month", "recent", "latest",
    "just", "now", "currently", "this week", "this month",
})


@dataclass
class RankedResult:
    ref_path: str
    content: str
    source_file: str
    semantic_score: float
    authority_score: float
    temporal_score: float
    entity_score: float
    final_score: float
    memory_type: str
    route_intent: str = ""

    def to_dict(self) -> dict:
        return {
            "ref_path": self.ref_path,
            "content": self.content[:500],
            "final_score": round(self.final_score, 4),
            "semantic": round(self.semantic_score, 3),
            "authority": round(self.authority_score, 3),
            "temporal": round(self.temporal_score, 3),
            "entity": round(self.entity_score, 3),
            "memory_type": self.memory_type,
        }


def _temporal_score(time_scope: str, updated_at_ts: Optional[float], query: str) -> float:
    """Calculate temporal relevance score [0, 1]."""
    if time_scope == "atemporal":
        return 0.8  # timeless facts always moderately relevant

    has_time_query = any(tw in query.lower() for tw in TIME_WORDS)

    if time_scope == "recency-sensitive" and updated_at_ts:
        age_days = (time.time() - updated_at_ts) / 86400.0
        # Exponential decay: fresh = high score, stale = low
        import math
        decay = math.exp(-0.693 * age_days / EPISODIC_HALF_LIFE_DAYS)
        if has_time_query:
            return min(decay * 1.5, 1.0)  # extra boost for time queries
        return decay

    if time_scope == "time-bound":
        return 0.6  # neutral for general content

    return 0.5


def _entity_score(entity_tags_json: str, query: str, db: sqlite3.Connection) -> float:
    """Calculate entity match bonus [0, 1]."""
    if not entity_tags_json or entity_tags_json == "[]":
        return 0.0
    try:
        import json
        entity_ids = json.loads(entity_tags_json)
    except Exception:
        return 0.0

    if not entity_ids:
        return 0.0

    # Get entity names for these IDs
    placeholders = ",".join("?" * len(entity_ids))
    rows = db.execute(
        f"SELECT entity_name FROM entities WHERE entity_id IN ({placeholders})",
        entity_ids,
    ).fetchall()

    q_lower = query.lower()
    for row in rows:
        name_lower = row["entity_name"].lower()
        if name_lower in q_lower or any(
            part in q_lower for part in name_lower.split("_") if len(part) > 3
        ):
            return 1.0

    # Alias check
    alias_rows = db.execute(
        f"""
        SELECT alias_text FROM entity_aliases
        WHERE entity_id IN ({placeholders})
        """,
        entity_ids,
    ).fetchall()
    for row in alias_rows:
        if row["alias_text"].lower() in q_lower:
            return 0.8

    return 0.0


class ScoreFusionReranker:
    def __init__(self, db: Optional[sqlite3.Connection] = None):
        self.db = db or get_db()

    def rerank(
        self,
        query: str,
        raw_results: list[dict],  # {ref_path, content, source_file, distance, memory_type?, time_scope?, entity_tags?}
        top_k: int = 5,
        route_intent: str = "",
    ) -> list[RankedResult]:
        """
        Apply score fusion to raw vector search results.
        raw_results: each dict must have at least ref_path, content, distance.
        Returns top_k RankedResult sorted by final_score desc.
        """
        ranked: list[RankedResult] = []

        for r in raw_results:
            ref = r.get("ref_path", "")
            content = r.get("content", "")
            source_file = r.get("source_file", ref)
            distance = float(r.get("distance", 0.5))

            # 1. Semantic score from cosine distance
            semantic_score = max(0.0, 1.0 - distance)

            # 2. Authority
            mem_type = r.get("memory_type") or _infer_memory_type(ref)
            authority_score = AUTHORITY_WEIGHTS.get(mem_type, 0.5)

            # Skip vault content (sensitivity guard)
            if mem_type == "vault":
                continue

            # 3. Temporal
            time_scope = r.get("time_scope") or _infer_time_scope(mem_type)
            updated_at = r.get("updated_at")
            if updated_at is None:
                # Look up from DB
                row = self.db.execute(
                    "SELECT mu.updated_at FROM memory_units mu WHERE mu.source_ref = ?",
                    (source_file,),
                ).fetchone()
                updated_at = row["updated_at"] if row else None
            temporal = _temporal_score(time_scope, updated_at, query)

            # 4. Entity
            entity_tags_json = r.get("entity_tags", "[]")
            if entity_tags_json is None:
                unit_row = self.db.execute(
                    "SELECT entity_tags FROM memory_units WHERE source_ref = ?",
                    (source_file,),
                ).fetchone()
                entity_tags_json = unit_row["entity_tags"] if unit_row else "[]"
            entity = _entity_score(entity_tags_json, query, self.db)

            # Fusion
            final_score = (
                W_SEMANTIC * semantic_score
                + W_AUTHORITY * authority_score
                + W_TEMPORAL * temporal
                + W_ENTITY * entity
            )

            ranked.append(RankedResult(
                ref_path=ref,
                content=content,
                source_file=source_file,
                semantic_score=semantic_score,
                authority_score=authority_score,
                temporal_score=temporal,
                entity_score=entity,
                final_score=final_score,
                memory_type=mem_type,
                route_intent=route_intent,
            ))

        ranked.sort(key=lambda r: r.final_score, reverse=True)
        return ranked[:top_k]

    def explain(self, result: RankedResult) -> str:
        """Human-readable explanation of why this result was ranked here."""
        return (
            f"[final={result.final_score:.3f}] "
            f"semantic={result.semantic_score:.3f} "
            f"authority={result.authority_score:.3f} "
            f"temporal={result.temporal_score:.3f} "
            f"entity={result.entity_score:.3f} "
            f"type={result.memory_type}"
        )
