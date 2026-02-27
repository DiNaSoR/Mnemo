#!/usr/bin/env python3
"""
ingest_pipeline.py - Autonomous ingestion and chunking with typed metadata.

Detects changed .md files in .mnemo/memory/ (with bridge fallback), chunks them with context-aware
splitting, classifies memory type, and upserts into the DB as memory_units
with full metadata (authority, time_scope, sensitivity, entity_tags).
"""
import hashlib
import json
import os
import re
import sqlite3
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from autonomy.schema import get_db
from autonomy.common import (
    SKIP_NAMES, SKIP_DIRS, MAX_CHUNK_CHARS, AUTHORITY_WEIGHTS,
    infer_memory_type as _infer_memory_type,
    infer_time_scope as _infer_time_scope,
    infer_sensitivity as _infer_sensitivity,
    chunk_markdown as _chunk_markdown,
)


def _resolve_memory_root(repo_root: Path) -> Path:
    override = os.getenv("MNEMO_MEMORY_ROOT", "").strip()
    if override:
        return Path(override).expanduser().resolve()

    candidates = [
        repo_root / ".mnemo" / "memory",
        repo_root / ".cursor" / "memory",
    ]
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return candidates[0]


@dataclass
class MemoryUnit:
    unit_id: str
    source_ref: str
    memory_type: str
    authority: float
    time_scope: str
    sensitivity: str
    entity_tags: list[str]
    content_hash: str
    content: str
    chunks: list[tuple[str, str]] = field(default_factory=list)  # (text, ref)
    is_new: bool = True


def _content_hash(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


class IngestPipeline:
    def __init__(self, db: Optional[sqlite3.Connection] = None, repo_root: Optional[Path] = None):
        self.db = db or get_db()
        self.repo_root = repo_root or Path.cwd()
        self.mem_root = _resolve_memory_root(self.repo_root)

    def detect_changes(self) -> list[Path]:
        """Return list of .md files that have changed hash."""
        changed: list[Path] = []
        for p in self.mem_root.glob("**/*.md"):
            if p.name in SKIP_NAMES:
                continue
            if any(skip in p.parts for skip in SKIP_DIRS):
                continue
            try:
                content = p.read_text(encoding="utf-8-sig")
                h = _content_hash(content)
                row = self.db.execute(
                    "SELECT hash FROM file_meta WHERE path = ?", (str(p),)
                ).fetchone()
                if not row or row["hash"] != h:
                    changed.append(p)
            except OSError:
                pass
        return changed

    def ingest_file(self, file_path: Path) -> list[MemoryUnit]:
        """Ingest a single file, create/update memory units, return list."""
        content = file_path.read_text(encoding="utf-8-sig")
        h = _content_hash(content)
        path_str = str(file_path)

        mem_type = _infer_memory_type(path_str)
        authority = AUTHORITY_WEIGHTS.get(mem_type, 0.5)
        time_scope = _infer_time_scope(mem_type)
        sensitivity = _infer_sensitivity(path_str)
        chunks = _chunk_markdown(content, file_path)

        existing_row = self.db.execute(
            "SELECT unit_id FROM memory_units WHERE source_ref = ?", (path_str,)
        ).fetchone()

        if existing_row:
            unit_id = existing_row["unit_id"]
            is_new = False
        else:
            unit_id = str(uuid.uuid4())
            is_new = True

        unit = MemoryUnit(
            unit_id=unit_id,
            source_ref=path_str,
            memory_type=mem_type,
            authority=authority,
            time_scope=time_scope,
            sensitivity=sensitivity,
            entity_tags=[],
            content_hash=h,
            content=content,
            chunks=chunks,
            is_new=is_new,
        )

        if is_new:
            self.db.execute(
                """
                INSERT INTO memory_units
                    (unit_id, source_ref, memory_type, authority, time_scope, sensitivity, entity_tags, content_hash)
                VALUES (?, ?, ?, ?, ?, ?, '[]', ?)
                """,
                (unit_id, path_str, mem_type, authority, time_scope, sensitivity, h),
            )
        else:
            self.db.execute(
                """
                UPDATE memory_units
                SET memory_type=?, authority=?, time_scope=?, sensitivity=?,
                    content_hash=?, updated_at=unixepoch('now')
                WHERE unit_id=?
                """,
                (mem_type, authority, time_scope, sensitivity, h, unit_id),
            )

        self.db.execute(
            "INSERT OR REPLACE INTO file_meta(path, hash, chunk_count, updated_at) VALUES (?,?,?,unixepoch('now'))",
            (path_str, h, len(chunks)),
        )
        self.db.commit()
        return [unit]

    def update_entity_tags(self, unit: MemoryUnit, entity_ids: list[str]) -> None:
        """Persist resolved entity tags back to the unit row."""
        unit.entity_tags = entity_ids
        self.db.execute(
            "UPDATE memory_units SET entity_tags=?, updated_at=unixepoch('now') WHERE unit_id=?",
            (json.dumps(entity_ids), unit.unit_id),
        )
        self.db.commit()
