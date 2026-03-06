#!/usr/bin/env python3
"""
lifecycle_engine.py - Autonomous fact lifecycle engine.

Decides ADD / UPDATE / DEPRECATE / NOOP for each memory unit based on
similarity to existing facts, freshness, and contradiction detection.
All decisions are logged to lifecycle_events for full auditability.

No human required: transitions happen automatically on every ingest cycle.
"""
import hashlib
import json
import os
import re
import sqlite3
import uuid
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from autonomy.contradiction import compare_texts
from autonomy.schema import get_db
from autonomy.ingest_pipeline import MemoryUnit
from autonomy.token_counter import resolve_policy_path

PROMOTE_STABILITY_CYCLES = 3  # fact must appear N cycles before lesson promotion
NOOP_HASH_MATCH = True  # if content_hash unchanged, always NOOP


@dataclass
class LifecycleDecision:
    operation: str  # ADD | UPDATE | DEPRECATE | NOOP
    unit_id: str
    fact_id: Optional[str]
    reason: str
    confidence: float = 1.0
    contradiction_method: Optional[str] = None


def _extract_key_facts(content: str, memory_type: str) -> list[str]:
    """
    Heuristic extraction of canonical facts from content.
    Returns list of short declarative sentences.
    """
    facts = []

    # Hot rules / lessons: extract bullet points as facts
    if memory_type in ("core", "procedural"):
        for m in re.finditer(r"^[-*]\s+(.+)", content, re.MULTILINE):
            fact = m.group(1).strip()
            if len(fact) > 10:
                facts.append(fact)

    # Journal / active-context: extract decision lines
    if memory_type in ("episodic",):
        for m in re.finditer(r"(decided|confirmed|fixed|added|removed|changed):\s*(.+)", content, re.IGNORECASE):
            facts.append(m.group(0).strip())

    # Generic: extract first sentence of each section
    for m in re.finditer(r"^#{1,4}\s+(.+)\n+(.*?)(?:\n|$)", content, re.MULTILINE):
        heading = m.group(1).strip()
        body = m.group(2).strip()
        if body:
            facts.append(f"{heading}: {body}")

    return facts[:20]  # cap to prevent runaway


def _resolve_lessons_dir(repo_root: Path) -> Path:
    override = os.getenv("MNEMO_MEMORY_ROOT", "").strip()
    if override:
        return Path(override).expanduser().resolve() / "lessons"

    candidates = [
        repo_root / ".mnemo" / "memory" / "lessons",
        repo_root / ".cursor" / "memory" / "lessons",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


class LifecycleEngine:
    def __init__(
        self,
        db: Optional[sqlite3.Connection] = None,
        use_embedding_contradictions: Optional[bool] = None,
        contradiction_anchor_threshold: Optional[float] = None,
        contradiction_embed_threshold: Optional[float] = None,
        contradiction_mode: Optional[str] = None,
        contradiction_min_frame_confidence: Optional[float] = None,
        require_embedding_confirmation: Optional[bool] = None,
    ):
        self.db = db or get_db()
        policy = self._load_policy()
        contradiction_cfg = policy.get("contradiction", {}) if isinstance(policy, dict) else {}
        if not isinstance(contradiction_cfg, dict):
            contradiction_cfg = {}

        if use_embedding_contradictions is None:
            self.use_embedding_contradictions = bool(contradiction_cfg.get("use_embeddings", False))
        else:
            self.use_embedding_contradictions = bool(use_embedding_contradictions)
        self.contradiction_anchor_threshold = (
            float(contradiction_anchor_threshold)
            if contradiction_anchor_threshold is not None
            else float(contradiction_cfg.get("anchor_similarity_threshold", 0.45))
        )
        self.contradiction_embed_threshold = (
            float(contradiction_embed_threshold)
            if contradiction_embed_threshold is not None
            else float(contradiction_cfg.get("embedding_similarity_threshold", 0.72))
        )
        self.contradiction_mode = (
            str(contradiction_mode).strip().lower()
            if contradiction_mode is not None
            else str(contradiction_cfg.get("mode", "hybrid")).strip().lower()
        )
        self.contradiction_min_frame_confidence = (
            float(contradiction_min_frame_confidence)
            if contradiction_min_frame_confidence is not None
            else float(contradiction_cfg.get("min_frame_confidence", 0.55))
        )
        if require_embedding_confirmation is None:
            self.require_embedding_confirmation = bool(contradiction_cfg.get("require_embedding_confirmation", False))
        else:
            self.require_embedding_confirmation = bool(require_embedding_confirmation)

    def _load_policy(self) -> dict:
        policy_path = resolve_policy_path()
        if policy_path is None or not policy_path.exists():
            return {}
        try:
            import yaml  # type: ignore
        except Exception:
            return {}
        try:
            payload = yaml.safe_load(policy_path.read_text(encoding="utf-8"))
            return payload if isinstance(payload, dict) else {}
        except Exception:
            return {}

    def process(self, unit: MemoryUnit) -> LifecycleDecision:
        """
        Process a memory unit through the lifecycle state machine.
        Emits a lifecycle_event and returns the decision.
        """
        existing_hash = self.db.execute(
            "SELECT content_hash FROM memory_units WHERE unit_id = ?",
            (unit.unit_id,),
        ).fetchone()

        if existing_hash and NOOP_HASH_MATCH and existing_hash["content_hash"] == unit.content_hash:
            decision = LifecycleDecision("NOOP", unit.unit_id, None, "content_hash_unchanged")
            self._log_event(decision)
            return decision

        facts = _extract_key_facts(unit.content, unit.memory_type)
        if not facts:
            decision = LifecycleDecision("NOOP", unit.unit_id, None, "no_extractable_facts")
            self._log_event(decision)
            return decision

        existing_facts = self.db.execute(
            "SELECT fact_id, canonical_fact, status, confidence FROM facts WHERE source_ref = ?",
            (unit.source_ref,),
        ).fetchall()

        # Check for contradiction / supersession in global facts
        contradictions = self._detect_contradictions(facts)
        for old_fact_id, old_fact_text, contradiction_method in contradictions:
            self.db.execute(
                "UPDATE facts SET status='deprecated', updated_at=unixepoch('now') WHERE fact_id=?",
                (old_fact_id,),
            )
            dep_decision = LifecycleDecision(
                "DEPRECATE", unit.unit_id, old_fact_id,
                reason=f"superseded_by_unit:{unit.unit_id}:{contradiction_method}",
                confidence=0.8,
                contradiction_method=contradiction_method,
            )
            self._log_event(dep_decision)

        if existing_facts:
            # UPDATE existing facts from this source
            for ef in existing_facts:
                self.db.execute(
                    "UPDATE facts SET status='active', confidence=?, updated_at=unixepoch('now') WHERE fact_id=?",
                    (min(ef["confidence"] + 0.05, 1.0), ef["fact_id"]),
                )
            decision = LifecycleDecision("UPDATE", unit.unit_id, existing_facts[0]["fact_id"], "source_file_changed")
        else:
            # ADD new facts
            for fact_text in facts[:5]:  # cap facts per unit
                fact_id = str(uuid.uuid4())
                self.db.execute(
                    "INSERT INTO facts(fact_id, canonical_fact, status, confidence, source_ref) VALUES (?,?,'active',1.0,?)",
                    (fact_id, fact_text, unit.source_ref),
                )
            decision = LifecycleDecision("ADD", unit.unit_id, None, f"new_unit_{len(facts)}_facts_extracted")

        self._log_event(decision)
        self.db.commit()
        return decision

    def _detect_contradictions(self, new_facts: list[str]) -> list[tuple[str, str, str]]:
        """
        Find existing active facts that are semantically contradicted by new_facts.
        Uses polarity-aware shared-anchor contradiction matching.
        Optional embedding enhancement applies when dependency is installed and enabled.
        Bounded to most recent 200 facts to prevent full-table scans at scale.
        """
        contradicted: list[tuple[str, str, str]] = []
        existing = self.db.execute(
            "SELECT fact_id, canonical_fact FROM facts WHERE status = 'active' ORDER BY updated_at DESC LIMIT 200"
        ).fetchall()

        seen_fact_ids: set[str] = set()
        for ef in existing:
            ef_text = ef["canonical_fact"]
            for new_fact in new_facts:
                match = compare_texts(
                    new_fact,
                    ef_text,
                    use_embeddings=self.use_embedding_contradictions,
                    anchor_threshold=self.contradiction_anchor_threshold,
                    embed_threshold=self.contradiction_embed_threshold,
                    mode=self.contradiction_mode,
                    min_frame_confidence=self.contradiction_min_frame_confidence,
                    require_embedding_confirmation=self.require_embedding_confirmation,
                )
                if match is None:
                    continue
                if ef["fact_id"] in seen_fact_ids:
                    continue
                seen_fact_ids.add(ef["fact_id"])
                contradicted.append((ef["fact_id"], ef_text, match.method))
        return contradicted

    def _log_event(self, decision: LifecycleDecision) -> None:
        self.db.execute(
            "INSERT INTO lifecycle_events(event_id, unit_id, operation, reason) VALUES (?,?,?,?)",
            (str(uuid.uuid4()), decision.unit_id, decision.operation, decision.reason),
        )

    def promote_lessons(self, repo_root: Path) -> list[str]:
        """
        Auto-promote stable repeated signals into lesson files.
        A fact qualifies when: status=active AND confidence >= 0.95
        AND no lesson already covers the source_ref.
        Returns list of created lesson paths.
        """
        candidates = self.db.execute(
            """
            SELECT f.fact_id, f.canonical_fact, f.source_ref, f.confidence
            FROM facts f
            WHERE f.status = 'active' AND f.confidence >= 0.95
              AND f.source_ref NOT LIKE '%lessons/L-%'
            ORDER BY f.confidence DESC
            LIMIT 5
            """
        ).fetchall()

        promoted = []
        lessons_dir = _resolve_lessons_dir(repo_root)
        lessons_dir.mkdir(parents=True, exist_ok=True)

        existing = sorted(lessons_dir.glob("L-*.md"))
        next_id = 1
        if existing:
            m = re.match(r"L-(\d+)", existing[-1].name)
            if m:
                next_id = int(m.group(1)) + 1

        for row in candidates:
            fact_text = row["canonical_fact"][:200]
            lesson_id = f"L-{next_id:03d}"
            slug = re.sub(r"[^a-z0-9]+", "-", fact_text.lower())[:40].strip("-")
            lesson_file = lessons_dir / f"{lesson_id}-{slug}.md"

            if lesson_file.exists():
                continue

            today = datetime.now().strftime("%Y-%m-%d")
            content = (
                f"---\nid: {lesson_id}\ntitle: {fact_text[:80]}\nstatus: Active\n"
                f"tags: [Process]\nintroduced: {today}\napplies_to:\n  - \"**/*\"\n"
                f"triggers:\n  - auto-promoted\nrule: {fact_text[:120]}\n---\n\n"
                f"# {lesson_id} - Auto-Promoted Lesson\n\n"
                f"**Source:** `{row['source_ref']}`\n\n"
                f"**Canonical fact:** {fact_text}\n\n"
                f"> This lesson was auto-promoted by the Mnemo autonomous runner.\n"
                f"> Review and edit the rule to ensure accuracy.\n"
            )
            lesson_file.write_text(content, encoding="utf-8")
            promoted.append(str(lesson_file))

            # Mark fact as promoted
            self.db.execute(
                "UPDATE facts SET status='promoted', updated_at=unixepoch('now') WHERE fact_id=?",
                (row["fact_id"],),
            )
            next_id += 1

        if promoted:
            self.db.commit()
        return promoted
