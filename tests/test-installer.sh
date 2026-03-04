#!/bin/sh
# test-installer.sh
# Regression tests for the unified Node.js installer.
#
# USAGE:
#   sh ./tests/test-installer.sh
#   sh ./tests/test-installer.sh dry-run
#   sh ./tests/test-installer.sh scratch

set -eu

FILTER="${1:-}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

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
  node "$REPO_ROOT/bin/mnemo.js" --yes --repo-root "$dest" --project-name TestProject "$@" 2>&1 || true
}

printf "Mnemo installer regression tests (Node.js unified)\n"
printf "Installer: node bin/mnemo.js\n\n"

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
    "scripts/memory/lint-memory.ps1"; do
    [ -f "$dest/$f" ] || { fail scratch "Missing file: $f"; ok=0; break; }
  done
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

# ─── TEST: gitignore-dedup ────────────────────────────────────────────────────
if should_run gitignore-dedup; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  run_installer "$dest" >/dev/null
  run_installer "$dest" --force >/dev/null
  gi="$dest/.gitignore"
  if [ -f "$gi" ]; then
    count_begin="$(grep -c '>>> Mnemo' "$gi" 2>/dev/null)" || count_begin=0
    if [ "$count_begin" -gt 1 ]; then
      fail gitignore-dedup "duplicate Mnemo blocks ($count_begin occurrences)"
    else
      pass gitignore-dedup
    fi
  else
    fail gitignore-dedup ".gitignore not created"
  fi
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

# ─── TEST: vector-cli-empty-query ─────────────────────────────────────────────
if should_run vector-cli-empty-query; then
  if ! command -v python3 >/dev/null 2>&1 \
    || ! python3 -c 'import sqlite_vec' 2>/dev/null; then
    skip_test vector-cli-empty-query "python3 with sqlite_vec unavailable"
  else
    dest="$(make_dest)"
    mkdir -p "$dest"
    run_installer "$dest" --enable-vector >/dev/null 2>&1
    if [ -f "$dest/scripts/memory/mnemo_vector.py" ]; then
      out="$(cd "$dest" && python3 scripts/memory/mnemo_vector.py search "" --top-k 3 2>&1)" || true
      if echo "$out" | grep -qi "provide a search query\|please provide"; then
        pass vector-cli-empty-query
      else
        fail vector-cli-empty-query "Empty query did not return user-friendly message: $out"
      fi
    else
      skip_test vector-cli-empty-query "vector install did not produce mnemo_vector.py"
    fi
    rm -rf "$dest"
  fi
fi

# ─── TEST: vector-cli-topk-bounds ─────────────────────────────────────────────
if should_run vector-cli-topk-bounds; then
  if ! command -v python3 >/dev/null 2>&1 \
    || ! python3 -c 'import sqlite_vec' 2>/dev/null; then
    skip_test vector-cli-topk-bounds "python3 with sqlite_vec unavailable"
  else
    dest="$(make_dest)"
    mkdir -p "$dest"
    run_installer "$dest" --enable-vector >/dev/null 2>&1
    if [ -f "$dest/scripts/memory/mnemo_vector.py" ]; then
      # negative top_k should not crash
      out="$(cd "$dest" && python3 scripts/memory/mnemo_vector.py search "test" --top-k -5 2>&1)" || true
      if echo "$out" | grep -qi "error\|traceback"; then
        fail vector-cli-topk-bounds "Negative top_k caused a crash: $out"
      else
        pass vector-cli-topk-bounds
      fi
    else
      skip_test vector-cli-topk-bounds "vector install did not produce mnemo_vector.py"
    fi
    rm -rf "$dest"
  fi
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
printf "\nResults: %d passed, %d failed, %d skipped\n" "$passed" "$failed" "$skipped"

[ "$failed" -eq 0 ] || exit 1
