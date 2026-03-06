#!/usr/bin/env python3
"""
context_safety.py - Context safety guard for Mnemo retrieval packs.

Runs automatically on every retrieval/context-pack build.
Checks:
  1. Duplicate snippet detection (prevents redundant context)
  2. Contradiction detection (alerts on conflicting facts)
  3. Low-signal suppression (filters empty/trivial content)
  4. Token budget enforcement (hard cap on total context tokens)
  5. Sensitivity redaction (vault/secret entries stripped before delivery)
"""
from __future__ import annotations

import re
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from autonomy.contradiction import compare_texts
from autonomy.reranker import RankedResult
from autonomy.schema import get_db
from autonomy.token_counter import (
    DEFAULT_BUDGET_TOKENS,
    TokenCounter,
    load_token_budget_config,
    resolve_policy_path,
)

DEFAULT_TOKEN_BUDGET = DEFAULT_BUDGET_TOKENS
MIN_CONTENT_CHARS = 20
DUPLICATE_JACCARD_THRESHOLD = 0.85


@dataclass
class SafetyCheckResult:
    passed: bool
    issues: list[str] = field(default_factory=list)
    filtered_results: list[RankedResult] = field(default_factory=list)
    token_budget_used: int = 0
    token_budget_max: int = DEFAULT_TOKEN_BUDGET
    token_counter_mode: str = "chars/4"
    budget_source: str = "defaults"

    def summary(self) -> str:
        s = (
            f"safety={'PASS' if self.passed else 'ISSUES'} "
            f"used={self.token_budget_used}/{self.token_budget_max} tokens "
            f"counter={self.token_counter_mode}"
        )
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


def _safe_yaml_load(path: Optional[Path]) -> dict:
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


def _detect_contradictions(
    results: list[RankedResult],
    use_embeddings: bool = False,
    anchor_threshold: float = 0.45,
    embed_threshold: float = 0.72,
    mode: str = "hybrid",
    min_frame_confidence: float = 0.55,
    require_embedding_confirmation: bool = False,
) -> list[tuple[int, int, str]]:
    """Return (i, j, reason) triples indicating contradicting result pairs."""
    contradictions: list[tuple[int, int, str]] = []
    for i in range(len(results)):
        for j in range(i + 1, len(results)):
            match = compare_texts(
                results[i].content,
                results[j].content,
                use_embeddings=use_embeddings,
                anchor_threshold=anchor_threshold,
                embed_threshold=embed_threshold,
                mode=mode,
                min_frame_confidence=min_frame_confidence,
                require_embedding_confirmation=require_embedding_confirmation,
            )
            if match is not None:
                contradictions.append((i, j, f"{match.method}:{match.reason}"))
    return contradictions


class ContextSafetyGuard:
    def __init__(
        self,
        token_budget: Optional[int] = None,
        token_provider: str = "auto",
        token_model: str = "gpt-4o-mini",
        use_embedding_contradictions: Optional[bool] = None,
        contradiction_anchor_threshold: Optional[float] = None,
        contradiction_embed_threshold: Optional[float] = None,
        contradiction_mode: Optional[str] = None,
        contradiction_min_frame_confidence: Optional[float] = None,
        require_embedding_confirmation: Optional[bool] = None,
        db: Optional[sqlite3.Connection] = None,
    ):
        self.db = db or get_db()
        policy_path = resolve_policy_path()
        policy = _safe_yaml_load(policy_path)
        contradiction_cfg = policy.get("contradiction", {}) if isinstance(policy, dict) else {}
        if not isinstance(contradiction_cfg, dict):
            contradiction_cfg = {}

        budgets = load_token_budget_config(policy_path=policy_path)
        self.token_budget = token_budget if token_budget and token_budget > 0 else budgets.default_tokens
        self.budget_source = budgets.source
        self.token_counter = TokenCounter(provider=token_provider, model=token_model)

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
        contradictions = _detect_contradictions(
            filtered,
            use_embeddings=self.use_embedding_contradictions,
            anchor_threshold=self.contradiction_anchor_threshold,
            embed_threshold=self.contradiction_embed_threshold,
            mode=self.contradiction_mode,
            min_frame_confidence=self.contradiction_min_frame_confidence,
            require_embedding_confirmation=self.require_embedding_confirmation,
        )
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
            tokens = self.token_counter.count(r.content)
            if budget_used + tokens > self.token_budget:
                issues.append(f"Token budget exceeded; truncated at {budget_used} tokens")
                break
            final.append(r)
            budget_used += tokens

        passed = not any("REDACTED secret" in i or "REDACTED vault" in i for i in issues)
        return SafetyCheckResult(
            passed=passed,
            issues=issues,
            filtered_results=final,
            token_budget_used=budget_used,
            token_budget_max=self.token_budget,
            token_counter_mode=self.token_counter.mode,
            budget_source=self.budget_source,
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
