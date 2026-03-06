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

detect_python_cmd() {
  if command -v python3 >/dev/null 2>&1; then
    printf "%s" "python3"
  elif command -v python >/dev/null 2>&1; then
    printf "%s" "python"
  else
    printf ""
  fi
}

MEM="$(resolve_memory_dir)"
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
    BEGIN{ frontmatter=0; cur=""; id=""; title=""; status=""; introduced=""; tags=""; rule=""; applies="" }
    NR==1 && $0=="---"{frontmatter=1; next}
    frontmatter==1 && $0=="---"{frontmatter=0; next}
    frontmatter==1{
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
  printf '%s | %s | %s | %s | `%s`\n' "$id" "$tagText" "$appliesText" "$rule" "$file" >>"$out_md"
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
    echo "Token-cheap summary. See \`journal/$base\` in the memory root for details."
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

# Optional: build SQLite index if python/python3 exists
PYTHON_CMD="$(detect_python_cmd)"
if [ -n "$PYTHON_CMD" ] && [ -f "$ROOT/scripts/memory/build-memory-sqlite.py" ]; then
  echo "$PYTHON_CMD detected; building SQLite FTS index..."
  "$PYTHON_CMD" "$ROOT/scripts/memory/build-memory-sqlite.py" --repo "$ROOT" || true
else
  echo "Python not found; skipping SQLite build."
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
