#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

resolve_memory_dir() {
  for candidate in "$ROOT/.mnemo/memory" "$ROOT/.cursor/memory"; do
    if [ -d "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  printf '%s' "$ROOT/.mnemo/memory"
}

MEM="$(resolve_memory_dir)"
ACTIVE="$MEM/active-context.md"
mkdir -p "$MEM"
cat > "$ACTIVE" <<'T'
# Active Context (Session Scratchpad)

Priority: this overrides older journal history *for this session only*.

CLEAR this file when the task is done:
- Run `scripts/memory/clear-active.sh` or `scripts/memory/clear-active.ps1`

## Current Goal
-

## Files in Focus
-

## Findings / Decisions
-

## Temporary Constraints
-

## Blockers
-
T

echo "Cleared: $ACTIVE"
