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
