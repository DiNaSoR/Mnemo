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

SKIP_NAMES = frozenset({"README.md", "index.md", "lessons-index.json",
                        "journal-index.json", "journal-index.md"})
SKIP_DIRS = frozenset({"legacy", "templates"})
MAX_CHUNK_CHARS = 10000


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


AUTHORITY_WEIGHTS: dict[str, float] = {
    "core": 1.0,
    "procedural": 0.9,
    "semantic": 0.8,
    "episodic": 0.7,
    "resource": 0.5,
    "vault": 0.0,
}


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


def _infer_memory_type(path_str: str) -> str:
    p = path_str.lower().replace("\\", "/")
    if "hot-rules" in p or "memo.md" in p:
        return "core"
    if "/lessons/" in p and re.search(r"/l-\d+", p):
        return "procedural"
    if "/journal/" in p or "active-context" in p:
        return "episodic"
    if "/digests/" in p:
        return "semantic"
    if "/vault/" in p:
        return "vault"
    if "/adr/" in p:
        return "semantic"
    return "semantic"


def _infer_time_scope(memory_type: str) -> str:
    if memory_type == "episodic":
        return "recency-sensitive"
    if memory_type in ("core", "procedural"):
        return "atemporal"
    return "time-bound"


def _infer_sensitivity(path_str: str) -> str:
    p = path_str.lower()
    if "/vault/" in p or "secret" in p or ".secret." in p:
        return "secret"
    return "public"


def _content_hash(content: str) -> str:
    return hashlib.sha256(content.encode("utf-8")).hexdigest()


def _chunk_markdown(content: str, file_path: Path) -> list[tuple[str, str]]:
    """Split markdown content into (text, ref_path) chunks."""
    chunks: list[tuple[str, str]] = []
    path_str = str(file_path).replace("\\", "/")

    # Journal: split by date headings
    if "journal/" in path_str.lower():
        parts = re.split(r"^(##\s+\d{4}-\d{2}-\d{2})", content, flags=re.MULTILINE)
        preamble = parts[0].strip()
        if preamble:
            chunks.append((preamble, f"@{path_str}"))
        i = 1
        while i < len(parts) - 1:
            heading = parts[i].strip()
            body = parts[i + 1].strip()
            date_val = heading.replace("##", "").strip()
            chunk_text = f"{heading}\n{body}".strip()
            if chunk_text:
                chunks.append((chunk_text[:MAX_CHUNK_CHARS], f"@{path_str}#{date_val}"))
            i += 2
        return chunks

    # Lessons: single chunk per lesson file
    if re.search(r"/lessons/l-\d+", path_str.lower()):
        text = content.strip()
        if text:
            m = re.match(r"(L-\d{3})", file_path.name)
            ref = f"@{path_str}#{m.group(1)}" if m else f"@{path_str}"
            chunks.append((text[:MAX_CHUNK_CHARS], ref))
        return chunks

    # General: split by headers
    parts = re.split(r"^(#{1,4}\s+.+)$", content, flags=re.MULTILINE)
    preamble = parts[0].strip()
    if preamble:
        chunks.append((preamble[:MAX_CHUNK_CHARS], f"@{path_str}"))

    i = 1
    while i < len(parts) - 1:
        heading_line = parts[i].strip()
        body = parts[i + 1].strip()
        heading_text = re.sub(r"^#{1,4}\s+", "", heading_line)
        full = f"{heading_line}\n{body}".strip() if body else heading_line
        if full:
            chunks.append((full[:MAX_CHUNK_CHARS], f"@{path_str}#{heading_text}"))
        i += 2

    if not chunks and content.strip():
        chunks.append((content.strip()[:MAX_CHUNK_CHARS], f"@{path_str}"))
    return chunks


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
