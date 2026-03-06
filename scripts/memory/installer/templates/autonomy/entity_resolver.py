#!/usr/bin/env python3
"""
entity_resolver.py - Stable entity IDs and alias resolution.

Extracts named entities from memory units (paths, modules, concepts),
assigns stable UUIDs, maintains alias mappings with confidence scores,
and propagates entity_tags back to memory_units.

No human required: alias merging is automatic with confidence thresholds.
"""
import json
import re
import sqlite3
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from autonomy.schema import get_db
from autonomy.ingest_pipeline import MemoryUnit
from autonomy.token_counter import resolve_policy_path

ALIAS_MERGE_THRESHOLD = 0.85  # confidence required to merge aliases
ENTITY_CONFIDENCE_DECAY = 0.02  # decay per cycle without reinforcement
_MAX_FUZZY_CANDIDATES = 500  # max entities loaded for fuzzy matching


@dataclass
class Entity:
    entity_id: str
    entity_name: str
    entity_type: str
    confidence: float


_ENTITY_STOPWORDS = frozenset(
    {
        "this",
        "that",
        "these",
        "those",
        "with",
        "from",
        "into",
        "about",
        "after",
        "before",
        "where",
        "there",
        "their",
        "which",
        "when",
        "must",
        "should",
        "could",
        "would",
        "true",
        "false",
    }
)


def _extract_entities_from_text(
    content: str,
    source_ref: str,
    custom_entities: Optional[list[tuple[str, str, list[str]]]] = None,
) -> list[tuple[str, str]]:
    """
    Heuristic entity extraction from markdown content.
    Returns list of (entity_name, entity_type) tuples.
    """
    entities: list[tuple[str, str]] = []

    # File/path references (e.g., `path/to/file.py`)
    for m in re.finditer(r"`([^`]+\.[a-z]{1,10})`", content):
        p = m.group(1)
        if "/" in p or "\\" in p:
            entities.append((p, "file"))

    # Module/class names (CamelCase words used multiple times)
    camel_matches = re.findall(r"\b([A-Z][a-zA-Z]{3,}(?:[A-Z][a-z]+)+)\b", content)
    freq: dict[str, int] = {}
    for name in camel_matches:
        freq[name] = freq.get(name, 0) + 1
    for name, count in freq.items():
        if count >= 2:
            entities.append((name, "class"))

    # Lesson references (L-XXX)
    for m in re.finditer(r"\bL-(\d{3})\b", content):
        entities.append((f"L-{m.group(1)}", "lesson"))

    # Function/method references (snake_case in backticks)
    for m in re.finditer(r"`([a-z][a-z0-9_]{3,})\(\)`", content):
        entities.append((m.group(1), "function"))

    # Repeated snake_case identifiers (bare; 3+ mentions)
    snake_freq: dict[str, int] = {}
    for name in re.findall(r"\b([a-z][a-z0-9_]{2,})\b", content):
        if "_" not in name:
            continue
        if name in _ENTITY_STOPWORDS:
            continue
        snake_freq[name] = snake_freq.get(name, 0) + 1
    for name, count in snake_freq.items():
        if count >= 3:
            entities.append((name, "identifier"))

    # Hyphenated package/tool names (vue-router, openapi-schema, etc.)
    for m in re.finditer(r"\b([a-z0-9]+(?:-[a-z0-9]+)+)\b", content):
        name = m.group(1)
        if len(name) >= 5:
            entities.append((name, "package"))

    # Import statements: lower-case modules (numpy, fastapi, sqlalchemy, etc.)
    for m in re.finditer(r"^\s*(?:from|import)\s+([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)*)", content, re.MULTILINE):
        base = m.group(1).split(".", 1)[0]
        if base and base not in _ENTITY_STOPWORDS and len(base) >= 3:
            entities.append((base, "module"))

    # Common uppercase abbreviations (DB, API, HTTP, SDK, etc.)
    abbr_freq: dict[str, int] = {}
    for abbr in re.findall(r"\b([A-Z]{2,8})\b", content):
        if abbr in {"TODO", "NOTE"}:
            continue
        abbr_freq[abbr] = abbr_freq.get(abbr, 0) + 1
    for abbr, count in abbr_freq.items():
        if count >= 2:
            entities.append((abbr, "abbreviation"))

    # Policy-defined custom entities and aliases.
    if custom_entities:
        lowered = content.lower()
        for canonical_name, entity_type, aliases in custom_entities:
            candidates = [canonical_name] + aliases
            for raw in candidates:
                probe = raw.strip()
                if not probe:
                    continue
                # Word-boundary when possible, otherwise substring fallback.
                pattern = rf"(?<!\w){re.escape(probe.lower())}(?!\w)"
                if re.search(pattern, lowered):
                    entities.append((canonical_name, entity_type))
                    break

    return list(set(entities))[:30]  # deduplicate + cap


class EntityResolver:
    def __init__(self, db: Optional[sqlite3.Connection] = None):
        self.db = db or get_db()
        self.custom_entities = self._load_custom_entities()

    def _safe_yaml_load(self, path: Optional[Path]) -> dict:
        if path is None or not path.exists():
            return {}
        try:
            import yaml  # type: ignore
        except Exception:
            return {}
        try:
            payload = yaml.safe_load(path.read_text(encoding="utf-8"))
            return payload if isinstance(payload, dict) else {}
        except Exception:
            return {}

    def _load_custom_entities(self) -> list[tuple[str, str, list[str]]]:
        policy = self._safe_yaml_load(resolve_policy_path())
        raw = policy.get("custom_entities", []) if isinstance(policy, dict) else []
        out: list[tuple[str, str, list[str]]] = []

        if isinstance(raw, dict):
            for name, config in raw.items():
                if not name:
                    continue
                if isinstance(config, str):
                    out.append((name, config, []))
                    continue
                if isinstance(config, dict):
                    entity_type = str(config.get("type", "custom"))
                    aliases = [str(a) for a in config.get("aliases", []) if str(a).strip()]
                    out.append((name, entity_type, aliases))
            return out

        if not isinstance(raw, list):
            return out

        for item in raw:
            if not isinstance(item, dict):
                continue
            name = str(item.get("name", "")).strip()
            if not name:
                continue
            entity_type = str(item.get("type", "custom")).strip() or "custom"
            aliases = [str(a).strip() for a in item.get("aliases", []) if str(a).strip()]
            out.append((name, entity_type, aliases))
        return out

    def resolve(self, unit: MemoryUnit) -> list[str]:
        """
        Extract entities from unit content, resolve/create IDs, update unit.
        Returns list of entity_ids assigned to this unit.
        """
        raw_entities = _extract_entities_from_text(
            unit.content,
            unit.source_ref,
            custom_entities=self.custom_entities,
        )
        entity_ids: list[str] = []

        for entity_name, entity_type in raw_entities:
            eid = self._get_or_create(entity_name, entity_type)
            if eid:
                entity_ids.append(eid)

        if entity_ids:
            self.db.execute(
                "UPDATE memory_units SET entity_tags=?, updated_at=unixepoch('now') WHERE unit_id=?",
                (json.dumps(entity_ids), unit.unit_id),
            )
            self.db.commit()
            unit.entity_tags = entity_ids

        return entity_ids

    def _get_or_create(self, entity_name: str, entity_type: str) -> Optional[str]:
        """Resolve entity by exact match or alias, or create new."""
        # Check exact entity name
        row = self.db.execute(
            "SELECT entity_id FROM entities WHERE entity_name = ?", (entity_name,)
        ).fetchone()
        if row:
            self._reinforce(row["entity_id"])
            return row["entity_id"]

        # Check aliases
        alias_row = self.db.execute(
            "SELECT entity_id FROM entity_aliases WHERE alias_text = ?", (entity_name,)
        ).fetchone()
        if alias_row:
            self._reinforce(alias_row["entity_id"])
            return alias_row["entity_id"]

        # Try fuzzy alias match
        similar_id = self._find_similar_entity(entity_name)
        if similar_id:
            # Add as alias
            try:
                self.db.execute(
                    "INSERT INTO entity_aliases(alias_id, entity_id, alias_text, confidence) VALUES (?,?,?,?)",
                    (str(uuid.uuid4()), similar_id, entity_name, ALIAS_MERGE_THRESHOLD),
                )
                self.db.commit()
                self._reinforce(similar_id)
                return similar_id
            except sqlite3.IntegrityError:
                return similar_id

        # Create new entity
        entity_id = str(uuid.uuid4())
        try:
            self.db.execute(
                "INSERT INTO entities(entity_id, entity_name, entity_type, confidence) VALUES (?,?,?,1.0)",
                (entity_id, entity_name, entity_type),
            )
            self.db.commit()
        except sqlite3.IntegrityError:
            # Race condition: entity was created concurrently
            row = self.db.execute(
                "SELECT entity_id FROM entities WHERE entity_name = ?", (entity_name,)
            ).fetchone()
            return row["entity_id"] if row else None
        return entity_id

    def _find_similar_entity(self, name: str) -> Optional[str]:
        """
        Find an entity whose name is highly similar (token Jaccard).
        Returns entity_id if confidence >= threshold, else None.

        Uses a bounded query (LIMIT) to avoid full-table scans at scale.
        """
        candidates = self.db.execute(
            "SELECT entity_id, entity_name FROM entities ORDER BY confidence DESC LIMIT ?",
            (_MAX_FUZZY_CANDIDATES,),
        ).fetchall()

        name_tokens = set(re.findall(r"\w+", name.lower()))
        if not name_tokens:
            return None

        best_id = None
        best_score = 0.0

        for row in candidates:
            cand_tokens = set(re.findall(r"\w+", row["entity_name"].lower()))
            if not cand_tokens:
                continue
            score = len(name_tokens & cand_tokens) / len(name_tokens | cand_tokens)
            if score > best_score:
                best_score = score
                best_id = row["entity_id"]
                if score >= 1.0:  # perfect match — no need to keep searching
                    break

        return best_id if best_score >= ALIAS_MERGE_THRESHOLD else None

    def _reinforce(self, entity_id: str) -> None:
        """Increase confidence for an entity (re-observed)."""
        self.db.execute(
            "UPDATE entities SET confidence=MIN(confidence+0.01, 1.0) WHERE entity_id=?",
            (entity_id,),
        )

    def decay_stale_entities(self, min_confidence: float = 0.2) -> int:
        """
        Decay confidence of entities not reinforced recently.
        Quarantine entities below min_confidence.
        Returns number of quarantined entities.
        """
        self.db.execute(
            """
            UPDATE entities SET confidence = MAX(confidence - ?, 0.0)
            WHERE entity_id NOT IN (
                SELECT DISTINCT json_each.value
                FROM memory_units, json_each(memory_units.entity_tags)
            )
            """,
            (ENTITY_CONFIDENCE_DECAY,),
        )
        quarantined = self.db.execute(
            "SELECT COUNT(*) FROM entities WHERE confidence < ?", (min_confidence,)
        ).fetchone()[0]
        self.db.commit()
        return quarantined

    def get_entity_by_alias(self, alias: str) -> Optional[Entity]:
        """Resolve any alias or name to canonical Entity."""
        # Direct name match
        row = self.db.execute(
            "SELECT entity_id, entity_name, entity_type, confidence FROM entities WHERE entity_name = ?",
            (alias,),
        ).fetchone()
        if row:
            return Entity(**dict(row))
        # Alias lookup
        alias_row = self.db.execute(
            """
            SELECT e.entity_id, e.entity_name, e.entity_type, e.confidence
            FROM entity_aliases ea JOIN entities e ON ea.entity_id = e.entity_id
            WHERE ea.alias_text = ?
            """,
            (alias,),
        ).fetchone()
        if alias_row:
            return Entity(**dict(alias_row))
        return None
