# Mnemo Codebase Optimizer Reference

## Memo Template

Use this structure for `.mnemo/memory/memo.md`:

```markdown
# Project Memo - <project>

Last updated: YYYY-MM-DD

## Mission
- One short paragraph explaining what the repository does and why it exists.

## Tech Stack
- Languages: `<lang>`
- Frameworks / runtimes: `<framework>`
- Important dependencies: `<deps>`

## System Shape
- Runtime components:
  - `<component>`: `<responsibility>`
- Boundaries:
  - `<boundary>` -> `<dependency>`

## Ownership Map
| Module / Path | Responsibility |
|---|---|
| `<path>` | `<responsibility>` |

## Critical Flows
- **Flow name**
  - Trigger: `<event>`
  - Path: `<file>` -> `<file>` -> `<file>`
  - Side effects: `<effects>`
  - Failure modes: `<what breaks>`

## Data Contracts
| Type / Schema | Purpose | Key Fields |
|---|---|---|
| `<schema>` | `<purpose>` | `<fields>` |

## Commands Runbook
| Action | Command |
|---|---|
| Install / bootstrap | `<command>` |
| Dev run | `<command>` |
| Test | `<command>` |
| Lint / format | `<command>` |
| Build | `<command>` |
| Release / deploy | `<command>` |

## Constraints and Guardrails
- Non-negotiables:
  - `<rule>`
- Security / compliance:
  - `<constraint>`

## Known Risks
| Risk | Detection | Mitigation |
|---|---|---|
| `<risk>` | `<how to spot it>` | `<how to reduce it>` |
```

## Hot Rules Template

Use this for `.mnemo/memory/hot-rules.md` and keep it under about 20 lines:

```markdown
# Hot Rules (MUST READ)

## Authority Order
1) Lessons override EVERYTHING
2) active-context.md overrides memo and journal for the current session
3) memo.md is long-term project truth
4) Journal is history

## Retrieval Rules
- Check memo and lessons before inventing new patterns.
- Do not scan raw journal history first.
- Clear active-context.md when the task is done.

## Project Invariants
- Never `<unsafe action>` without `<precondition>`.
- `<generated file>` is generated. Do not edit it manually.
- Before release: run `<required commands>`.
```

## Active Context Template

Use this for `.mnemo/memory/active-context.md` during the seeding pass:

```markdown
# Active Context (Session Scratchpad)

## Current Goal
- Seeding Mnemo memory for this repository

## Files in Focus
- <files currently being summarized>

## Findings / Decisions
- <important findings from this pass>

## Temporary Constraints
- <session-specific constraints>

## Blockers
- <open unknowns>
```

## Lesson Template

Use the installed lesson template at `.mnemo/memory/templates/lesson.template.md` exactly:

```markdown
---
id: L-XXX
title: Short descriptive title
status: Active
tags: [Build, Reliability]
introduced: YYYY-MM-DD
applies_to:
  - path/or/glob/**
triggers:
  - error keyword or symptom
rule: One sentence. Imperative. Testable.
supersedes: ""
---

# L-XXX - Short descriptive title

## Symptom
What the developer or agent observes.

## Root cause
Why this happens.

## Wrong approach (DO NOT REPEAT)
- Common failed fix or repeated mistake.

## Correct approach
- The reliable prevention or repair path.
```

## Approved Tag Vocabulary

Use tags from `.mnemo/memory/tag-vocabulary.md` only.
Common starter tags include:

- Domain: `Architecture`, `Build`, `CI`, `Compat`, `DX`, `Docs`, `Data`, `Init`, `Integration`, `Process`, `Release`, `Reliability`, `Server`, `UI`
- Type: `Fix`, `Feature`, `Refactor`

Do not invent new tags unless the installed vocabulary already contains them.

## Journal Entry Template

Use this structure in `.mnemo/memory/journal/YYYY-MM.md`:

```markdown
## YYYY-MM-DD

- [Area][Type] Seeding summary
  - Why: <why this memory pass was needed>
  - Key files:
    - `path/to/file`
  - Verification: rebuild PASS/FAIL; lint PASS/FAIL; retrieval PASS/FAIL
```

## Retrieval Validation Set

Run queries like these and confirm the right files surface:

| Query | Expected Primary Hit |
|---|---|
| `what are the runtime boundaries` | `memo.md` -> `System Shape` |
| `how do I run tests and lint` | `memo.md` -> `Commands Runbook` |
| `who owns <critical module>` | `memo.md` -> `Ownership Map` |
| `what are the known pitfalls` | `lessons/*.md` |
| `how does release work` | `memo.md` -> `Commands Runbook` or `Known Risks` |

If vector mode is enabled, also run:

```text
vector_search "how do I run tests"
vector_search "what are the main project risks"
vector_search "who owns the critical modules"
```

## Quality Heuristics

- Prefer headings and tables over long paragraphs.
- Split dense memo sections before they become hard to retrieve.
- Move reusable pitfalls into lessons instead of bloating the memo.
- Keep the memo current and conceptual; keep the journal historical.
- Every important claim should map to a file path, command, or schema.
- End by clearing `active-context.md`.
