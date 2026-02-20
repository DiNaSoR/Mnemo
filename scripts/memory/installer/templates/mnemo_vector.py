#!/usr/bin/env python3
"""
Mnemo vector memory engine (v2).
Optional semantic layer for .cursor/memory with MCP tools.
Schema v2 adds typed memory units, fact lifecycle tables, and entity tags.
"""
import os
import re
import json
import sqlite3
import hashlib
from pathlib import Path

import sqlite_vec
try:
    from sqlite_vec import serialize_float32 as serialize_f32
except ImportError:
    from sqlite_vec import serialize_f32  # backwards compatibility
from mcp.server.fastmcp import FastMCP

SCHEMA_VERSION = 2
EMBED_DIM = 1536
MEM_ROOT = Path(".cursor/memory")
DB_PATH = MEM_ROOT / "mnemo_vector.sqlite"
PROVIDER = os.getenv("MNEMO_PROVIDER", "openai").lower()

SKIP_NAMES = {
    "README.md", "index.md", "lessons-index.json",
    "journal-index.json", "journal-index.md",
}
SKIP_DIRS = {"legacy", "templates"}
MAX_EMBED_CHARS = 12000
BATCH_SIZE = 16 if PROVIDER == "gemini" else 64
_EMBED_CLIENT = None

# Memory type authority weights for reranking
AUTHORITY_WEIGHTS = {
    "core": 1.0,       # hot-rules.md
    "procedural": 0.9, # lessons
    "episodic": 0.7,   # journal/active-context
    "semantic": 0.8,   # digests/memo
    "resource": 0.5,   # general docs
    "vault": 0.0,      # redacted unless authorized
}

# File → memory_type mapping
def _infer_memory_type(path_str: str) -> str:
    p = path_str.lower().replace("\\", "/")
    if "hot-rules" in p or "memo.md" in p:
        return "core"
    if "/lessons/" in p and "/l-" in p:
        return "procedural"
    if "/journal/" in p or "active-context" in p:
        return "episodic"
    if "/digests/" in p:
        return "semantic"
    if "/vault/" in p:
        return "vault"
    return "semantic"


def _infer_time_scope(memory_type: str) -> str:
    if memory_type in ("episodic",):
        return "recency-sensitive"
    if memory_type in ("core", "procedural"):
        return "atemporal"
    return "time-bound"


mcp = FastMCP("MnemoVector")


def _trim_for_embedding(text: str) -> str:
    return text[:MAX_EMBED_CHARS] if len(text) > MAX_EMBED_CHARS else text


def _get_embed_client():
    global _EMBED_CLIENT
    if _EMBED_CLIENT is not None:
        return _EMBED_CLIENT

    if PROVIDER == "gemini":
        key = os.getenv("GEMINI_API_KEY")
        if not key:
            raise RuntimeError("GEMINI_API_KEY is not set")
        from google import genai
        _EMBED_CLIENT = genai.Client(api_key=key)
        return _EMBED_CLIENT

    key = os.getenv("OPENAI_API_KEY")
    if not key:
        raise RuntimeError("OPENAI_API_KEY is not set")
    from openai import OpenAI
    _EMBED_CLIENT = OpenAI(api_key=key)
    return _EMBED_CLIENT


def get_embeddings(texts: list[str]) -> list[list[float]]:
    if not texts:
        return []
    trimmed = [_trim_for_embedding(t) for t in texts]
    client = _get_embed_client()

    if PROVIDER == "gemini":
        from google.genai import types
        result = client.models.embed_content(
            model="gemini-embedding-001",
            contents=trimmed,
            config=types.EmbedContentConfig(output_dimensionality=EMBED_DIM),
        )
        vectors = [emb.values for emb in result.embeddings]
    else:
        resp = client.embeddings.create(input=trimmed, model="text-embedding-3-small")
        vectors = [item.embedding for item in resp.data]

    if len(vectors) != len(trimmed):
        raise RuntimeError(f"Embedding provider returned {len(vectors)} vectors for {len(trimmed)} inputs")
    return vectors


def get_embedding(text: str) -> list[float]:
    return get_embeddings([text])[0]


def get_db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(str(DB_PATH), timeout=30)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA busy_timeout=10000")
    db.enable_load_extension(True)
    sqlite_vec.load(db)
    return db


def init_db() -> sqlite3.Connection:
    db = get_db()
    db.execute("CREATE TABLE IF NOT EXISTS schema_info (key TEXT PRIMARY KEY, value TEXT)")
    row = db.execute("SELECT value FROM schema_info WHERE key='version'").fetchone()
    ver = int(row[0]) if row else 0

    if ver < 1:
        db.execute("DROP TABLE IF EXISTS file_meta")
        db.execute("DROP TABLE IF EXISTS vec_memory")
        db.execute(
            """
            CREATE TABLE file_meta (
                path TEXT PRIMARY KEY,
                hash TEXT NOT NULL,
                chunk_count INTEGER DEFAULT 0,
                updated_at REAL DEFAULT (unixepoch('now'))
            )
            """
        )
        db.execute(
            f"""
            CREATE VIRTUAL TABLE vec_memory USING vec0(
                embedding float[{EMBED_DIM}] distance_metric=cosine,
                +ref_path TEXT,
                +content TEXT,
                +source_file TEXT
            )
            """
        )

    if ver < SCHEMA_VERSION:
        # v2: typed memory units, fact lifecycle, entity tables
        db.execute(
            """
            CREATE TABLE IF NOT EXISTS memory_units (
                unit_id      TEXT PRIMARY KEY,
                source_ref   TEXT NOT NULL,
                memory_type  TEXT NOT NULL DEFAULT 'semantic',
                authority    REAL NOT NULL DEFAULT 0.5,
                time_scope   TEXT NOT NULL DEFAULT 'time-bound',
                sensitivity  TEXT NOT NULL DEFAULT 'public',
                entity_tags  TEXT NOT NULL DEFAULT '[]',
                content_hash TEXT NOT NULL,
                created_at   REAL DEFAULT (unixepoch('now')),
                updated_at   REAL DEFAULT (unixepoch('now'))
            )
            """
        )
        db.execute(
            """
            CREATE TABLE IF NOT EXISTS facts (
                fact_id        TEXT PRIMARY KEY,
                canonical_fact TEXT NOT NULL,
                status         TEXT NOT NULL DEFAULT 'active',
                confidence     REAL NOT NULL DEFAULT 1.0,
                source_ref     TEXT NOT NULL,
                created_at     REAL DEFAULT (unixepoch('now')),
                updated_at     REAL DEFAULT (unixepoch('now'))
            )
            """
        )
        db.execute(
            """
            CREATE TABLE IF NOT EXISTS lifecycle_events (
                event_id   TEXT PRIMARY KEY,
                unit_id    TEXT NOT NULL,
                operation  TEXT NOT NULL,
                old_status TEXT,
                new_status TEXT,
                reason     TEXT,
                ts         REAL DEFAULT (unixepoch('now'))
            )
            """
        )
        db.execute(
            """
            CREATE TABLE IF NOT EXISTS entities (
                entity_id   TEXT PRIMARY KEY,
                entity_name TEXT NOT NULL,
                entity_type TEXT NOT NULL DEFAULT 'general',
                confidence  REAL NOT NULL DEFAULT 1.0,
                created_at  REAL DEFAULT (unixepoch('now'))
            )
            """
        )
        db.execute(
            """
            CREATE TABLE IF NOT EXISTS entity_aliases (
                alias_id    TEXT PRIMARY KEY,
                entity_id   TEXT NOT NULL,
                alias_text  TEXT NOT NULL,
                confidence  REAL NOT NULL DEFAULT 1.0
            )
            """
        )
        db.execute(
            "INSERT OR REPLACE INTO schema_info(key, value) VALUES ('version', ?)",
            (str(SCHEMA_VERSION),),
        )
        db.commit()
    return db


def _upsert_memory_unit(db: sqlite3.Connection, ref_path: str, content_hash: str) -> str:
    import uuid
    mem_type = _infer_memory_type(ref_path)
    auth = AUTHORITY_WEIGHTS.get(mem_type, 0.5)
    time_scope = _infer_time_scope(mem_type)

    existing = db.execute(
        "SELECT unit_id FROM memory_units WHERE source_ref = ?", (ref_path,)
    ).fetchone()

    if existing:
        unit_id = existing[0]
        db.execute(
            "UPDATE memory_units SET content_hash=?, authority=?, updated_at=unixepoch('now') WHERE unit_id=?",
            (content_hash, auth, unit_id),
        )
    else:
        unit_id = str(uuid.uuid4())
        db.execute(
            """
            INSERT INTO memory_units(unit_id, source_ref, memory_type, authority, time_scope, sensitivity, entity_tags, content_hash)
            VALUES (?, ?, ?, ?, ?, 'public', '[]', ?)
            """,
            (unit_id, ref_path, mem_type, auth, time_scope, content_hash),
        )
        # Log ADD lifecycle event
        db.execute(
            "INSERT INTO lifecycle_events(event_id, unit_id, operation, new_status, reason) VALUES (?,?,'ADD',NULL,'initial_index')",
            (str(uuid.uuid4()), unit_id),
        )
    return unit_id


def chunk_markdown(content: str, file_path: Path) -> list[tuple[str, str]]:
    chunks: list[tuple[str, str]] = []
    path_str = str(file_path).replace("\\", "/")

    if "journal/" in path_str.lower():
        parts = re.split(r"^(##\s+\d{4}-\d{2}-\d{2})", content, flags=re.MULTILINE)
        preamble = parts[0].strip()
        if preamble:
            chunks.append((preamble, f"@{path_str}"))
        i = 1
        while i < len(parts) - 1:
            heading = parts[i].strip()
            body = parts[i + 1].strip()
            date = heading.replace("##", "").strip()
            chunks.append((f"{heading}\n{body}".strip(), f"@{path_str}# {date}"))
            i += 2
        if chunks:
            return chunks

    if file_path.parent.name == "lessons" and file_path.name.startswith("L-"):
        text = content.strip()
        if text:
            m = re.match(r"(L-\d{3})", file_path.name)
            ref = f"@{path_str}# {m.group(1)}" if m else f"@{path_str}"
            chunks.append((text, ref))
        return chunks

    parts = re.split(r"^(#{1,4}\s+.+)$", content, flags=re.MULTILINE)
    preamble = parts[0].strip()
    if preamble:
        chunks.append((preamble, f"@{path_str}"))

    i = 1
    while i < len(parts) - 1:
        heading_line = parts[i].strip()
        body = parts[i + 1].strip()
        heading_text = re.sub(r"^#{1,4}\s+", "", heading_line)
        full = f"{heading_line}\n{body}".strip() if body else heading_line
        if full.strip():
            chunks.append((full, f"@{path_str}# {heading_text}"))
        i += 2

    if not chunks and content.strip():
        chunks.append((content.strip(), f"@{path_str}"))
    return chunks


@mcp.tool()
def vector_sync() -> str:
    try:
        db = init_db()
    except Exception as e:
        return f"DB init failed: {e}"

    files: dict[str, Path] = {}
    for p in MEM_ROOT.glob("**/*.md"):
        if p.name in SKIP_NAMES:
            continue
        if any(skip in p.parts for skip in SKIP_DIRS):
            continue
        files[str(p)] = p

    updated = 0
    skipped = 0
    errors = 0

    known = db.execute("SELECT path FROM file_meta").fetchall()
    for (stored,) in known:
        if stored not in files:
            db.execute("DELETE FROM vec_memory WHERE source_file = ?", (stored,))
            db.execute("DELETE FROM file_meta WHERE path = ?", (stored,))
            updated += 1

    for str_path, file_path in files.items():
        try:
            content = file_path.read_text(encoding="utf-8-sig")
        except (UnicodeDecodeError, PermissionError, OSError):
            errors += 1
            continue

        if not content.strip():
            skipped += 1
            continue

        f_hash = hashlib.sha256(content.encode("utf-8")).hexdigest()
        row = db.execute("SELECT hash FROM file_meta WHERE path = ?", (str_path,)).fetchone()
        if row and row[0] == f_hash:
            skipped += 1
            continue

        db.execute("DELETE FROM vec_memory WHERE source_file = ?", (str_path,))
        _upsert_memory_unit(db, str_path, f_hash)
        chunks = chunk_markdown(content, file_path)
        embedded = 0
        chunk_errors = 0

        for i in range(0, len(chunks), BATCH_SIZE):
            batch = chunks[i : i + BATCH_SIZE]
            texts = [text for text, _ in batch]
            try:
                vectors = get_embeddings(texts)
                for (text, ref), emb in zip(batch, vectors):
                    db.execute(
                        "INSERT INTO vec_memory(embedding, ref_path, content, source_file) VALUES (?, ?, ?, ?)",
                        (serialize_f32(emb), ref, text, str_path),
                    )
                    embedded += 1
            except Exception:
                for text, ref in batch:
                    try:
                        emb = get_embedding(text)
                        db.execute(
                            "INSERT INTO vec_memory(embedding, ref_path, content, source_file) VALUES (?, ?, ?, ?)",
                            (serialize_f32(emb), ref, text, str_path),
                        )
                        embedded += 1
                    except Exception:
                        chunk_errors += 1

        if chunk_errors == 0:
            db.execute(
                "INSERT OR REPLACE INTO file_meta(path, hash, chunk_count, updated_at) VALUES (?, ?, ?, unixepoch('now'))",
                (str_path, f_hash, embedded),
            )
        else:
            db.execute(
                "INSERT OR REPLACE INTO file_meta(path, hash, chunk_count, updated_at) VALUES (?, ?, ?, unixepoch('now'))",
                (str_path, "DIRTY", embedded),
            )
            errors += chunk_errors
        updated += 1

    db.commit()
    db.close()
    msg = f"Synced: {updated} files processed, {skipped} unchanged"
    if errors:
        msg += f", {errors} chunk errors (will retry)"
    return msg


@mcp.tool()
def vector_search(query: str, top_k: int = 5) -> str:
    """Semantic search with authority-aware reranking."""
    try:
        db = init_db()
        emb = get_embedding(query)
        rows = db.execute(
            "SELECT ref_path, content, distance FROM vec_memory WHERE embedding MATCH ? AND k = ? ORDER BY distance",
            (serialize_f32(emb), top_k * 3),  # over-fetch for reranking
        ).fetchall()
        db.close()
    except Exception as e:
        return f"Search failed: {e}"

    if not rows:
        return "No relevant memory found."

    # Rerank: combine semantic score with authority weight
    reranked = []
    for ref, content, dist in rows:
        sem_score = round(1.0 - dist, 4)
        mem_type = _infer_memory_type(ref)
        auth_weight = AUTHORITY_WEIGHTS.get(mem_type, 0.5)
        # Skip vault entries entirely (sensitivity guard)
        if mem_type == "vault":
            continue
        # Temporal boost for recency-sensitive types when query mentions time words
        temporal_boost = 0.0
        time_words = {"today", "yesterday", "last week", "last month", "recent", "latest"}
        if mem_type == "episodic" and any(w in query.lower() for w in time_words):
            temporal_boost = 0.1
        final_score = (sem_score * 0.6) + (auth_weight * 0.3) + temporal_boost
        reranked.append((ref, content, sem_score, auth_weight, final_score))

    reranked.sort(key=lambda x: x[4], reverse=True)
    top = reranked[:top_k]

    out = []
    for ref, content, sem, auth, final in top:
        preview = " ".join(content[:400].split())
        out.append(f"[score={final:.3f} sem={sem:.3f} auth={auth:.2f}] {ref}\n{preview}")
    return "\n\n---\n\n".join(out)


@mcp.tool()
def vector_forget(path_pattern: str = "") -> str:
    try:
        db = init_db()
        removed = 0
        if path_pattern:
            like = f"%{path_pattern}%"
            r1 = db.execute("DELETE FROM vec_memory WHERE source_file LIKE ?", (like,)).rowcount
            r2 = db.execute("DELETE FROM file_meta WHERE path LIKE ?", (like,)).rowcount
            db.execute("DELETE FROM memory_units WHERE source_ref LIKE ?", (like,))
            removed = max(r1, r2)
        else:
            known = db.execute("SELECT path FROM file_meta").fetchall()
            for (p,) in known:
                if not Path(p).exists():
                    db.execute("DELETE FROM vec_memory WHERE source_file = ?", (p,))
                    db.execute("DELETE FROM file_meta WHERE path = ?", (p,))
                    db.execute("DELETE FROM memory_units WHERE source_ref = ?", (p,))
                    removed += 1
        db.commit()
        db.close()
        return f"Pruned {removed} entries."
    except Exception as e:
        return f"Forget failed: {e}"


@mcp.tool()
def vector_health() -> str:
    lines = []
    try:
        db = init_db()
        ver = db.execute("SELECT value FROM schema_info WHERE key='version'").fetchone()
        lines.append(f"Schema: v{ver[0] if ver else '?'}")
        files = db.execute("SELECT COUNT(*) FROM file_meta").fetchone()[0]
        vecs = db.execute("SELECT COUNT(*) FROM vec_memory").fetchone()[0]
        dirty = db.execute("SELECT COUNT(*) FROM file_meta WHERE hash = 'DIRTY'").fetchone()[0]
        units = db.execute("SELECT COUNT(*) FROM memory_units").fetchone()[0]
        facts = db.execute("SELECT COUNT(*) FROM facts WHERE status = 'active'").fetchone()[0]
        lines.append(f"Files tracked: {files}")
        lines.append(f"Vector chunks: {vecs}")
        lines.append(f"Memory units: {units}")
        lines.append(f"Active facts: {facts}")
        if dirty:
            lines.append(f"Dirty files: {dirty}")
        lines.append(f"DB integrity: {db.execute('PRAGMA integrity_check').fetchone()[0]}")
        db.close()
    except Exception as e:
        lines.append(f"DB error: {e}")

    try:
        _ = get_embedding("health check")
        lines.append(f"Embedding API ({PROVIDER}): OK")
    except Exception as e:
        lines.append(f"Embedding API ({PROVIDER}): FAILED - {e}")
    return "\n".join(lines)


@mcp.tool()
def memory_status() -> str:
    """Return a JSON summary of memory system status for autonomous monitoring."""
    try:
        db = init_db()
        files = db.execute("SELECT COUNT(*) FROM file_meta").fetchone()[0]
        vecs = db.execute("SELECT COUNT(*) FROM vec_memory").fetchone()[0]
        dirty = db.execute("SELECT COUNT(*) FROM file_meta WHERE hash = 'DIRTY'").fetchone()[0]
        units = db.execute("SELECT COUNT(*) FROM memory_units").fetchone()[0]
        facts_active = db.execute("SELECT COUNT(*) FROM facts WHERE status = 'active'").fetchone()[0]
        facts_deprecated = db.execute("SELECT COUNT(*) FROM facts WHERE status = 'deprecated'").fetchone()[0]
        events = db.execute("SELECT COUNT(*) FROM lifecycle_events").fetchone()[0]
        type_dist = db.execute(
            "SELECT memory_type, COUNT(*) FROM memory_units GROUP BY memory_type"
        ).fetchall()
        db.close()
        return json.dumps({
            "files": files, "vectors": vecs, "dirty": dirty,
            "memory_units": units, "facts_active": facts_active,
            "facts_deprecated": facts_deprecated, "lifecycle_events": events,
            "type_distribution": dict(type_dist),
        }, indent=2)
    except Exception as e:
        return json.dumps({"error": str(e)})


if __name__ == "__main__":
    mcp.run()
