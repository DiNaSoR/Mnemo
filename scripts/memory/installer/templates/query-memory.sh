#!/bin/sh
set -eu

QUERY=""
AREA="All"
FORMAT="Human"
USE_SQLITE="0"

while [ $# -gt 0 ]; do
  case "$1" in
    --query) QUERY="$2"; shift 2 ;;
    --area) AREA="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --use-sqlite) USE_SQLITE="1"; shift 1 ;;
    -h|--help)
      echo "Usage: sh ./scripts/memory/query-memory.sh --query \"...\" [--area All|HotRules|Active|Memo|Lessons|Journal|Digests] [--format Human|AI] [--use-sqlite]"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$QUERY" ]; then
  echo "Missing --query" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

to_lower() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]'
}

resolve_memory_dir() {
  for candidate in "$ROOT/.mnemo/memory" "$ROOT/.cursor/memory"; do
    if [ -d "$candidate" ]; then
      printf '%s' "$candidate"
      return 0
    fi
  done
  printf '%s' "$ROOT/.mnemo/memory"
}

detect_python_cmd() {
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' 'python3'
  elif command -v python >/dev/null 2>&1; then
    printf '%s' 'python'
  else
    printf ''
  fi
}

search_file() {
  file_path="$1"
  [ -f "$file_path" ] || return 0
  grep -nH -F -- "$QUERY" "$file_path" 2>/dev/null >>"$TMP_RESULTS" || true
}

search_named_files() {
  search_dir="$1"
  search_name="$2"
  [ -d "$search_dir" ] || return 0
  find "$search_dir" -maxdepth 1 -type f -name "$search_name" -print | while IFS= read -r file_path; do
    grep -nH -F -- "$QUERY" "$file_path" 2>/dev/null >>"$TMP_RESULTS" || true
  done
}

MEM="$(resolve_memory_dir)"
LESSONS="$MEM/lessons"
SQLITE_PATH="$MEM/memory.sqlite"
AREA_L="$(to_lower "$AREA")"
FORMAT_L="$(to_lower "$FORMAT")"
TMP_RESULTS="${TMPDIR:-/tmp}/mnemo-query.$$"
rm -f "$TMP_RESULTS"
trap 'rm -f "$TMP_RESULTS"' EXIT INT TERM

if [ "$USE_SQLITE" = "1" ]; then
  PYTHON_CMD="$(detect_python_cmd)"
  SQLITE_QUERY="$ROOT/scripts/memory/query-memory-sqlite.py"
  if [ -n "$PYTHON_CMD" ] && [ -f "$SQLITE_PATH" ] && [ -f "$SQLITE_QUERY" ]; then
    "$PYTHON_CMD" "$SQLITE_QUERY" --repo "$ROOT" --q "$QUERY" --area "$AREA" --format "$FORMAT"
    exit $?
  fi
  echo "SQLite mode unavailable (need python/python3 + memory.sqlite + query-memory-sqlite.py). Falling back to file search." >&2
fi

case "$AREA_L" in
  hotrules|hot)
    search_file "$MEM/hot-rules.md"
    ;;
  active)
    search_file "$MEM/active-context.md"
    ;;
  memo)
    search_file "$MEM/memo.md"
    ;;
  lessons)
    search_file "$LESSONS/index.md"
    search_named_files "$LESSONS" 'L-*.md'
    ;;
  journal)
    search_file "$MEM/journal-index.md"
    ;;
  digests)
    search_named_files "$MEM/digests" '*.digest.md'
    ;;
  all)
    search_file "$MEM/hot-rules.md"
    search_file "$MEM/active-context.md"
    search_file "$MEM/memo.md"
    search_file "$LESSONS/index.md"
    search_file "$MEM/journal-index.md"
    search_named_files "$MEM/digests" '*.digest.md'
    ;;
  *)
    echo "Unknown --area: $AREA" >&2
    exit 2
    ;;
esac

if [ "$FORMAT_L" = 'ai' ]; then
  if [ ! -s "$TMP_RESULTS" ]; then
    echo "No matches found for: $QUERY"
  else
    echo 'Files to read:'
    cut -d: -f1 "$TMP_RESULTS" | awk '!seen[$0]++' | while IFS= read -r file_path; do
      rel="${file_path#$ROOT/}"
      echo "  @$rel"
    done
  fi
  exit 0
fi

echo "Searching: $QUERY"
echo "Area: $AREA"
echo ''
if [ ! -s "$TMP_RESULTS" ]; then
  echo 'No matches found.'
else
  cat "$TMP_RESULTS"
fi
