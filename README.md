<p align="center">
  <img src="assets/header.png" alt="Mnemo - A Memory System for AI Coding Agents" width="100%">
</p>

# Mnemo

Windows-first, token-safe **repo memory system** for Cursor (or any AI agent).

Mnemo is a PowerShell installer (`memory.ps1`) that scaffolds a structured memory layer under `.cursor/`, adds helper scripts for indexing/querying/linting, and optionally wires a pre-commit hook to keep the memory indexes up to date.

### What you get

- **Always-read layer**: `.cursor/memory/hot-rules.md`, `active-context.md`, `memo.md` (kept small + token-aware)
- **Atomic lessons**: `.cursor/memory/lessons/L-XXX-*.md` with strict YAML frontmatter + generated index
- **Monthly journal**: `.cursor/memory/journal/YYYY-MM.md` + generated digest + journal index
- **Cursor rule enforcement**: `.cursor/rules/00-memory-system.mdc` (alwaysApply)
- **Helper scripts**: `scripts/memory/*` (rebuild, lint, query, add-lesson, add-journal-entry, clear-active)
- **Optional SQLite FTS**: built if Python is available (`.cursor/memory/memory.sqlite`)
- **Portable git hook**: `.githooks/pre-commit` (and a best-effort `.git/hooks/pre-commit`) to auto-rebuild + lint

### Quickstart

From the repo root:

```powershell
# Install / scaffold memory system in this repo
powershell -ExecutionPolicy Bypass -File .\memory.ps1

# Optional: set a custom name used in memo/journal headers
powershell -ExecutionPolicy Bypass -File .\memory.ps1 -ProjectName "MyProject"

# Optional: overwrite previously generated files
powershell -ExecutionPolicy Bypass -File .\memory.ps1 -Force
```

After setup:

```powershell
# Build indexes + (optionally) SQLite index
powershell -ExecutionPolicy Bypass -File .\scripts\memory\rebuild-memory-index.ps1

# Validate memory health (frontmatter, tags, token budget, etc.)
powershell -ExecutionPolicy Bypass -File .\scripts\memory\lint-memory.ps1

# Enable portable hooks (recommended)
git config core.hooksPath .githooks
```

### Daily workflow (recommended)

- **At task start**: write the goal + files in focus into `.cursor/memory/active-context.md`
- **When you need context**: search first, then open only the matches:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\memory\query-memory.ps1 -Query "your term"
```

- **When done**:
  - add a journal entry
  - create a lesson if you discovered a repeatable pitfall
  - rebuild indexes
  - clear `active-context.md`

### Memory layout

Mnemo generates:

- **`.cursor/memory/index.md`**: entry point + “read order”
- **`.cursor/memory/hot-rules.md`**: tiny invariants (keep ~20 lines)
- **`.cursor/memory/active-context.md`**: session scratchpad (clear when done)
- **`.cursor/memory/memo.md`**: long-term “current truth” + ownership
- **`.cursor/memory/tag-vocabulary.md`**: canonical tag list used by the linter
- **`.cursor/memory/regression-checklist.md`**: lightweight “what to verify” checklist
- **`.cursor/memory/lessons/`**: atomic lessons + generated `index.md`
- **`.cursor/memory/journal/`**: monthly journal files `YYYY-MM.md`
- **`.cursor/memory/digests/`**: generated `YYYY-MM.digest.md` summaries
- **`.cursor/memory/adr/`**: architecture decision records (ADRs)
- **`.cursor/memory/templates/`**: templates for lessons, journal entries, ADRs
- **`.cursor/rules/00-memory-system.mdc`**: Cursor rule that enforces the retrieval workflow

### Helper scripts

All scripts live in `scripts/memory/`.

- **Rebuild indexes** (`rebuild-memory-index.ps1`)
  - Generates `lessons/index.md`, `lessons-index.json`, `journal-index.md`, `journal-index.json`, and monthly digests
  - If Python exists, also builds `.cursor/memory/memory.sqlite`

- **Lint memory** (`lint-memory.ps1`)
  - Validates lesson frontmatter + unique IDs
  - Ensures lesson tags exist in `tag-vocabulary.md`
  - Checks journal date headings don’t repeat within a month file
  - Checks “always-read layer” token budget

- **Query memory** (`query-memory.ps1`)
  - File-based search by default; optional SQLite FTS with `-UseSqlite`
  - Parameters:
    - `-Query "..."` (required)
    - `-Area All|HotRules|Active|Memo|Lessons|Journal|Digests`
    - `-Format Human|AI` (AI prints “Files to read” paths)
    - `-UseSqlite`

- **Add lesson** (`add-lesson.ps1`)
  - Creates a new `lessons/L-XXX-*.md` with the next available ID
  - Canonicalizes tags using `tag-vocabulary.md`

- **Add journal entry** (`add-journal-entry.ps1`)
  - Adds a bullet under `## YYYY-MM-DD` in the current month file (or creates it)
  - Ensures only one date heading per day (appends if it already exists)

- **Clear active context** (`clear-active.ps1`)
  - Resets `.cursor/memory/active-context.md` to the blank template

### Git hooks

Mnemo writes a pre-commit hook that:

- runs `rebuild-memory-index.ps1` and `lint-memory.ps1`
- stages the generated indexes/digests
- skips gracefully if PowerShell isn’t available

Enable the portable hook with:

```powershell
git config core.hooksPath .githooks
```

### Requirements

- **PowerShell**: Windows PowerShell 5.1+ or PowerShell 7 (`pwsh`)
- **Git**
- **Optional**: Python 3 for SQLite FTS index (`memory.sqlite`)

### License

See `LICENSE`.

