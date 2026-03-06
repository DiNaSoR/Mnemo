#!/usr/bin/env python3
"""
token_counter.py - Shared token counting and budget policy loading.

Supports provider-aware token counting with graceful fallback:
  - OpenAI: tiktoken
  - Gemini: google.genai LocalTokenizer
  - Fallback: chars/4 estimate

Policy compatibility:
  - Preferred keys: token_budget_default_tokens, token_budget_extended_tokens
  - Legacy keys: token_budget_default, token_budget_extended (chars)
"""
from __future__ import annotations

import math
import os
import warnings
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Optional


LEGACY_CHAR_PER_TOKEN = 4
DEFAULT_BUDGET_TOKENS = 1500
EXTENDED_BUDGET_TOKENS = 3000


@dataclass(frozen=True)
class TokenBudgetConfig:
    default_tokens: int
    extended_tokens: int
    source: str


def _safe_int(value: Any) -> Optional[int]:
    try:
        parsed = int(value)
        return parsed if parsed > 0 else None
    except Exception:
        return None


def _safe_yaml_load(path: Path) -> dict:
    try:
        import yaml  # type: ignore
    except Exception:
        return {}
    try:
        payload = yaml.safe_load(path.read_text(encoding="utf-8"))
        return payload if isinstance(payload, dict) else {}
    except Exception:
        return {}


def _candidate_policy_paths() -> list[Path]:
    here = Path(__file__).resolve()
    env_path = os.getenv("MNEMO_POLICY_PATH", "").strip()
    candidates: list[Path] = []
    if env_path:
        candidates.append(Path(env_path).expanduser().resolve())

    candidates.extend(
        [
            here.with_name("policies.yaml"),
            Path.cwd() / ".mnemo" / "memory" / "scripts" / "autonomy" / "policies.yaml",
            Path.cwd() / ".cursor" / "memory" / "scripts" / "autonomy" / "policies.yaml",
            Path.cwd() / "scripts" / "memory" / "installer" / "templates" / "autonomy" / "policies.yaml",
        ]
    )

    seen: set[str] = set()
    out: list[Path] = []
    for p in candidates:
        key = str(p)
        if key in seen:
            continue
        seen.add(key)
        out.append(p)
    return out


def resolve_policy_path() -> Optional[Path]:
    for p in _candidate_policy_paths():
        if p.exists():
            return p
    return None


def load_token_budget_config(
    policy_path: Optional[Path] = None,
    default_tokens: int = DEFAULT_BUDGET_TOKENS,
    extended_tokens: int = EXTENDED_BUDGET_TOKENS,
) -> TokenBudgetConfig:
    """
    Load token budget settings with backward compatibility.

    Preferred keys:
      - token_budget_default_tokens
      - token_budget_extended_tokens

    Legacy keys (chars):
      - token_budget_default
      - token_budget_extended
    """
    path = policy_path or resolve_policy_path()
    if path is None:
        return TokenBudgetConfig(default_tokens=default_tokens, extended_tokens=extended_tokens, source="defaults")

    payload = _safe_yaml_load(path)
    if not payload:
        return TokenBudgetConfig(default_tokens=default_tokens, extended_tokens=extended_tokens, source=f"defaults:{path}")

    d_tokens = _safe_int(payload.get("token_budget_default_tokens"))
    e_tokens = _safe_int(payload.get("token_budget_extended_tokens"))
    if d_tokens and e_tokens:
        return TokenBudgetConfig(default_tokens=d_tokens, extended_tokens=e_tokens, source=f"policy_tokens:{path}")

    # Legacy char budgets fallback.
    d_chars = _safe_int(payload.get("token_budget_default"))
    e_chars = _safe_int(payload.get("token_budget_extended"))
    if d_chars and e_chars:
        warnings.warn(
            "Using legacy char budget keys (token_budget_default/token_budget_extended). "
            "Please migrate to *_tokens keys.",
            RuntimeWarning,
            stacklevel=2,
        )
        return TokenBudgetConfig(
            default_tokens=max(1, math.ceil(d_chars / LEGACY_CHAR_PER_TOKEN)),
            extended_tokens=max(1, math.ceil(e_chars / LEGACY_CHAR_PER_TOKEN)),
            source=f"policy_chars_legacy:{path}",
        )

    return TokenBudgetConfig(default_tokens=default_tokens, extended_tokens=extended_tokens, source=f"defaults:{path}")


class TokenCounter:
    """
    Provider-aware token counter with graceful fallback.
    """

    def __init__(self, provider: str = "auto", model: str = "gpt-4o-mini"):
        self.provider = provider.strip().lower() if provider else "auto"
        self.model = model.strip() if model else "gpt-4o-mini"
        self.mode = "chars/4"
        self._tiktoken_enc = None
        self._gemini_tokenizer = None

        if self.provider == "openai":
            self._try_init_tiktoken()
        elif self.provider == "gemini":
            self._try_init_gemini()
        else:
            self._try_init_tiktoken()
            if self._tiktoken_enc is None:
                self._try_init_gemini()

    def _try_init_tiktoken(self) -> None:
        try:
            import tiktoken  # type: ignore

            self._tiktoken_enc = tiktoken.encoding_for_model(self.model)
            self.mode = f"tiktoken:{self.model}"
        except Exception:
            self._tiktoken_enc = None

    def _try_init_gemini(self) -> None:
        try:
            from google import genai  # type: ignore

            self._gemini_tokenizer = genai.LocalTokenizer(model_name=self.model)
            self.mode = f"gemini-local:{self.model}"
        except Exception:
            self._gemini_tokenizer = None

    def count(self, text: str) -> int:
        if not text:
            return 0

        if self._tiktoken_enc is not None:
            try:
                return len(self._tiktoken_enc.encode(text))
            except Exception:
                pass

        if self._gemini_tokenizer is not None:
            try:
                result = self._gemini_tokenizer.count_tokens(text)
                if isinstance(result, int):
                    return result
                if hasattr(result, "total_tokens"):
                    return int(result.total_tokens)
                return int(result)
            except Exception:
                pass

        return max(1, math.ceil(len(text) / LEGACY_CHAR_PER_TOKEN))
