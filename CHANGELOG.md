# Changelog

All notable changes to Mnemo are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Mnemo uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- `VERSION` file as single source of truth for version number
- `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `SECURITY.md`, `SUPPORT.md`
- GitHub issue templates (bug report, feature request)
- GitHub PR template
- Cross-platform CI workflow (Windows / macOS / Ubuntu)
- Installer smoke tests and idempotency tests in `tests/`
- `--dry-run` flag for both `memory.ps1` and `memory_mac.sh`
- Canonical `.mnemo` storage root with permanent compatibility bridges to `.cursor` and `.agent`
- Cross-platform bridge manager with link fallback modes (symlink/junction/hardlink/mirror)
- Bridge-specific regression coverage (`legacy-migration-bridge`, `bridge-repair-idempotent`)
- Atomic backup before mutating canonical MCP config (`.mnemo/mcp/cursor.mcp.json`)
- Safer `.gitignore` deduplication with section markers
- `CODEOWNERS` and `dependabot.yml`

### Changed
- Version string centralized to `VERSION` file; installers and generated output derive from it
- Improved Python detection in `memory.ps1` to be consistent with `rebuild-memory-index.ps1`
- `query-memory.ps1` now uses the same multi-candidate Python resolver as the rest of `memory.ps1`
- Installers, templates, vector/autonomy runtime, hooks, and retrieval benchmarks now resolve `.mnemo` first with `.cursor` compatibility fallback
- Git hooks and managed `.gitignore` now stage/ignore canonical `.mnemo` artifacts while preserving Cursor bridge compatibility

### Fixed
- Duplicate `.gitignore` entries on repeated `--force` runs
- Version mismatch between file header (`v3.3.0`) and generated output strings (`v3.2.2`)
- `query-memory.ps1` using only `python` instead of trying `py`/`python3` fallbacks
- File bridge idempotency for hardlinked `.cursor/mcp.json` targets (prevents self-copy IO errors)

---

## [3.3.0] - 2025-02-20

### Added
- macOS/POSIX shell installer (`memory_mac.sh`) as first-class counterpart to `memory.ps1`
- Multi-agent bridge files: `CLAUDE.md`, `AGENTS.md`, `.agent/rules/memory-system.md`
- Optional vector semantic layer (`--EnableVector` / `--enable-vector`): `mnemo_vector.py` MCP server with `vector_search`, `vector_sync`, `vector_forget`, `vector_health`
- `post-commit` hook for non-blocking vector auto-sync with lock guard
- Gemini embedding provider support (`-VectorProvider gemini` / `--vector-provider gemini`)
- `customization.md` prompt template for AI-assisted repo customization

### Changed
- Lesson ID regex now requires exactly 3 digits (`L-XXX`)
- Tag validation is now enforced on all add-lesson/add-journal-entry helpers

### Fixed
- BOM handling in all PowerShell and shell readers
- CRLF/LF line ending consistency per file type

---

## [3.2.2] - 2024-12-01

### Added
- Atomic lessons with strict YAML frontmatter (`L-XXX-*.md`)
- Monthly journal + auto-generated digest + journal index
- SQLite FTS5 index (`memory.sqlite`) built when Python is available
- Tag vocabulary validation in linter
- Portable git hooks via `.githooks/`
- `add-lesson.ps1`, `add-journal-entry.ps1`, `clear-active.ps1` helper scripts

### Fixed
- Lesson ID uniqueness check in linter
- Token budget estimation in rebuild script

[Unreleased]: https://github.com/DiNaSoR/Mnemo/compare/v3.3.0...HEAD
[3.3.0]: https://github.com/DiNaSoR/Mnemo/compare/v3.2.2...v3.3.0
[3.2.2]: https://github.com/DiNaSoR/Mnemo/releases/tag/v3.2.2
