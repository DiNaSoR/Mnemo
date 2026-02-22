<p align="center">
  <img src="assets/header.png" alt="Mnemo - A Memory System for AI Coding Agents" width="100%">
</p>

# Mnemo 🧠

[![CI](https://github.com/DiNaSoR/Mnemo/actions/workflows/ci.yml/badge.svg)](https://github.com/DiNaSoR/Mnemo/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/github/license/DiNaSoR/Mnemo)](LICENSE)

> Token-safe repo memory for AI coding agents, with an autonomous runtime and optional semantic recall.
>
> ✅ Works with Cursor • Claude Code • Gemini Antigravity • OpenAI Codex • Windsurf • and more

Mnemo scaffolds a structured memory layer under `.mnemo/` (canonical) and keeps permanent compatibility bridges for `.cursor/` and `.agent/`.

## ✨ Why Mnemo

- 🧭 **Predictable retrieval order** so agents read high-signal memory first
- 🧱 **Atomic lessons + indexed journal** for durable project knowledge
- 🛡️ **Quality guardrails** (lint, token budget checks, CI benchmarks)
- ⚙️ **Autonomous mode** with vector sync and lifecycle tracking
- 🔌 **MCP tools** for semantic recall in Cursor when vector mode is enabled

## 🚀 Install Mnemo (once per project)

Run from the **target project root**.

### Any OS (npx, recommended)

```sh
# Interactive wizard — guides you through every option (recommended)
npx @dinasor/mnemo-cli@latest
```

The wizard will ask you:

1. **Vector mode** — enable semantic / embedding-based memory recall?
2. **Provider** — Gemini (`GEMINI_API_KEY`) or OpenAI (`OPENAI_API_KEY`)?
3. **API key** — enter now (saved to `.env`), already in `.env`, or skip.

It then runs a live dependency check (Node · Git · Python · pip · packages) and launches the installer.

```sh
# Non-interactive (CI / scripting) — skip wizard, use flags directly
npx @dinasor/mnemo-cli@latest --yes
npx @dinasor/mnemo-cli@latest --enable-vector --vector-provider gemini --yes
npx @dinasor/mnemo-cli@latest --dry-run
npx @dinasor/mnemo-cli@latest --force
```

### Windows (PowerShell)

```powershell
# Standard install
powershell -ExecutionPolicy Bypass -File .\memory.ps1

# With vector mode (OpenAI default)
powershell -ExecutionPolicy Bypass -File .\memory.ps1 -EnableVector

# With vector mode (Gemini embeddings)
powershell -ExecutionPolicy Bypass -File .\memory.ps1 -EnableVector -VectorProvider gemini
```

### macOS / Linux (POSIX shell)

```sh
# Standard install
sh ./memory_mac.sh

# With vector mode (OpenAI default)
sh ./memory_mac.sh --enable-vector

# With vector mode (Gemini embeddings)
sh ./memory_mac.sh --enable-vector --vector-provider gemini
```

### Post-install sanity check

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\memory\rebuild-memory-index.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\memory\lint-memory.ps1
```

If vector mode is enabled, restart your IDE once and run:

```text
vector_health
vector_sync
```

---

## 🧠 Seeding memory for an existing codebase

After installing Mnemo in a project that already has code, use the bundled
`mnemo-codebase-optimizer` skill to fill memory quickly and accurately.

**In Cursor (or any agent that loads `.cursor/skills/`):**

1. Open the project.
2. Start a new conversation and say:

   > Use the **mnemo-codebase-optimizer** skill to seed memory for this codebase.

   Or load the skill directly:

   ```text
   @.cursor/skills/mnemo-codebase-optimizer/SKILL.md
   ```

3. The agent will map architecture, ownership, dev workflows, risks, commands,
   and write optimized `memo.md`, `hot-rules.md`, `active-context.md`, lessons,
   and a journal summary — then validate retrieval quality.

The skill is installed automatically by `memory.ps1` / `memory_mac.sh` and lives at:

```text
.cursor/skills/mnemo-codebase-optimizer/
  SKILL.md        ← skill prompt + checklist
  reference.md    ← memory file templates + retrieval queries
```

---

## 🧩 IDE setup guide (per project)

Use the section that matches your IDE. Each project should run Mnemo install once.

| IDE / Agent | What installer creates | What you do next |
|---|---|---|
| Cursor | `.mnemo/rules/cursor/00-memory-system.mdc` (+ `.mnemo/mcp/cursor.mcp.json`, bridged to `.cursor/mcp.json`) | Restart Cursor, run `vector_health`, then `vector_sync` |
| Claude Code | `.mnemo/memory/` knowledge base (also visible via `.cursor/memory`) | Open repo in Claude Code and follow retrieval order from `.mnemo/memory/index.md` |
| Gemini Antigravity | `.agent/rules/00-memory-system.md` (+ `.agent/rules/01-vector-search.md` in vector mode) | Ensure Antigravity loads project rules from `.agent/rules/` |
| OpenAI Codex | `.mnemo/memory/` knowledge base (also visible via `.cursor/memory`) | Start Codex from repo root and follow retrieval order from `.mnemo/memory/index.md` |
| Windsurf / Other IDEs | `.mnemo/memory/` knowledge base (also visible at `.cursor/memory/`) | Point memory/context path to `.mnemo/memory/` |

### 1) Cursor IDE 🟦

1. Run installer in your project (`memory.ps1` or `memory_mac.sh`).
2. For semantic tools, enable vector mode during install.
3. Confirm `.mnemo/mcp/cursor.mcp.json` exists (and `.cursor/mcp.json` bridge is present).
4. Restart Cursor.
5. Run `vector_health` then `vector_sync`.

You should see MCP tools:
`vector_search`, `vector_sync`, `vector_forget`, `vector_health`, `memory_status`.

### 2) Claude Code 🤝

1. Run Mnemo install in your project root.
2. Confirm `.mnemo/memory/` exists (and `.cursor/memory/` bridge is present).
3. Start Claude Code from the project root.
4. Follow retrieval order from `.mnemo/memory/index.md`.

### 3) Gemini Antigravity 🔷

1. Run Mnemo install in your project root.
2. Confirm `.agent/rules/00-memory-system.md` exists.
3. Ensure your Antigravity setup loads `.agent/rules/`.
4. (Optional) Enable vector mode for semantic memory workflows.

### 4) OpenAI Codex 🧪

1. Run Mnemo install in your project root.
2. Confirm `.mnemo/memory/` exists (and `.cursor/memory/` bridge is present).
3. Launch Codex from the same project root.
4. Follow retrieval order from `.mnemo/memory/index.md`.

### 5) Windsurf / Other IDEs 🌊

1. Run Mnemo install in your project root.
2. Point your IDE's memory/context config to `.mnemo/memory/` (or `.cursor/memory/` bridge).
3. Reuse the same retrieval order:
   `hot-rules.md` → `active-context.md` → `memo.md` → indexed lessons/digests.

---

## 🧠 What Mnemo gives you

- **Always-read layer**: `.mnemo/memory/hot-rules.md`, `active-context.md`, `memo.md`
- **Atomic lessons**: `.mnemo/memory/lessons/L-XXX-*.md` + generated lesson index
- **Monthly journal + digests**: `.mnemo/memory/journal/YYYY-MM.md` + `.mnemo/memory/digests/*.digest.md`
- **Rule enforcement**: `.mnemo/rules/cursor/00-memory-system.mdc` and `.mnemo/rules/agent/00-memory-system.md` (bridged to `.cursor/rules/` and `.agent/rules/`)
- **Project skill bootstrap**: `.cursor/skills/mnemo-codebase-optimizer/{SKILL.md,reference.md}` for fast codebase-to-memory optimization workflows
- **Helper scripts**: `scripts/memory/*` (rebuild, lint, query, add-lesson, add-journal-entry, clear-active)
- **Optional SQLite FTS**: `.mnemo/memory/memory.sqlite` when Python is available
- **Optional vector layer**: `scripts/memory/mnemo_vector.py` + MCP tools
- **Optional autonomous runtime**: `scripts/memory/autonomy/*` (vector mode)

## 🤖 Autonomous mode (no human in the loop)

When installed with vector mode (`-EnableVector` / `--enable-vector`), Mnemo can run autonomously:

| Component | Purpose |
|---|---|
| `autonomy/runner.py` | Orchestrates detect → ingest → lifecycle → journal delta |
| `autonomy/ingest_pipeline.py` | Classifies/ingests changed memory content |
| `autonomy/lifecycle_engine.py` | Fact ADD / UPDATE / DEPRECATE / NOOP with audit trail |
| `autonomy/entity_resolver.py` | Stable entity IDs + alias mapping |
| `autonomy/retrieval_router.py` | Intent routing to memory categories |
| `autonomy/reranker.py` | Score fusion (semantic + authority + temporal + entity) |
| `autonomy/context_safety.py` | Dedup, contradiction checks, token budget guard |
| `autonomy/vault_policy.py` | Redaction/sensitivity policy enforcement |
| `autonomy/policies.yaml` | Benchmark + safety thresholds |

Runner triggers:
- `post-commit` hook
- `post-merge` / `post-checkout` hooks
- `python runner.py --mode schedule`
- `python runner.py --mode once`

## 🗂️ Generated layout

```text
.mnemo/
  memory/
    hot-rules.md
    active-context.md
    memo.md
    lessons/
    journal/
    digests/
    adr/
    templates/
  rules/
    cursor/
      00-memory-system.mdc
      01-vector-search.mdc   # vector mode only
    agent/
      00-memory-system.md
      01-vector-search.md    # vector mode only
  mcp/
    cursor.mcp.json          # vector mode only

.cursor/                     # permanent compatibility bridge
  memory/
  rules/
  skills/
    mnemo-codebase-optimizer/
      SKILL.md
      reference.md
  mcp.json                  # bridge to .mnemo/mcp/cursor.mcp.json

.agent/                     # permanent compatibility bridge
  rules/

scripts/
  memory/
    rebuild-memory-index.ps1
    lint-memory.ps1
    query-memory.ps1
    add-lesson.ps1
    add-journal-entry.ps1
    clear-active.ps1
    mnemo_vector.py        # vector mode only
    autonomy/              # vector mode only
```

## 🛠️ Helper scripts (quick reference)

| Script | What it does |
|---|---|
| `rebuild-memory-index.ps1` | Rebuilds lesson/journal indexes and digests |
| `lint-memory.ps1` | Validates frontmatter, tags, date headers, token budget |
| `query-memory.ps1` | Searches memory via file search or SQLite FTS (`-UseSqlite`) |
| `add-lesson.ps1` | Creates next `L-XXX` lesson with normalized tags |
| `add-journal-entry.ps1` | Adds entry under current date in monthly journal |
| `clear-active.ps1` | Resets `active-context.md` |
| `mnemo_vector.py` | Vector MCP server + CLI (`sync`, `search`, `forget`, `health`, `status`) in vector mode |

## 🔐 Git hooks and API keys

Mnemo auto-configures `core.hooksPath` to `.githooks` and installs:

- `pre-commit`: rebuild + lint memory
- `post-commit` (vector mode): non-blocking `vector_sync` with lock protection

Important:
- Cursor MCP tools read API keys from `.mnemo/mcp/cursor.mcp.json` env placeholders (`.cursor/mcp.json` stays bridged).
- Git hooks read API keys from your shell environment.
- If `GEMINI_API_KEY` is not already in the environment, `scripts/memory/mnemo_vector.py` also tries loading keys from project-root `.env`.

```sh
# bash/zsh example
export OPENAI_API_KEY="sk-..."
# or
export GEMINI_API_KEY="..."

# optional direct CLI usage (outside MCP tool calls)
python3 scripts/memory/mnemo_vector.py sync
python3 scripts/memory/mnemo_vector.py health
```

## ✅ Recommended daily workflow

1. Update `.mnemo/memory/active-context.md` at task start.
2. Search first (`query-memory.ps1`) before opening many files.
3. Use `vector_search` when keyword lookup misses.
4. At finish: add journal entry, add lesson if needed, rebuild, clear active context.

## 📋 Requirements

- **Node.js 18+** (for `npx @dinasor/mnemo-cli@latest`)
- **PowerShell**: Windows PowerShell 5.1+ or PowerShell 7 (`pwsh`)
- **Git**
- **Optional**: Python 3 for SQLite FTS index
- **Optional (vector mode)**:
  - Python 3.10+
  - API key: `OPENAI_API_KEY` or `GEMINI_API_KEY`
  - Auto-installed deps: `openai`, `sqlite-vec`, `mcp[cli]>=1.2.0,<2.0` (+ `google-genai` for Gemini)

> The interactive wizard (`npx @dinasor/mnemo-cli@latest`) checks all of these
> before running the installer and reports which packages are already installed.

## 🤝 Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Bug reports and feature requests use the issue templates in [.github/ISSUE_TEMPLATE/](.github/ISSUE_TEMPLATE/). Security issues go to [SECURITY.md](SECURITY.md).

## 📄 License

See [LICENSE](LICENSE).
