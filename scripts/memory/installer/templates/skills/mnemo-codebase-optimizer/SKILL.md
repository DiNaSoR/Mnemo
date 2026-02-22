---
name: mnemo-codebase-optimizer
description: Builds high-signal Mnemo memory quickly for any codebase by mapping architecture, ownership, workflows, risks, and commands, then writing optimized memo/hot-rules/active-context/lessons/journal entries and validating retrieval quality. Use when users ask to bootstrap Mnemo memory, optimize project context, or fill memory in a new or existing repository.
---

# Mnemo Codebase Optimizer

## Purpose

Use this skill to rapidly produce a detailed, reliable Mnemo knowledge base for any project.
The goal is high retrieval quality with low token waste.

## Quick Start

Use this checklist and keep one step `in_progress` at a time:

```text
Memory Seeding Progress
- [ ] 1) Confirm Mnemo install + paths
- [ ] 2) Map codebase architecture and ownership
- [ ] 3) Extract runbook commands and dev workflows
- [ ] 4) Write/update core memory files
- [ ] 5) Add initial lessons and journal summary
- [ ] 6) Rebuild + lint + (optional) vector sync
- [ ] 7) Validate retrieval quality and refine
```

## 1) Confirm Mnemo Install

Verify these paths exist:
- `.mnemo/memory/`
- `.mnemo/rules/`
- `scripts/memory/`

If missing, run installer first and stop this skill until setup succeeds.

## 2) Map Architecture Fast

Collect only high-value context:
- product purpose and core user flows
- entrypoints and runtime boundaries (frontend/backend/workers/CLI)
- module ownership and key responsibilities
- data model sources and contracts
- integration surfaces (APIs, queues, webhooks, external services)
- quality/security constraints and release workflow

Avoid copying large code blocks into memory files. Summarize and reference paths.

## 3) Capture Operational Workflow

Record:
- install/build/test/lint commands
- local run commands for each app/service
- deployment/release commands and prerequisites
- debugging commands and common failure signatures

Prefer explicit command examples over vague prose.

## 4) Write Core Memory Files

Update these files in priority order:

1. `.mnemo/memory/hot-rules.md`
   - 10-20 lines max
   - only hard invariants and "never do" rules
2. `.mnemo/memory/memo.md`
   - architecture map, ownership, critical paths, runbook
3. `.mnemo/memory/active-context.md`
   - current migration task + open risks + next actions

Use short sections and bullets. Keep each bullet atomic and testable.

## 5) Seed Lessons + Journal

Create 3-8 starter lessons from known pitfalls:
- naming conventions
- data migration gotchas
- environment/setup traps
- release regressions and prevention checks

Add one monthly journal entry summarizing:
- what memory was seeded
- why those sections matter
- what remains unknown

## 6) Rebuild and Validate

Run:
- `scripts/memory/rebuild-memory-index.ps1` (or shell equivalent)
- `scripts/memory/lint-memory.ps1` (or shell equivalent)

If vector mode is enabled:
- run `vector_sync`
- run `vector_health`

## 7) Retrieval Quality Gate

Ask 5-10 realistic queries and verify results:
- architecture query (module boundaries)
- workflow query (how to run/test/release)
- ownership query (who owns what)
- pitfall query (common mistakes)
- troubleshooting query (known failure/fix)

If retrieval misses:
- tighten memo headings
- split overloaded bullets
- add a lesson instead of bloating memo
- prune low-signal historical text

## Memory Quality Rules

- Keep `hot-rules.md` tiny and immutable-focused.
- Keep `memo.md` as current truth, not raw history.
- Put historical detail in journal, not memo.
- Prefer lessons for reusable error-prevention patterns.
- Use stable terminology for search consistency.
- Every important claim should map to concrete file paths or commands.

## Output Contract

When done, return:

1. **Coverage summary**
   - what domains are now represented in memory
2. **Files changed**
   - list of memory files updated/created
3. **Quality checks**
   - rebuild/lint/vector status
4. **Top retrieval queries**
   - sample queries and expected hit files
5. **Remaining unknowns**
   - explicit gaps to fill in next pass

## Additional Resources

- Detailed templates: [reference.md](reference.md)
