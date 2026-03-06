# Mnemo Tests

This folder contains regression, smoke, modularization guardrail, and retrieval quality tests for the Mnemo memory system (`.mnemo` canonical + `.cursor/.agent` bridge compatibility).

## Running tests

### Windows

```powershell
# All installer regression tests
powershell -ExecutionPolicy Bypass -File .\tests\test-installer.ps1

# Single test
powershell -ExecutionPolicy Bypass -File .\tests\test-installer.ps1 -TestName malformed-mcp-json

# Installer modularization guardrail tests (entrypoint surface + module/template file presence)
powershell -ExecutionPolicy Bypass -File .\tests\test-installer-modularization.ps1
# Retrieval quality benchmark (FTS mode, no API key required)
python tests/retrieval/benchmark_runner.py --fixtures tests/retrieval/fixtures/

# Retrieval benchmark ablation mode (signal contribution matrix)
python tests/retrieval/benchmark_runner.py --fixtures tests/retrieval/fixtures/ --ablation

# Deep token-cost simulation for retrieval/context packing
python tests/retrieval/token_cost_simulation.py --show-per-query --output tests/retrieval/token_cost_report.json

# Contradiction detector evaluation (precision/recall/F1 + category breakdown + report artifacts)
python tests/retrieval/eval_contradiction.py --by-category --report-json tests/retrieval/reports/contradiction.json --report-csv tests/retrieval/reports/contradiction.csv

# Score-fusion weight sensitivity search + curve artifacts
python tests/retrieval/weight_sweep.py --curve-json tests/retrieval/reports/weight_curve.json --curve-csv tests/retrieval/reports/weight_curve.csv

# End-to-end pipeline simulation (install -> retrieve -> store -> compact -> resync)
python tests/retrieval/e2e_pipeline_simulation.py --output tests/retrieval/e2e_pipeline_report.json
```

### macOS / Linux

```sh
# All installer regression tests
sh ./tests/test-installer.sh

# Single test
sh ./tests/test-installer.sh malformed-mcp-json

# Retrieval quality benchmark
python3 tests/retrieval/benchmark_runner.py --fixtures tests/retrieval/fixtures/

# Retrieval benchmark ablation mode
python3 tests/retrieval/benchmark_runner.py --fixtures tests/retrieval/fixtures/ --ablation

# Contradiction detector evaluation + category breakdown + report artifacts
python3 tests/retrieval/eval_contradiction.py --by-category --report-json tests/retrieval/reports/contradiction.json --report-csv tests/retrieval/reports/contradiction.csv

# Score-fusion weight sensitivity search + curve artifacts
python3 tests/retrieval/weight_sweep.py --curve-json tests/retrieval/reports/weight_curve.json --curve-csv tests/retrieval/reports/weight_curve.csv
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
| `malformed-mcp-json` | Installer recovers gracefully from corrupt `.cursor/mcp.json` and restores canonical MCP bridge target |
| `missing-python` | SQLite build skipped gracefully when Python is absent (mock) |
| `rebuild-lint` | `rebuild-memory-index` + `lint-memory` pass after fresh install |
| `gitignore-dedup` | Running installer twice does not duplicate `.gitignore` entries |
| `version-in-output` | Generated files reference the correct version from `VERSION` |
| `legacy-migration-bridge` | Legacy `.cursor/.agent` memory/rules are migrated into `.mnemo` and remain visible via bridges |
| `bridge-repair-idempotent` | Installer recreates broken `.cursor` bridge paths on re-run |

### Modularization guardrail (`test-installer-modularization.ps1`)

| Test name | What it verifies |
|-----------|-----------------|
| `installer-entrypoint-surface` | Unified installer entrypoint stays small enough to remain maintainable |
| `no-large-heredoc-in-entrypoint` | No large heredocs re-introduced into the installer entrypoint |
| `module-files-present` | All installer module files exist under `scripts/memory/installer/` |
| `template-files-present` | All template files exist under `scripts/memory/installer/templates/` |
| `entrypoint-uses-installer-modules` | Entrypoint delegates to installer modules instead of embedding large install logic |
| `installed-scripts-match-templates` | Installer copies template content to target correctly |

### Retrieval quality benchmark (`tests/retrieval/`)

| File | What it does |
|------|-------------|
| `benchmark_runner.py` | Computes hit@k, nDCG@k, MRR, p50/p95 latency, token cost |
| `drift_check.py` | Detects quality regression vs saved baseline |
| `token_cost_simulation.py` | Simulates token usage by stage (query/candidates/context pack/prompt total) across top-k + budget scenarios |
| `eval_contradiction.py` | Evaluates contradiction detector precision/recall/F1 with optional per-category output and JSON/CSV reports |
| `weight_sweep.py` | Grid-searches score-fusion weights and emits best configs plus sensitivity-curve JSON/CSV artifacts |
| `e2e_pipeline_simulation.py` | Simulates full user journey from install to retrieval, memory write, compact/rebuild, vector resync, and re-retrieval |
| `fixtures/*.json` | Multi-category benchmark fixtures (`basic`, `procedural`, `episodic`, `entity`, contradiction pairs) |

## Adding fixtures

To add retrieval test cases, add or edit JSON files under `tests/retrieval/fixtures/`:

```json
{
  "query": "your search query",
  "description": "What this tests",
  "category": "basic|procedural|episodic|entity",
  "difficulty": "easy|medium|hard",
  "notes": "optional note for maintainers",
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
3. Check `.mnemo/memory/.autonomy/runner.lock` (or `.cursor/memory/.autonomy/runner.lock` bridge) — if stale (>10 min old), delete it
4. Run `vector_sync` manually in Cursor to force-rebuild the vector index
5. Run `powershell -ExecutionPolicy Bypass -File scripts/memory/rebuild-memory-index.ps1` for FTS index
