#!/usr/bin/env python3
"""
common.py - Shared constants, types, and utilities for Mnemo autonomy and vector modules.

Single source of truth for memory type classification, authority weights,
skip lists, and chunk sizing used by both mnemo_vector.py and autonomy modules.
"""
import re
from pathlib import Path
from typing import Callable

SKIP_NAMES = frozenset({
    "README.md", "index.md", "lessons-index.json",
    "journal-index.json", "journal-index.md",
})

SKIP_DIRS = frozenset({"legacy", "templates"})

MAX_CHUNK_CHARS = 10000
MAX_EMBED_CHARS = 12000

AUTHORITY_WEIGHTS: dict[str, float] = {
    "core": 1.0,
    "procedural": 0.9,
    "semantic": 0.8,
    "episodic": 0.7,
    "resource": 0.5,
    "vault": 0.0,
}


def infer_memory_type(path_str: str) -> str:
    """Classify a memory file path into a memory type."""
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


def infer_time_scope(memory_type: str) -> str:
    """Derive the time scope from a memory type."""
    if memory_type == "episodic":
        return "recency-sensitive"
    if memory_type in ("core", "procedural"):
        return "atemporal"
    return "time-bound"


def infer_sensitivity(path_str: str) -> str:
    """Classify sensitivity from a file path."""
    p = path_str.lower()
    if "/vault/" in p or "secret" in p or ".secret." in p:
        return "secret"
    return "public"


def chunk_markdown(content: str, file_path: Path) -> list[tuple[str, str]]:
    """Split markdown content into (text, ref_path) chunks with context-aware splitting."""
    chunks: list[tuple[str, str]] = []
    path_str = str(file_path).replace("\\", "/")

    if "journal/" in path_str.lower():
        parts = re.split(r"^(##\s+\d{4}-\d{2}-\d{2})", content, flags=re.MULTILINE)
        preamble = parts[0].strip()
        if preamble:
            chunks.append((preamble[:MAX_CHUNK_CHARS], f"@{path_str}"))
        i = 1
        while i < len(parts) - 1:
            heading = parts[i].strip()
            body = parts[i + 1].strip()
            date_val = heading.replace("##", "").strip()
            chunk_text = f"{heading}\n{body}".strip()
            if chunk_text:
                chunks.append((chunk_text[:MAX_CHUNK_CHARS], f"@{path_str}#{date_val}"))
            i += 2
        if chunks:
            return chunks

    if file_path.parent.name == "lessons" and file_path.name.startswith("L-"):
        text = content.strip()
        if text:
            m = re.match(r"(L-\d{3})", file_path.name)
            ref = f"@{path_str}#{m.group(1)}" if m else f"@{path_str}"
            chunks.append((text[:MAX_CHUNK_CHARS], ref))
        return chunks

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
        if full.strip():
            chunks.append((full[:MAX_CHUNK_CHARS], f"@{path_str}#{heading_text}"))
        i += 2

    if not chunks and content.strip():
        chunks.append((content.strip()[:MAX_CHUNK_CHARS], f"@{path_str}"))
    return chunks
