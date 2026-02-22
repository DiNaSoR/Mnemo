# Changelog

All notable changes to Mnemo are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Mnemo uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.0.4] - 2026-02-22

### Added
- Installers now seed a project-level Cursor skill at `.cursor/skills/mnemo-codebase-optimizer/` (`SKILL.md` + `reference.md`) to accelerate high-signal memory bootstrapping for any codebase.

### Changed
- Installer-managed `.gitignore` now includes `.cursor/skills/` to keep generated Mnemo skill artifacts out of default project tracking.
- Windows and POSIX regression tests now assert skill generation so installer behavior stays consistent across platforms.

## [0.0.3] - 2026-02-21

### Changed
- Vector engine now loads project `.env` values (when `GEMINI_API_KEY` is not already set in the shell) before provider resolution, so local API key setup works more reliably in CLI and MCP contexts.
- Default vector provider auto-resolves to `gemini` when `MNEMO_PROVIDER` is unset and `GEMINI_API_KEY` is available; otherwise it falls back to `openai`.
- Vector memory root discovery now prioritizes the script location (repo-local `scripts/memory/mnemo_vector.py`) before current working directory scanning, preventing cross-project context leaks when invoked from another directory.
- Embedded POSIX fallback vector engine now mirrors the same `.env` and provider-resolution behavior as the primary template.

### Added
- `mnemo_vector.py` now supports direct CLI operations: `sync`, `search`, `forget`, `health`, and `status`, enabling manual vector workflows outside MCP tool calls.

## [0.0.2] - 2026-02-21

### Changed
- Installers no longer generate root `CLAUDE.md` and `AGENTS.md`; integrations now use canonical `.mnemo/memory/` and agent bridge rules under `.agent/rules/`.
- Agent rule naming is normalized to ordered files: `00-memory-system.md` and `01-vector-search.md` (vector mode), aligned with cursor rule naming.
- Installer-managed `.gitignore` now uses top-level Mnemo paths (`.mnemo/`, `.cursor/memory/`, `.cursor/rules/`, `.cursor/mcp.json`, `.agent/rules/`, `scripts/memory/`, `.githooks/`) for cleaner defaults in target repositories.
- README IDE guidance now points Claude/Codex users to canonical `.mnemo/memory/` retrieval flow and updated agent rule paths.

### Fixed
- PowerShell installer no longer hard-fails when `git config core.hooksPath .githooks` cannot be written (permission/lock); it warns and continues.
- POSIX vector re-runs are idempotent for autonomy module installation when `--force` is not used.
- Cross-platform installer regression tests now validate the new numbered agent rule output.

## [0.0.1] - 2026-02-21

### Added
- First public Mnemo release with dual installers: `memory.ps1` (Windows PowerShell 5.1+/7+) and `memory_mac.sh` (macOS/Linux POSIX shell).
- Installer CLI support for `--dry-run` / `-DryRun`, `--force` / `-Force`, project naming, and optional vector enablement.
- Modular installer architecture with dedicated core and feature modules under `scripts/memory/installer/` (bootstrap, path resolution, I/O, bridges, scaffold, hooks, vector, MCP, `.gitignore`).
- Canonical memory root at `.mnemo/` with compatibility bridges to `.cursor/` and `.agent/` so existing IDE integrations continue to work.
- Bridge manager with cross-platform fallback behavior (symlink/junction/hardlink/mirror) and repair/migration logic for legacy layouts.
- Canonical memory scaffold including always-read files (`hot-rules.md`, `active-context.md`, `memo.md`), lessons, journals, digests, ADR, and templates.
- Atomic lesson workflow (`L-XXX-*`) and monthly journal workflow with rebuildable indexes/digests.
- Helper script suite for daily operations (PowerShell + shell variants): rebuild index, lint memory, query memory, add lesson, add journal entry, clear active context.
- Tag vocabulary enforcement and memory lint guardrails for frontmatter, structure, and token-safety checks.
- Optional SQLite FTS support (`memory.sqlite`) when Python is available, including build/query helpers.
- Optional vector mode with `mnemo_vector.py` MCP server and tools: `vector_search`, `vector_sync`, `vector_forget`, `vector_health`, `memory_status`.
- Vector embedding provider support for both OpenAI and Gemini.
- Autonomy runtime templates installed with vector mode (`autonomy/*` + `policies.yaml`) for ingestion, lifecycle, reranking, context safety, and policy handling.
- Portable git hooks via `.githooks/` with automatic `core.hooksPath` setup.
- Hook automation: `pre-commit` rebuild/lint and optional `post-commit` non-blocking vector sync.
- Multi-agent bridge outputs under `.cursor/rules/` and `.agent/rules/` for IDE-specific rule loading.
- Cross-platform CI coverage (Windows/macOS/Ubuntu), regression tests, modularization guardrails, and Python syntax checks for autonomy/retrieval modules.
- Nightly benchmark workflow for retrieval quality/drift monitoring plus artifact upload.
- GitHub release workflow for tag-based publishing with preflight/version/changelog validation and packaged installer assets.
- Governance and contribution assets: `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md`, issue templates, PR template, `CODEOWNERS`, and Dependabot config.

### Changed
- Versioning is centralized in root `VERSION` and consumed by installers and generated output.
- Installer/runtime path resolution prefers canonical `.mnemo` while preserving `.cursor` compatibility bridges.
- Python resolution strategy is aligned across memory tooling (`py` / `python3` / `python` fallback behavior where applicable).
- Managed `.gitignore` and hook behavior now reflect canonical `.mnemo` artifacts while keeping bridge compatibility.

### Fixed
- Duplicate managed `.gitignore` entries on repeated force installs.
- Bridge idempotency/self-copy failures around `.cursor/mcp.json` compatibility targets.
- Version string drift between installer metadata and generated output by using `VERSION` as single source of truth.
- Python fallback handling in memory query flows that previously depended on a single interpreter name.

[Unreleased]: https://github.com/DiNaSoR/Mnemo/compare/v0.0.4...HEAD
[0.0.4]: https://github.com/DiNaSoR/Mnemo/releases/tag/v0.0.4
[0.0.3]: https://github.com/DiNaSoR/Mnemo/releases/tag/v0.0.3
[0.0.2]: https://github.com/DiNaSoR/Mnemo/releases/tag/v0.0.2
[0.0.1]: https://github.com/DiNaSoR/Mnemo/releases/tag/v0.0.1
