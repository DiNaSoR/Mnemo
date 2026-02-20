# Mnemo Tests

This folder contains regression and smoke tests for the Mnemo installers.

## Running tests

### Windows

```powershell
# All tests
powershell -ExecutionPolicy Bypass -File .\tests\test-installer.ps1

# Single test
powershell -ExecutionPolicy Bypass -File .\tests\test-installer.ps1 -TestName malformed-mcp-json
```

### macOS / Linux

```sh
# All tests
sh ./tests/test-installer.sh

# Single test
sh ./tests/test-installer.sh malformed-mcp-json
```

## Test categories

| Test name | What it verifies |
|-----------|-----------------|
| `scratch` | Fresh install produces all expected directories and files |
| `idempotent-no-force` | Re-run without `--force` skips all existing files |
| `idempotent-force` | Re-run with `--force` overwrites all files |
| `dry-run` | `--dry-run` produces no files on disk |
| `path-with-spaces` | Installer works when repo path contains spaces |
| `malformed-mcp-json` | Installer recovers gracefully from corrupt `.cursor/mcp.json` |
| `missing-python` | SQLite build skipped gracefully when Python is absent (mock) |
| `rebuild-lint` | `rebuild-memory-index` + `lint-memory` pass after fresh install |
| `gitignore-dedup` | Running installer twice does not duplicate `.gitignore` entries |
| `version-in-output` | Generated files reference the correct version from `VERSION` |
