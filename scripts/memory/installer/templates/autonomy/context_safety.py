#!/usr/bin/env python3
"""
context_safety.py - Context safety guard for Mnemo retrieval packs.

Runs automatically on every retrieval/context-pack build.
Checks:
  1. Duplicate snippet detection (prevents redundant context)
  2. Contradiction detection (alerts on conflicting facts)
  3. Low-signal suppression (filters empty/trivial content)
  4. Token budget enforcement (hard cap on total context chars)
  5. Sensitivity redaction (vault/secret entries stripped before delivery)

No human required: all checks are policy-driven.
"""
import re
import sqlite3
from dataclasses import dataclass, field
from typing import Optional

from autonomy.schema import get_db
from autonomy.reranker import RankedResult

DEFAULT_TOKEN_BUDGET = 6000  # chars (~1500 tokens)
MIN_CONTENT_CHARS = 20       # snippets shorter than this are suppressed
DUPLICATE_JACCARD_THRESHOLD = 0.85  # above = duplicate
CONTRADICTION_KEYWORD_PAIRS = [
    ("do not", "always"),
    ("never", "must"),
    ("disabled", "enabled"),
    ("false", "true"),
    ("forbidden", "required"),
]


@dataclass
class SafetyCheckResult:
    passed: bool
    issues: list[str] = field(default_factory=list)
    filtered_results: list[RankedResult] = field(default_factory=list)
    token_budget_used: int = 0
    token_budget_max: int = DEFAULT_TOKEN_BUDGET

    def summary(self) -> str:
        s = f"safety={'PASS' if self.passed else 'ISSUES'} used={self.token_budget_used}/{self.token_budget_max}"
        if self.issues:
            s += f" issues={len(self.issues)}"
        return s


def _jaccard(a: str, b: str) -> float:
    ta = set(re.findall(r"\w+", a.lower()))
    tb = set(re.findall(r"\w+", b.lower()))
    if not ta or not tb:
        return 0.0
    return len(ta & tb) / len(ta | tb)


def _detect_duplicates(results: list[RankedResult], max_pairs: int = 50) -> list[tuple[int, int]]:
    """Return (i, j) pairs where results[i] and results[j] are near-duplicates."""
    pairs: list[tuple[int, int]] = []
    n = len(results)
    for i in range(n):
        for j in range(i + 1, n):
            if _jaccard(results[i].content, results[j].content) >= DUPLICATE_JACCARD_THRESHOLD:
                pairs.append((i, j))
                if len(pairs) >= max_pairs:
                    return pairs
    return pairs


def _detect_contradictions(results: list[RankedResult]) -> list[tuple[int, int, str]]:
    """Return (i, j, reason) triples indicating contradicting result pairs."""
    contradictions: list[tuple[int, int, str]] = []
    for i in range(len(results)):
        for j in range(i + 1, len(results)):
            a = results[i].content.lower()
            b = results[j].content.lower()
            for neg, pos in CONTRADICTION_KEYWORD_PAIRS:
                if neg in a and pos in b:
                    contradictions.append((i, j, f"'{neg}' vs '{pos}'"))
                    break
                if pos in a and neg in b:
                    contradictions.append((i, j, f"'{pos}' vs '{neg}'"))
                    break
    return contradictions


class ContextSafetyGuard:
    def __init__(
        self,
        token_budget: int = DEFAULT_TOKEN_BUDGET,
        db: Optional[sqlite3.Connection] = None,
    ):
        self.token_budget = token_budget
        self.db = db or get_db()

    def check(self, results: list[RankedResult]) -> SafetyCheckResult:
        """
        Run all safety checks on results, return SafetyCheckResult.
        Modifies results list by removing failing entries.
        """
        issues: list[str] = []
        filtered: list[RankedResult] = []

        # 1. Sensitivity redaction (vault/secret always stripped first)
        for r in results:
            if r.memory_type == "vault":
                issues.append(f"REDACTED vault entry: {r.ref_path}")
                continue
            # Check DB sensitivity flag
            row = self.db.execute(
                "SELECT sensitivity FROM memory_units WHERE source_ref = ?",
                (r.source_file,),
            ).fetchone()
            if row and row["sensitivity"] == "secret":
                issues.append(f"REDACTED secret entry: {r.ref_path}")
                continue
            filtered.append(r)

        # 2. Low-signal suppression
        filtered = [r for r in filtered if len(r.content.strip()) >= MIN_CONTENT_CHARS]
        suppressed = len(results) - len(filtered)
        if suppressed > 0:
            issues.append(f"Suppressed {suppressed} low-signal entries (<{MIN_CONTENT_CHARS} chars)")

        # 3. Duplicate detection (remove lower-scored duplicate)
        dup_pairs = _detect_duplicates(filtered)
        to_remove: set[int] = set()
        for i, j in dup_pairs:
            # Keep higher-scored result
            remove_idx = j if filtered[i].final_score >= filtered[j].final_score else i
            to_remove.add(remove_idx)
            issues.append(f"Duplicate pair removed: {filtered[remove_idx].ref_path}")
        filtered = [r for idx, r in enumerate(filtered) if idx not in to_remove]

        # 4. Contradiction detection (warn but keep both, lower confidence)
        contradictions = _detect_contradictions(filtered)
        for i, j, reason in contradictions:
            issues.append(
                f"Contradiction detected ({reason}): {filtered[i].ref_path} vs {filtered[j].ref_path}"
            )
            # Reduce score of both to signal uncertainty
            filtered[i].final_score = filtered[i].final_score * 0.9
            filtered[j].final_score = filtered[j].final_score * 0.9

        # 5. Token budget enforcement
        budget_used = 0
        final: list[RankedResult] = []
        for r in sorted(filtered, key=lambda x: x.final_score, reverse=True):
            chars = len(r.content)
            if budget_used + chars > self.token_budget:
                issues.append(f"Token budget exceeded; truncated at {budget_used} chars")
                break
            final.append(r)
            budget_used += chars

        passed = not any("REDACTED secret" in i or "REDACTED vault" in i for i in issues)
        return SafetyCheckResult(
            passed=passed,
            issues=issues,
            filtered_results=final,
            token_budget_used=budget_used,
            token_budget_max=self.token_budget,
        )

    def build_context_pack(self, results: list[RankedResult]) -> str:
        """
        Build a formatted context pack string from safety-checked results.
        Safe to pass directly to LLM context.
        """
        check = self.check(results)
        lines: list[str] = []

        if not check.passed:
            sensitive_warnings = [i for i in check.issues if "REDACTED" in i]
            if sensitive_warnings:
                lines.append(f"[Safety] {'; '.join(sensitive_warnings)}")

        for r in check.filtered_results:
            lines.append(f"<!-- {r.ref_path} | score={r.final_score:.3f} type={r.memory_type} -->")
            lines.append(r.content.strip())
            lines.append("")

        return "\n".join(lines).strip()
