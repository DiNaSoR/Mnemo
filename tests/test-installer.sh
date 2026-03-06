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

cursor_rules_only_mdc() {
  dest="$1"
  invalid="$(find "$dest/.cursor/rules" -type f ! -name '*.mdc' 2>/dev/null | head -n 1 || true)"
  [ -z "$invalid" ]
}

skill_dir_only_expected() {
  dest="$1"
  skill_dir="$dest/.cursor/skills/mnemo-codebase-optimizer"
  [ -f "$skill_dir/SKILL.md" ] || return 1
  [ -f "$skill_dir/reference.md" ] || return 1
  count="$(find "$skill_dir" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
  [ "$count" -eq 2 ]
}

detect_python_cmd() {
  if command -v python3 >/dev/null 2>&1; then
    printf "python3"
  elif command -v python >/dev/null 2>&1; then
    printf "python"
  else
    printf ""
  fi
}

PYTHON_CMD="$(detect_python_cmd)"

has_sqlite_vec() {
  [ -n "$PYTHON_CMD" ] && "$PYTHON_CMD" -c 'import sqlite_vec' >/dev/null 2>&1
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
    "scripts/memory/add-journal-entry.sh" "scripts/memory/add-journal-entry.ps1" \
    "scripts/memory/add-lesson.sh" "scripts/memory/add-lesson.ps1" \
    "scripts/memory/clear-active.sh" "scripts/memory/clear-active.ps1" \
    "scripts/memory/lint-memory.sh" "scripts/memory/lint-memory.ps1" \
    "scripts/memory/query-memory.sh" "scripts/memory/query-memory.ps1" \
    "scripts/memory/rebuild-memory-index.sh" "scripts/memory/rebuild-memory-index.ps1" \
    "scripts/memory/customization.md"; do
    [ -f "$dest/$f" ] || { fail scratch "Missing file: $f"; ok=0; break; }
  done
  if [ "$ok" -eq 1 ]; then
    for f in \
      "scripts/memory/add-journal-entry.sh" \
      "scripts/memory/add-lesson.sh" \
      "scripts/memory/clear-active.sh" \
      "scripts/memory/lint-memory.sh" \
      "scripts/memory/query-memory.sh" \
      "scripts/memory/rebuild-memory-index.sh"; do
      [ -x "$dest/$f" ] || { fail scratch "Shell helper not executable: $f"; ok=0; break; }
    done
  fi
  if [ "$ok" -eq 1 ] && ! cursor_rules_only_mdc "$dest"; then
    fail scratch ".cursor/rules contains non-.mdc files"
    ok=0
  fi
  if [ "$ok" -eq 1 ] && ! skill_dir_only_expected "$dest"; then
    fail scratch ".cursor/skills/mnemo-codebase-optimizer contains unexpected entries"
    ok=0
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

# ─── TEST: posix-helper-smoke ──────────────────────────────────────────────────
if should_run posix-helper-smoke; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  run_installer "$dest" >/dev/null
  ok=1

  printf 'temporary scratch\n' >> "$dest/.mnemo/memory/active-context.md"

  (cd "$dest" && sh ./scripts/memory/clear-active.sh >/dev/null) || ok=0
  if [ "$ok" -eq 1 ] && ! grep -q "## Current Goal" "$dest/.mnemo/memory/active-context.md"; then
    fail posix-helper-smoke "clear-active.sh did not restore the active context template"
    ok=0
  fi

  if [ "$ok" -eq 1 ]; then
    (cd "$dest" && sh ./scripts/memory/add-lesson.sh --title "Smoke lesson" --tags "Process" --rule "Keep shell helpers working" >/dev/null) || ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    (cd "$dest" && sh ./scripts/memory/add-journal-entry.sh --tags "Process" --title "Smoke journal entry" --files "scripts/memory/lint-memory.sh" >/dev/null) || ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    (cd "$dest" && sh ./scripts/memory/rebuild-memory-index.sh >/dev/null) || ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    query_out="$(cd "$dest" && sh ./scripts/memory/query-memory.sh --query "Smoke lesson" --area Lessons --format AI)"
    printf '%s\n' "$query_out" | grep -q "lessons/" || ok=0
  fi
  if [ "$ok" -eq 1 ]; then
    (cd "$dest" && sh ./scripts/memory/lint-memory.sh >/dev/null) || ok=0
  fi

  if [ "$ok" -eq 1 ] \
    && [ -f "$dest/.mnemo/memory/lessons/index.md" ] \
    && [ -f "$dest/.mnemo/memory/journal-index.md" ]; then
    pass posix-helper-smoke
  else
    fail posix-helper-smoke "POSIX helper flow failed (clear/add/rebuild/query/lint)"
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
  printf 'legacy cursor note\n' > "$dest/.cursor/rules/legacy-note.md"
  printf 'legacy agent rule\n' > "$dest/.agent/rules/legacy-agent.md"
  run_installer "$dest" >/dev/null
  if [ -f "$dest/.mnemo/memory/legacy-note.md" ] \
    && [ -f "$dest/.mnemo/rules/cursor/legacy-rule.mdc" ] \
    && [ -f "$dest/.mnemo/rules/agent/legacy-agent.md" ] \
    && [ -f "$dest/.cursor/memory/legacy-note.md" ] \
    && [ ! -f "$dest/.cursor/rules/legacy-note.md" ] \
    && [ ! -f "$dest/.mnemo/rules/cursor/legacy-note.md" ] \
    && [ -f "$dest/.mnemo/legacy/cursor-rules-non-mdc/bridge/legacy-note.md" ] \
    && cursor_rules_only_mdc "$dest"; then
    pass legacy-migration-bridge
  else
    fail legacy-migration-bridge "Cursor rules contract violated during legacy migration"
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

# ─── TEST: skill-orphan-quarantine ───────────────────────────────────────────
if should_run skill-orphan-quarantine; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  run_installer "$dest" >/dev/null
  mkdir -p "$dest/.cursor/skills/mnemo-codebase-optimizer/drafts"
  mkdir -p "$dest/.cursor/skills/other-skill"
  printf 'legacy note\n' > "$dest/.cursor/skills/mnemo-codebase-optimizer/notes.md"
  printf 'todo\n' > "$dest/.cursor/skills/mnemo-codebase-optimizer/drafts/todo.txt"
  printf 'keep me\n' > "$dest/.cursor/skills/other-skill/keep.txt"
  out="$(run_installer "$dest")"
  quarantine_notes="$(find "$dest/.mnemo/legacy/skill-orphans/mnemo-codebase-optimizer" -type f -name 'notes.md' 2>/dev/null | head -n 1 || true)"
  quarantine_todo="$(find "$dest/.mnemo/legacy/skill-orphans/mnemo-codebase-optimizer" -type f -name 'todo.txt' 2>/dev/null | head -n 1 || true)"
  if [ -f "$dest/.cursor/skills/mnemo-codebase-optimizer/notes.md" ]; then
    fail skill-orphan-quarantine "Skill orphan file was not quarantined"
  elif [ -d "$dest/.cursor/skills/mnemo-codebase-optimizer/drafts" ]; then
    fail skill-orphan-quarantine "Skill orphan directory was not quarantined"
  elif [ -z "$quarantine_notes" ]; then
    fail skill-orphan-quarantine "Quarantine copy for notes.md missing"
  elif [ -z "$quarantine_todo" ]; then
    fail skill-orphan-quarantine "Quarantine copy for drafts/todo.txt missing"
  elif [ ! -f "$dest/.cursor/skills/other-skill/keep.txt" ]; then
    fail skill-orphan-quarantine "Sibling skill was modified"
  elif ! skill_dir_only_expected "$dest"; then
    fail skill-orphan-quarantine "Managed skill directory still contains unexpected entries"
  elif ! echo "$out" | grep -q "Moved .*skill orphan"; then
    fail skill-orphan-quarantine "Installer did not report quarantined skill orphans"
  else
    pass skill-orphan-quarantine
  fi
  rm -rf "$dest"
fi

# ─── TEST: skill-orphan-dry-run ──────────────────────────────────────────────
if should_run skill-orphan-dry-run; then
  dest="$(make_dest)"
  mkdir -p "$dest"
  run_installer "$dest" >/dev/null
  mkdir -p "$dest/.cursor/skills/mnemo-codebase-optimizer/drafts"
  printf 'legacy note\n' > "$dest/.cursor/skills/mnemo-codebase-optimizer/notes.md"
  printf 'todo\n' > "$dest/.cursor/skills/mnemo-codebase-optimizer/drafts/todo.txt"
  out="$(run_installer "$dest" --dry-run)"
  if [ ! -f "$dest/.cursor/skills/mnemo-codebase-optimizer/notes.md" ]; then
    fail skill-orphan-dry-run "Dry-run removed orphan file"
  elif [ ! -f "$dest/.cursor/skills/mnemo-codebase-optimizer/drafts/todo.txt" ]; then
    fail skill-orphan-dry-run "Dry-run removed orphan directory contents"
  elif [ -d "$dest/.mnemo/legacy/skill-orphans" ]; then
    fail skill-orphan-dry-run "Dry-run created quarantine directory"
  elif ! echo "$out" | grep -q "WOULD MOVE .*skill orphan"; then
    fail skill-orphan-dry-run "Dry-run did not report skill orphan quarantine"
  else
    pass skill-orphan-dry-run
  fi
  rm -rf "$dest"
fi

# ─── TEST: vector-autonomy-upgrade ─────────────────────────────────────────────
if should_run vector-autonomy-upgrade; then
  dest="$(make_dest)"
  mkdir -p "$dest/scripts/memory/autonomy"
  for f in \
    "__init__.py" "common.py" "schema.py" "runner.py" \
    "ingest_pipeline.py" "lifecycle_engine.py" "entity_resolver.py" \
    "retrieval_router.py" "reranker.py" "context_safety.py" \
    "vault_policy.py" "policies.yaml"; do
    : > "$dest/scripts/memory/autonomy/$f"
  done
  run_installer "$dest" --enable-vector >/dev/null 2>&1
  if [ -f "$dest/scripts/memory/autonomy/contradiction.py" ] \
    && [ -f "$dest/scripts/memory/autonomy/token_counter.py" ]; then
    pass vector-autonomy-upgrade
  else
    fail vector-autonomy-upgrade "Vector upgrade did not install newly required autonomy modules"
  fi
  rm -rf "$dest"
fi

# ─── TEST: vector-cli-empty-query ─────────────────────────────────────────────
if should_run vector-cli-empty-query; then
  if ! has_sqlite_vec; then
    skip_test vector-cli-empty-query "python/python3 with sqlite_vec unavailable"
  else
    dest="$(make_dest)"
    mkdir -p "$dest"
    run_installer "$dest" --enable-vector >/dev/null 2>&1
    if [ -f "$dest/scripts/memory/mnemo_vector.py" ]; then
      out="$(cd "$dest" && "$PYTHON_CMD" scripts/memory/mnemo_vector.py search "" --top-k 3 2>&1)" || true
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
  if ! has_sqlite_vec; then
    skip_test vector-cli-topk-bounds "python/python3 with sqlite_vec unavailable"
  else
    dest="$(make_dest)"
    mkdir -p "$dest"
    run_installer "$dest" --enable-vector >/dev/null 2>&1
    if [ -f "$dest/scripts/memory/mnemo_vector.py" ]; then
      # negative top_k should not crash
      out="$(cd "$dest" && "$PYTHON_CMD" scripts/memory/mnemo_vector.py search "test" --top-k -5 2>&1)" || true
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
