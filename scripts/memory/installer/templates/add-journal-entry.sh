#!/bin/sh
set -eu

TAGS=""
TITLE=""
FILES=""
WHY=""
DATE="$(date +%Y-%m-%d)"

while [ $# -gt 0 ]; do
  case "$1" in
    --tags) TAGS="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --files) FILES="$2"; shift 2 ;;
    --why) WHY="$2"; shift 2 ;;
    --date) DATE="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: sh ./scripts/memory/add-journal-entry.sh --tags \"UI,Fix\" --title \"...\" [--files \"a,b\"] [--why \"...\"] [--date YYYY-MM-DD]"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$TAGS" ] || [ -z "$TITLE" ]; then
  echo "Missing --tags or --title" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

resolve_memory_dir() {
  for candidate in "$ROOT/.mnemo/memory" "$ROOT/.cursor/memory"; do
    if [ -d "$candidate" ]; then
      printf "%s" "$candidate"
      return 0
    fi
  done
  printf "%s" "$ROOT/.mnemo/memory"
}

MEM="$(resolve_memory_dir)"
JOURNAL_DIR="$MEM/journal"
TAG_VOCAB="$MEM/tag-vocabulary.md"
MONTH="$(printf "%s" "$DATE" | cut -c1-7)"
JOURNAL="$JOURNAL_DIR/$MONTH.md"
PROJECT_NAME="$(basename "$ROOT")"

mkdir -p "$JOURNAL_DIR"

canon_tag() {
  want_l="$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')"
  [ -f "$TAG_VOCAB" ] || {
    printf "%s" "$1"
    return 0
  }
  awk -v w="$want_l" '
    BEGIN { IGNORECASE=1 }
    /^- \[[^]]+\]/ {
      t=$0
      sub(/^- \[/, "", t)
      sub(/\].*$/, "", t)
      if (tolower(t) == w) { print t; exit }
    }
  ' "$TAG_VOCAB" 2>/dev/null || true
}

tag_string=""
old_ifs="$IFS"
IFS=','
set -- $TAGS
IFS="$old_ifs"
for tag in "$@"; do
  trimmed="$(printf "%s" "$tag" | awk '{$1=$1; print}')"
  [ -z "$trimmed" ] && continue
  canon="$(canon_tag "$trimmed")"
  if [ -z "$canon" ]; then
    echo "Unknown tag '$trimmed'. Add it to tag-vocabulary.md or fix the tag." >&2
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
  old_ifs="$IFS"
  IFS=','
  set -- $FILES
  IFS="$old_ifs"
  for file_ref in "$@"; do
    trimmed="$(printf "%s" "$file_ref" | awk '{$1=$1; print}')"
    [ -n "$trimmed" ] && entry="${entry}\n    - \`$trimmed\`"
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

if grep -q "^## $DATE$" "$JOURNAL"; then
  entry_file="$JOURNAL.entry.$$"
  printf "%b\n" "$entry" > "$entry_file"
  awk -v d="$DATE" -v entry_file="$entry_file" '
    function print_entry(    line) {
      while ((getline line < entry_file) > 0) {
        print line
      }
      close(entry_file)
    }
    BEGIN { in_day=0; done=0 }
    {
      if (in_day == 1 && done == 0 && $0 ~ /^## [0-9]{4}-[0-9]{2}-[0-9]{2}$/) {
        print ""
        print_entry()
        print ""
        done=1
        in_day=0
      }
      print $0
      if ($0 == "## " d) {
        in_day=1
      }
    }
    END {
      if (done == 0) {
        print ""
        print_entry()
        print ""
      }
    }
  ' "$JOURNAL" > "$JOURNAL.tmp.$$"
  mv "$JOURNAL.tmp.$$" "$JOURNAL"
  rm -f "$entry_file"
else
  {
    printf "\n## %s\n\n" "$DATE"
    printf "%b\n" "$entry"
  } >> "$JOURNAL"
fi

echo "Added journal entry to: $JOURNAL"
