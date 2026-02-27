#!/bin/sh
# Mnemo memory installer (macOS / POSIX shell)
# Zero extra requirements on macOS: uses /bin/sh + standard Unix tools.
#
# Usage (from repo root, macOS Terminal):
#   sh ./memory_mac.sh
#   sh ./memory_mac.sh --project-name "MyProject"
#   sh ./memory_mac.sh --force
#   sh ./memory_mac.sh --dry-run
#   sh ./memory_mac.sh --enable-vector
#   sh ./memory_mac.sh --enable-vector --vector-provider gemini
#
# This creates:
#   .cursor/memory/*, .cursor/rules/*, .cursor/skills/*, scripts/memory/*, .githooks/pre-commit
#   (and optional .githooks/post-commit when --enable-vector is used)

set -eu

REPO_ROOT="$(pwd)"
PROJECT_NAME=""
FORCE="0"
DRY_RUN="0"
ENABLE_VECTOR="0"
VECTOR_PROVIDER="openai"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo-root)
      REPO_ROOT="$2"; shift 2;;
    --project-name)
      PROJECT_NAME="$2"; shift 2;;
    --force)
      FORCE="1"; shift 1;;
    --dry-run)
      DRY_RUN="1"; shift 1;;
    --enable-vector)
      ENABLE_VECTOR="1"; shift 1;;
    --vector-provider)
      VECTOR_PROVIDER="$2"; shift 2;;
    -h|--help)
      echo "Usage: sh ./memory_mac.sh [--repo-root PATH] [--project-name NAME] [--force] [--dry-run] [--enable-vector] [--vector-provider openai|gemini]"
      exit 0;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2;;
  esac
done

if [ "$DRY_RUN" = "1" ]; then
  echo "[DRY RUN] No files will be written. Showing what would happen."
fi

if [ "$VECTOR_PROVIDER" != "openai" ] && [ "$VECTOR_PROVIDER" != "gemini" ]; then
  echo "Invalid --vector-provider: $VECTOR_PROVIDER (expected openai or gemini)" >&2
  exit 2
fi

if [ -z "$PROJECT_NAME" ]; then
  PROJECT_NAME="$(basename "$REPO_ROOT")"
fi

# Read version from VERSION file at installer location (single source of truth)
_INSTALLER_DIR="$(cd "$(dirname "$0")" && pwd)"
MNEMO_VERSION="0.0.0"
if [ -f "$_INSTALLER_DIR/VERSION" ]; then
  MNEMO_VERSION="$(cat "$_INSTALLER_DIR/VERSION" | tr -d '[:space:]')"
fi

MONTH="$(date +%Y-%m)"
TODAY="$(date +%Y-%m-%d)"

# Canonical Mnemo identity root
MNEMO_DIR="$REPO_ROOT/.mnemo"
MNEMO_MEMORY_DIR="$MNEMO_DIR/memory"
MNEMO_RULES_DIR="$MNEMO_DIR/rules"
MNEMO_RULES_CURSOR_DIR="$MNEMO_RULES_DIR/cursor"
MNEMO_RULES_AGENT_DIR="$MNEMO_RULES_DIR/agent"
MNEMO_MCP_DIR="$MNEMO_DIR/mcp"
MNEMO_CURSOR_MCP_PATH="$MNEMO_MCP_DIR/cursor.mcp.json"

# IDE integration bridge targets
CURSOR_DIR="$REPO_ROOT/.cursor"
CURSOR_MEMORY_BRIDGE="$CURSOR_DIR/memory"
CURSOR_RULES_BRIDGE="$CURSOR_DIR/rules"
CURSOR_MCP_BRIDGE="$CURSOR_DIR/mcp.json"
AGENT_DIR="$REPO_ROOT/.agent"
AGENT_RULES_BRIDGE="$AGENT_DIR/rules"

# Backward-compatible aliases used by script body (now canonicalized to .mnemo)
MEMORY_DIR="$MNEMO_MEMORY_DIR"
RULES_DIR="$MNEMO_RULES_CURSOR_DIR"
JOURNAL_DIR="$MEMORY_DIR/journal"
DIGESTS_DIR="$MEMORY_DIR/digests"
ADR_DIR="$MEMORY_DIR/adr"
LESSONS_DIR="$MEMORY_DIR/lessons"
TEMPLATES_DIR="$MEMORY_DIR/templates"
SCRIPTS_DIR="$REPO_ROOT/scripts"
MEM_SCRIPTS_DIR="$SCRIPTS_DIR/memory"
GITHOOKS_DIR="$REPO_ROOT/.githooks"
AGENT_RULES_DIR="$MNEMO_RULES_AGENT_DIR"

mkdir -p "$MNEMO_DIR" "$MNEMO_MEMORY_DIR" "$MNEMO_RULES_DIR" "$MNEMO_RULES_CURSOR_DIR" "$MNEMO_RULES_AGENT_DIR" "$MNEMO_MCP_DIR" \
  "$CURSOR_DIR" "$AGENT_DIR" \
  "$MEMORY_DIR" "$RULES_DIR" "$JOURNAL_DIR" "$DIGESTS_DIR" "$ADR_DIR" "$LESSONS_DIR" "$TEMPLATES_DIR" \
  "$SCRIPTS_DIR" "$MEM_SCRIPTS_DIR" "$GITHOOKS_DIR"

write_file() {
  # write_file <path> <stdin>
  path="$1"
  if [ -f "$path" ] && [ "$FORCE" != "1" ]; then
    printf '%s\n' "SKIP (exists): $path"
    # Still consume stdin to avoid broken pipe
    cat > /dev/null
    return 0
  fi
  if [ "$DRY_RUN" = "1" ]; then
    printf '%s\n' "[DRY RUN] WOULD WRITE: $path"
    cat > /dev/null
    return 0
  fi
  dir="$(dirname "$path")"
  [ -d "$dir" ] || mkdir -p "$dir"
  tmp="${path}.tmp.$$"
  cat > "$tmp" || { rm -f "$tmp"; echo "ERROR: failed to write $path" >&2; return 1; }
  mv "$tmp" "$path" || { rm -f "$tmp"; echo "ERROR: failed to move $tmp -> $path" >&2; return 1; }
  printf '%s\n' "WROTE: $path"
}

install_template_file() {
  # install_template_file <template_path> <dest_path>
  template_path="$1"
  dest_path="$2"
  if [ ! -f "$template_path" ]; then
    printf '%s\n' "WARNING: Template not found: $template_path"
    return 0
  fi
  write_file "$dest_path" < "$template_path"
}

sync_dir_one_way() {
  src="$1"
  dst="$2"
  [ -d "$src" ] || return 0
  mkdir -p "$dst"
  if [ "$DRY_RUN" = "1" ]; then
    printf '%s\n' "[DRY RUN] WOULD SYNC DIR: $src -> $dst"
    return 0
  fi
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --ignore-existing "$src/" "$dst/" >/dev/null 2>&1 || true
  else
    cp -R "$src/." "$dst/" 2>/dev/null || true
  fi
}

ensure_dir_bridge() {
  canonical="$1"
  bridge="$2"
  bridge_parent="$(dirname "$bridge")"
  mkdir -p "$canonical" "$bridge_parent"

  if [ -L "$bridge" ]; then
    current_target="$(readlink "$bridge" 2>/dev/null || true)"
    if [ "$current_target" = "$canonical" ]; then
      printf '%s\n' "BRIDGE (linked): $bridge -> $canonical"
      return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
      printf '%s\n' "[DRY RUN] WOULD REPAIR BRIDGE: $bridge -> $canonical"
      return 0
    fi
    rm -f "$bridge"
  fi

  if [ -e "$bridge" ] && [ ! -L "$bridge" ]; then
    # Existing real directory: keep permanent mirror mode (no destructive removal).
    sync_dir_one_way "$bridge" "$canonical"
    sync_dir_one_way "$canonical" "$bridge"
    printf '%s\n' "BRIDGE (mirror): $bridge <-> $canonical"
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    printf '%s\n' "[DRY RUN] WOULD CREATE SYMLINK: $bridge -> $canonical"
    return 0
  fi

  if ln -s "$canonical" "$bridge" 2>/dev/null; then
    printf '%s\n' "BRIDGE (symlink): $bridge -> $canonical"
    return 0
  fi

  mkdir -p "$bridge"
  sync_dir_one_way "$canonical" "$bridge"
  printf '%s\n' "BRIDGE (mirror): $bridge <-> $canonical"
}

ensure_file_bridge() {
  canonical="$1"
  bridge="$2"
  bridge_parent="$(dirname "$bridge")"
  canonical_parent="$(dirname "$canonical")"
  mkdir -p "$bridge_parent" "$canonical_parent"

  if [ ! -f "$canonical" ] && [ -f "$bridge" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      printf '%s\n' "[DRY RUN] WOULD COPY FILE: $bridge -> $canonical"
    else
      cp "$bridge" "$canonical"
    fi
  fi
  [ -f "$canonical" ] || return 0

  if [ -L "$bridge" ]; then
    current_target="$(readlink "$bridge" 2>/dev/null || true)"
    if [ "$current_target" = "$canonical" ]; then
      printf '%s\n' "BRIDGE (linked): $bridge -> $canonical"
      return 0
    fi
    if [ "$DRY_RUN" = "1" ]; then
      printf '%s\n' "[DRY RUN] WOULD REPAIR FILE BRIDGE: $bridge -> $canonical"
      return 0
    fi
    rm -f "$bridge"
  fi

  if [ -e "$bridge" ] && [ ! -L "$bridge" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      printf '%s\n' "[DRY RUN] WOULD MIRROR FILE: $canonical <-> $bridge"
      return 0
    fi
    if [ "$bridge" -nt "$canonical" ]; then
      cp "$bridge" "$canonical"
    fi
    cp "$canonical" "$bridge"
    printf '%s\n' "BRIDGE (mirror): $bridge <-> $canonical"
    return 0
  fi

  if [ "$DRY_RUN" = "1" ]; then
    printf '%s\n' "[DRY RUN] WOULD CREATE FILE SYMLINK: $bridge -> $canonical"
    return 0
  fi
  if ln -s "$canonical" "$bridge" 2>/dev/null; then
    printf '%s\n' "BRIDGE (symlink): $bridge -> $canonical"
    return 0
  fi
  cp "$canonical" "$bridge"
  printf '%s\n' "BRIDGE (mirror): $bridge <-> $canonical"
}

ensure_mnemo_bridges() {
  ensure_dir_bridge "$MNEMO_MEMORY_DIR" "$CURSOR_MEMORY_BRIDGE"
  ensure_dir_bridge "$MNEMO_RULES_CURSOR_DIR" "$CURSOR_RULES_BRIDGE"
  ensure_dir_bridge "$MNEMO_RULES_AGENT_DIR" "$AGENT_RULES_BRIDGE"
  if [ -f "$MNEMO_CURSOR_MCP_PATH" ] || [ -f "$CURSOR_MCP_BRIDGE" ]; then
    ensure_file_bridge "$MNEMO_CURSOR_MCP_PATH" "$CURSOR_MCP_BRIDGE"
  fi
}

# Migrate legacy paths into canonical .mnemo before generating files.
if [ "$DRY_RUN" != "1" ]; then
  if [ -d "$CURSOR_MEMORY_BRIDGE" ] && [ ! -L "$CURSOR_MEMORY_BRIDGE" ]; then
    sync_dir_one_way "$CURSOR_MEMORY_BRIDGE" "$MNEMO_MEMORY_DIR"
  fi
  if [ -d "$CURSOR_RULES_BRIDGE" ] && [ ! -L "$CURSOR_RULES_BRIDGE" ]; then
    sync_dir_one_way "$CURSOR_RULES_BRIDGE" "$MNEMO_RULES_CURSOR_DIR"
  fi
  if [ -d "$AGENT_RULES_BRIDGE" ] && [ ! -L "$AGENT_RULES_BRIDGE" ]; then
    sync_dir_one_way "$AGENT_RULES_BRIDGE" "$MNEMO_RULES_AGENT_DIR"
  fi
fi

# -------------------------
# Memory files
# -------------------------

write_file "$MEMORY_DIR/index.md" <<'EOF'
# Memory Index

Entry point for repo memory.

## Read order (token-safe)

ALWAYS READ (in order):
1) `hot-rules.md` (tiny invariants, <20 lines)
2) `active-context.md` (this session only)
3) `memo.md` (long-term current truth + ownership)

SEARCH FIRST, THEN OPEN ONLY WHAT MATCHES:
4) `lessons/index.md` -> find lesson ID(s)
5) `lessons/L-XXX-*.md` -> open only specific lesson(s)
6) `digests/YYYY-MM.digest.md` -> before raw journal
7) `journal/YYYY-MM.md` -> only for archaeology

## Maintenance commands

Shell helper scripts (macOS-friendly):
- Add lesson: `scripts/memory/add-lesson.sh --title "..." --tags "..." --rule "..."`
- Add journal: `scripts/memory/add-journal-entry.sh --tags "..." --title "..."`
- Rebuild indexes: `scripts/memory/rebuild-memory-index.sh`
- Lint: `scripts/memory/lint-memory.sh`
- Query: `scripts/memory/query-memory.sh --query "..."`
- Clear session: `scripts/memory/clear-active.sh`
EOF

write_file "$MEMORY_DIR/hot-rules.md" <<'EOF'
# Hot Rules (MUST READ)

Keep this file under ~20 lines. If it grows, move content into memo or lessons.

## Authority Order (highest to lowest)
1) Lessons override EVERYTHING (including active-context)
2) `active-context.md` overrides memo/journal (but NOT lessons)
3) `memo.md` is long-term project truth
4) journal is history

## Retrieval Rules
5) Do NOT scan raw journals. Use indexes/digests first.
6) Reuse existing patterns. Check memo.md ownership before creating new systems.
7) When done: clear active-context.md, add journal entry if significant.
EOF

write_file "$MEMORY_DIR/active-context.md" <<'EOF'
# Active Context (Session Scratchpad)

Priority: this overrides older journal history *for this session only*.

CLEAR this file when the task is done:
- Run `scripts/memory/clear-active.sh`

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
EOF

write_file "$MEMORY_DIR/memo.md" <<EOF
# Project Memo - $PROJECT_NAME

Last updated: $TODAY

## Ownership / Modules
- TODO

## Invariants
- TODO

## Build / Run
- TODO

## Integration Points
- TODO
EOF

write_file "$LESSONS_DIR/README.md" <<'EOF'
# Lessons

Lessons are atomic “rules learned the hard way”.

Rules:
- One lesson per file: `L-XXX-title.md`
- Must include YAML frontmatter at the top (`---` … `---`)
- Keep lessons high-signal and reusable
EOF

write_file "$LESSONS_DIR/index.md" <<'EOF'
# Lessons Index (generated)

Generated by `scripts/memory/rebuild-memory-index.sh`.

Format: ID | [Tags] | AppliesTo | Rule | File

(No lessons yet.)
EOF

write_file "$JOURNAL_DIR/README.md" <<'EOF'
# Journal

Monthly file: `YYYY-MM.md`

Rules:
- Each date appears ONCE per file: `## YYYY-MM-DD`
- Put multiple entries under that header as bullets.
- Keep it high-signal: what changed, why, key files.
EOF

write_file "$JOURNAL_DIR/$MONTH.md" <<EOF
# Development Journal - $PROJECT_NAME ($MONTH)

## $TODAY

- [Process] Initialized memory system (Mnemo v$MNEMO_VERSION)
  - Why: token-safe AI memory + indexed retrieval + portable hooks
  - Key files:
    - \`.cursor/memory/*\`
    - \`.cursor/rules/00-memory-system.mdc\`
    - \`scripts/memory/*\`
EOF

write_file "$DIGESTS_DIR/README.md" <<'EOF'
# Digests

Generated summaries of journal months.
AI should read digests before raw journal.
EOF

write_file "$ADR_DIR/README.md" <<'EOF'
# ADRs

Architecture Decision Records: why we did it this way.

Naming:
- `ADR-001-short-title.md`
EOF

write_file "$MEMORY_DIR/tag-vocabulary.md" <<'EOF'
# Tag Vocabulary (fixed set)

Use a small vocabulary so retrieval stays reliable.

- [UI] - UI behavior, rendering, interaction
- [Layout] - layout groups, anchors, sizing, rects
- [Input] - mouse/keyboard/controller input rules
- [Data] - parsing, payloads, formats, state sync
- [Server] - server-side logic and lifecycle
- [Init] - initialization / load order / startup
- [Build] - compilation, project files
- [CI] - automation, pipelines
- [Release] - packaging, artifacts, uploads
- [Compat] - runtime constraints, environment quirks
- [Integration] - plugins, external systems
- [Docs] - documentation and changelog work
- [Architecture] - module boundaries, refactors, ownership
- [DX] - developer experience, tooling, maintainability
- [Reliability] - crash prevention, guardrails, self-healing
- [Process] - workflow, memory system, tooling changes

# Common "type" tags (templates/examples)
- [Fix] - bug fixes, regressions, patches
- [Feature] - new behavior/capability
- [Refactor] - restructuring without behavior changes
EOF

write_file "$MEMORY_DIR/regression-checklist.md" <<'EOF'
# Regression Checklist

Run only what is relevant.

## Build
- [ ] Build / run relevant commands
- [ ] No new warnings (or documented)

## Runtime (if applicable)
- [ ] Core UI renders
- [ ] Core interactions work
- [ ] No obvious errors/log spam

## Docs (if applicable)
- [ ] Journal updated
- [ ] Memo updated (if truth changed)
- [ ] Lesson added (if pitfall discovered)
EOF

write_file "$TEMPLATES_DIR/lesson.template.md" <<'EOF'
---
id: L-XXX
title: Short descriptive title
status: Active
tags: [UI, Reliability]
introduced: YYYY-MM-DD
applies_to:
  - path/or/glob/**
triggers:
  - error keyword
rule: One sentence. Imperative. Testable.
supersedes: ""
---

# L-XXX - Short descriptive title

## Symptom
TODO

## Root cause
TODO

## Wrong approach (DO NOT REPEAT)
- TODO

## Correct approach
- TODO
EOF

write_file "$TEMPLATES_DIR/journal-entry.template.md" <<'EOF'
# Journal Entry Template (paste under an existing date header)

- [Area][Type] Title
  - Why: ...
  - Key files:
    - `path/to/file`
  - Verification: Build PASS/FAIL/NOT RUN; Runtime PASS/FAIL/NOT RUN
EOF

write_file "$TEMPLATES_DIR/adr.template.md" <<'EOF'
# ADR-XXX - Title

Date: YYYY-MM-DD
Status: Proposed | Accepted | Deprecated

## Context
TODO

## Decision
TODO

## Consequences
TODO
EOF

# -------------------------
# Cursor rule (Cursor will pick this up; other agents can still read .cursor/memory)
# -------------------------

write_file "$RULES_DIR/00-memory-system.mdc" <<EOF
---
description: Mnemo Memory System v$MNEMO_VERSION - Authority + Atomic Retrieval + Token Safety
globs:
  - "**/*"
alwaysApply: true
---

# Memory System (MANDATORY)

## Authority Order (highest to lowest)
1) Lessons override EVERYTHING (including active-context)
2) active-context.md overrides memo/journal (but NOT lessons)
3) memo.md is long-term project truth
4) Journal is history

## Token-Safe Retrieval

ALWAYS READ (in order):
1. .cursor/memory/hot-rules.md
2. .cursor/memory/active-context.md
3. .cursor/memory/memo.md

SEARCH FIRST, THEN FETCH:
4. .cursor/memory/lessons/index.md -> find relevant lesson ID
5. .cursor/memory/lessons/L-XXX-title.md -> load ONLY the specific file
6. .cursor/memory/digests/YYYY-MM.digest.md -> before raw journal
7. .cursor/memory/journal/YYYY-MM.md -> only for archaeology

## Helper Scripts (macOS)

- Add lesson: scripts/memory/add-lesson.sh --title "..." --tags "..." --rule "..."
- Add journal: scripts/memory/add-journal-entry.sh --tags "..." --title "..."
- Rebuild: scripts/memory/rebuild-memory-index.sh
- Lint: scripts/memory/lint-memory.sh
- Query: scripts/memory/query-memory.sh --query "..."
- Clear: scripts/memory/clear-active.sh
EOF

# -------------------------
# Agent bridge files
# -------------------------

mkdir -p "$AGENT_RULES_DIR"

write_file "$AGENT_RULES_DIR/00-memory-system.md" <<'EOF'
---
description: Mnemo memory system - structured AI memory in .cursor/memory/
alwaysApply: true
---

# Memory System (Mnemo)

This project uses Mnemo for structured AI memory. All memory lives in `.cursor/memory/`.

## Read Order (ALWAYS)
1. `.cursor/memory/hot-rules.md` - tiny invariants (read first)
2. `.cursor/memory/active-context.md` - current session state
3. `.cursor/memory/memo.md` - project truth + ownership

## Search First, Then Fetch
- `.cursor/memory/lessons/index.md` - searchable lesson index
- `.cursor/memory/digests/*.digest.md` - monthly summaries
- `.cursor/memory/journal/*.md` - raw history (last resort)

## Authority Order
1. Lessons override everything
2. active-context overrides memo/journal (but NOT lessons)
3. memo.md is long-term truth
4. Journal is history

## After Any Task
- Update active-context.md during work
- Add journal entry when done
- Create lesson if you discovered a pitfall
- Clear active-context.md when task is merged
EOF

# -------------------------
# Cursor project skills
# -------------------------

_skills_tpl_dir="$_INSTALLER_DIR/scripts/memory/installer/templates/skills/mnemo-codebase-optimizer"
install_template_file "$_skills_tpl_dir/SKILL.md" "$CURSOR_DIR/skills/mnemo-codebase-optimizer/SKILL.md"
install_template_file "$_skills_tpl_dir/reference.md" "$CURSOR_DIR/skills/mnemo-codebase-optimizer/reference.md"

write_file "$MEM_SCRIPTS_DIR/customization.md" <<'EOF'
# Mnemo Memory Customization Prompt (paste into an AI)

You are an AI coding agent. Your task is to **customize the Mnemo memory system** created by running the installer in the root of THIS repository.

## Non-negotiable rules

- **Do not lose legacy memory.** If you find an older memory system (e.g. `Archive/`, `.cursor_old/`, `docs/memory/`, etc.), copy it into:
  - `.cursor/memory/legacy/<source-name>/`
- **Do not overwrite** the Mnemo structure unless explicitly required. Prefer merge + preserve.
- Keep the always-read layer token-safe:
  - `.cursor/memory/hot-rules.md` stays ~20 lines (hard invariants only).
  - `.cursor/memory/memo.md` is “current truth”, not history (move history into journals).
- Mnemo authority order (highest → lowest):
  - Lessons > active-context > memo > journal.

## Deliverable

1) Project-customized memory in `.cursor/memory/` (memo + index + regression checklist updated).  
2) Legacy memory preserved in `.cursor/memory/legacy/...`.  
3) Lint passes for the memory system.
EOF

# -------------------------
# Helper scripts (shell)
# -------------------------

write_file "$MEM_SCRIPTS_DIR/query-memory.sh" <<'EOF'
#!/bin/sh
set -eu

QUERY=""
AREA="All"
FORMAT="Human"
USE_SQLITE="0"

while [ $# -gt 0 ]; do
  case "$1" in
    --query) QUERY="$2"; shift 2;;
    --area) AREA="$2"; shift 2;;
    --format) FORMAT="$2"; shift 2;;
    --use-sqlite) USE_SQLITE="1"; shift 1;;
    -h|--help)
      echo "Usage: sh ./scripts/memory/query-memory.sh --query \"...\" [--area All|HotRules|Active|Memo|Lessons|Journal|Digests] [--format Human|AI] [--use-sqlite]"
      exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [ -z "$QUERY" ]; then
  echo "Missing --query" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MEM="$ROOT/.cursor/memory"
LESSONS="$MEM/lessons"

to_lower() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

area_l="$(to_lower "$AREA")"
format_l="$(to_lower "$FORMAT")"

if [ "$USE_SQLITE" = "1" ]; then
  if command -v python3 >/dev/null 2>&1 && [ -f "$MEM/memory.sqlite" ] && [ -f "$ROOT/scripts/memory/query-memory-sqlite.py" ]; then
    python3 "$ROOT/scripts/memory/query-memory-sqlite.py" --repo "$ROOT" --q "$QUERY" --area "$AREA" --format "$FORMAT"
    exit $?
  fi
  echo "SQLite mode unavailable (need python3 + .cursor/memory/memory.sqlite + query-memory-sqlite.py). Falling back to file search." >&2
fi

targets=""
case "$area_l" in
  hotrules|hot) targets="$MEM/hot-rules.md" ;;
  active) targets="$MEM/active-context.md" ;;
  memo) targets="$MEM/memo.md" ;;
  lessons) targets="$LESSONS/index.md $LESSONS/L-*.md" ;;
  journal) targets="$MEM/journal-index.md" ;;
  digests) targets="$MEM/digests/"'*.digest.md' ;;
  all) targets="$MEM/hot-rules.md $MEM/active-context.md $MEM/memo.md $LESSONS/index.md $MEM/journal-index.md $MEM/digests/"'*.digest.md' ;;
  *) echo "Unknown --area: $AREA" >&2; exit 2 ;;
esac

tmp="${TMPDIR:-/tmp}/mnemo-query.$$"
rm -f "$tmp"

for t in $targets; do
  [ -e "$t" ] || continue
  grep -nH "$QUERY" "$t" 2>/dev/null >>"$tmp" || true
done

match_count=0
if [ -f "$tmp" ]; then
  match_count="$(wc -l < "$tmp" | awk '{$1=$1;print}')"
fi

if [ "$format_l" = "ai" ]; then
  if [ "$match_count" -eq 0 ]; then
    echo "No matches found for: $QUERY"
  else
    echo "Files to read:"
    cut -d: -f1 "$tmp" | sort -u | while IFS= read -r f; do
      rel="${f#$ROOT/}"
      echo "  @$rel"
    done
  fi
else
  echo "Searching: $QUERY"
  echo "Area: $AREA"
  echo ""
  if [ "$match_count" -eq 0 ]; then
    echo "No matches found."
  else
    cat "$tmp"
  fi
fi

rm -f "$tmp"
EOF

write_file "$MEM_SCRIPTS_DIR/clear-active.sh" <<'EOF'
#!/bin/sh
set -eu
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ACTIVE="$ROOT/.cursor/memory/active-context.md"
cat > "$ACTIVE" <<'T'
# Active Context (Session Scratchpad)

Priority: this overrides older journal history *for this session only*.

CLEAR this file when the task is done:
- Run `scripts/memory/clear-active.sh`

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
EOF

write_file "$MEM_SCRIPTS_DIR/add-journal-entry.sh" <<'EOF'
#!/bin/sh
set -eu

TAGS=""
TITLE=""
FILES=""
WHY=""
DATE="$(date +%Y-%m-%d)"

while [ $# -gt 0 ]; do
  case "$1" in
    --tags) TAGS="$2"; shift 2;;
    --title) TITLE="$2"; shift 2;;
    --files) FILES="$2"; shift 2;;
    --why) WHY="$2"; shift 2;;
    --date) DATE="$2"; shift 2;;
    -h|--help)
      echo "Usage: sh ./scripts/memory/add-journal-entry.sh --tags \"UI,Fix\" --title \"...\" [--files \"a,b\"] [--why \"...\"] [--date YYYY-MM-DD]"
      exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [ -z "$TAGS" ] || [ -z "$TITLE" ]; then
  echo "Missing --tags or --title" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MEM="$ROOT/.cursor/memory"
JOURNAL_DIR="$MEM/journal"
TAG_VOCAB="$MEM/tag-vocabulary.md"
MONTH="$(echo "$DATE" | cut -c1-7)"
JOURNAL="$JOURNAL_DIR/$MONTH.md"
PROJECT_NAME="$(basename "$ROOT")"

mkdir -p "$JOURNAL_DIR"

canon_tag() {
  want_l="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  [ -f "$TAG_VOCAB" ] || { echo "$1"; return 0; }
  awk -v w="$want_l" '
    /^\- \[[^]]+\]/ {
      t=$0
      sub(/^\- \[/,"",t); sub(/\].*$/,"",t)
      if (tolower(t)==w) { print t; exit }
    }
  ' "$TAG_VOCAB" 2>/dev/null || true
}

tag_string=""
oldIFS="$IFS"; IFS=','; set -- $TAGS; IFS="$oldIFS"
for t in "$@"; do
  tt="$(echo "$t" | awk '{$1=$1;print}')"
  [ -z "$tt" ] && continue
  canon="$(canon_tag "$tt")"
  if [ -z "$canon" ]; then
    echo "Unknown tag '$tt'. Add it to tag-vocabulary.md or fix the tag." >&2
    exit 1
  fi
  tag_string="${tag_string}[$canon]"
done

entry="- $tag_string $TITLE"
if [ -n "$WHY" ]; then
  entry="${entry}\n  - Why: $WHY"
fi
if [ -n "$FILES" ]; then
  entry="${entry}\n  - Key files:"
  oldIFS="$IFS"; IFS=','; set -- $FILES; IFS="$oldIFS"
  for f in "$@"; do
    ff="$(echo "$f" | awk '{$1=$1;print}')"
    [ -n "$ff" ] && entry="${entry}\n    - \`$ff\`"
  done
fi

if [ ! -f "$JOURNAL" ]; then
  cat > "$JOURNAL" <<EOF2
# Development Journal - $PROJECT_NAME ($MONTH)

## $DATE

$(printf "%b" "$entry")
EOF2
  echo "Added journal entry to: $JOURNAL"
  exit 0
fi

if grep -q "^## $DATE\$" "$JOURNAL"; then
  awk -v d="$DATE" -v e="$(printf "%b" "$entry")" '
    BEGIN { inhdr=0; done=0 }
    {
      print $0
      if ($0 == "## " d) { inhdr=1; next }
      if (inhdr==1 && done==0 && $0 ~ /^## [0-9]{4}-[0-9]{2}-[0-9]{2}$/) {
        print ""
        print e
        print ""
        done=1
        inhdr=0
      }
    }
    END {
      if (done==0) {
        print ""
        print e
        print ""
      }
    }
  ' "$JOURNAL" > "$JOURNAL.tmp.$$"
  mv "$JOURNAL.tmp.$$" "$JOURNAL" || { rm -f "$JOURNAL.tmp.$$"; echo "ERROR: failed to update $JOURNAL" >&2; exit 1; }
else
  {
    printf "\n## %s\n\n" "$DATE"
    printf "%b\n" "$entry"
  } >> "$JOURNAL"
fi

echo "Added journal entry to: $JOURNAL"
EOF

write_file "$MEM_SCRIPTS_DIR/add-lesson.sh" <<'EOF'
#!/bin/sh
set -eu

TITLE=""
TAGS=""
RULE=""
APPLIES_TO="*"

while [ $# -gt 0 ]; do
  case "$1" in
    --title) TITLE="$2"; shift 2;;
    --tags) TAGS="$2"; shift 2;;
    --rule) RULE="$2"; shift 2;;
    --applies-to) APPLIES_TO="$2"; shift 2;;
    -h|--help)
      echo "Usage: sh ./scripts/memory/add-lesson.sh --title \"...\" --tags \"Reliability,Data\" --rule \"...\" [--applies-to \"*\"]"
      exit 0;;
    *) echo "Unknown arg: $1" >&2; exit 2;;
  esac
done

if [ -z "$TITLE" ] || [ -z "$TAGS" ] || [ -z "$RULE" ]; then
  echo "Missing --title/--tags/--rule" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
LESSONS="$ROOT/.cursor/memory/lessons"
TAG_VOCAB="$ROOT/.cursor/memory/tag-vocabulary.md"
mkdir -p "$LESSONS"

max=0
for f in "$LESSONS"/L-*.md; do
  [ -e "$f" ] || continue
  b="$(basename "$f")"
  n="$(echo "$b" | sed -n 's/^L-\([0-9][0-9][0-9]\).*/\1/p')"
  [ -n "$n" ] && [ "$n" -gt "$max" ] && max="$n"
done

next=$((max + 1))
ID="$(printf "L-%03d" "$next")"

kebab="$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//;')"
[ -z "$kebab" ] && kebab="lesson"
file="$LESSONS/${ID}-${kebab}.md"

today="$(date +%Y-%m-%d)"

canon_tag() {
  want_l="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
  [ -f "$TAG_VOCAB" ] || { echo "$1"; return 0; }
  awk -v w="$want_l" '
    /^\- \[[^]]+\]/ {
      t=$0
      sub(/^\- \[/,"",t); sub(/\].*$/,"",t)
      if (tolower(t)==w) { print t; exit }
    }
  ' "$TAG_VOCAB" 2>/dev/null || true
}

tags_out=""
oldIFS="$IFS"; IFS=','; set -- $TAGS; IFS="$oldIFS"
for t in "$@"; do
  tt="$(echo "$t" | awk '{$1=$1;print}')"
  [ -z "$tt" ] && continue
  canon="$(canon_tag "$tt")"
  if [ -z "$canon" ]; then
    echo "Unknown tag '$tt'. Add it to tag-vocabulary.md or fix the tag." >&2
    exit 1
  fi
  if echo ",$tags_out," | grep -qi ",$canon,"; then
    continue
  fi
  if [ -z "$tags_out" ]; then tags_out="$canon"; else tags_out="$tags_out, $canon"; fi
done

tags_list="$tags_out"
if [ -z "$tags_list" ]; then
  echo "No valid tags provided." >&2
  exit 1
fi

cat > "$file" <<EOF2
---
id: $ID
title: $TITLE
status: Active
tags: [$tags_list]
introduced: $today
applies_to:
  - $APPLIES_TO
triggers:
  - TODO: add error messages or keywords
rule: $RULE
---

# $ID - $TITLE

## Symptom

TODO

## Root Cause

TODO

## Wrong Approach (DO NOT REPEAT)

- TODO

## Correct Approach

- TODO
EOF2

echo "Created lesson: $file"
echo "Next: run scripts/memory/rebuild-memory-index.sh"
EOF

write_file "$MEM_SCRIPTS_DIR/rebuild-memory-index.sh" <<'EOF'
#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MEM="$ROOT/.cursor/memory"
LESSONS="$MEM/lessons"
JOURNAL="$MEM/journal"
DIGESTS="$MEM/digests"

mkdir -p "$LESSONS" "$JOURNAL" "$DIGESTS"

gen="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

json_escape() {
  # prints JSON-safe string (no surrounding quotes)
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e 's/\"/\\"/g' -e ':a;N;$!ba;s/\r//g;s/\n/\\n/g'
}

tmp_lessons="${TMPDIR:-/tmp}/mnemo-lessons.$$"
sorted_lessons="${TMPDIR:-/tmp}/mnemo-lessons.sorted.$$"
tmp_entries="${TMPDIR:-/tmp}/mnemo-journal-entries.$$"
sorted_entries="${TMPDIR:-/tmp}/mnemo-journal-entries.sorted.$$"
rm -f "$tmp_lessons" "$sorted_lessons" "$tmp_entries" "$sorted_entries"

# ---------------------------------
# Lessons -> index.md + lessons-index.json
# ---------------------------------

# num\tid\ttitle\tstatus\tintroduced\ttags_raw\tapplies_csv\trule\tfile
for f in "$LESSONS"/L-*.md; do
  [ -e "$f" ] || continue
  bn="$(basename "$f")"
  awk -v file="$bn" '
    function trim(s){ sub(/^[ \t]+/,"",s); sub(/[ \t]+$/,"",s); return s }
    BEGIN{ inhdr=0; cur=""; id=""; title=""; status=""; introduced=""; tags=""; rule=""; applies="" }
    NR==1 && $0=="---"{inhdr=1; next}
    inhdr==1 && $0=="---"{inhdr=0; next}
    inhdr==1{
      if ($0 ~ /^[ \t]*#/ || $0 ~ /^[ \t]*$/) next
      if ($0 ~ /^[A-Za-z0-9_]+:[ \t]*$/) {
        key=$1; sub(/:$/,"",key); cur=tolower(key); next
      }
      if ($0 ~ /^[ \t]*-[ \t]+/ && cur=="applies_to") {
        sub(/^[ \t]*-[ \t]+/,"",$0); v=trim($0)
        applies = applies (applies==""? v : "," v)
        next
      }
      if ($0 ~ /^[A-Za-z0-9_]+:[ \t]*/) {
        key=$1; sub(/:$/,"",key); k=tolower(key)
        $1=""; v=trim($0)
        if ((v ~ /^".*"$/) || (v ~ /^\047.*\047$/)) { v=substr(v,2,length(v)-2) }
        if (k=="id") id=v
        else if (k=="title") title=v
        else if (k=="status") status=v
        else if (k=="introduced") introduced=v
        else if (k=="rule") rule=v
        else if (k=="tags") tags=v
        cur=""
        next
      }
    }
    END{
      if (id=="") exit
      num=0
      if (id ~ /^L-[0-9]+$/) { idn=id; sub(/^L-/,"",idn); num=idn+0 }
      if (status=="") status="Active"
      if (title=="") title=file
      if (rule=="") rule=title
      print num "\t" id "\t" title "\t" status "\t" introduced "\t" tags "\t" applies "\t" rule "\t" file
    }
  ' "$f" >>"$tmp_lessons" 2>/dev/null || true
done

if [ -f "$tmp_lessons" ]; then
  sort -n -k1,1 "$tmp_lessons" >"$sorted_lessons" || true
else
  : >"$sorted_lessons"
fi

out_md="$LESSONS/index.md"
{
  echo "# Lessons Index (generated)"
  echo ""
  echo "Generated: $gen"
  echo ""
  echo "Format: ID | [Tags] | AppliesTo | Rule | File"
  echo ""
} >"$out_md"

lesson_count=0
while IFS="$(printf '\t')" read -r num id title status introduced tags applies rule file; do
  [ -z "$id" ] && continue
  lesson_count=$((lesson_count + 1))
  tagText="$(printf "%s" "$tags" | sed -n 's/^[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p' | sed 's/[[:space:]]*,[[:space:]]*/,/g' | awk -F, '{for(i=1;i<=NF;i++){if($i!=""){printf "[%s]",$i}}}')"
  appliesText="(any)"
  if [ -n "$applies" ]; then appliesText="$(printf "%s" "$applies" | sed 's/,/, /g')"; fi
  printf "%s | %s | %s | %s | `%s`\n" "$id" "$tagText" "$appliesText" "$rule" "$file" >>"$out_md"
done <"$sorted_lessons"

if [ "$lesson_count" -eq 0 ]; then
  echo "(No lessons yet.)" >>"$out_md"
fi

out_json="$MEM/lessons-index.json"
{
  echo "["
  first=1
  while IFS="$(printf '\t')" read -r num id title status introduced tags applies rule file; do
    [ -z "$id" ] && continue
    tags_inner="$(printf "%s" "$tags" | sed -n 's/^[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p' | sed 's/[[:space:]]*,[[:space:]]*/,/g')"
    tags_json=""
    oldIFS="$IFS"; IFS=','; set -- $tags_inner; IFS="$oldIFS"
    for t in "$@"; do
      tt="$(printf "%s" "$t" | awk '{$1=$1;print}')"
      [ -z "$tt" ] && continue
      [ -n "$tags_json" ] && tags_json="$tags_json,"
      tags_json="$tags_json\"$(json_escape "$tt")\""
    done
    applies_json=""
    if [ -n "$applies" ]; then
      oldIFS="$IFS"; IFS=','; set -- $applies; IFS="$oldIFS"
      for a in "$@"; do
        aa="$(printf "%s" "$a" | awk '{$1=$1;print}')"
        [ -z "$aa" ] && continue
        [ -n "$applies_json" ] && applies_json="$applies_json,"
        applies_json="$applies_json\"$(json_escape "$aa")\""
      done
    fi
    if [ "$first" -eq 1 ]; then first=0; else echo ","; fi
    printf "  {\"Id\":\"%s\",\"Num\":%s,\"Title\":\"%s\",\"Status\":\"%s\",\"Introduced\":\"%s\",\"Tags\":[%s],\"AppliesTo\":[%s],\"Rule\":\"%s\",\"File\":\"%s\"}" \
      "$(json_escape "$id")" \
      "${num:-0}" \
      "$(json_escape "$title")" \
      "$(json_escape "$status")" \
      "$(json_escape "$introduced")" \
      "$tags_json" \
      "$applies_json" \
      "$(json_escape "$rule")" \
      "$(json_escape "$file")"
  done <"$sorted_lessons"
  echo ""
  echo "]"
} >"$out_json"

# ---------------------------------
# Journal -> journal-index.md + journal-index.json + digests
# ---------------------------------

for jf in "$JOURNAL"/*.md; do
  [ -e "$jf" ] || continue
  base="$(basename "$jf")"
  [ "$base" = "README.md" ] && continue
  case "$base" in
    ????-??.md) ;;
    *) continue ;;
  esac

  # monthfile\tdate\ttags_csv\ttitle\tfiles_csv
  awk -v mf="$base" '
    function trim(s){ sub(/^[ \t]+/,"",s); sub(/[ \t]+$/,"",s); return s }
    function addfile(v){
      if (v=="") return
      if (v ~ /[\/\\]/ || v ~ /\.(cs|md|mdx|yml|yaml|csproj|ps1|sh|ts|tsx|json|py)$/) {
        if (files=="" || (","files"," !~ ","v",")) files = files (files==""? v : "," v)
      }
    }
    function flush(){
      if (inEntry==1 && date!="") {
        print mf "\t" date "\t" tags "\t" title "\t" files
      }
    }
    BEGIN{ date=""; inEntry=0; tags=""; title=""; files="" }
    /^##[ \t]+[0-9]{4}-[0-9]{2}-[0-9]{2}/{
      flush()
      inEntry=0
      tags=""; title=""; files=""
      date=$2
      next
    }
    /^-[ \t]+(\[[^]]+\])+/{
      flush()
      inEntry=1
      files=""; tags=""; title=""
      line=$0
      while (match(line, /\[[^]]+\]/)) {
        t=substr(line, RSTART+1, RLENGTH-2)
        tags = tags (tags==""? t : "," t)
        line = substr(line, RSTART+RLENGTH)
      }
      sub(/^[ \t]*-+[ \t]*/,"",$0)
      tline=$0
      gsub(/\[[^]]+\]/,"",tline)
      title=trim(tline)
      # collect backticks on same line
      line2=$0
      while (match(line2, /`[^`]+`/)) {
        v=substr(line2, RSTART+1, RLENGTH-2); addfile(v)
        line2=substr(line2, RSTART+RLENGTH)
      }
      next
    }
    inEntry==1{
      line=$0
      while (match(line, /`[^`]+`/)) {
        v=substr(line, RSTART+1, RLENGTH-2); addfile(v)
        line=substr(line, RSTART+RLENGTH)
      }
      next
    }
    END{ flush() }
  ' "$jf" >>"$tmp_entries" 2>/dev/null || true

  month="${base%.md}"
  digest="$DIGESTS/$month.digest.md"
  {
    echo "# Monthly Digest - $month (generated)"
    echo ""
    echo "Generated: $gen"
    echo ""
    echo "Token-cheap summary. See \`.cursor/memory/journal/$base\` for details."
    echo ""
  } >"$digest"

  awk '
    function trim(s){ sub(/^[ \t]+/,"",s); sub(/[ \t]+$/,"",s); return s }
    /^##[ \t]+[0-9]{4}-[0-9]{2}-[0-9]{2}/{
      d=$2
      print "## " d "\n"
      next
    }
    /^-[ \t]+(\[[^]]+\])+/{
      sub(/^[ \t]*-+[ \t]*/,"",$0)
      line=$0
      tags=""
      while (match(line, /\[[^]]+\]/)) {
        tags=tags substr(line, RSTART, RLENGTH)
        line=substr(line, RSTART+RLENGTH)
      }
      title=$0
      gsub(/\[[^]]+\]/,"",title)
      title=trim(title)
      print "- " tags " " title
      next
    }
  ' "$jf" >>"$digest"
done

if [ -f "$tmp_entries" ]; then
  sort -k2,2 -k4,4 "$tmp_entries" >"$sorted_entries" || true
else
  : >"$sorted_entries"
fi

ji="$MEM/journal-index.md"
{
  echo "# Journal Index (generated)"
  echo ""
  echo "Generated: $gen"
  echo ""
  echo "Format: YYYY-MM-DD | [Tags] | Title | Files"
  echo ""
} >"$ji"

while IFS="$(printf '\t')" read -r mf date tags title files; do
  [ -z "$date" ] && continue
  tagText=""
  oldIFS="$IFS"; IFS=','; set -- $tags; IFS="$oldIFS"
  for t in "$@"; do
    tt="$(printf "%s" "$t" | awk '{$1=$1;print}')"
    [ -n "$tt" ] && tagText="${tagText}[$tt]"
  done
  fileText="-"
  [ -n "$files" ] && fileText="$(printf "%s" "$files" | sed 's/,/, /g')"
  printf "%s | %s | %s | %s\n" "$date" "$tagText" "$title" "$fileText" >>"$ji"
done <"$sorted_entries"

out_jjson="$MEM/journal-index.json"
{
  echo "["
  first=1
  while IFS="$(printf '\t')" read -r mf date tags title files; do
    [ -z "$date" ] && continue
    tags_json=""
    oldIFS="$IFS"; IFS=','; set -- $tags; IFS="$oldIFS"
    for t in "$@"; do
      tt="$(printf "%s" "$t" | awk '{$1=$1;print}')"
      [ -z "$tt" ] && continue
      [ -n "$tags_json" ] && tags_json="$tags_json,"
      tags_json="$tags_json\"$(json_escape "$tt")\""
    done
    files_json=""
    if [ -n "$files" ]; then
      oldIFS="$IFS"; IFS=','; set -- $files; IFS="$oldIFS"
      for f in "$@"; do
        ff="$(printf "%s" "$f" | awk '{$1=$1;print}')"
        [ -z "$ff" ] && continue
        [ -n "$files_json" ] && files_json="$files_json,"
        files_json="$files_json\"$(json_escape "$ff")\""
      done
    fi
    if [ "$first" -eq 1 ]; then first=0; else echo ","; fi
    printf "  {\"MonthFile\":\"%s\",\"Date\":\"%s\",\"Tags\":[%s],\"Title\":\"%s\",\"Files\":[%s]}" \
      "$(json_escape "$mf")" \
      "$(json_escape "$date")" \
      "$tags_json" \
      "$(json_escape "$title")" \
      "$files_json"
  done <"$sorted_entries"
  echo ""
  echo "]"
} >"$out_jjson"

# Optional: build SQLite index if python3 exists
if command -v python3 >/dev/null 2>&1 && [ -f "$ROOT/scripts/memory/build-memory-sqlite.py" ]; then
  echo "Python3 detected; building SQLite FTS index..."
  python3 "$ROOT/scripts/memory/build-memory-sqlite.py" --repo "$ROOT" || true
else
  echo "Python3 not found; skipping SQLite build."
fi

# Token usage monitoring (informational)
totalChars=0
for hf in "$MEM/hot-rules.md" "$MEM/active-context.md" "$MEM/memo.md"; do
  [ -f "$hf" ] || continue
  c="$(wc -c < "$hf" | awk '{$1=$1;print}')"
  totalChars=$((totalChars + c))
done
estimatedTokens=$((totalChars / 4))
echo ""
if [ "$totalChars" -gt 8000 ]; then
  echo "WARNING: Always-read layer is $totalChars chars (~$estimatedTokens tokens)"
else
  echo "Always-read layer: $totalChars chars (~$estimatedTokens tokens) - Healthy"
fi

rm -f "$tmp_lessons" "$sorted_lessons" "$tmp_entries" "$sorted_entries" 2>/dev/null || true
echo ""
echo "Rebuild complete."
EOF

write_file "$MEM_SCRIPTS_DIR/lint-memory.sh" <<'EOF'
#!/bin/sh
set -eu

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
MEM="$ROOT/.cursor/memory"
LESSONS="$MEM/lessons"
JOURNAL="$MEM/journal"
TAG_VOCAB="$MEM/tag-vocabulary.md"

hot="$MEM/hot-rules.md"
active="$MEM/active-context.md"
memo="$MEM/memo.md"

errors=0
warnings=0

err() { echo "  ERROR: $1" >&2; errors=$((errors + 1)); }
warn() { echo "  WARN: $1" >&2; warnings=$((warnings + 1)); }

echo "Linting Mnemo Memory System..."
echo ""

# Allowed tags
allowed_tmp="${TMPDIR:-/tmp}/mnemo-allowed-tags.$$"
rm -f "$allowed_tmp"
if [ -f "$TAG_VOCAB" ]; then
  awk '/^\- \[[^]]+\]/{t=$0; sub(/^\- \[/,"",t); sub(/\].*$/,"",t); print t}' "$TAG_VOCAB" >"$allowed_tmp"
else
  warn "Missing tag vocabulary: $TAG_VOCAB"
  : >"$allowed_tmp"
fi

echo "Checking lessons..."
ids_tmp="${TMPDIR:-/tmp}/mnemo-lesson-ids.$$"
rm -f "$ids_tmp"

lesson_count=0
for lf in "$LESSONS"/L-*.md; do
  [ -e "$lf" ] || continue
  lesson_count=$((lesson_count + 1))
  bn="$(basename "$lf")"

  first="$(awk 'NR==1{print $0; exit}' "$lf" 2>/dev/null || true)"
  if [ "$first" != "---" ]; then
    err "[$bn] Missing YAML frontmatter"
    continue
  fi

  id="$(awk 'NR==1 && $0=="---"{h=1;next} h && $0=="---"{exit} h && $1=="id:"{print $2; exit}' "$lf" 2>/dev/null || true)"
  title="$(awk 'NR==1 && $0=="---"{h=1;next} h && $0=="---"{exit} h && $1=="title:"{$1=""; sub(/^ /,""); print; exit}' "$lf" 2>/dev/null || true)"
  status="$(awk 'NR==1 && $0=="---"{h=1;next} h && $0=="---"{exit} h && $1=="status:"{$1=""; sub(/^ /,""); print; exit}' "$lf" 2>/dev/null || true)"
  tags="$(awk 'NR==1 && $0=="---"{h=1;next} h && $0=="---"{exit} h && $1=="tags:"{$1=""; sub(/^ /,""); print; exit}' "$lf" 2>/dev/null || true)"
  introduced="$(awk 'NR==1 && $0=="---"{h=1;next} h && $0=="---"{exit} h && $1=="introduced:"{print $2; exit}' "$lf" 2>/dev/null || true)"
  rule="$(awk 'NR==1 && $0=="---"{h=1;next} h && $0=="---"{exit} h && $1=="rule:"{$1=""; sub(/^ /,""); print; exit}' "$lf" 2>/dev/null || true)"

  [ -z "$id" ] && err "[$bn] Missing required field: id"
  [ -z "$title" ] && err "[$bn] Missing required field: title"
  [ -z "$status" ] && err "[$bn] Missing required field: status"
  [ -z "$tags" ] && err "[$bn] Missing required field: tags"
  [ -z "$introduced" ] && err "[$bn] Missing required field: introduced"
  [ -z "$rule" ] && err "[$bn] Missing required field: rule"

  if [ -n "$id" ]; then
    echo "$id	$bn" >>"$ids_tmp"
    echo "$id" | grep -Eq '^L-[0-9]{3}$' || warn "[$bn] ID '$id' doesn't match format L-XXX (3 digits)"
    pref="$(echo "$id" | tr '[:upper:]' '[:lower:]')"
    echo "$bn" | tr '[:upper:]' '[:lower:]' | grep -q "^$pref" || warn "[$bn] Filename doesn't start with ID '$id'"
  fi

  if [ -s "$allowed_tmp" ] && [ -n "$tags" ]; then
    inner="$(printf "%s" "$tags" | sed -n 's/^[[:space:]]*\[\(.*\)\][[:space:]]*$/\1/p' | sed 's/[[:space:]]*,[[:space:]]*/,/g')"
    oldIFS="$IFS"; IFS=','; set -- $inner; IFS="$oldIFS"
    for t in "$@"; do
      tt="$(printf "%s" "$t" | awk '{$1=$1;print}')"
      [ -z "$tt" ] && continue
      if ! grep -Fxq "$tt" "$allowed_tmp"; then
        err "[$bn] Unknown tag [$tt]. Add it to tag-vocabulary.md or fix the lesson."
      fi
    done
  fi
done

echo "  Found $lesson_count lesson files"

# Duplicate IDs
if [ -f "$ids_tmp" ]; then
  dups="$(cut -f1 "$ids_tmp" | sort | uniq -d || true)"
  if [ -n "$dups" ]; then
    echo "$dups" | while IFS= read -r did; do
      [ -z "$did" ] && continue
      files="$(awk -v i="$did" -F'\t' '$1==i{print $2}' "$ids_tmp" | paste -sd', ' -)"
      err "Duplicate lesson ID $did (files: $files)"
    done
  fi
fi

echo ""
echo "Checking journals..."
journal_count=0
for jf in "$JOURNAL"/????-??.md; do
  [ -e "$jf" ] || continue
  journal_count=$((journal_count + 1))
  bn="$(basename "$jf")"
  dups="$(awk '/^##[ \t]+[0-9]{4}-[0-9]{2}-[0-9]{2}/{print $2}' "$jf" | sort | uniq -d || true)"
  if [ -n "$dups" ]; then
    echo "$dups" | while IFS= read -r d; do
      [ -z "$d" ] && continue
      c="$(awk -v dd="$d" '/^##[ \t]+[0-9]{4}-[0-9]{2}-[0-9]{2}/{if($2==dd) n++} END{print n+0}' "$jf")"
      err "[$bn] Duplicate date heading $d x$c. Merge into one section."
    done
  fi
done
echo "  Found $journal_count journal files"

echo ""
echo "Checking token budget..."
total=0
for f in "$hot" "$active" "$memo"; do
  [ -f "$f" ] || continue
  c="$(wc -c < "$f" | awk '{$1=$1;print}')"
  total=$((total + c))
  if [ "$c" -gt 3000 ]; then
    warn "[$(basename "$f")] File is $c chars (~$((c/4)) tokens) - consider trimming"
  fi
done
echo "  Always-read layer: $total chars (~$((total/4)) tokens)"
if [ "$total" -gt 8000 ]; then
  err "[Token Budget] Always-read layer exceeds 8000 chars (~2000 tokens)"
elif [ "$total" -gt 6000 ]; then
  warn "[Token Budget] Always-read layer is $total chars - approaching limit"
fi

echo ""
echo "Checking for orphans..."
[ -f "$LESSONS/index.md" ] || warn "[lessons/index.md] Missing - run rebuild-memory-index.sh"
[ -f "$MEM/journal-index.md" ] || warn "[journal-index.md] Missing - run rebuild-memory-index.sh"

echo ""
echo "====== LINT RESULTS ======"
echo "Errors: $errors"
echo "Warnings: $warnings"

rm -f "$allowed_tmp" "$ids_tmp" 2>/dev/null || true

if [ "$errors" -gt 0 ]; then
  echo ""
  echo "Lint FAILED with $errors error(s)" >&2
  exit 1
fi
echo ""
echo "Lint passed"
EOF

# -------------------------
# Git hook (portable)
# -------------------------

write_file "$GITHOOKS_DIR/pre-commit" <<'EOF'
#!/bin/sh
set -e

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

echo "[Mnemo] Rebuilding indexes + lint..."
sh "./scripts/memory/rebuild-memory-index.sh"
sh "./scripts/memory/lint-memory.sh"

for p in \
  .mnemo/memory/lessons/index.md \
  .mnemo/memory/lessons-index.json \
  .mnemo/memory/journal-index.md \
  .mnemo/memory/journal-index.json \
  .mnemo/memory/digests/*.digest.md \
  .cursor/memory/lessons/index.md \
  .cursor/memory/lessons-index.json \
  .cursor/memory/journal-index.md \
  .cursor/memory/journal-index.json \
  .cursor/memory/digests/*.digest.md
do
  git add "$p" 2>/dev/null || true
done
exit 0
EOF

# Also write .git/hooks/pre-commit for immediate effect (best effort)
if [ -d "$REPO_ROOT/.git/hooks" ]; then
  legacy="$REPO_ROOT/.git/hooks/pre-commit"
  if [ -f "$legacy" ] && [ "$FORCE" != "1" ]; then
    if grep -q "Mnemo" "$legacy" 2>/dev/null; then
      echo "SKIP (exists): $legacy"
    else
      printf "\n\n" >>"$legacy" || true
      cat "$GITHOOKS_DIR/pre-commit" >>"$legacy" || true
      echo "Updated: $legacy"
    fi
  else
    cp "$GITHOOKS_DIR/pre-commit" "$legacy" 2>/dev/null || true
  fi
fi

# Optional: write python helpers (for SQLite build/query). Used only if python3 exists.
write_file "$MEM_SCRIPTS_DIR/build-memory-sqlite.py" <<'EOF'
#!/usr/bin/env python3
"""Build SQLite FTS5 index from memory JSON indexes."""
import argparse
import json
import sqlite3
from pathlib import Path

def read_text(p: Path) -> str:
    return p.read_text(encoding="utf-8-sig", errors="replace")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    args = ap.parse_args()

    repo = Path(args.repo)
    mem = repo / ".cursor" / "memory"
    out_db = mem / "memory.sqlite"

    lessons_index = mem / "lessons-index.json"
    journal_index = mem / "journal-index.json"

    lessons = []
    if lessons_index.exists():
        t = read_text(lessons_index).strip()
        if t:
            lessons = json.loads(t)
            if not isinstance(lessons, list):
                lessons = [lessons] if lessons else []

    journal = []
    if journal_index.exists():
        t = read_text(journal_index).strip()
        if t:
            journal = json.loads(t)
            if not isinstance(journal, list):
                journal = [journal] if journal else []

    if out_db.exists():
        out_db.unlink()

    con = sqlite3.connect(str(out_db))
    cur = con.cursor()
    cur.execute("CREATE VIRTUAL TABLE memory_fts USING fts5(kind, id, date, tags, title, content, path);")

    for kind, fid, path in [
        ("hot_rules", "HOT", mem / "hot-rules.md"),
        ("active", "ACTIVE", mem / "active-context.md"),
        ("memo", "MEMO", mem / "memo.md"),
    ]:
        if path.exists():
            cur.execute(
                "INSERT INTO memory_fts(kind,id,date,tags,title,content,path) VALUES (?,?,?,?,?,?,?)",
                (kind, fid, None, "", path.name, read_text(path), str(path)),
            )

    lessons_dir = mem / "lessons"
    for l in lessons:
        lid = l.get("Id")
        title = l.get("Title", "")
        tags = " ".join(l.get("Tags") or [])
        date = l.get("Introduced")
        file = l.get("File", "")
        path = lessons_dir / file if file else (mem / "lessons.md")
        content = read_text(path) if path.exists() else f"{title}\nRule: {l.get('Rule','')}"
        cur.execute(
            "INSERT INTO memory_fts(kind,id,date,tags,title,content,path) VALUES (?,?,?,?,?,?,?)",
            ("lesson", lid, date, tags, title, content, str(path)),
        )

    for e in journal:
        tags = " ".join(e.get("Tags") or [])
        files = e.get("Files") or []
        if isinstance(files, dict):
            files = []
        content = f"{e.get('Title','')}\nFiles: {', '.join(files)}"
        path = mem / "journal" / (e.get("MonthFile") or "")
        cur.execute(
            "INSERT INTO memory_fts(kind,id,date,tags,title,content,path) VALUES (?,?,?,?,?,?,?)",
            ("journal", None, e.get("Date"), tags, e.get("Title"), content, str(path)),
        )

    digests = mem / "digests"
    if digests.exists():
        for p in digests.glob("*.digest.md"):
            cur.execute(
                "INSERT INTO memory_fts(kind,id,date,tags,title,content,path) VALUES (?,?,?,?,?,?,?)",
                ("digest", None, None, "", p.name, read_text(p), str(p)),
            )

    con.commit()
    con.close()
    print(f"Built: {out_db}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
EOF

write_file "$MEM_SCRIPTS_DIR/query-memory-sqlite.py" <<'EOF'
#!/usr/bin/env python3
"""Query memory SQLite FTS index."""
import argparse
import sqlite3
from pathlib import Path

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--repo", required=True)
    ap.add_argument("--q", required=True)
    ap.add_argument("--area", default="All")
    ap.add_argument("--format", default="Human")
    args = ap.parse_args()

    repo = Path(args.repo)
    db = repo / ".cursor" / "memory" / "memory.sqlite"
    if not db.exists():
        print("SQLite DB not found. Run rebuild-memory-index.sh first.")
        return 2

    area = args.area.lower()
    kind_filter = None
    if area == "hotrules": kind_filter = "hot_rules"
    elif area == "active": kind_filter = "active"
    elif area == "memo": kind_filter = "memo"
    elif area == "lessons": kind_filter = "lesson"
    elif area == "journal": kind_filter = "journal"
    elif area == "digests": kind_filter = "digest"

    con = sqlite3.connect(str(db))
    cur = con.cursor()

    sql = "SELECT kind, id, date, title, path, snippet(memory_fts, 5, '[', ']', '...', 12) FROM memory_fts WHERE memory_fts MATCH ?"
    params = [args.q]
    if kind_filter:
        sql += " AND kind = ?"
        params.append(kind_filter)
    sql += " LIMIT 20"

    rows = cur.execute(sql, params).fetchall()
    con.close()

    if args.format.lower() == "ai":
        paths = []
        for r in rows:
            p = r[4]
            try:
                rel = str(Path(p).resolve().relative_to(repo.resolve()))
            except Exception:
                rel = p
            paths.append(rel.replace("\\", "/"))
        uniq = []
        for p in paths:
            if p not in uniq:
                uniq.append(p)
        if not uniq:
            print(f"No matches for: {args.q}")
        else:
            print("Files to read:")
            for p in uniq:
                print(f"  @{p}")
        return 0

    if not rows:
        print(f"No matches for: {args.q}")
        return 0

    for kind, idv, date, title, path, snip in rows:
        print(f"==> {kind} | {idv or '-'} | {date or '-'} | {title}")
        print(f"    {path}")
        print(f"    {snip}")
        print("")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
EOF

if [ "$ENABLE_VECTOR" = "1" ]; then
  echo "Vector mode enabled (provider: $VECTOR_PROVIDER)"

  if [ "$DRY_RUN" != "1" ]; then
    # Robust Python detection: try python3.12, python3.11, python3.10, python3, python
    PYTHON3_CMD=""
    for _py_candidate in python3.12 python3.11 python3.10 python3 python; do
      if command -v "$_py_candidate" >/dev/null 2>&1; then
        _ver="$($_py_candidate -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
        _major="$(echo "$_ver" | cut -d. -f1)"
        _minor="$(echo "$_ver" | cut -d. -f2)"
        if [ "${_major:-0}" -ge 3 ] && [ "${_minor:-0}" -ge 10 ] 2>/dev/null; then
          PYTHON3_CMD="$_py_candidate"
          break
        fi
      fi
    done
    if [ -z "$PYTHON3_CMD" ]; then
      echo "Vector mode requires Python 3.10+ (python3/python not found or version too old)." >&2
      echo "Install Homebrew Python: brew install python@3.12" >&2
      exit 1
    fi

    if ! "$PYTHON3_CMD" -m pip --version >/dev/null 2>&1; then
      echo "pip is unavailable for $PYTHON3_CMD." >&2
      echo "Install Homebrew Python (brew install python) or use a virtualenv." >&2
      exit 1
    fi

    need_pip_install="1"
    if [ "$FORCE" != "1" ] && "$PYTHON3_CMD" - "$VECTOR_PROVIDER" <<'PY' >/dev/null 2>&1; then
import importlib.util
import sys

provider = sys.argv[1]
mods = ["openai", "sqlite_vec", "mcp"]
if provider == "gemini":
    mods.append("google.genai")
missing = [m for m in mods if importlib.util.find_spec(m) is None]
raise SystemExit(0 if not missing else 1)
PY
      need_pip_install="0"
    fi

    if [ "$need_pip_install" = "1" ]; then
      pip_err="${TMPDIR:-/tmp}/mnemo-vector-pip.$$"
      pkgs="openai sqlite-vec mcp[cli]>=1.2.0,<2.0"
      if [ "$VECTOR_PROVIDER" = "gemini" ]; then
        pkgs="$pkgs google-genai"
      fi

      # shellcheck disable=SC2086
      if ! "$PYTHON3_CMD" -m pip install --quiet $pkgs 2>"$pip_err"; then
        if grep -Ei "externally managed|externally-managed" "$pip_err" >/dev/null 2>&1; then
          echo "Python is externally managed (PEP668)." >&2
          echo "Use Homebrew Python or a venv, then re-run with --enable-vector." >&2
        fi
        cat "$pip_err" >&2 || true
        rm -f "$pip_err"
        exit 1
      fi
      rm -f "$pip_err"
    else
      echo "SKIP (deps installed): vector dependency install"
    fi
  else
    echo "[DRY RUN] Skipping vector dependency checks/install."
  fi

  # Use template file if running from Mnemo installer repo; else use embedded copy
  _vector_tpl="$_INSTALLER_DIR/scripts/memory/installer/templates/mnemo_vector.py"
  if [ -f "$_vector_tpl" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      echo "[DRY RUN] WOULD WRITE: $MEM_SCRIPTS_DIR/mnemo_vector.py"
    elif [ -f "$MEM_SCRIPTS_DIR/mnemo_vector.py" ] && [ "$FORCE" != "1" ]; then
      echo "SKIP (exists): $MEM_SCRIPTS_DIR/mnemo_vector.py"
    else
      cp "$_vector_tpl" "$MEM_SCRIPTS_DIR/mnemo_vector.py"
      echo "WROTE: $MEM_SCRIPTS_DIR/mnemo_vector.py"
    fi
  else
  write_file "$MEM_SCRIPTS_DIR/mnemo_vector.py" <<'EOF'
#!/usr/bin/env python3
"""
Mnemo vector memory engine (v2 - embedded fallback).
Optional semantic layer for .cursor/memory with MCP tools.
"""
import os
import re
import sqlite3
import hashlib
from pathlib import Path

import sqlite_vec
try:
    from sqlite_vec import serialize_float32 as serialize_f32
except ImportError:
    from sqlite_vec import serialize_f32  # backwards compatibility
from mcp.server.fastmcp import FastMCP

SCHEMA_VERSION = 2
EMBED_DIM = 1536


def _resolve_memory_root() -> Path:
    override = os.getenv("MNEMO_MEMORY_ROOT", "").strip()
    if override:
        return Path(override).expanduser().resolve()

    script_repo = Path(__file__).resolve().parents[2]
    for rel in ((".mnemo", "memory"), (".cursor", "memory")):
        candidate = script_repo.joinpath(*rel)
        if candidate.exists():
            return candidate

    cwd = Path.cwd().resolve()
    for root in (cwd, *cwd.parents):
        for rel in ((".mnemo", "memory"), (".cursor", "memory")):
            candidate = root.joinpath(*rel)
            if candidate.exists():
                return candidate
    return script_repo / ".mnemo" / "memory"


def _resolve_repo_root(memory_root: Path) -> Path:
    root = memory_root.resolve()
    if root.name == "memory" and root.parent.name in {".mnemo", ".cursor"}:
        return root.parent.parent
    cwd = Path.cwd().resolve()
    for candidate in (cwd, *cwd.parents):
        if candidate.joinpath(".mnemo", "memory").exists() or candidate.joinpath(".cursor", "memory").exists():
            return candidate
    return cwd


def _parse_env_line(raw_line: str):
    line = raw_line.strip()
    if not line or line.startswith("#"):
        return None
    if line.startswith("export "):
        line = line[7:].strip()
    if "=" not in line:
        return None
    key, value = line.split("=", 1)
    key = key.strip()
    if not key or any(ch.isspace() for ch in key):
        return None
    value = value.strip()
    if value and len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        value = value[1:-1]
    elif " #" in value:
        value = value.split(" #", 1)[0].rstrip()
    return key, value


def _is_missing_env_value(value):
    if value is None:
        return True
    stripped = str(value).strip()
    if not stripped:
        return True
    if stripped.startswith("${env:") and stripped.endswith("}"):
        return True
    return False


def _get_env_value(name: str) -> str:
    value = os.getenv(name)
    if _is_missing_env_value(value):
        return ""
    return str(value).strip()


def _load_project_env(repo_root: Path) -> None:
    env_path = repo_root / ".env"
    if not env_path.exists():
        return
    try:
        for raw_line in env_path.read_text(encoding="utf-8").splitlines():
            parsed = _parse_env_line(raw_line)
            if not parsed:
                continue
            key, value = parsed
            key = key.lstrip("\ufeff")
            if _is_missing_env_value(os.getenv(key)):
                os.environ[key] = value
    except OSError:
        pass


def _resolve_provider() -> str:
    configured = os.getenv("MNEMO_PROVIDER", "").strip().lower()
    if configured.startswith("${env:") and configured.endswith("}"):
        configured = ""
    if configured in {"openai", "gemini"}:
        return configured
    return "gemini" if _get_env_value("GEMINI_API_KEY") else "openai"


MEM_ROOT = _resolve_memory_root()
REPO_ROOT = _resolve_repo_root(MEM_ROOT)
_DB_OVERRIDE = os.getenv("MNEMO_DB_PATH", "").strip()
DB_PATH = Path(_DB_OVERRIDE).expanduser().resolve() if _DB_OVERRIDE else (MEM_ROOT / "mnemo_vector.sqlite")
_load_project_env(REPO_ROOT)
PROVIDER = _resolve_provider()

SKIP_NAMES = {
    "README.md",
    "index.md",
    "lessons-index.json",
    "journal-index.json",
    "journal-index.md",
}
SKIP_DIRS = {"legacy", "templates"}
MAX_EMBED_CHARS = 12000
BATCH_SIZE = 16 if PROVIDER == "gemini" else 64
_EMBED_CLIENT = None

mcp = FastMCP("MnemoVector")


def _trim_for_embedding(text: str) -> str:
    return text[:MAX_EMBED_CHARS] if len(text) > MAX_EMBED_CHARS else text


def _get_embed_client():
    global _EMBED_CLIENT
    if _EMBED_CLIENT is not None:
        return _EMBED_CLIENT

    if PROVIDER == "gemini":
        key = _get_env_value("GEMINI_API_KEY")
        if not key:
            raise RuntimeError("GEMINI_API_KEY is not set")
        from google import genai
        _EMBED_CLIENT = genai.Client(api_key=key)
        return _EMBED_CLIENT

    key = _get_env_value("OPENAI_API_KEY")
    if not key:
        raise RuntimeError("OPENAI_API_KEY is not set")
    from openai import OpenAI
    _EMBED_CLIENT = OpenAI(api_key=key)
    return _EMBED_CLIENT


def get_embeddings(texts: list[str]) -> list[list[float]]:
    if not texts:
        return []
    trimmed = [_trim_for_embedding(t) for t in texts]
    client = _get_embed_client()

    if PROVIDER == "gemini":
        from google.genai import types
        result = client.models.embed_content(
            model="gemini-embedding-001",
            contents=trimmed,
            config=types.EmbedContentConfig(output_dimensionality=EMBED_DIM),
        )
        vectors = [emb.values for emb in result.embeddings]
    else:
        resp = client.embeddings.create(input=trimmed, model="text-embedding-3-small")
        vectors = [item.embedding for item in resp.data]

    if len(vectors) != len(trimmed):
        raise RuntimeError(f"Embedding provider returned {len(vectors)} vectors for {len(trimmed)} inputs")
    return vectors


def get_embedding(text: str) -> list[float]:
    return get_embeddings([text])[0]


def get_db() -> sqlite3.Connection:
    DB_PATH.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(str(DB_PATH), timeout=30)
    db.execute("PRAGMA journal_mode=WAL")
    db.execute("PRAGMA busy_timeout=10000")
    db.enable_load_extension(True)
    sqlite_vec.load(db)
    return db


def init_db() -> sqlite3.Connection:
    db = get_db()
    db.execute("CREATE TABLE IF NOT EXISTS schema_info (key TEXT PRIMARY KEY, value TEXT)")
    row = db.execute("SELECT value FROM schema_info WHERE key='version'").fetchone()
    ver = int(row[0]) if row else 0

    if ver < SCHEMA_VERSION:
        db.execute("DROP TABLE IF EXISTS file_meta")
        db.execute("DROP TABLE IF EXISTS vec_memory")
        db.execute(
            """
            CREATE TABLE file_meta (
                path TEXT PRIMARY KEY,
                hash TEXT NOT NULL,
                chunk_count INTEGER DEFAULT 0,
                updated_at REAL DEFAULT (unixepoch('now'))
            )
            """
        )
        db.execute(
            f"""
            CREATE VIRTUAL TABLE vec_memory USING vec0(
                embedding float[{EMBED_DIM}] distance_metric=cosine,
                +ref_path TEXT,
                +content TEXT,
                +source_file TEXT
            )
            """
        )
        db.execute(
            "INSERT OR REPLACE INTO schema_info(key, value) VALUES ('version', ?)",
            (str(SCHEMA_VERSION),),
        )
        db.commit()
    return db


def chunk_markdown(content: str, file_path: Path) -> list[tuple[str, str]]:
    chunks: list[tuple[str, str]] = []
    path_str = str(file_path).replace("\\", "/")

    if "journal/" in path_str.lower():
        parts = re.split(r"^(##\s+\d{4}-\d{2}-\d{2})", content, flags=re.MULTILINE)
        preamble = parts[0].strip()
        if preamble:
            chunks.append((preamble, f"@{path_str}"))
        i = 1
        while i < len(parts) - 1:
            heading = parts[i].strip()
            body = parts[i + 1].strip()
            date = heading.replace("##", "").strip()
            chunks.append((f"{heading}\n{body}".strip(), f"@{path_str}# {date}"))
            i += 2
        if chunks:
            return chunks

    if file_path.parent.name == "lessons" and file_path.name.startswith("L-"):
        text = content.strip()
        if text:
            m = re.match(r"(L-\d{3})", file_path.name)
            ref = f"@{path_str}# {m.group(1)}" if m else f"@{path_str}"
            chunks.append((text, ref))
        return chunks

    parts = re.split(r"^(#{1,4}\s+.+)$", content, flags=re.MULTILINE)
    preamble = parts[0].strip()
    if preamble:
        chunks.append((preamble, f"@{path_str}"))

    i = 1
    while i < len(parts) - 1:
        heading_line = parts[i].strip()
        body = parts[i + 1].strip()
        heading_text = re.sub(r"^#{1,4}\s+", "", heading_line)
        full = f"{heading_line}\n{body}".strip() if body else heading_line
        if full.strip():
            chunks.append((full, f"@{path_str}# {heading_text}"))
        i += 2

    if not chunks and content.strip():
        chunks.append((content.strip(), f"@{path_str}"))
    return chunks


@mcp.tool()
def vector_sync() -> str:
    db = init_db()
    files: dict[str, Path] = {}
    for p in MEM_ROOT.glob("**/*.md"):
        if p.name in SKIP_NAMES:
            continue
        if any(skip in p.parts for skip in SKIP_DIRS):
            continue
        files[str(p)] = p

    updated = 0
    skipped = 0
    errors = 0
    known = db.execute("SELECT path FROM file_meta").fetchall()
    for (stored,) in known:
        if stored not in files:
            db.execute("DELETE FROM vec_memory WHERE source_file = ?", (stored,))
            db.execute("DELETE FROM file_meta WHERE path = ?", (stored,))
            updated += 1

    for str_path, file_path in files.items():
        try:
            content = file_path.read_text(encoding="utf-8-sig")
        except (UnicodeDecodeError, PermissionError, OSError):
            errors += 1
            continue
        if not content.strip():
            skipped += 1
            continue

        f_hash = hashlib.sha256(content.encode("utf-8")).hexdigest()
        row = db.execute("SELECT hash FROM file_meta WHERE path = ?", (str_path,)).fetchone()
        if row and row[0] == f_hash:
            skipped += 1
            continue

        db.execute("DELETE FROM vec_memory WHERE source_file = ?", (str_path,))
        chunks = chunk_markdown(content, file_path)
        embedded = 0
        chunk_errors = 0
        for i in range(0, len(chunks), BATCH_SIZE):
            batch = chunks[i : i + BATCH_SIZE]
            texts = [text for text, _ in batch]
            try:
                vectors = get_embeddings(texts)
                for (text, ref), emb in zip(batch, vectors):
                    db.execute(
                        "INSERT INTO vec_memory(embedding, ref_path, content, source_file) VALUES (?, ?, ?, ?)",
                        (serialize_f32(emb), ref, text, str_path),
                    )
                    embedded += 1
            except Exception:
                for text, ref in batch:
                    try:
                        emb = get_embedding(text)
                        db.execute(
                            "INSERT INTO vec_memory(embedding, ref_path, content, source_file) VALUES (?, ?, ?, ?)",
                            (serialize_f32(emb), ref, text, str_path),
                        )
                        embedded += 1
                    except Exception:
                        chunk_errors += 1

        if chunk_errors == 0:
            db.execute(
                "INSERT OR REPLACE INTO file_meta(path, hash, chunk_count, updated_at) VALUES (?, ?, ?, unixepoch('now'))",
                (str_path, f_hash, embedded),
            )
        else:
            db.execute(
                "INSERT OR REPLACE INTO file_meta(path, hash, chunk_count, updated_at) VALUES (?, ?, ?, unixepoch('now'))",
                (str_path, "DIRTY", embedded),
            )
            errors += chunk_errors
        updated += 1

    db.commit()
    db.close()
    msg = f"Synced: {updated} files processed, {skipped} unchanged"
    if errors:
        msg += f", {errors} chunk errors (will retry)"
    return msg


@mcp.tool()
def vector_search(query: str, top_k: int = 5) -> str:
    db = init_db()
    emb = get_embedding(query)
    rows = db.execute(
        "SELECT ref_path, content, distance FROM vec_memory WHERE embedding MATCH ? AND k = ? ORDER BY distance",
        (serialize_f32(emb), top_k),
    ).fetchall()
    db.close()
    if not rows:
        return "No relevant memory found."
    out = []
    for ref, content, dist in rows:
        sim = round(1.0 - dist, 4)
        preview = " ".join(content[:400].split())
        out.append(f"[sim={sim:.3f}] {ref}\n{preview}")
    return "\n\n---\n\n".join(out)


@mcp.tool()
def vector_forget(path_pattern: str = "") -> str:
    db = init_db()
    removed = 0
    if path_pattern:
        like = f"%{path_pattern}%"
        r1 = db.execute("DELETE FROM vec_memory WHERE source_file LIKE ?", (like,)).rowcount
        r2 = db.execute("DELETE FROM file_meta WHERE path LIKE ?", (like,)).rowcount
        removed = max(r1, r2)
    else:
        known = db.execute("SELECT path FROM file_meta").fetchall()
        for (p,) in known:
            if not Path(p).exists():
                db.execute("DELETE FROM vec_memory WHERE source_file = ?", (p,))
                db.execute("DELETE FROM file_meta WHERE path = ?", (p,))
                removed += 1
    db.commit()
    db.close()
    return f"Pruned {removed} entries."


@mcp.tool()
def vector_health() -> str:
    lines = []
    db = init_db()
    ver = db.execute("SELECT value FROM schema_info WHERE key='version'").fetchone()
    lines.append(f"Schema: v{ver[0] if ver else '?'}")
    files = db.execute("SELECT COUNT(*) FROM file_meta").fetchone()[0]
    vecs = db.execute("SELECT COUNT(*) FROM vec_memory").fetchone()[0]
    dirty = db.execute("SELECT COUNT(*) FROM file_meta WHERE hash = 'DIRTY'").fetchone()[0]
    lines.append(f"Files tracked: {files}")
    lines.append(f"Vector chunks: {vecs}")
    if dirty:
        lines.append(f"Dirty files: {dirty}")
    lines.append(f"DB integrity: {db.execute('PRAGMA integrity_check').fetchone()[0]}")
    db.close()
    return "\n".join(lines)


if __name__ == "__main__":
    mcp.run()
EOF
  fi  # end: template file check for mnemo_vector.py

  write_file "$RULES_DIR/01-vector-search.mdc" <<'EOF'
---
description: Mnemo vector semantic retrieval layer (optional)
globs:
  - "**/*"
alwaysApply: true
---

# Vector Memory Layer (Optional)

This rule supplements `00-memory-system.mdc` and does not replace governance.

## Use vector tools when:
- You do not know the exact keyword for prior context.
- Keyword/FTS search did not find relevant history.

## MCP tools
- `vector_search` - semantic retrieval with cosine similarity.
- `vector_sync` - incremental indexing.
- `vector_forget` - remove stale entries.
- `vector_health` - DB/API health check.

## Fallback
If vector search is unavailable, keep using:
- `scripts/memory/query-memory.sh --query "..."`
- `scripts/memory/query-memory.sh --query "..." --use-sqlite`
EOF

  write_file "$AGENT_RULES_DIR/01-vector-search.md" <<'EOF'
---
description: Mnemo vector semantic retrieval layer (optional)
alwaysApply: true
---

# Vector Memory Layer (Optional)

This rule supplements `00-memory-system.md` and does not replace governance.

## Use vector tools when:
- You do not know the exact keyword for prior context.
- Keyword/FTS search did not find relevant history.

## MCP tools
- `vector_search` - semantic retrieval with cosine similarity.
- `vector_sync` - incremental indexing.
- `vector_forget` - remove stale entries.
- `vector_health` - DB/API health check.

## Fallback
If vector search is unavailable, keep using:
- `scripts/memory/query-memory.sh --query "..."`
- `scripts/memory/query-memory.sh --query "..." --use-sqlite`
EOF

  if [ "$DRY_RUN" != "1" ]; then
  mcp_status="$(python3 - "$REPO_ROOT" "$VECTOR_PROVIDER" "$FORCE" "$MNEMO_CURSOR_MCP_PATH" <<'PY'
import json
import sys
from pathlib import Path

repo = Path(sys.argv[1])
provider = sys.argv[2]
force = sys.argv[3] == "1"
mcp_path = Path(sys.argv[4])
engine = str((repo / "scripts" / "memory" / "mnemo_vector.py").resolve())

root = {}
existing_root = None
if mcp_path.exists():
    try:
        existing_root = json.loads(mcp_path.read_text(encoding="utf-8"))
        root = dict(existing_root) if isinstance(existing_root, dict) else {}
    except Exception:
        root = {}
        existing_root = None

servers = root.get("mcpServers") if isinstance(root, dict) else {}
if not isinstance(servers, dict):
    servers = {}

env = {"MNEMO_PROVIDER": provider}
if provider == "gemini":
    env["GEMINI_API_KEY"] = "${env:GEMINI_API_KEY}"
else:
    env["OPENAI_API_KEY"] = "${env:OPENAI_API_KEY}"

servers["MnemoVector"] = {
    "command": "python3",
    "args": [engine],
    "env": env,
}
root["mcpServers"] = servers
if (not force) and isinstance(existing_root, dict) and existing_root == root:
    print("UNCHANGED")
    raise SystemExit(0)
new_content = json.dumps(root, indent=2)
if mcp_path.exists():
    import shutil
    shutil.copy2(str(mcp_path), str(mcp_path) + ".bak")
tmp = str(mcp_path) + ".tmp"
Path(tmp).write_text(new_content, encoding="utf-8")
Path(tmp).replace(mcp_path)
print("UPDATED")
PY
)"
    if [ "$mcp_status" = "UNCHANGED" ]; then
      echo "SKIP (exists): $MNEMO_CURSOR_MCP_PATH (MnemoVector MCP unchanged)"
    else
      echo "WROTE: $MNEMO_CURSOR_MCP_PATH"
    fi

    post_hook="$GITHOOKS_DIR/post-commit"
    backup_hook="$GITHOOKS_DIR/post-commit.before-mnemo-vector"
    marker="Mnemo Vector Hook Wrapper"
    if [ -f "$post_hook" ] && ! grep -Fq "$marker" "$post_hook" 2>/dev/null; then
      cp "$post_hook" "$backup_hook" 2>/dev/null || true
    fi

    if [ "$VECTOR_PROVIDER" = "gemini" ]; then
      api_guard='[ -z "${GEMINI_API_KEY:-}" ] && exit 0'
    else
      api_guard='[ -z "${OPENAI_API_KEY:-}" ] && exit 0'
    fi

    post_tmp="${TMPDIR:-/tmp}/mnemo-post-hook.$$"
    cat >"$post_tmp" <<EOF
#!/bin/sh
# Mnemo Vector Hook Wrapper
set -e

ROOT="\$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "\$ROOT" || exit 0

if [ -f ".githooks/post-commit.before-mnemo-vector" ]; then
  sh ".githooks/post-commit.before-mnemo-vector" || true
fi

$api_guard

LOCKDIR="\$ROOT/.mnemo/memory/.sync.lock"
if [ ! -d "\$ROOT/.mnemo/memory" ] && [ -d "\$ROOT/.cursor/memory" ]; then
  LOCKDIR="\$ROOT/.cursor/memory/.sync.lock"
fi
if [ -d "\$LOCKDIR" ]; then
  NOW=\$(date +%s 2>/dev/null || echo 0)
  MTIME=\$(stat -f %m "\$LOCKDIR" 2>/dev/null || stat -c %Y "\$LOCKDIR" 2>/dev/null || echo 0)
  AGE=\$((NOW - MTIME))
  if [ "\$AGE" -gt 600 ] 2>/dev/null; then
    rmdir "\$LOCKDIR" 2>/dev/null || true
  fi
fi

if mkdir "\$LOCKDIR" 2>/dev/null; then
  trap 'rmdir "\$LOCKDIR" 2>/dev/null || true' EXIT INT TERM
  python3 -c "import sys; sys.path.insert(0, 'scripts/memory'); from mnemo_vector import vector_sync; print('[MnemoVector]', vector_sync())" 2>&1 | tail -1 || true
fi

exit 0
EOF
    if [ -f "$post_hook" ] && [ "$FORCE" != "1" ] && cmp -s "$post_hook" "$post_tmp" 2>/dev/null; then
      echo "SKIP (exists): $post_hook"
    else
      cp "$post_tmp" "$post_hook" 2>/dev/null || cat "$post_tmp" >"$post_hook"
      chmod +x "$post_hook" 2>/dev/null || true
      echo "WROTE: $post_hook"
    fi
    rm -f "$post_tmp"

    if [ -d "$REPO_ROOT/.git/hooks" ]; then
      legacy_post="$REPO_ROOT/.git/hooks/post-commit"
      if [ -f "$legacy_post" ] && [ "$FORCE" != "1" ] && ! grep -Fq "$marker" "$legacy_post" 2>/dev/null; then
        echo "SKIP (legacy post-commit exists): $legacy_post"
      elif [ -f "$legacy_post" ] && [ "$FORCE" != "1" ] && cmp -s "$post_hook" "$legacy_post" 2>/dev/null; then
        echo "SKIP (exists): $legacy_post"
      else
        cp "$post_hook" "$legacy_post" 2>/dev/null || true
        echo "WROTE: $legacy_post"
      fi
    fi
  else
    echo "[DRY RUN] WOULD WRITE: $MNEMO_CURSOR_MCP_PATH"
    echo "[DRY RUN] WOULD CONFIGURE: $GITHOOKS_DIR/post-commit (MnemoVector wrapper)"
  fi
fi

# Update .gitignore with memory artifacts (marker-based, idempotent)
gi="$REPO_ROOT/.gitignore"
GI_BEGIN="# >>> Mnemo (generated) - do not edit this block manually <<<"
GI_END="# <<< Mnemo (generated) >>>"

ignore_lines=".mnemo/
.cursor/memory/
.cursor/rules/
.cursor/skills/
.cursor/mcp.json
.agent/rules/
scripts/memory/
.githooks/"

if [ "$DRY_RUN" = "1" ]; then
  echo "[DRY RUN] WOULD UPDATE: $gi (managed Mnemo block)"
else
  new_block="$GI_BEGIN
$ignore_lines
$GI_END"

  if [ ! -f "$gi" ]; then
    printf "%s\n" "$new_block" >"$gi"
    echo "Created .gitignore with Mnemo managed block"
  elif grep -qF "$GI_BEGIN" "$gi" 2>/dev/null; then
    # Replace existing managed block using awk (POSIX, no temp file race)
    awk -v begin="$GI_BEGIN" -v block="$new_block" '
      BEGIN { skipping=0; done=0 }
      $0 == begin { skipping=1 }
      skipping && /^# <<< Mnemo \(generated\) >>>/ {
        skipping=0
        if (!done) { print block; done=1 }
        next
      }
      !skipping { print }
    ' "$gi" > "$gi.tmp.$$" && mv "$gi.tmp.$$" "$gi"
    echo "Updated .gitignore managed block"
  else
    printf "\n%s\n" "$new_block" >> "$gi"
    echo "Added Mnemo managed block to .gitignore"
  fi
fi

# Ensure permanent compatibility bridges are present and healthy.
ensure_mnemo_bridges

chmod +x "$MEM_SCRIPTS_DIR/"*.sh "$GITHOOKS_DIR/pre-commit" "$GITHOOKS_DIR/post-commit" 2>/dev/null || true

# Auto-configure portable hooks path (removes manual step)
if [ "$DRY_RUN" != "1" ] && [ -d "$REPO_ROOT/.git" ]; then
  _current_hp="$(git -C "$REPO_ROOT" config core.hooksPath 2>/dev/null || true)"
  if [ "$_current_hp" != ".githooks" ]; then
    git -C "$REPO_ROOT" config core.hooksPath .githooks 2>/dev/null || true
    echo "Configured: git config core.hooksPath .githooks"
  fi
fi

# Copy autonomy modules from installer templates if available and vector is enabled
if [ "$ENABLE_VECTOR" = "1" ] && [ "$DRY_RUN" != "1" ]; then
  _autonomy_tpl="$_INSTALLER_DIR/scripts/memory/installer/templates/autonomy"
  _autonomy_dest="$MEM_SCRIPTS_DIR/autonomy"
  mkdir -p "$_autonomy_dest"
  if [ -d "$_autonomy_tpl" ]; then
    _autonomy_missing=0
    for _f in __init__.py schema.py runner.py ingest_pipeline.py lifecycle_engine.py entity_resolver.py retrieval_router.py reranker.py context_safety.py vault_policy.py policies.yaml; do
      if [ ! -f "$_autonomy_dest/$_f" ]; then
        _autonomy_missing=1
        break
      fi
    done
    if [ "$FORCE" = "1" ] || [ "$_autonomy_missing" = "1" ]; then
      cp -r "$_autonomy_tpl/." "$_autonomy_dest/" 2>/dev/null || true
      echo "WROTE: $MEM_SCRIPTS_DIR/autonomy/ (autonomy runtime modules)"
    else
      echo "SKIP (exists): $MEM_SCRIPTS_DIR/autonomy/ (autonomy runtime modules)"
    fi
  fi
fi

echo ""
echo "Setup complete. (Mnemo v$MNEMO_VERSION)"
echo "Next:"
echo "  skill: .cursor/skills/mnemo-codebase-optimizer/SKILL.md"
echo "  sh ./scripts/memory/rebuild-memory-index.sh"
echo "  sh ./scripts/memory/lint-memory.sh"
if [ "$ENABLE_VECTOR" = "1" ] && [ "$DRY_RUN" != "1" ]; then
  echo "  restart Cursor, then run: vector_health and vector_sync"
  echo ""
  echo "Vector tools enabled: vector_search, vector_sync, vector_forget, vector_health"
  echo "Important: post-commit uses shell env vars (export OPENAI_API_KEY/GEMINI_API_KEY)."
elif [ "$ENABLE_VECTOR" = "1" ] && [ "$DRY_RUN" = "1" ]; then
  echo "  (dry run) vector setup preview only; no MCP/hooks changed"
  echo ""
  echo "Vector tools previewed (dry run): no dependencies installed and no MCP/hooks were modified."
fi

