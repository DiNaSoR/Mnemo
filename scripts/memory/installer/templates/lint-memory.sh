#!/bin/sh
set -eu

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

  id="$(awk 'NR==1 && $0=="---"{frontmatter=1;next} frontmatter && $0=="---"{exit} frontmatter && $1=="id:"{print $2; exit}' "$lf" 2>/dev/null || true)"
  title="$(awk 'NR==1 && $0=="---"{frontmatter=1;next} frontmatter && $0=="---"{exit} frontmatter && $1=="title:"{$1=""; sub(/^ /,""); print; exit}' "$lf" 2>/dev/null || true)"
  status="$(awk 'NR==1 && $0=="---"{frontmatter=1;next} frontmatter && $0=="---"{exit} frontmatter && $1=="status:"{$1=""; sub(/^ /,""); print; exit}' "$lf" 2>/dev/null || true)"
  tags="$(awk 'NR==1 && $0=="---"{frontmatter=1;next} frontmatter && $0=="---"{exit} frontmatter && $1=="tags:"{$1=""; sub(/^ /,""); print; exit}' "$lf" 2>/dev/null || true)"
  introduced="$(awk 'NR==1 && $0=="---"{frontmatter=1;next} frontmatter && $0=="---"{exit} frontmatter && $1=="introduced:"{print $2; exit}' "$lf" 2>/dev/null || true)"
  rule="$(awk 'NR==1 && $0=="---"{frontmatter=1;next} frontmatter && $0=="---"{exit} frontmatter && $1=="rule:"{$1=""; sub(/^ /,""); print; exit}' "$lf" 2>/dev/null || true)"

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
