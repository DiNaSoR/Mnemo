---
name: mnemo-codebase-optimizer
description: Seeds high-signal Mnemo memory for any codebase — maps architecture, ownership, workflows, risks, and commands, then writes optimized memo/hot-rules/active-context/lessons/journal and validates retrieval quality. Use when a user installs Mnemo on a new or existing repo and needs to initialize memory.
---

# Mnemo Codebase Optimizer

## Purpose

Fresh Mnemo installs create the directory structure but leave all memory files empty.
This skill rapidly fills them with high-signal, retrieval-optimized content so the AI agent can start working effectively immediately.

**When to use:** right after `npx @dinasor/mnemo-cli@latest` completes on a project.

## Quick Start

Keep one step `in_progress` at a time:

```text
Memory Seeding Progress
- [ ] 1) Confirm Mnemo install + understand paths
- [ ] 2) Scan codebase — architecture, ownership, boundaries
- [ ] 3) Extract runbook commands + dev workflows
- [ ] 4) Write core memory files (hot-rules → memo → active-context)
- [ ] 5) Seed starter lessons + initial journal entry
- [ ] 6) Rebuild indexes + lint + optional vector sync
- [ ] 7) Validate retrieval quality and refine
- [ ] 8) Clear active-context (seeding is done)
```

## 1) Confirm Mnemo Install

Verify these paths exist:

| Path | Purpose |
|---|---|
| `.mnemo/memory/` | Canonical memory store |
| `.mnemo/rules/cursor/` | Cursor IDE rules |
| `.mnemo/rules/agent/` | Agent rules (Antigravity, Codex, etc.) |
| `.cursor/memory/` | Bridge → `.mnemo/memory/` |
| `.cursor/rules/` | Bridge → `.mnemo/rules/cursor/` |
| `.agent/rules/` | Bridge → `.mnemo/rules/agent/` |
| `scripts/memory/` | Helper scripts |

Also read:
- `.mnemo/memory/tag-vocabulary.md` — use these tags for lessons (don't invent new ones)
- `.mnemo/memory/regression-checklist.md` — reference this for quality gates
- `.mnemo/memory/templates/lesson.template.md` — use this exact format for lessons

If any of these are missing, run `npx @dinasor/mnemo-cli@latest` first and stop this skill.

> **Important:** Always edit files in `.mnemo/memory/` (canonical path). The `.cursor/memory/` bridge mirrors automatically.

## 2) Scan Codebase — Architecture Fast

Collect only high-value context (do NOT paste large code blocks):

- **Product purpose** — what this project does and for whom
- **Entrypoints** — main entry files, runtime boundaries (frontend/backend/workers/CLI)
- **Module ownership** — key directories and their responsibilities
- **Data model** — primary schemas, contracts, database structure
- **Integration surfaces** — APIs, queues, webhooks, external services
- **Tech stack** — languages, frameworks, major dependencies
- **Quality/security constraints** — required checks, compliance rules

Summarize. Reference file paths instead of copying code.

## 3) Capture Operational Workflow

Record **explicit commands** (not vague prose):

- Install/setup: `npm install`, `pip install -r requirements.txt`, etc.
- Dev run: `npm run dev`, `python manage.py runserver`, etc.
- Test: `npm test`, `pytest`, etc.
- Lint/format: `npm run lint`, `eslint .`, etc.
- Build/release: `npm run build`, `docker build`, etc.
- Debugging: common failure signatures and their fixes

## 4) Write Core Memory Files

Update in this exact priority order:

### 4a) `.mnemo/memory/hot-rules.md` (10-20 lines MAX)

Only hard invariants, "never do" rules, and the authority order. Keep it tiny — this is read on EVERY interaction.

```markdown
# Hot Rules

## Authority Order
1) Lessons override EVERYTHING
2) active-context overrides memo/journal (but NOT lessons)
3) memo.md is long-term truth
4) Journal is history

## Project Invariants
- Never bypass <critical check>
- Always run <required command> before release
- <generated file> is auto-generated — do not edit manually
```

### 4b) `.mnemo/memory/memo.md` (the meat — current truth)

Use the detailed template from [reference.md](reference.md). Must cover:
- Mission (1 paragraph)
- System shape (components + boundaries)
- Ownership map (path → responsibility)
- Critical flows (trigger → path → side effects → failure modes)
- Commands runbook (copy-paste ready)
- Constraints and known risks

### 4c) `.mnemo/memory/active-context.md` (session scratchpad)

Fill with the current seeding task status:

```markdown
## Current Goal
- Seeding Mnemo memory for this codebase

## Files in Focus
- .mnemo/memory/memo.md
- .mnemo/memory/hot-rules.md

## Findings / Decisions
- <key architectural findings>

## Blockers
- <remaining unknowns>
```

## 5) Seed Lessons + Journal

### Lessons (3-8 starter lessons)

Use **exactly** the template from `.mnemo/memory/templates/lesson.template.md`:

```yaml
---
id: L-001
title: "Short descriptive title"
status: Active
tags: [Build, Reliability]        # ← use tags from tag-vocabulary.md only
introduced: 2026-03-05
applies_to:
  - "path/or/glob/**"
triggers:
  - "error keyword or symptom"
rule: "One sentence. Imperative. Testable."
supersedes: ""
---
```

Common starter lessons to extract:
- Setup/environment traps
- Naming conventions that bite newcomers
- Data migration or schema gotchas
- Release regressions and prevention checks
- Build/dependency pitfalls

### Journal (one initial entry)

Write to `.mnemo/memory/journal/YYYY-MM.md`:

```markdown
## YYYY-MM-DD

- [Process] Seeded Mnemo memory for <project>
  - Why: AI agents need high-signal context to work effectively
  - Key files: memo.md, hot-rules.md, L-001 through L-XXX
  - Coverage: architecture, ownership, runbook, N known pitfalls
  - Gaps: <what remains unknown>
```

## 6) Rebuild and Validate

Run these commands in order:

```sh
# Rebuild indexes
scripts/memory/rebuild-memory-index.sh    # macOS/Linux
scripts/memory/rebuild-memory-index.ps1   # Windows

# Lint memory files
scripts/memory/lint-memory.sh             # macOS/Linux
scripts/memory/lint-memory.ps1            # Windows
```

If vector mode is enabled, also run:
```
vector_sync      # rebuild the vector index
vector_health    # verify index is healthy
```

Fix any lint errors before proceeding.

## 7) Retrieval Quality Gate

Test with 5-10 real queries and verify they return the right files:

| Query | Expected hit |
|---|---|
| "What are the core runtime boundaries?" | memo.md (System Shape) |
| "How do I run tests and lint?" | memo.md (Commands Runbook) |
| "Who owns `<critical module>`?" | memo.md (Ownership Map) |
| "What regressions happened before?" | lessons/L-XXX-*.md |
| "What are the top risks?" | memo.md (Known Risks) |
| "How do I deploy/release?" | memo.md (Commands Runbook) |

If using vector mode, test with:
```
vector_search "how to run tests"
vector_search "what are the known pitfalls"
```

### If retrieval misses:
- Tighten memo headings (make them search-friendly)
- Split overloaded bullets into separate lines
- Add a lesson instead of bloating memo
- Prune low-signal historical text
- Use consistent terminology from tag-vocabulary.md

## 8) Clear Active Context

Seeding is done. Reset active-context so the agent starts fresh:

```markdown
# Active Context (Session Scratchpad)

## Current Goal
-

## Files in Focus
-

## Findings / Decisions
-

## Temporary Constraints
-

## Blockers
-
```

## Memory Quality Rules

- `hot-rules.md` — tiny, immutable-focused, read every time
- `memo.md` — current truth, not raw history
- `journal/` — chronological history, low priority
- `lessons/` — reusable error-prevention patterns
- Use tags from `tag-vocabulary.md` only (don't invent new ones)
- Every claim should reference concrete file paths or commands
- Prefer short headings over long paragraphs

## Output Contract

When done, return:

1. **Coverage summary** — what domains are now in memory
2. **Files changed** — list of memory files created/updated
3. **Quality checks** — rebuild + lint status (PASS/FAIL)
4. **Sample queries** — 3-5 queries and their expected results
5. **Remaining gaps** — explicit unknowns to fill in a future pass

## Additional Resources

- Detailed memo/lesson/query templates: [reference.md](reference.md)
