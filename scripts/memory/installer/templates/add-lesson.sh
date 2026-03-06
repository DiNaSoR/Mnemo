#!/bin/sh
set -eu

TITLE=""
TAGS=""
RULE=""
APPLIES_TO="*"

while [ $# -gt 0 ]; do
  case "$1" in
    --title) TITLE="$2"; shift 2 ;;
    --tags) TAGS="$2"; shift 2 ;;
    --rule) RULE="$2"; shift 2 ;;
    --applies-to) APPLIES_TO="$2"; shift 2 ;;
    -h|--help)
      echo "Usage: sh ./scripts/memory/add-lesson.sh --title \"...\" --tags \"Reliability,Data\" --rule \"...\" [--applies-to \"*\"]"
      exit 0
      ;;
    *)
      echo "Unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

if [ -z "$TITLE" ] || [ -z "$TAGS" ] || [ -z "$RULE" ]; then
  echo "Missing --title/--tags/--rule" >&2
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
LESSONS="$MEM/lessons"
TAG_VOCAB="$MEM/tag-vocabulary.md"
mkdir -p "$LESSONS"

max=0
for lesson_file in "$LESSONS"/L-*.md; do
  [ -e "$lesson_file" ] || continue
  file_name="$(basename "$lesson_file")"
  number="$(printf "%s" "$file_name" | sed -n 's/^L-\([0-9][0-9][0-9]\).*/\1/p')"
  [ -n "$number" ] && [ "$number" -gt "$max" ] && max="$number"
done

next=$((max + 1))
ID="$(printf "L-%03d" "$next")"
kebab="$(printf "%s" "$TITLE" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//;')"
[ -z "$kebab" ] && kebab="lesson"
kebab="$(printf "%s" "$kebab" | cut -c1-50)"
FILE_PATH="$LESSONS/${ID}-${kebab}.md"
TODAY="$(date +%Y-%m-%d)"
MONTH_ID="$(printf "%s" "$TODAY" | cut -c1-7)"

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

tags_out=""
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
  if printf ",%s," "$tags_out" | grep -Fqi ",$canon,"; then
    continue
  fi
  if [ -z "$tags_out" ]; then
    tags_out="$canon"
  else
    tags_out="$tags_out, $canon"
  fi
done

if [ -z "$tags_out" ]; then
  echo "No valid tags provided." >&2
  exit 1
fi

cat > "$FILE_PATH" <<EOF2
---
id: $ID
title: $TITLE
status: Active
tags: [$tags_out]
introduced: $TODAY
applies_to:
  - $APPLIES_TO
triggers:
  - TODO: add error messages or keywords
rule: $RULE
---

# $ID - $TITLE

## Symptom

TODO: Describe what happened

## Root Cause

TODO: Describe why it happened

## Wrong Approach (DO NOT REPEAT)

- TODO: What not to do

## Correct Approach

- TODO: What to do instead

## References

- Files: \`TODO\`
- Journal: \`journal/$MONTH_ID.md#$TODAY\`
EOF2

echo "Created lesson: $FILE_PATH"
echo "  ID: $ID"
echo "  Title: $TITLE"
echo "  Tags: [$tags_out]"
echo ""
echo "Next: run scripts/memory/rebuild-memory-index.sh"
