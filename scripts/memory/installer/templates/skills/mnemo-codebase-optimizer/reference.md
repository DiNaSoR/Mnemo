# Mnemo Codebase Optimizer Reference

## Memo Template (Detailed)

Use this structure for `.mnemo/memory/memo.md`:

```markdown
# Project Memo - <project>

## Mission
- One-paragraph purpose and primary user outcomes.

## System Shape
- Runtime components:
  - `<component>`: `<responsibility>`
- Boundaries:
  - `<boundary>` -> `<dependency>`

## Ownership Map
- `<module/path>` -> `<team/owner>`
- `<module/path>` -> `<team/owner>`

## Critical Flows
- Flow A:
  - Trigger:
  - Core path:
  - Side effects:
  - Failure modes:
- Flow B:
  - Trigger:
  - Core path:
  - Side effects:
  - Failure modes:

## Data Contracts
- `<type/schema/file>`: purpose + key fields + constraints
- `<type/schema/file>`: purpose + key fields + constraints

## Commands Runbook
- Install: `<command>`
- Dev run: `<command>`
- Tests: `<command>`
- Lint/format: `<command>`
- Build/release: `<command>`

## Constraints and Guardrails
- Non-negotiables:
  - `<rule>`
  - `<rule>`
- Security/compliance:
  - `<constraint>`

## Known Risks
- `<risk>` -> detection -> mitigation
- `<risk>` -> detection -> mitigation
```

## Hot Rules Template

Use this structure for `.mnemo/memory/hot-rules.md` (10-20 lines):

```markdown
# Hot Rules

- Never bypass `<critical check>`.
- Do not edit `<generated path>` manually.
- Keep `<artifact>` synchronized with `<source>`.
- Before release: run `<required command list>`.
- If `<failure condition>`, stop and verify `<source of truth>`.
```

## Active Context Template

Use this structure for `.mnemo/memory/active-context.md`:

```markdown
# Active Context

## Current Task
- Goal:
- Scope:
- Out of scope:

## Working Notes
- Current status:
- Decisions made:
- Risks and blockers:

## Next Actions
1. `<action>`
2. `<action>`
3. `<action>`
```

## Starter Lesson Template

Use this for each `L-XXX-*.md`:

```markdown
---
id: L-XXX
title: "<short pitfall title>"
tags: ["pitfall", "regression", "<domain>"]
applies_to: ["<path/glob>"]
rule: "<single actionable rule>"
---

## Context
When this appears and why it happens.

## Failure Pattern
Observable signs and likely root causes.

## Corrective Action
Exact steps to fix safely.

## Prevention Check
How to detect it before merge/release.
```

## Retrieval Validation Query Set

Run and confirm each query returns high-signal files:

1. "What are the core runtime boundaries?"
2. "Which files define the main data contracts?"
3. "How do I run full tests and lint before release?"
4. "What regressions happened before and how do we prevent them?"
5. "Who owns `<critical module>` and what are the rules?"
6. "What are the top production risks in this repo?"

## Optimization Heuristics

- Prefer one clear heading over long paragraphs.
- Replace duplicate bullets with one canonical bullet.
- If a memo section grows too long, split into lessons.
- Keep journaling chronological; keep memo conceptual.
- Remove stale TODOs from memo; keep only current truth.
