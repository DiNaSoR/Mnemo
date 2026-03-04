# Mnemo Codebase Optimizer Reference

## Memo Template (Detailed)

Use this structure for `.mnemo/memory/memo.md`:

```markdown
# Project Memo - <project>

Last updated: YYYY-MM-DD

## Mission
- One-paragraph purpose and primary user outcomes.

## Tech Stack
- Language(s): `<lang>`
- Framework(s): `<framework>`
- Key dependencies: `<deps>`

## System Shape
- Runtime components:
  - `<component>`: `<responsibility>`
  - `<component>`: `<responsibility>`
- Boundaries:
  - `<boundary>` -> `<dependency>`

## Ownership Map
| Module / Path | Responsibility |
|---|---|
| `<module/path>` | `<what it does>` |
| `<module/path>` | `<what it does>` |

## Critical Flows
- **Flow A:**
  - Trigger: `<event>`
  - Core path: `<file>` → `<file>` → `<file>`
  - Side effects: `<what else happens>`
  - Failure modes: `<what can go wrong>`

## Data Contracts
| Type / Schema | Purpose | Key Fields |
|---|---|---|
| `<schema>` | `<purpose>` | `<fields>` |

## Commands Runbook
| Action | Command |
|---|---|
| Install | `<command>` |
| Dev run | `<command>` |
| Test | `<command>` |
| Lint/format | `<command>` |
| Build | `<command>` |
| Release/deploy | `<command>` |

## Constraints and Guardrails
- Non-negotiables:
  - `<rule>`
- Security/compliance:
  - `<constraint>`

## Known Risks
| Risk | Detection | Mitigation |
|---|---|---|
| `<risk>` | `<how to detect>` | `<how to fix>` |
```

## Hot Rules Template

Use this for `.mnemo/memory/hot-rules.md` (10-20 lines strict):

```markdown
# Hot Rules (MUST READ)

Keep this file under ~20 lines. If it grows, move content into memo or lessons.

## Authority Order (highest to lowest)
1) Lessons override EVERYTHING (including active-context)
2) active-context.md overrides memo/journal (but NOT lessons)
3) memo.md is long-term project truth
4) Journal is history

## Retrieval Rules
5) Do NOT scan raw journals. Use indexes/digests first.
6) Reuse existing patterns. Check memo.md before creating new systems.
7) When done: clear active-context.md, add journal entry if significant.

## Project Invariants
- Never <critical action> without <safety precondition>.
- <generated file> is auto-generated — do not edit manually.
- Before release: run <required commands>.
```

## Active Context Template

Use this for `.mnemo/memory/active-context.md`:

```markdown
# Active Context (Session Scratchpad)

Priority: this overrides older journal history *for this session only*.

## Current Goal
- <what you are working on>

## Files in Focus
- <key files for this task>

## Findings / Decisions
- <discovered during this session>

## Temporary Constraints
- <session-specific rules>

## Blockers
- <what is preventing progress>
```

## Lesson Template (Exact Match)

Use this for each `.mnemo/memory/lessons/L-XXX-title.md`.
This must match the installed template at `.mnemo/memory/templates/lesson.template.md`:

```markdown
---
id: L-XXX
title: Short descriptive title
status: Active
tags: [UI, Reliability]
introduced: YYYY-MM-DD
applies_to:
  - path/or/glob/**
triggers:
  - error keyword
rule: One sentence. Imperative. Testable.
supersedes: ""
---

# L-XXX - Short descriptive title

## Symptom
What does the developer observe when this pitfall is hit?

## Root cause
Why does this happen? What is the underlying mechanism?

## Wrong approach (DO NOT REPEAT)
- What someone might try that makes it worse

## Correct approach
- The right way to fix or prevent this
```

### Tag vocabulary (use only these)

> From `.mnemo/memory/tag-vocabulary.md`

**Domain tags:** `[UI]`, `[Layout]`, `[Input]`, `[Data]`, `[Server]`, `[Init]`, `[Build]`, `[CI]`, `[Release]`, `[Compat]`, `[Integration]`, `[Docs]`, `[Architecture]`, `[DX]`, `[Reliability]`, `[Process]`

**Type tags:** `[Fix]`, `[Feature]`, `[Refactor]`

Do not invent new tags. Pick the closest match.

## Journal Entry Template

Use for `.mnemo/memory/journal/YYYY-MM.md`:

```markdown
## YYYY-MM-DD

- [Area][Type] Title
  - Why: <reason>
  - Key files:
    - `path/to/file`
  - Verification: Build PASS/FAIL; Runtime PASS/FAIL
```

## Retrieval Validation Query Set

Run these and confirm each returns high-signal files:

| # | Query | Expected Primary Hit |
|---|---|---|
| 1 | "What are the core runtime boundaries?" | memo.md → System Shape |
| 2 | "Which files define the main data contracts?" | memo.md → Data Contracts |
| 3 | "How do I run full tests and lint?" | memo.md → Commands Runbook |
| 4 | "What regressions happened and how to prevent?" | lessons/L-XXX-*.md |
| 5 | "Who owns `<critical module>` and what are the rules?" | memo.md → Ownership Map |
| 6 | "What are the top production risks?" | memo.md → Known Risks |

If vector mode is enabled, test with MCP tools:
```
vector_search "how to run tests"
vector_search "known pitfalls and regressions"
vector_search "deployment process"
```

## Optimization Heuristics

- Prefer one clear heading over long paragraphs
- Replace duplicate bullets with one canonical bullet
- If a memo section grows beyond ~50 lines, split into lessons
- Keep journal chronological; keep memo conceptual
- Remove stale TODOs from memo; only keep current truth
- Use consistent tags and terminology from tag-vocabulary.md
- Every important claim should map to a concrete file path or command
