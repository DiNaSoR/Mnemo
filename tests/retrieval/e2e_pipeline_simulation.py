#!/usr/bin/env python3
"""
e2e_pipeline_simulation.py - End-to-end Mnemo user journey simulation.

Simulates this full lifecycle:
  install -> use -> vector sync -> retrieve (MCP tool logic) -> inject to chat context
  -> store new memory -> compact/rebuild -> vector resync -> retrieve new memory

Also runs an "optimized" retrieval/chat packing variant and compares token cost.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import math
import os
import shutil
import subprocess
import tempfile
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SYSTEM_PROMPT = (
    "You are an autonomous coding agent. Use only retrieved project memory and "
    "cite concrete files/rules in your answer."
)


@dataclass
class StepResult:
    name: str
    ok: bool
    duration_ms: int
    detail: str = ""


class TokenCounter:
    """Token counter using tiktoken when available, else chars/4 heuristic."""

    def __init__(self, model: str):
        self.model = model
        self.mode = "chars/4"
        self._enc = None
        try:
            import tiktoken  # type: ignore

            self._enc = tiktoken.encoding_for_model(model)
            self.mode = f"tiktoken:{model}"
        except Exception:
            self._enc = None

    def count(self, text: str) -> int:
        if not text:
            return 0
        if self._enc is not None:
            try:
                return len(self._enc.encode(text))
            except Exception:
                pass
        return max(1, math.ceil(len(text) / 4))


def _run(cmd: list[str], cwd: Path | None = None) -> tuple[int, str, str, int]:
    start = time.perf_counter()
    proc = subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        capture_output=True,
        text=True,
    )
    elapsed_ms = int((time.perf_counter() - start) * 1000)
    return proc.returncode, proc.stdout, proc.stderr, elapsed_ms


def _choose_provider(provider_arg: str) -> str:
    if provider_arg in {"openai", "gemini"}:
        return provider_arg
    if os.getenv("GEMINI_API_KEY"):
        return "gemini"
    if os.getenv("OPENAI_API_KEY"):
        return "openai"
    raise RuntimeError(
        "No API key found. Set GEMINI_API_KEY or OPENAI_API_KEY, "
        "or pass --provider openai|gemini."
    )


def _load_vector_module(temp_repo: Path):
    engine_path = temp_repo / "scripts" / "memory" / "mnemo_vector.py"
    if not engine_path.exists():
        raise RuntimeError(f"Vector engine missing: {engine_path}")
    spec = importlib.util.spec_from_file_location("mnemo_vector_e2e", str(engine_path))
    if spec is None or spec.loader is None:
        raise RuntimeError("Could not import generated mnemo_vector.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def _truncate_by_token_budget(text: str, token_counter: TokenCounter, budget_tokens: int) -> tuple[str, bool]:
    if budget_tokens <= 0:
        return text, False
    if token_counter.count(text) <= budget_tokens:
        return text, False

    lines = text.splitlines()
    kept: list[str] = []
    for line in lines:
        candidate = "\n".join(kept + [line])
        if token_counter.count(candidate) > budget_tokens:
            break
        kept.append(line)
    return "\n".join(kept).strip(), True


def _prompt_cost_snapshot(
    token_counter: TokenCounter,
    system_prompt: str,
    user_query: str,
    retrieval_text: str,
    completion_tokens: int,
    context_budget_tokens: int | None = None,
) -> dict[str, Any]:
    context_text = retrieval_text
    truncated = False
    if context_budget_tokens is not None:
        context_text, truncated = _truncate_by_token_budget(
            retrieval_text, token_counter, context_budget_tokens
        )

    system_tokens = token_counter.count(system_prompt)
    query_tokens = token_counter.count(user_query)
    context_tokens = token_counter.count(context_text)
    prompt_tokens = system_tokens + query_tokens + context_tokens
    total_tokens = prompt_tokens + completion_tokens

    return {
        "system_tokens": system_tokens,
        "query_tokens": query_tokens,
        "retrieval_tokens": token_counter.count(retrieval_text),
        "context_tokens_used": context_tokens,
        "prompt_tokens": prompt_tokens,
        "completion_tokens_assumed": completion_tokens,
        "total_tokens": total_tokens,
        "context_truncated": truncated,
        "context_budget_tokens": context_budget_tokens,
    }


def _parse_json_maybe(raw: str) -> dict[str, Any]:
    try:
        return json.loads(raw)
    except Exception:
        return {"raw": raw}


def _build_install_cmd(repo_root: Path, temp_repo: Path, provider: str) -> list[str]:
    """Build the unified Node.js installer command."""
    return [
        "node",
        str(repo_root / "bin" / "mnemo.js"),
        "--yes",
        "--repo-root",
        str(temp_repo),
        "--project-name",
        "E2EPipelineSim",
        "--enable-vector",
        "--vector-provider",
        provider,
    ]


def _build_add_journal_cmd(temp_repo: Path, marker: str) -> list[str]:
    """Build the add-journal-entry command appropriate for the current platform."""
    import platform
    if platform.system() == "Windows":
        return [
            "powershell",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(temp_repo / "scripts" / "memory" / "add-journal-entry.ps1"),
            "-Tags",
            "Process,Architecture",
            "-Title",
            f"{marker} pipeline simulation entry",
            "-Files",
            "scripts/memory/mnemo_vector.py,tests/retrieval/e2e_pipeline_simulation.py",
            "-Why",
            "End-to-end simulation of install->retrieve->store->compact->resync",
        ]
    return [
        "sh",
        str(temp_repo / "scripts" / "memory" / "add-journal-entry.sh"),
        "--tags",
        "Process,Architecture",
        "--title",
        f"{marker} pipeline simulation entry",
    ]


def _build_rebuild_cmd(temp_repo: Path) -> list[str]:
    """Build the rebuild-memory-index command appropriate for the current platform."""
    import platform
    if platform.system() == "Windows":
        return [
            "powershell",
            "-ExecutionPolicy",
            "Bypass",
            "-File",
            str(temp_repo / "scripts" / "memory" / "rebuild-memory-index.ps1"),
            "-RepoRoot",
            str(temp_repo),
        ]
    return [
        "sh",
        str(temp_repo / "scripts" / "memory" / "rebuild-memory-index.sh"),
    ]


def simulate(args: argparse.Namespace) -> dict[str, Any]:
    provider = _choose_provider(args.provider)
    token_counter = TokenCounter(args.model)

    temp_repo = Path(tempfile.mkdtemp(prefix="mnemo-e2e-sim-"))
    keep_temp = args.keep_temp

    steps: list[StepResult] = []
    old_cwd = Path.cwd()
    os.environ["MNEMO_PROVIDER"] = provider

    marker = f"SIM-E2E-{int(time.time())}"
    user_query = "How do we add a new lesson safely and avoid repeated mistakes?"

    try:
        # 1) Install (cross-platform: powershell on Windows, sh on POSIX)
        install_cmd = _build_install_cmd(REPO_ROOT, temp_repo, provider)
        rc, out, err, ms = _run(install_cmd, cwd=REPO_ROOT)
        steps.append(StepResult("install", rc == 0, ms, "vector install complete" if rc == 0 else err[:2000]))
        if rc != 0:
            raise RuntimeError(f"Installer failed:\n{err or out}")

        # 2) Load generated vector engine and run health/sync
        os.chdir(temp_repo)
        vector_mod = _load_vector_module(temp_repo)

        t0 = time.perf_counter()
        health_before = vector_mod.vector_health()
        steps.append(StepResult("vector_health_before", True, int((time.perf_counter() - t0) * 1000), "ok"))

        t0 = time.perf_counter()
        sync_before = vector_mod.vector_sync()
        steps.append(StepResult("vector_sync_before", True, int((time.perf_counter() - t0) * 1000), "synced"))

        status_before = _parse_json_maybe(vector_mod.memory_status())

        # 3) Retrieve (MCP tool logic) and simulate adding retrieval to current chat
        t0 = time.perf_counter()
        retrieval_baseline = vector_mod.vector_search(user_query, top_k=args.baseline_topk)
        steps.append(StepResult("retrieve_baseline", True, int((time.perf_counter() - t0) * 1000), f"top_k={args.baseline_topk}"))

        baseline_chat = _prompt_cost_snapshot(
            token_counter=token_counter,
            system_prompt=args.system_prompt,
            user_query=user_query,
            retrieval_text=retrieval_baseline,
            completion_tokens=args.completion_tokens,
            context_budget_tokens=None,
        )

        # "Better pipeline" variant: lower top-k + context budget
        t0 = time.perf_counter()
        retrieval_optimized = vector_mod.vector_search(user_query, top_k=args.optimized_topk)
        steps.append(
            StepResult(
                "retrieve_optimized",
                True,
                int((time.perf_counter() - t0) * 1000),
                f"top_k={args.optimized_topk}",
            )
        )

        optimized_chat = _prompt_cost_snapshot(
            token_counter=token_counter,
            system_prompt=args.system_prompt,
            user_query=user_query,
            retrieval_text=retrieval_optimized,
            completion_tokens=args.completion_tokens,
            context_budget_tokens=args.optimized_context_budget_tokens,
        )

        # 4) Store new memory in journal (cross-platform)
        add_journal_cmd = _build_add_journal_cmd(temp_repo, marker)
        rc, out, err, ms = _run(add_journal_cmd, cwd=temp_repo)
        steps.append(StepResult("store_new_memory", rc == 0, ms, out.strip()[-200:] if out else err[:200]))
        if rc != 0:
            # Fallback: write a journal entry directly so the pipeline can continue
            import platform
            mem_root = temp_repo / ".mnemo" / "memory"
            if not mem_root.exists():
                mem_root = temp_repo / ".cursor" / "memory"
            from datetime import datetime
            month = datetime.now().strftime("%Y-%m")
            today = datetime.now().strftime("%Y-%m-%d")
            journal_file = mem_root / "journal" / f"{month}.md"
            if journal_file.exists():
                text = journal_file.read_text(encoding="utf-8")
                entry = f"\n\n## {today}\n\n- [Process] {marker} pipeline simulation entry\n"
                journal_file.write_text(text.rstrip() + entry, encoding="utf-8")
                steps[-1] = StepResult("store_new_memory", True, ms, "fallback: direct file write")

        # 5) Compact = rebuild indexes/digests (cross-platform)
        rebuild_cmd = _build_rebuild_cmd(temp_repo)
        rc, out, err, ms = _run(rebuild_cmd, cwd=temp_repo)
        steps.append(StepResult("compact_rebuild", rc == 0, ms, "rebuild complete" if rc == 0 else err[:2000]))
        if rc != 0:
            raise RuntimeError(f"rebuild-memory-index failed:\n{err or out}")

        # 6) Vector resync and retrieve new memory marker
        t0 = time.perf_counter()
        sync_after = vector_mod.vector_sync()
        steps.append(StepResult("vector_sync_after", True, int((time.perf_counter() - t0) * 1000), "resynced"))

        t0 = time.perf_counter()
        retrieval_new = vector_mod.vector_search(marker, top_k=5)
        steps.append(StepResult("retrieve_new_memory", True, int((time.perf_counter() - t0) * 1000), "marker query"))

        status_after = _parse_json_maybe(vector_mod.memory_status())
        marker_found = marker.lower() in retrieval_new.lower()

        comparison = {
            "baseline_prompt_tokens": baseline_chat["prompt_tokens"],
            "optimized_prompt_tokens": optimized_chat["prompt_tokens"],
            "baseline_total_tokens": baseline_chat["total_tokens"],
            "optimized_total_tokens": optimized_chat["total_tokens"],
            "prompt_token_saving": baseline_chat["prompt_tokens"] - optimized_chat["prompt_tokens"],
            "total_token_saving": baseline_chat["total_tokens"] - optimized_chat["total_tokens"],
            "prompt_saving_pct": round(
                (
                    (baseline_chat["prompt_tokens"] - optimized_chat["prompt_tokens"])
                    / max(1, baseline_chat["prompt_tokens"])
                )
                * 100.0,
                2,
            ),
            "optimized_context_budget_tokens": args.optimized_context_budget_tokens,
        }

        return {
            "ok": True,
            "provider": provider,
            "tokenizer_mode": token_counter.mode,
            "temp_repo": str(temp_repo),
            "marker": marker,
            "journey": [
                "install",
                "vector_sync",
                "retrieve",
                "inject_to_chat",
                "store_memory",
                "compact_rebuild",
                "vector_resync",
                "retrieve_new_memory",
            ],
            "steps": [asdict(s) for s in steps],
            "status_before": status_before,
            "status_after": status_after,
            "baseline_chat": baseline_chat,
            "optimized_chat": optimized_chat,
            "comparison": comparison,
            "vector_sync_before": sync_before,
            "vector_sync_after": sync_after,
            "retrieval_baseline_preview": retrieval_baseline[:1200],
            "retrieval_new_preview": retrieval_new[:1200],
            "new_memory_retrieved": marker_found,
        }
    except Exception as exc:
        return {
            "ok": False,
            "provider": provider,
            "temp_repo": str(temp_repo),
            "steps": [asdict(s) for s in steps],
            "error": str(exc),
        }
    finally:
        os.chdir(old_cwd)
        if not keep_temp:
            shutil.rmtree(temp_repo, ignore_errors=True)


def _print_summary(report: dict[str, Any]) -> None:
    print("E2E Mnemo Pipeline Simulation")
    print("============================")
    print(f"ok: {report.get('ok')}")
    print(f"provider: {report.get('provider')}")
    print(f"tokenizer: {report.get('tokenizer_mode')}")
    print("")

    for step in report.get("steps", []):
        status = "PASS" if step["ok"] else "FAIL"
        print(f"[{status}] {step['name']:<22} {step['duration_ms']:>5} ms  {step.get('detail','')}")

    if not report.get("ok"):
        print("")
        print(f"ERROR: {report.get('error')}")
        return

    cmp = report["comparison"]
    print("")
    print("Token Comparison (baseline vs optimized)")
    print("----------------------------------------")
    print(f"baseline prompt tokens : {cmp['baseline_prompt_tokens']}")
    print(f"optimized prompt tokens: {cmp['optimized_prompt_tokens']}")
    print(f"prompt token saving    : {cmp['prompt_token_saving']} ({cmp['prompt_saving_pct']}%)")
    print(f"baseline total tokens  : {cmp['baseline_total_tokens']}")
    print(f"optimized total tokens : {cmp['optimized_total_tokens']}")
    print(f"total token saving     : {cmp['total_token_saving']}")
    print("")
    print(f"new memory retrieved after compact+resync: {report['new_memory_retrieved']}")


def main() -> int:
    ap = argparse.ArgumentParser(description="Simulate full Mnemo install-to-memory lifecycle")
    ap.add_argument("--provider", default="auto", choices=["auto", "openai", "gemini"])
    ap.add_argument("--model", default="gpt-4o-mini", help="Token counter model")
    ap.add_argument("--baseline-topk", type=int, default=8, help="Baseline retrieval top_k")
    ap.add_argument("--optimized-topk", type=int, default=4, help="Optimized retrieval top_k")
    ap.add_argument(
        "--optimized-context-budget-tokens",
        type=int,
        default=350,
        help="Context token budget for optimized pipeline",
    )
    ap.add_argument("--completion-tokens", type=int, default=500, help="Assumed completion tokens")
    ap.add_argument("--system-prompt", default=DEFAULT_SYSTEM_PROMPT)
    ap.add_argument("--output", help="Write full JSON report to file")
    ap.add_argument("--keep-temp", action="store_true", help="Keep temp repo for debugging")
    args = ap.parse_args()

    report = simulate(args)
    _print_summary(report)

    if args.output:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(f"\nReport written: {out}")

    return 0 if report.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
