# Mnemo Tests

This folder contains regression, smoke, modularization guardrail, and retrieval quality tests for the Mnemo memory system.

## Running tests

### Windows

```powershell
# All installer regression tests
powershell -ExecutionPolicy Bypass -File .\tests\test-installer.ps1

# Single test
powershell -ExecutionPolicy Bypass -File .\tests\test-installer.ps1 -TestName malformed-mcp-json

# Modularization guardrail tests (LOC limits + module/template file presence)
powershell -ExecutionPolicy Bypass -File .\tests\test-installer-modularization.ps1

# Retrieval quality benchmark (FTS mode, no API key required)
python tests/retrieval/benchmark_runner.py --fixtures tests/retrieval/fixtures/
```

### macOS / Linux

```sh
# All installer regression tests
sh ./tests/test-installer.sh

# Single test
sh ./tests/test-installer.sh malformed-mcp-json

# Retrieval quality benchmark
python3 tests/retrieval/benchmark_runner.py --fixtures tests/retrieval/fixtures/
```

## Test categories

### Installer regression (`test-installer.ps1` / `test-installer.sh`)

| Test name | What it verifies |
|-----------|-----------------|
| `scratch` | Fresh install produces all expected directories and files |
| `idempotent-no-force` | Re-run without `--force` skips all existing files |
| `idempotent-vector-no-force` | Re-run with vector mode without `--force` does not rewrite unchanged vector artifacts |
| `idempotent-force` | Re-run with `--force` overwrites all files |
| `dry-run` | `--dry-run` produces no files on disk |
| `dry-run-vector` | `--dry-run` with vector mode performs no writes or dependency installs |
| `path-with-spaces` | Installer works when repo path contains spaces |
| `malformed-mcp-json` | Installer recovers gracefully from corrupt `.cursor/mcp.json` |
| `missing-python` | SQLite build skipped gracefully when Python is absent (mock) |
| `rebuild-lint` | `rebuild-memory-index` + `lint-memory` pass after fresh install |
| `gitignore-dedup` | Running installer twice does not duplicate `.gitignore` entries |
| `version-in-output` | Generated files reference the correct version from `VERSION` |

### Modularization guardrail (`test-installer-modularization.ps1`)

| Test name | What it verifies |
|-----------|-----------------|
| `memory-ps1-loc` | `memory.ps1` stays within 400-line soft / 500-line hard limit |
| `no-large-heredoc-in-entrypoint` | No large heredocs re-introduced into `memory.ps1` |
| `module-files-present` | All installer module files exist under `scripts/memory/installer/` |
| `template-files-present` | All template files exist under `scripts/memory/installer/templates/` |
| `entrypoint-uses-bootstrap` | `memory.ps1` dot-sources `bootstrap.ps1` |
| `installed-scripts-match-templates` | Installer copies template content to target correctly |

### Retrieval quality benchmark (`tests/retrieval/`)

| File | What it does |
|------|-------------|
| `benchmark_runner.py` | Computes hit@k, nDCG@k, MRR, p50/p95 latency, token cost |
| `drift_check.py` | Detects quality regression vs saved baseline |
| `fixtures/basic_queries.json` | Ground-truth query→relevant_ref pairs for evaluation |

## Adding fixtures

To add retrieval test cases, edit `tests/retrieval/fixtures/basic_queries.json`:

```json
{
  "query": "your search query",
  "description": "What this tests",
  "relevant_refs": ["expected/file.md", "another/path.md"]
}
```

## Autonomous mode testing

The autonomous memory runtime (`scripts/memory/autonomy/`) is tested via:
- Syntax checks in CI (`autonomy-syntax` job)
- End-to-end ingestion in the nightly benchmark workflow
- Manual: `python scripts/memory/autonomy/runner.py --mode once` from repo root (requires vector setup)

### Fallback / debug when autonomous runner fails

1. Run `vector_health` in Cursor to check DB + API status
2. Run `python scripts/memory/autonomy/runner.py --mode once` from repo root to see runner output
3. Check `.cursor/memory/.autonomy/runner.lock` — if stale (>10 min old), delete it
4. Run `vector_sync` manually in Cursor to force-rebuild the vector index
5. Run `powershell -ExecutionPolicy Bypass -File scripts/memory/rebuild-memory-index.ps1` for FTS index
