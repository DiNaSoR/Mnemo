# Changelog

All notable changes to Mnemo are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Mnemo uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
- Multi-agent bridge outputs: `CLAUDE.md`, `AGENTS.md`, and `.agent/rules/memory-system.md`.
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

[Unreleased]: https://github.com/DiNaSoR/Mnemo/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/DiNaSoR/Mnemo/releases/tag/v0.0.1
