#!/usr/bin/env python3
"""
contradiction.py - Shared contradiction detection for autonomy flows.

Default mode is dependency-free and deterministic:
  1) Anchor-token prefilter
  2) Predicate-aware fact-frame contradiction checks
  3) Heuristic fallback (antonym / polarity)

Optional enhancement:
  - embedding similarity check with sentence-transformers
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from functools import lru_cache
from typing import Optional


ANCHOR_SIM_THRESHOLD = 0.45
EMBED_SIM_THRESHOLD = 0.72
DEFAULT_MODE = "hybrid"  # predicate | hybrid | heuristic
DEFAULT_MIN_FRAME_CONFIDENCE = 0.55

NEGATION_CUES = frozenset(
    {
        "no",
        "not",
        "never",
        "cannot",
        "cant",
        "can't",
        "without",
        "disabled",
        "disable",
        "forbid",
        "forbidden",
        "avoid",
        "prohibit",
        "prohibited",
        "false",
        "off",
        "deny",
        "denied",
    }
)

AFFIRMATIVE_CUES = frozenset(
    {
        "always",
        "must",
        "can",
        "able",
        "required",
        "require",
        "requires",
        "enabled",
        "enable",
        "allowed",
        "allow",
        "allows",
        "true",
        "on",
        "enforce",
        "enforced",
    }
)

MODALITY_REQUIRED = frozenset(
    {
        "must",
        "required",
        "require",
        "requires",
        "mandatory",
    }
)

MODALITY_OPTIONAL = frozenset(
    {
        "optional",
        "may",
        "might",
        "can",
    }
)

MODALITY_FORBIDDEN = frozenset(
    {
        "forbid",
        "forbidden",
        "prohibit",
        "prohibited",
        "disallow",
        "denied",
        "deny",
    }
)

STOPWORDS = frozenset(
    {
        "a",
        "an",
        "the",
        "and",
        "or",
        "to",
        "of",
        "in",
        "on",
        "for",
        "with",
        "this",
        "that",
        "these",
        "those",
        "is",
        "are",
        "be",
        "being",
        "been",
        "do",
        "does",
        "did",
        "it",
        "as",
        "by",
        "from",
        "at",
        "if",
        "then",
        "than",
        "all",
        "any",
        "every",
        "each",
        "only",
    }
)

PREDICATE_CANONICAL = {
    "enable": "enable",
    "enabled": "enable",
    "disable": "enable",
    "disabled": "enable",
    "allow": "allow",
    "allows": "allow",
    "allowed": "allow",
    "forbid": "allow",
    "forbidden": "allow",
    "prohibit": "allow",
    "prohibited": "allow",
    "require": "require",
    "required": "require",
    "optional": "require",
    "use": "use",
    "uses": "use",
    "store": "store",
    "stores": "store",
    "stored": "store",
    "run": "run",
    "runs": "run",
    "running": "run",
    "rotate": "rotate",
    "rotates": "rotate",
    "include": "include",
    "includes": "include",
    "included": "include",
    "true": "boolean",
    "false": "boolean",
    "on": "boolean",
    "off": "boolean",
}

ACTION_HINTS = frozenset(PREDICATE_CANONICAL.keys()) | frozenset(
    {
        "support",
        "supports",
        "supported",
        "inject",
        "injects",
        "injected",
        "enforce",
        "enforces",
        "enforced",
        "log",
        "logs",
        "logged",
    }
)

ANTONYM_PAIRS = (
    ("enabled", "disabled"),
    ("enable", "disable"),
    ("allow", "forbid"),
    ("allowed", "forbidden"),
    ("required", "optional"),
    ("true", "false"),
    ("on", "off"),
)


def _normalize_mode(mode: str) -> str:
    value = (mode or DEFAULT_MODE).strip().lower()
    if value not in {"predicate", "hybrid", "heuristic"}:
        return DEFAULT_MODE
    return value


def _tokenize_list(text: str) -> list[str]:
    return re.findall(r"[a-z0-9_./-]+", (text or "").lower())


def _tokenize_set(text: str) -> set[str]:
    return set(_tokenize_list(text))


def _anchor_tokens(text: str) -> set[str]:
    tokens = _tokenize_set(text)
    return {t for t in tokens if t not in STOPWORDS and t not in NEGATION_CUES and t not in AFFIRMATIVE_CUES}


def _jaccard(a: set[str], b: set[str]) -> float:
    if not a or not b:
        return 0.0
    return len(a & b) / len(a | b)


def _polarity(text: str) -> int:
    """
    Return polarity marker:
      -1: negative/forbid language
       1: affirmative/require language
       0: unknown/mixed
    """
    lower = (text or "").lower()
    if re.search(r"\b(?:do|does|did|must|should|can|could|will|would)\s+not\b", lower):
        return -1
    if "never" in lower or "cannot" in lower or "can't" in lower:
        return -1

    tokens = _tokenize_set(lower)
    neg = len(tokens & NEGATION_CUES)
    pos = len(tokens & AFFIRMATIVE_CUES)
    if neg and not pos:
        return -1
    if pos and not neg:
        return 1
    return 0


def _modality(text: str) -> str:
    tokens = _tokenize_set(text)
    if tokens & MODALITY_FORBIDDEN:
        return "forbidden"
    if tokens & MODALITY_REQUIRED:
        return "required"
    if tokens & MODALITY_OPTIONAL:
        return "optional"
    return "neutral"


def _has_any_negation(text: str) -> bool:
    lower = (text or "").lower()
    if re.search(r"\b(?:do|does|did|must|should|can|could|will|would)\s+not\b", lower):
        return True
    tokens = _tokenize_set(lower)
    return bool(tokens & NEGATION_CUES)


def _has_antonym_conflict(a: str, b: str) -> bool:
    ta = _tokenize_set(a)
    tb = _tokenize_set(b)
    for left, right in ANTONYM_PAIRS:
        if (left in ta and right in tb) or (right in ta and left in tb):
            return True
    return False


def _canonical_predicate(token: str) -> str:
    if not token:
        return ""
    tok = token.lower().strip()
    if tok in PREDICATE_CANONICAL:
        return PREDICATE_CANONICAL[tok]
    if len(tok) > 4 and tok.endswith("ing"):
        stem = tok[:-3]
        if stem in PREDICATE_CANONICAL:
            return PREDICATE_CANONICAL[stem]
    if len(tok) > 3 and tok.endswith("ed"):
        stem = tok[:-2]
        if stem in PREDICATE_CANONICAL:
            return PREDICATE_CANONICAL[stem]
    if len(tok) > 3 and tok.endswith("s"):
        stem = tok[:-1]
        if stem in PREDICATE_CANONICAL:
            return PREDICATE_CANONICAL[stem]
    return tok


def _clean_frame_tokens(tokens: list[str]) -> list[str]:
    noisy = STOPWORDS | NEGATION_CUES | AFFIRMATIVE_CUES | MODALITY_REQUIRED | MODALITY_OPTIONAL | MODALITY_FORBIDDEN
    return [t for t in tokens if t and t not in noisy]


def _modality_conflict(a: str, b: str) -> bool:
    if a == b or "neutral" in {a, b}:
        return False
    pairs = {
        ("required", "optional"),
        ("optional", "required"),
        ("required", "forbidden"),
        ("forbidden", "required"),
        ("optional", "forbidden"),
        ("forbidden", "optional"),
    }
    return (a, b) in pairs


@dataclass
class FactFrame:
    subject: str
    predicate: str
    object: str
    polarity: int
    modality: str
    confidence: float
    subject_tokens: set[str] = field(default_factory=set)
    object_tokens: set[str] = field(default_factory=set)


def _extract_fact_frame(text: str) -> FactFrame:
    tokens = _tokenize_list(text)
    if not tokens:
        return FactFrame(
            subject="",
            predicate="",
            object="",
            polarity=0,
            modality="neutral",
            confidence=0.0,
        )

    action_idx: Optional[int] = None
    action_token = ""
    for idx, tok in enumerate(tokens):
        if tok in ACTION_HINTS:
            action_idx = idx
            action_token = tok
            break

    if action_idx is None:
        # Fallback to first informative token as pseudo-predicate.
        for idx, tok in enumerate(tokens):
            if tok not in STOPWORDS:
                action_idx = idx
                action_token = tok
                break

    if action_idx is None:
        action_idx = 0
        action_token = tokens[0]

    subject_tokens = _clean_frame_tokens(tokens[:action_idx])
    object_tokens = _clean_frame_tokens(tokens[action_idx + 1 :])
    subject = " ".join(subject_tokens[:4]) if subject_tokens else "implicit_subject"
    obj = " ".join(object_tokens[:8]) if object_tokens else ""
    predicate = _canonical_predicate(action_token)
    polarity = _polarity(text)
    modality = _modality(text)

    confidence = 0.25
    if predicate:
        confidence += 0.35
    if subject_tokens:
        confidence += 0.2
    if object_tokens:
        confidence += 0.15
    if modality != "neutral" or polarity != 0:
        confidence += 0.1
    if len(tokens) >= 4:
        confidence += 0.05
    confidence = min(confidence, 1.0)

    return FactFrame(
        subject=subject,
        predicate=predicate,
        object=obj,
        polarity=polarity,
        modality=modality,
        confidence=confidence,
        subject_tokens=set(subject_tokens),
        object_tokens=set(object_tokens),
    )


def _frame_compatible(a: FactFrame, b: FactFrame, anchor_sim: float) -> bool:
    if not a.predicate or not b.predicate:
        return False
    if a.predicate != b.predicate:
        return False

    subject_sim = 0.5
    if a.subject_tokens and b.subject_tokens:
        subject_sim = _jaccard(a.subject_tokens, b.subject_tokens)

    object_sim = anchor_sim
    if a.object_tokens and b.object_tokens:
        object_sim = _jaccard(a.object_tokens, b.object_tokens)

    return subject_sim >= 0.12 and object_sim >= 0.12


@dataclass
class ContradictionMatch:
    reason: str
    method: str
    anchor_similarity: float
    embedding_similarity: Optional[float] = None


@lru_cache(maxsize=1)
def _load_embedding_model():
    try:
        from sentence_transformers import SentenceTransformer  # type: ignore

        return SentenceTransformer("all-MiniLM-L6-v2")
    except Exception:
        return None


def _embedding_similarity(a: str, b: str) -> Optional[float]:
    model = _load_embedding_model()
    if model is None:
        return None
    try:
        vecs = model.encode([a, b], normalize_embeddings=True)
        return float(vecs[0] @ vecs[1])
    except Exception:
        return None


def compare_texts(
    a: str,
    b: str,
    use_embeddings: bool = False,
    anchor_threshold: float = ANCHOR_SIM_THRESHOLD,
    embed_threshold: float = EMBED_SIM_THRESHOLD,
    mode: str = DEFAULT_MODE,
    min_frame_confidence: float = DEFAULT_MIN_FRAME_CONFIDENCE,
    require_embedding_confirmation: bool = False,
) -> Optional[ContradictionMatch]:
    """
    Compare two facts and return contradiction evidence when found.

    Decision flow:
      1) anchor prefilter
      2) predicate-aware fact-frame checks (predicate/hybrid modes)
      3) heuristic fallback (hybrid/heuristic modes)
      4) optional embedding confirmation
    """
    selected_mode = _normalize_mode(mode)
    a_anchor = _anchor_tokens(a)
    b_anchor = _anchor_tokens(b)
    anchor_sim = _jaccard(a_anchor, b_anchor)
    if anchor_sim < anchor_threshold:
        return None

    base_match: Optional[ContradictionMatch] = None

    a_frame = _extract_fact_frame(a)
    b_frame = _extract_fact_frame(b)
    if selected_mode in {"predicate", "hybrid"}:
        if a_frame.confidence >= min_frame_confidence and b_frame.confidence >= min_frame_confidence:
            if _frame_compatible(a_frame, b_frame, anchor_sim):
                opposite_polarity = a_frame.polarity * b_frame.polarity == -1
                if opposite_polarity:
                    base_match = ContradictionMatch(
                        reason="frame_predicate_match_with_opposite_polarity",
                        method="predicate_polarity",
                        anchor_similarity=anchor_sim,
                    )
                elif _modality_conflict(a_frame.modality, b_frame.modality):
                    base_match = ContradictionMatch(
                        reason="frame_predicate_match_with_modal_conflict",
                        method="predicate_modality",
                        anchor_similarity=anchor_sim,
                    )

    if base_match is None and selected_mode in {"hybrid", "heuristic"}:
        a_pol = _polarity(a)
        b_pol = _polarity(b)
        opposite_polarity = a_pol * b_pol == -1
        one_sided_negation = (
            (a_pol == -1 and b_pol == 0 and not _has_any_negation(b))
            or (b_pol == -1 and a_pol == 0 and not _has_any_negation(a))
        )
        antonym_conflict = _has_antonym_conflict(a, b)

        if antonym_conflict:
            base_match = ContradictionMatch(
                reason="antonym_pair_shared_anchor",
                method="heuristic_antonym",
                anchor_similarity=anchor_sim,
            )
        elif opposite_polarity:
            base_match = ContradictionMatch(
                reason="opposite_polarity_shared_anchor",
                method="heuristic_polarity",
                anchor_similarity=anchor_sim,
            )
        elif one_sided_negation:
            base_match = ContradictionMatch(
                reason="one_sided_negation_shared_anchor",
                method="heuristic_negation",
                anchor_similarity=anchor_sim,
            )

    if base_match is None:
        return None

    if use_embeddings:
        emb_sim = _embedding_similarity(a, b)
        if require_embedding_confirmation:
            if emb_sim is None or emb_sim < embed_threshold:
                return None
            if base_match.method.startswith("heuristic_"):
                return ContradictionMatch(
                    reason=f"{base_match.reason}_embedding_confirmed",
                    method="heuristic_embedding",
                    anchor_similarity=base_match.anchor_similarity,
                    embedding_similarity=emb_sim,
                )
            base_match.embedding_similarity = emb_sim
            return base_match

        if emb_sim is not None and emb_sim >= embed_threshold and base_match.method.startswith("heuristic_"):
            return ContradictionMatch(
                reason=f"{base_match.reason}_high_embedding_similarity",
                method="heuristic_embedding",
                anchor_similarity=base_match.anchor_similarity,
                embedding_similarity=emb_sim,
            )
        if emb_sim is not None:
            base_match.embedding_similarity = emb_sim

    return base_match


def detect_cross_contradictions(
    source_texts: list[str],
    target_texts: list[str],
    use_embeddings: bool = False,
    anchor_threshold: float = ANCHOR_SIM_THRESHOLD,
    embed_threshold: float = EMBED_SIM_THRESHOLD,
    mode: str = DEFAULT_MODE,
    min_frame_confidence: float = DEFAULT_MIN_FRAME_CONFIDENCE,
    require_embedding_confirmation: bool = False,
) -> list[tuple[int, int, ContradictionMatch]]:
    """
    Compare each source text against each target text.
    Returns (source_idx, target_idx, match).
    """
    matches: list[tuple[int, int, ContradictionMatch]] = []
    for i, left in enumerate(source_texts):
        for j, right in enumerate(target_texts):
            match = compare_texts(
                left,
                right,
                use_embeddings=use_embeddings,
                anchor_threshold=anchor_threshold,
                embed_threshold=embed_threshold,
                mode=mode,
                min_frame_confidence=min_frame_confidence,
                require_embedding_confirmation=require_embedding_confirmation,
            )
            if match is not None:
                matches.append((i, j, match))
    return matches
