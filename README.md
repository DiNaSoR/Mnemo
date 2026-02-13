<p align="center">
  <img src="assets/header.png" alt="Mnemo - A Memory System for AI Coding Agents" width="100%">
</p>

# Mnemo

Windows-first, token-safe **repo memory system** for AI coding agents.

> **Works with:** Cursor • Claude Code • Gemini Antigravity • OpenAI Codex • Windsurf • and more

Mnemo scaffolds a structured memory layer under `.cursor/` as the single source of truth. Other agents can be configured to read from this same directory—no duplication needed.

### What you get

- **Always-read layer**: `.cursor/memory/hot-rules.md`, `active-context.md`, `memo.md` (kept small + token-aware)
- **Atomic lessons**: `.cursor/memory/lessons/L-XXX-*.md` with strict YAML frontmatter + generated index
- **Monthly journal**: `.cursor/memory/journal/YYYY-MM.md` + generated digest + journal index
- **Agent rule enforcement**: `.cursor/rules/00-memory-system.mdc` (Cursor-native, adaptable for others)
- **Helper scripts**: `scripts/memory/*` (rebuild, lint, query, add-lesson, add-journal-entry, clear-active)
- **Optional SQLite FTS**: built if Python is available (`.cursor/memory/memory.sqlite`)
- **Portable git hook**: `.githooks/pre-commit` to auto-rebuild + lint
- **Optional vector semantic layer**: enable via installer flag to generate `scripts/memory/mnemo_vector.py` + Cursor tools (`vector_search`, `vector_sync`, `vector_forget`, `vector_health`)
- **Optional vector rule + hook**: `.cursor/rules/01-vector-search.mdc` and `.githooks/post-commit` (only when vector mode is enabled)

### Quickstart

From the repo root:

```powershell
# Install / scaffold memory system in this repo
powershell -ExecutionPolicy Bypass -File .\memory.ps1

# Optional: set a custom name used in memo/journal headers
powershell -ExecutionPolicy Bypass -File .\memory.ps1 -ProjectName "MyProject"

# Optional: overwrite previously generated files
powershell -ExecutionPolicy Bypass -File .\memory.ps1 -Force

# Optional: enable semantic vector layer (OpenAI default)
powershell -ExecutionPolicy Bypass -File .\memory.ps1 -EnableVector

# Optional: enable semantic vector layer with Gemini embeddings
powershell -ExecutionPolicy Bypass -File .\memory.ps1 -EnableVector -VectorProvider gemini
```

macOS / POSIX shell:

```sh
sh ./memory_mac.sh
sh ./memory_mac.sh --enable-vector
sh ./memory_mac.sh --enable-vector --vector-provider gemini
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

If vector mode is enabled, run once after restart:

```text
vector_health
vector_sync
```

### Daily workflow (recommended)

- **At task start**: write the goal + files in focus into `.cursor/memory/active-context.md`
- **When you need context**: search first, then open only the matches:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\memory\query-memory.ps1 -Query "your term"
```

- **When keywords fail** (vector mode enabled): run semantic recall with `vector_search`.

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

- **Vector engine** (`mnemo_vector.py`) - optional
  - Generated only when vector mode is enabled at install time
  - Exposes MCP tools: `vector_search`, `vector_sync`, `vector_forget`, `vector_health`
  - Uses cosine similarity over markdown chunks from `.cursor/memory/`

### Git hooks

Mnemo writes a pre-commit hook that:

- runs `rebuild-memory-index.ps1` and `lint-memory.ps1`
- stages the generated indexes/digests
- skips gracefully if PowerShell isn’t available

If vector mode is enabled, Mnemo also writes a post-commit hook that:

- runs `vector_sync` non-blocking with a lock directory to avoid overlap
- skips safely when API keys are missing
- preserves existing post-commit behavior via a backup chain

Enable the portable hook with:

```powershell
git config core.hooksPath .githooks
```

Important: Cursor MCP tools read API keys from `.cursor/mcp.json` env placeholders, but git hooks read shell environment variables.  
Export keys in your shell profile if you want post-commit vector auto-sync:

```sh
# bash/zsh examples
export OPENAI_API_KEY="sk-..."
# or
export GEMINI_API_KEY="..."
```

### Multi-Agent Support

Mnemo uses `.cursor/` as the canonical memory directory. Here's how to configure other agents to use it:

#### Claude Code

Add to your `CLAUDE.md` at repo root:

```markdown
# Project Memory

This project uses Mnemo for structured AI memory.

## Read Order (ALWAYS)
1. `.cursor/memory/hot-rules.md` - invariants
2. `.cursor/memory/active-context.md` - current session
3. `.cursor/memory/memo.md` - project truth

## Search First, Then Fetch
- `.cursor/memory/lessons/index.md` → find lesson ID → open specific lesson
- `.cursor/memory/digests/YYYY-MM.digest.md` → before raw journal
```

#### Gemini Antigravity

Create `.agent/rules/memory-system.md`:

```markdown
---
description: Mnemo memory system integration
---

## Memory Location
Read project memory from `.cursor/memory/`:
- `hot-rules.md` - tiny invariants (read first)
- `active-context.md` - current session state
- `memo.md` - project truth + ownership
- `lessons/index.md` - searchable lesson index
- `digests/*.digest.md` - monthly summaries
```

#### OpenAI Codex

Add to your root `AGENTS.md`:

```markdown
# Memory System

This project uses Mnemo. Memory lives in `.cursor/memory/`.

## Retrieval Order
1. Read `.cursor/memory/hot-rules.md` first (tiny, <20 lines)
2. Read `.cursor/memory/active-context.md` for current session
3. Read `.cursor/memory/memo.md` for project truth
4. Search `.cursor/memory/lessons/index.md` before creating new patterns
5. Check `.cursor/memory/digests/` before raw journal archaeology
```

#### Windsurf / Others

Point your agent's memory/context configuration to `.cursor/memory/`. The markdown files are agent-agnostic—only `.cursor/rules/*.mdc` is Cursor-specific.

### Requirements

- **PowerShell**: Windows PowerShell 5.1+ or PowerShell 7 (`pwsh`)
- **Git**
- **Optional**: Python 3 for SQLite FTS index (`memory.sqlite`)
- **Optional (vector mode)**:
  - Python 3.10+
  - API key (`OPENAI_API_KEY` or `GEMINI_API_KEY`)
  - Installer auto-installs: `openai`, `sqlite-vec`, `mcp[cli]>=1.2.0,<2.0` (+ `google-genai` for Gemini)

### License

See `LICENSE`.
