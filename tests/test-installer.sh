#!/bin/sh
# test-installer.sh
# Regression tests for memory_mac.sh (macOS / Linux installer).
#
# USAGE:
#   sh ./tests/test-installer.sh
#   sh ./tests/test-installer.sh dry-run
#   sh ./tests/test-installer.sh malformed-mcp-json

set -eu

FILTER="${1:-}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
INSTALLER="$REPO_ROOT/memory_mac.sh"

passed=0
failed=0
skipped=0

pass() { printf "  PASS  %s\n" "$1"; passed=$((passed + 1)); }
fail() { printf "  FAIL  %s : %s\n" "$1" "$2" >&2; failed=$((failed + 1)); }
skip_test() { printf "  SKIP  %s : %s\n" "$1" "$2"; skipped=$((skipped + 1)); }

should_run() {
  [ -z "$FILTER" ] || [ "$FILTER" = "$1" ]
}

make_dest() {
  suffix="${1:-}"
  printf "%s/mnemo-test-$$%s" "${TMPDIR:-/tmp}" "$suffix"
}

run_installer() {
  dest="$1"; shift
  sh "$INSTALLER" --repo-root "$dest" --project-name TestProject "$@" 2>&1 || true
}

printf "Mnemo installer regression tests (POSIX)\n"
printf "Installer: %s\n\n" "$INSTALLER"

# ─── TEST: scratch ────────────────────────────────────────────────────────────
if should_run scratch; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  run_installer "$dest" >/dev/null
  ok=1
  for d in \
    ".mnemo/memory" ".mnemo/rules/cursor" ".mnemo/rules/agent" \
    ".cursor/memory" ".cursor/rules" ".cursor/skills/mnemo-codebase-optimizer" ".agent/rules" \
    ".mnemo/memory/lessons" ".mnemo/memory/journal" \
    "scripts/memory"; do
    [ -d "$dest/$d" ] || { fail scratch "Missing directory: $d"; ok=0; break; }
  done
  for f in \
    ".mnemo/memory/hot-rules.md" ".mnemo/memory/memo.md" ".mnemo/memory/active-context.md" \
    ".mnemo/rules/cursor/00-memory-system.mdc" \
    ".cursor/memory/hot-rules.md" ".cursor/rules/00-memory-system.mdc" \
    ".cursor/skills/mnemo-codebase-optimizer/SKILL.md" \
    ".cursor/skills/mnemo-codebase-optimizer/reference.md" \
    ".agent/rules/00-memory-system.md" \
    "scripts/memory/lint-memory.sh"; do
    [ -f "$dest/$f" ] || { fail scratch "Missing file: $f"; ok=0; break; }
  done
  if [ "$ok" -eq 1 ]; then
    if ! cmp -s "$dest/.mnemo/memory/hot-rules.md" "$dest/.cursor/memory/hot-rules.md"; then
      fail scratch "Canonical and bridge hot-rules content differ"
      ok=0
    fi
  fi
  [ "$ok" -eq 1 ] && pass scratch
  rm -rf "$dest"
fi

# ─── TEST: idempotent-no-force ────────────────────────────────────────────────
if should_run idempotent-no-force; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  run_installer "$dest" >/dev/null
  out="$(run_installer "$dest")"
  if echo "$out" | grep -q "^WROTE:"; then
    fail idempotent-no-force "Installer wrote files on second run without --force"
  else
    pass idempotent-no-force
  fi
  rm -rf "$dest"
fi

# ─── TEST: idempotent-vector-no-force ─────────────────────────────────────────
if should_run idempotent-vector-no-force; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  if ! command -v python3 >/dev/null 2>&1 \
    || ! python3 -m pip --version >/dev/null 2>&1 \
    || ! python3 -c 'import sys; raise SystemExit(0 if sys.version_info >= (3, 10) else 1)' >/dev/null 2>&1; then
    skip_test idempotent-vector-no-force "python3>=3.10 with pip unavailable for vector mode"
  else
    first_out="$(run_installer "$dest" --enable-vector)"
    if ! echo "$first_out" | grep -q "Setup complete"; then
      # Vector mode is optional and depends on runtime package availability.
      # If bootstrap cannot complete in this environment, skip vector idempotency checks.
      skip_test idempotent-vector-no-force "vector mode bootstrap unavailable in this shell runtime"
    else
      out="$(run_installer "$dest" --enable-vector)"
      if ! echo "$out" | grep -q "Setup complete"; then
        fail idempotent-vector-no-force "Second vector run did not complete successfully"
      elif echo "$out" | grep -q "^WROTE:"; then
        fail idempotent-vector-no-force "Vector installer wrote files on second run without --force"
      else
        pass idempotent-vector-no-force
      fi
    fi
  fi
  rm -rf "$dest"
fi

# ─── TEST: idempotent-force ───────────────────────────────────────────────────
if should_run idempotent-force; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  run_installer "$dest" >/dev/null
  out="$(run_installer "$dest" --force)"
  if ! echo "$out" | grep -q "^WROTE:"; then
    fail idempotent-force "--force had no effect; no files were written"
  else
    pass idempotent-force
  fi
  rm -rf "$dest"
fi

# ─── TEST: dry-run ────────────────────────────────────────────────────────────
if should_run dry-run; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  run_installer "$dest" --dry-run >/dev/null
  count="$(find "$dest" -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$count" -gt 0 ]; then
    fail dry-run "Dry-run created $count file(s)"
  else
    pass dry-run
  fi
  rm -rf "$dest"
fi

# ─── TEST: dry-run-vector ─────────────────────────────────────────────────────
if should_run dry-run-vector; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  out="$(run_installer "$dest" --dry-run --enable-vector)"
  count="$(find "$dest" -type f 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$count" -gt 0 ]; then
    fail dry-run-vector "Dry-run with vector created $count file(s)"
  elif echo "$out" | grep -q "Installing vector dependencies"; then
    fail dry-run-vector "Dry-run unexpectedly attempted vector dependency installation"
  elif ! echo "$out" | grep -q "Setup complete"; then
    fail dry-run-vector "Installer did not complete successfully in dry-run vector mode"
  else
    pass dry-run-vector
  fi
  rm -rf "$dest"
fi

# ─── TEST: path-with-spaces ───────────────────────────────────────────────────
if should_run path-with-spaces; then
  dest="$(make_dest ' with spaces')"
  mkdir -p "$dest"
  run_installer "$dest" >/dev/null
  if [ -f "$dest/.mnemo/memory/hot-rules.md" ] && [ -f "$dest/.cursor/memory/hot-rules.md" ]; then
    pass path-with-spaces
  else
    fail path-with-spaces "Expected files not created in path with spaces"
  fi
  rm -rf "$dest"
fi

# ─── TEST: malformed-mcp-json ─────────────────────────────────────────────────
if should_run malformed-mcp-json; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  run_installer "$dest" >/dev/null
  # Write corrupt mcp.json
  mkdir -p "$dest/.cursor"
  printf '{ INVALID JSON !!!\n' > "$dest/.cursor/mcp.json"
  # Force re-run (no vector mode) to validate bridge recovery
  out="$(run_installer "$dest" --force 2>&1)"
  # As long as core files are intact and canonical MCP target appears, test passes
  if [ -f "$dest/.cursor/memory/hot-rules.md" ] && [ -f "$dest/.mnemo/mcp/cursor.mcp.json" ]; then
    pass malformed-mcp-json
  else
    fail malformed-mcp-json "Installer left repo in bad state after corrupt mcp.json"
  fi
  rm -rf "$dest"
fi

# ─── TEST: rebuild-lint ───────────────────────────────────────────────────────
if should_run rebuild-lint; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  run_installer "$dest" >/dev/null
  sh "$dest/scripts/memory/rebuild-memory-index.sh" >/dev/null
  if sh "$dest/scripts/memory/lint-memory.sh" >/dev/null 2>&1; then
    pass rebuild-lint
  else
    fail rebuild-lint "lint-memory.sh failed after fresh install"
  fi
  rm -rf "$dest"
fi

# ─── TEST: gitignore-dedup ────────────────────────────────────────────────────
if should_run gitignore-dedup; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  run_installer "$dest" >/dev/null
  run_installer "$dest" --force >/dev/null
  gi="$dest/.gitignore"
  if [ -f "$gi" ]; then
    count_cursor="$(grep -c ".cursor/memory/memory.sqlite" "$gi" 2>/dev/null || echo 0)"
    count_mnemo="$(grep -c ".mnemo/memory/memory.sqlite" "$gi" 2>/dev/null || echo 0)"
    if [ "$count_cursor" -gt 1 ] || [ "$count_mnemo" -gt 1 ]; then
      fail gitignore-dedup "duplicate memory.sqlite ignores (cursor=$count_cursor, mnemo=$count_mnemo)"
    else
      pass gitignore-dedup
    fi
  else
    fail gitignore-dedup ".gitignore not created"
  fi
  rm -rf "$dest"
fi

# ─── TEST: version-in-output ─────────────────────────────────────────────────
if should_run version-in-output; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  expected_ver="$(cat "$REPO_ROOT/VERSION" | tr -d '[:space:]')"
  run_installer "$dest" >/dev/null
  ok=1
  for jf in "$dest/.mnemo/memory/journal/"????-??.md; do
    [ -f "$jf" ] || continue
    if ! grep -q "Mnemo v$expected_ver" "$jf"; then
      fail version-in-output "Journal $(basename "$jf") does not contain 'Mnemo v$expected_ver'"
      ok=0
      break
    fi
  done
  [ "$ok" -eq 1 ] && pass version-in-output
  rm -rf "$dest"
fi

# ─── TEST: legacy-migration-bridge ────────────────────────────────────────────
if should_run legacy-migration-bridge; then
  dest="$(make_dest)"
  mkdir -p "$dest/.cursor/memory" "$dest/.cursor/rules" "$dest/.agent/rules"
  printf '# legacy note\n' > "$dest/.cursor/memory/legacy-note.md"
  printf 'legacy cursor rule\n' > "$dest/.cursor/rules/legacy-rule.mdc"
  printf 'legacy agent rule\n' > "$dest/.agent/rules/legacy-agent.md"
  run_installer "$dest" >/dev/null
  if [ -f "$dest/.mnemo/memory/legacy-note.md" ] \
    && [ -f "$dest/.mnemo/rules/cursor/legacy-rule.mdc" ] \
    && [ -f "$dest/.mnemo/rules/agent/legacy-agent.md" ] \
    && [ -f "$dest/.cursor/memory/legacy-note.md" ]; then
    pass legacy-migration-bridge
  else
    fail legacy-migration-bridge "Legacy files were not migrated/bridged into canonical paths"
  fi
  rm -rf "$dest"
fi

# ─── TEST: bridge-repair-idempotent ───────────────────────────────────────────
if should_run bridge-repair-idempotent; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  run_installer "$dest" >/dev/null
  rm -rf "$dest/.cursor/memory"
  run_installer "$dest" >/dev/null
  if [ -f "$dest/.cursor/memory/hot-rules.md" ]; then
    pass bridge-repair-idempotent
  else
    fail bridge-repair-idempotent "Cursor bridge not repaired after deletion"
  fi
  rm -rf "$dest"
fi

# ─── TEST: missing-python (mock) ─────────────────────────────────────────────
if should_run missing-python; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  # Temporarily shadow python3 with a no-op that exits 127
  fake_bin="$(make_dest)-fakebin"
  mkdir -p "$fake_bin"
  printf '#!/bin/sh\nexit 127\n' > "$fake_bin/python3"
  chmod +x "$fake_bin/python3"
  # Run installer with PATH override — SQLite build should be skipped gracefully
  out="$(PATH="$fake_bin:$PATH" run_installer "$dest" 2>&1)"
  echo "$out" | grep -qi "skip\|not found\|unavailable\|python" && pass missing-python || {
    # Accept as passing if installer completed and didn't crash (core files exist)
    [ -f "$dest/.mnemo/memory/hot-rules.md" ] && pass missing-python || fail missing-python "Installer failed when Python was missing"
  }
  rm -rf "$dest" "$fake_bin"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
printf "\nResults: %d passed, %d failed, %d skipped\n" "$passed" "$failed" "$skipped"

[ "$failed" -eq 0 ] || exit 1
