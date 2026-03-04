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
