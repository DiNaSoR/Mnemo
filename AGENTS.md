# AGENTS.md

## Cursor Cloud specific instructions

**Product**: Mnemo is a CLI tool (`@dinasor/mnemo-cli`) that scaffolds a structured `.mnemo/` memory layer for AI coding agents. It is NOT a web app or server — it's a Node.js CLI + POSIX shell installer + optional Python vector layer.

### Running tests

All test commands are documented in `tests/README.md`. Key commands for Linux:

| Test | Command |
|------|---------|
| POSIX installer regression (15 tests) | `sh ./tests/test-installer.sh` |
| Python syntax checks | `python3 -m py_compile scripts/memory/installer/templates/autonomy/*.py` |
| Retrieval quality benchmark (FTS) | Install Mnemo to a temp dir first, then run `python3 tests/retrieval/benchmark_runner.py --fixtures tests/retrieval/fixtures/` from that dir |
| Token cost simulation | `python3 tests/retrieval/token_cost_simulation.py` (from an installed Mnemo dir) |
| Version consistency | Check `VERSION` is valid semver and `CHANGELOG.md` has version sections |
| Modularization guard | Verify `memory.ps1` is under 500 lines; all module/template files exist |

### Running the CLI

Non-interactive (CI-safe): `node bin/mnemo.js --yes --repo-root <target-dir> --project-name <name>`

The CLI runs the POSIX installer (`memory_mac.sh`) on Linux. There are no npm runtime dependencies to install — `package.json` has zero `dependencies`.

### Gotchas

- The `e2e_pipeline_simulation.py` test requires a real `GEMINI_API_KEY` or `OPENAI_API_KEY` environment variable. CI runs it with `|| true`. The FTS-mode benchmark (`benchmark_runner.py`) works without API keys.
- The `test-installer.sh` script emits harmless `[: Illegal number:` warnings on `dash` (the default `/bin/sh` on Ubuntu) in the `gitignore-dedup` test — this does not affect results.
- Python packages needed for full test coverage: `pyyaml`, `sqlite-vec`, `mcp[cli]>=1.2.0,<2.0`.
- PowerShell tests (`test-installer.ps1`, `test-installer-modularization.ps1`) are Windows-only and require `pwsh`. They are not runnable in the Cloud Agent Linux environment.
