#!/usr/bin/env python3
"""
schema.py - Mnemo typed memory schema v2.
Initializes and migrates the vector DB with full typed memory unit tables.
Used by all autonomy modules to get a DB connection with guaranteed schema.
"""
import sqlite3
import os
from pathlib import Path

import sqlite_vec

SCHEMA_VERSION = 2
EMBED_DIM = int(os.getenv("MNEMO_EMBED_DIM", "1536"))


def _db_path() -> Path:
    cwd = Path.cwd()
    candidate = cwd / ".cursor" / "memory" / "mnemo_vector.sqlite"
    if candidate.exists():
        return candidate
    # Walk up to find it
    for parent in cwd.parents:
        c = parent / ".cursor" / "memory" / "mnemo_vector.sqlite"
        if c.exists():
            return c
    return cwd / ".cursor" / "memory" / "mnemo_vector.sqlite"


def get_db(db_path: Path | None = None, timeout: float = 30.0) -> sqlite3.Connection:
    """Return a connected, migrated DB."""
    if db_path is None:
        db_path = _db_path()
    db_path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(str(db_path), timeout=timeout)
    db.row_factory = sqlite3.Row
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA foreign_keys=ON")
    db.execute("PRAGMA busy_timeout=10000")
    db.enable_load_extension(True)
    sqlite_vec.load(db)
    _migrate(db)
    return db


def _migrate(db: sqlite3.Connection) -> None:
    db.execute("CREATE TABLE IF NOT EXISTS schema_info (key TEXT PRIMARY KEY, value TEXT)")
    row = db.execute("SELECT value FROM schema_info WHERE key='version'").fetchone()
    ver = int(row["value"]) if row else 0

    if ver < 1:
        db.execute("DROP TABLE IF EXISTS file_meta")
        db.execute("DROP TABLE IF EXISTS vec_memory")
        db.execute("""
            CREATE TABLE file_meta (
                path        TEXT PRIMARY KEY,
                hash        TEXT NOT NULL,
                chunk_count INTEGER DEFAULT 0,
                updated_at  REAL DEFAULT (unixepoch('now'))
            )
        """)
        db.execute(f"""
            CREATE VIRTUAL TABLE vec_memory USING vec0(
                embedding float[{EMBED_DIM}] distance_metric=cosine,
                +ref_path TEXT,
                +content TEXT,
                +source_file TEXT
            )
        """)

    if ver < 2:
        db.execute("""
            CREATE TABLE IF NOT EXISTS memory_units (
                unit_id      TEXT PRIMARY KEY,
                source_ref   TEXT NOT NULL UNIQUE,
                memory_type  TEXT NOT NULL DEFAULT 'semantic',
                authority    REAL NOT NULL DEFAULT 0.5,
                time_scope   TEXT NOT NULL DEFAULT 'time-bound',
                sensitivity  TEXT NOT NULL DEFAULT 'public',
                entity_tags  TEXT NOT NULL DEFAULT '[]',
                content_hash TEXT NOT NULL,
                created_at   REAL DEFAULT (unixepoch('now')),
                updated_at   REAL DEFAULT (unixepoch('now'))
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS facts (
                fact_id        TEXT PRIMARY KEY,
                canonical_fact TEXT NOT NULL,
                status         TEXT NOT NULL DEFAULT 'active',
                confidence     REAL NOT NULL DEFAULT 1.0,
                source_ref     TEXT NOT NULL,
                created_at     REAL DEFAULT (unixepoch('now')),
                updated_at     REAL DEFAULT (unixepoch('now'))
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS lifecycle_events (
                event_id   TEXT PRIMARY KEY,
                unit_id    TEXT NOT NULL,
                operation  TEXT NOT NULL CHECK (operation IN ('ADD','UPDATE','DEPRECATE','NOOP')),
                old_status TEXT,
                new_status TEXT,
                reason     TEXT,
                ts         REAL DEFAULT (unixepoch('now'))
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS entities (
                entity_id   TEXT PRIMARY KEY,
                entity_name TEXT NOT NULL,
                entity_type TEXT NOT NULL DEFAULT 'general',
                confidence  REAL NOT NULL DEFAULT 1.0,
                created_at  REAL DEFAULT (unixepoch('now'))
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS entity_aliases (
                alias_id    TEXT PRIMARY KEY,
                entity_id   TEXT NOT NULL REFERENCES entities(entity_id),
                alias_text  TEXT NOT NULL,
                confidence  REAL NOT NULL DEFAULT 1.0,
                UNIQUE(alias_text)
            )
        """)
        db.execute("""
            CREATE TABLE IF NOT EXISTS autonomy_state (
                key   TEXT PRIMARY KEY,
                value TEXT,
                updated_at REAL DEFAULT (unixepoch('now'))
            )
        """)
        db.execute(
            "INSERT OR REPLACE INTO schema_info(key, value) VALUES ('version', ?)",
            (str(SCHEMA_VERSION),),
        )
        db.commit()


def get_schema_version(db: sqlite3.Connection) -> int:
    row = db.execute("SELECT value FROM schema_info WHERE key='version'").fetchone()
    return int(row["value"]) if row else 0
