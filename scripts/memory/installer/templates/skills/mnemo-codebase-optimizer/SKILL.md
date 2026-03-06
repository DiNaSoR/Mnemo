---
name: mnemo-codebase-optimizer
description: Optional post-install Mnemo skill that scans the current repository, fills `.mnemo/memory/*` with high-signal project context, and validates that future retrieval will work.
---

# Mnemo Codebase Optimizer

## Purpose

Use this skill after Mnemo is installed in a repository when you want the agent to seed Mnemo with project-specific context.
It should gather facts about the current codebase, write clean memory files under `.mnemo/memory/`, run the Mnemo helper scripts, and leave the repo with retrievable project knowledge.

## Do Not Use This Skill When

- You want to keep Mnemo empty and seed memory manually.
- The repository is still too incomplete to describe meaningfully.
- Mnemo is not installed yet.

## Success Criteria

The skill is done only when all of the following are true:

1. `.mnemo/memory/hot-rules.md`, `memo.md`, and `active-context.md` reflect the current repository.
2. Starter lessons and one journal entry exist if meaningful project facts were discovered.
3. `scripts/memory/rebuild-memory-index.*` and `scripts/memory/lint-memory.*` were run successfully.
4. Retrieval checks were performed and obvious misses were corrected.
5. `active-context.md` is cleared before finishing.

## Confirm Mnemo Install First

Verify these paths exist before writing anything:

| Path | Purpose |
|---|---|
| `.mnemo/memory/` | Canonical Mnemo memory store |
| `.mnemo/rules/cursor/` | Cursor rule source |
| `.mnemo/rules/agent/` | Agent rule source |
| `.cursor/memory/` | Bridge to `.mnemo/memory/` |
| `.cursor/rules/` | Bridge to `.mnemo/rules/cursor/` |
| `.agent/rules/` | Bridge to `.mnemo/rules/agent/` |
| `scripts/memory/` | Mnemo helper scripts |

If they are missing, stop and tell the user to install Mnemo first.

> Always edit `.mnemo/memory/*` directly. Treat `.cursor/memory/*` as a bridge, not the source of truth.

## Execution Order

Keep one step `in_progress` at a time:

```text
Memory Seeding Progress
- [ ] 1) Confirm Mnemo install and current repo shape
- [ ] 2) Scan architecture, entrypoints, ownership, and workflows
- [ ] 3) Capture concrete runbook commands
- [ ] 4) Write hot-rules.md, memo.md, and active-context.md
- [ ] 5) Seed starter lessons and one journal entry if warranted
- [ ] 6) Rebuild indexes, lint memory, and optionally run vector checks
- [ ] 7) Run retrieval checks and tighten weak sections
- [ ] 8) Clear active-context.md and report results
```

## What to Collect

Collect only high-signal repository truth:

- project purpose and primary user outcomes
- runtime entrypoints and module boundaries
- ownership map by directory or subsystem
- data contracts, schemas, or API surfaces
- build, test, lint, release, and debugging commands
- major constraints, invariants, and known risks
- setup pitfalls and repeated failure patterns worth turning into lessons

Do not paste large code blocks into memory files. Summarize and reference file paths.

## What to Write

### `hot-rules.md`

Keep it short. Only include:

- memory authority order
- hard project invariants
- critical safety or release rules
- generated-file warnings

### `memo.md`

This is the main project briefing. It should cover:

- mission
- tech stack
- system shape
- ownership map
- critical flows
- data contracts
- commands runbook
- constraints and guardrails
- known risks

Use the detailed structure from [reference.md](reference.md).

### `active-context.md`

Use it only as the temporary scratchpad for the current seeding pass:

- current goal
- files in focus
- major findings
- blockers or unknowns

### Lessons

Create 3-8 starter lessons only if you found reusable, prevention-oriented patterns.
Use the installed lesson template and tag vocabulary exactly.

### Journal

Add one initial journal entry summarizing the seeding pass if memory was materially updated.

## Required Commands

Run the commands that match the current platform:

```text
Windows
- scripts/memory/rebuild-memory-index.ps1
- scripts/memory/lint-memory.ps1
- scripts/memory/query-memory.ps1

macOS/Linux
- sh ./scripts/memory/rebuild-memory-index.sh
- sh ./scripts/memory/lint-memory.sh
- sh ./scripts/memory/query-memory.sh
```

If vector mode is enabled, also validate with:

```text
vector_health
vector_sync
vector_search "how do I run tests"
vector_search "what are the main project risks"
```

## Retrieval Quality Gate

Check 5-10 realistic queries and confirm the right files surface quickly.
Use queries like:

- `what are the main runtime boundaries`
- `how do I run tests and lint`
- `who owns <critical module>`
- `what are the known pitfalls`
- `how does release or deployment work`

If retrieval is weak:

- split overloaded memo sections
- tighten headings and terminology
- move reusable pitfalls into lessons
- remove stale or low-signal prose

## Final Output Contract

When finished, return exactly these sections:

1. `Coverage summary` - what project domains are now represented in Mnemo.
2. `Files updated` - every Mnemo memory file created or edited.
3. `Commands run` - rebuild, lint, query, and vector commands actually executed.
4. `Retrieval checks` - queries tried and whether the expected hits were returned.
5. `Remaining gaps` - explicit unknowns or areas not yet captured.

## Additional Guidance

- Prefer precise file paths and commands over generic prose.
- Keep `hot-rules.md` small and `memo.md` current.
- Do not store raw noise from logs or huge code excerpts.
- Clear `active-context.md` before ending the seeding pass.
- Use [reference.md](reference.md) for the exact memo, lesson, journal, and validation structure.
