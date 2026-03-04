#!/usr/bin/env python3
"""
runner.py - Mnemo Autonomous Memory Runtime (no-human-in-the-loop).

Triggered by:
  - Git hooks: post-commit, post-merge, post-checkout
  - Periodic scheduler tick (--mode schedule)
  - Direct invocation: python runner.py [--mode {auto|schedule|once}]

Responsibilities:
  1. Change detection on .mnemo/memory/**/*.md (with .cursor bridge compatibility)
  2. Ingest and chunk changed files
  3. Metadata classification + entity resolution
  4. Fact lifecycle (ADD/UPDATE/DEPRECATE/NOOP)
  5. Vector index update
  6. Autonomous journal delta generation
  7. Lesson promotion from stable signals
  8. Safety check on retrieval packs
"""
import argparse
import json
import os
import signal
import sys
import time
import traceback
from pathlib import Path
from datetime import datetime, timezone

# Allow running from scripts/memory/ directory
_HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(_HERE.parent))

from autonomy.schema import get_db
from autonomy.ingest_pipeline import IngestPipeline
from autonomy.lifecycle_engine import LifecycleEngine
from autonomy.entity_resolver import EntityResolver


LOCK_PATH: Path | None = None
STATE_KEY_LAST_RUN = "last_run_ts"
STATE_KEY_CYCLE = "cycle_count"
SCHEDULE_INTERVAL_S = int(os.getenv("MNEMO_SCHEDULE_INTERVAL", "300"))  # 5 min default
MAX_LOCK_AGE_S = 600  # stale lock timeout


def resolve_memory_root(repo_root: Path) -> Path:
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


def _require_lock_path() -> Path:
    if LOCK_PATH is None:
        raise RuntimeError("LOCK_PATH is not initialized")
    return LOCK_PATH


def _acquire_lock() -> bool:
    lock_path = _require_lock_path()
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    if lock_path.exists():
        try:
            mtime = lock_path.stat().st_mtime
            age = time.time() - mtime
            if age < MAX_LOCK_AGE_S:
                return False
            lock_path.unlink()
        except OSError:
            return False
    try:
        fd = os.open(str(lock_path), os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o644)
        os.write(fd, str(os.getpid()).encode())
        os.close(fd)
        return True
    except FileExistsError:
        return False
    except OSError:
        return False


def _release_lock() -> None:
    lock_path = _require_lock_path()
    try:
        if lock_path.exists():
            lock_path.unlink()
    except OSError:
        pass


def _emit_log(level: str, msg: str) -> None:
    ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    print(f"[{ts}] [{level}] {msg}", flush=True)


def run_once(repo_root: Path) -> dict:
    """Execute one autonomous memory cycle. Returns summary dict."""
    summary = {"status": "ok", "ingested": 0, "facts_added": 0, "facts_deprecated": 0, "errors": []}

    db = get_db()
    ingester = IngestPipeline(db=db, repo_root=repo_root)
    lifecycle = LifecycleEngine(db=db)
    resolver = EntityResolver(db=db)

    # 1. Detect changed files
    changed = ingester.detect_changes()
    _emit_log("INFO", f"Detected {len(changed)} changed memory files")

    # 2. Ingest each changed file
    for path in changed:
        try:
            units = ingester.ingest_file(path)
            summary["ingested"] += len(units)

            # 3. Entity resolution per unit
            for unit in units:
                resolver.resolve(unit)

            # 4. Fact lifecycle decisions
            for unit in units:
                result = lifecycle.process(unit)
                if result.operation == "ADD":
                    summary["facts_added"] += 1
                elif result.operation == "DEPRECATE":
                    summary["facts_deprecated"] += 1

        except Exception as e:
            err = f"{path}: {e}"
            summary["errors"].append(err)
            _emit_log("ERROR", err)

    # 5. Autonomous journal delta
    if summary["ingested"] > 0:
        try:
            _write_autonomy_journal_delta(repo_root, summary)
        except Exception as e:
            _emit_log("WARN", f"Journal delta failed: {e}")

    # 6. Lesson promotion (stable signals → new lessons)
    try:
        promoted = lifecycle.promote_lessons(repo_root=repo_root)
        if promoted:
            _emit_log("INFO", f"Promoted {len(promoted)} new lessons")
            summary["lessons_promoted"] = len(promoted)
    except Exception as e:
        _emit_log("WARN", f"Lesson promotion failed: {e}")

    # 7. Persist cycle state
    now_ts = str(time.time())
    db.execute(
        "INSERT OR REPLACE INTO autonomy_state(key, value, updated_at) VALUES ('last_run_ts', ?, unixepoch('now'))",
        (now_ts,),
    )
    db.execute(
        """
        INSERT INTO autonomy_state(key, value, updated_at) VALUES ('cycle_count', '1', unixepoch('now'))
        ON CONFLICT(key) DO UPDATE SET
            value = CAST(CAST(value AS INTEGER) + 1 AS TEXT),
            updated_at = unixepoch('now')
        """
    )
    db.commit()
    db.close()

    if summary["errors"]:
        summary["status"] = "partial"
    return summary


def _write_autonomy_journal_delta(repo_root: Path, summary: dict) -> None:
    """Write an autonomous journal entry summarizing the cycle."""
    today = datetime.now().strftime("%Y-%m-%d")
    month = today[:7]
    journal_path = resolve_memory_root(repo_root) / "journal" / f"{month}.md"
    journal_path.parent.mkdir(parents=True, exist_ok=True)

    facts_line = f"{summary['facts_added']} facts added"
    if summary.get("facts_deprecated"):
        facts_line += f", {summary['facts_deprecated']} deprecated"
    if summary.get("lessons_promoted"):
        facts_line += f", {summary['lessons_promoted']} lessons promoted"

    entry_lines = [
        f"- [Process][Autonomy] Auto-cycle: ingested {summary['ingested']} units ({facts_line})",
        f"  - System: Mnemo autonomous runner (no human in loop)",
    ]
    if summary.get("errors"):
        entry_lines.append(f"  - Warnings: {len(summary['errors'])} errors (see runner log)")

    entry = "\n".join(entry_lines)
    date_heading = f"## {today}"

    if journal_path.exists():
        text = journal_path.read_text(encoding="utf-8-sig")
        if f"## {today}" in text and "[Process][Autonomy]" in text:
            return  # Don't spam: one autonomy entry per day per file
        if f"## {today}" in text:
            text = text.rstrip() + "\n\n" + entry + "\n"
        else:
            text = text.rstrip() + f"\n\n{date_heading}\n\n{entry}\n"
        journal_path.write_text(text, encoding="utf-8")
    else:
        project = repo_root.name
        content = f"# Development Journal - {project} ({month})\n\n{date_heading}\n\n{entry}\n"
        journal_path.write_text(content, encoding="utf-8")


def run_schedule(repo_root: Path) -> None:
    """Run continuously on a fixed interval schedule."""
    _emit_log("INFO", f"Scheduler started (interval={SCHEDULE_INTERVAL_S}s)")

    def _handle_signal(sig, frame):
        _emit_log("INFO", "Runner received shutdown signal")
        _release_lock()
        sys.exit(0)

    signal.signal(signal.SIGINT, _handle_signal)
    if hasattr(signal, "SIGTERM"):
        signal.signal(signal.SIGTERM, _handle_signal)

    while True:
        if _acquire_lock():
            try:
                summary = run_once(repo_root)
                _emit_log("INFO", f"Cycle complete: {json.dumps(summary)}")
            except Exception:
                _emit_log("ERROR", traceback.format_exc())
            finally:
                _release_lock()
        else:
            _emit_log("DEBUG", "Another runner is active; skipping cycle")
        time.sleep(SCHEDULE_INTERVAL_S)


def main() -> int:
    ap = argparse.ArgumentParser(description="Mnemo autonomous memory runner")
    ap.add_argument("--mode", choices=["auto", "schedule", "once"], default="once",
                    help="auto=once+return, schedule=loop, once=single run")
    ap.add_argument("--repo", default=str(Path.cwd()), help="Repo root directory")
    args = ap.parse_args()

    repo_root = Path(args.repo).resolve()
    global LOCK_PATH
    LOCK_PATH = resolve_memory_root(repo_root) / ".autonomy" / "runner.lock"

    if args.mode == "schedule":
        run_schedule(repo_root)
        return 0

    if not _acquire_lock():
        _emit_log("INFO", "Another runner is active; exiting")
        return 0

    try:
        summary = run_once(repo_root)
        _emit_log("INFO", f"Done: {json.dumps(summary)}")
        return 0 if summary["status"] != "error" else 1
    except Exception:
        _emit_log("ERROR", traceback.format_exc())
        return 1
    finally:
        _release_lock()


if __name__ == "__main__":
    raise SystemExit(main())
