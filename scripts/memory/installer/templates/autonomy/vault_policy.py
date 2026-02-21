#!/usr/bin/env python3
"""
vault_policy.py - Vault lane and sensitivity enforcement for Mnemo.

Handles:
  - Marking files/units as secret/vault (sensitivity classification)
  - Automatic redaction before context pack delivery
  - Policy config loading from policies.yaml
  - Autonomous redaction pipeline (no human required)
"""
import re
import sqlite3
import os
import yaml
from pathlib import Path
from typing import Optional

from autonomy.schema import get_db


def _resolve_memory_root() -> Path:
    override = os.getenv("MNEMO_MEMORY_ROOT", "").strip()
    if override:
        return Path(override).expanduser().resolve()

    cwd = Path.cwd().resolve()
    for root in (cwd, *cwd.parents):
        for rel in ((".mnemo", "memory"), (".cursor", "memory")):
            candidate = root.joinpath(*rel)
            if candidate.exists():
                return candidate
    return cwd / ".mnemo" / "memory"


DEFAULT_POLICY_PATH = _resolve_memory_root() / ".autonomy" / "policies.yaml"
_POLICY_CACHE: dict | None = None

# Built-in secret patterns (supplemented by policies.yaml)
_BUILTIN_SECRET_PATTERNS = [
    r"(?i)(api[_-]?key|secret[_-]?key|password|token|auth[_-]?token)\s*[:=]\s*\S+",
    r"(?i)bearer\s+[a-zA-Z0-9._-]{20,}",
    r"[a-zA-Z0-9]{32,}",  # Long API keys (conservative - only in vault paths)
]

REDACTION_PLACEHOLDER = "[REDACTED]"


def load_policy(policy_path: Path = DEFAULT_POLICY_PATH) -> dict:
    """Load vault policy from YAML file, with fallback to defaults."""
    global _POLICY_CACHE
    if _POLICY_CACHE is not None:
        return _POLICY_CACHE

    defaults = {
        "sensitivity_paths": {
            "secret": [".mnemo/memory/vault/", ".cursor/memory/vault/", ".env", "*.secret.*"],
            "internal": [".mnemo/memory/active-context.md", ".cursor/memory/active-context.md"],
        },
        "redaction_patterns": [],
        "allow_internal_for_roles": ["agent", "autonomous"],
        "max_sensitivity_in_context": "internal",
    }

    if not policy_path.exists():
        _POLICY_CACHE = defaults
        return defaults

    try:
        with open(policy_path, "r", encoding="utf-8") as f:
            loaded = yaml.safe_load(f) or {}
        merged = {**defaults, **loaded}
        _POLICY_CACHE = merged
        return merged
    except Exception:
        _POLICY_CACHE = defaults
        return defaults


def invalidate_policy_cache() -> None:
    global _POLICY_CACHE
    _POLICY_CACHE = None


def classify_sensitivity(path_str: str, policy: dict | None = None) -> str:
    """Return 'public', 'internal', or 'secret' for a given file path."""
    if policy is None:
        policy = load_policy()

    p_lower = path_str.lower().replace("\\", "/")
    patterns = policy.get("sensitivity_paths", {})

    for label in ("secret", "internal", "public"):
        for pattern in patterns.get(label, []):
            pat_lower = pattern.lower().replace("\\", "/")
            if pat_lower.endswith("/") and pat_lower in p_lower:
                return label
            if pat_lower.startswith("*.") and p_lower.endswith(pat_lower[1:]):
                return label
            if pat_lower in p_lower:
                return label

    # Built-in vault detection
    if "/vault/" in p_lower:
        return "secret"
    if ".secret." in p_lower or "secret." in p_lower:
        return "secret"

    return "public"


def redact_content(content: str, sensitivity: str, policy: dict | None = None) -> str:
    """
    Redact sensitive patterns from content.
    For 'secret' sensitivity: apply all redaction patterns.
    For 'internal': apply only external-facing redaction.
    """
    if sensitivity == "public":
        return content

    if policy is None:
        policy = load_policy()

    result = content
    patterns_to_apply = list(_BUILTIN_SECRET_PATTERNS)
    extra = policy.get("redaction_patterns", [])
    if isinstance(extra, list):
        patterns_to_apply.extend(extra)

    for pat in patterns_to_apply:
        try:
            result = re.sub(pat, REDACTION_PLACEHOLDER, result)
        except re.error:
            pass

    return result


class VaultPolicy:
    def __init__(
        self,
        db: Optional[sqlite3.Connection] = None,
        policy_path: Path = DEFAULT_POLICY_PATH,
    ):
        self.db = db or get_db()
        self.policy = load_policy(policy_path)

    def classify_and_persist(self, source_ref: str) -> str:
        """Classify sensitivity and update DB record."""
        sensitivity = classify_sensitivity(source_ref, self.policy)
        self.db.execute(
            "UPDATE memory_units SET sensitivity=?, updated_at=unixepoch('now') WHERE source_ref=?",
            (sensitivity, source_ref),
        )
        self.db.commit()
        return sensitivity

    def bulk_reclassify(self) -> dict[str, int]:
        """Reclassify all memory units. Returns {sensitivity: count}."""
        rows = self.db.execute("SELECT unit_id, source_ref FROM memory_units").fetchall()
        counts: dict[str, int] = {"public": 0, "internal": 0, "secret": 0}

        for row in rows:
            sensitivity = classify_sensitivity(row["source_ref"], self.policy)
            self.db.execute(
                "UPDATE memory_units SET sensitivity=?, updated_at=unixepoch('now') WHERE unit_id=?",
                (sensitivity, row["unit_id"]),
            )
            counts[sensitivity] = counts.get(sensitivity, 0) + 1

        self.db.commit()
        return counts

    def is_authorized(self, sensitivity: str, role: str = "agent") -> bool:
        """Return True if the given role is authorized to see this sensitivity level."""
        max_level = self.policy.get("max_sensitivity_in_context", "internal")
        allowed_roles = self.policy.get("allow_internal_for_roles", [])

        if sensitivity == "public":
            return True
        if sensitivity == "secret":
            return False
        if sensitivity == "internal":
            return role in allowed_roles

        return False

    def apply_redaction(self, content: str, sensitivity: str) -> str:
        """Apply content redaction based on sensitivity level."""
        return redact_content(content, sensitivity, self.policy)

    def audit_report(self) -> dict:
        """Return audit summary of sensitivity distribution."""
        rows = self.db.execute(
            "SELECT sensitivity, COUNT(*) as cnt FROM memory_units GROUP BY sensitivity"
        ).fetchall()
        report = {r["sensitivity"]: r["cnt"] for r in rows}

        # Check for units with secret content in non-vault paths
        leaked = self.db.execute(
            "SELECT COUNT(*) FROM memory_units WHERE sensitivity='secret' AND source_ref NOT LIKE '%vault%'"
        ).fetchone()[0]
        if leaked:
            report["_warning_potential_leaks"] = leaked

        return report
