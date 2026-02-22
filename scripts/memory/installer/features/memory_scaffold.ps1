<#
memory_scaffold.ps1 - Installs memory content files and multi-agent bridges.
Dot-sourced by bootstrap.ps1. Depends on io.ps1 functions.
#>

function Install-MemoryScaffold {
  param(
    [Parameter(Mandatory=$true)][hashtable]$Ctx,
    [Parameter(Mandatory=$true)][string]$ProjectName,
    [Parameter(Mandatory=$true)][string]$MnemoVersion,
    [switch]$Force
  )

  $month = (Get-Date -Format "yyyy-MM")
  $today = (Get-Date -Format "yyyy-MM-dd")

  $indexMd = @"
# Memory Index

Entry point for repo memory.

## Read order (token-safe)

ALWAYS READ (in order):
1) ``hot-rules.md`` (tiny invariants, <20 lines)
2) ``active-context.md`` (this session only)
3) ``memo.md`` (long-term current truth + ownership)

SEARCH FIRST, THEN OPEN ONLY WHAT MATCHES:
4) ``lessons/index.md`` -> find lesson ID(s)
5) ``lessons/L-XXX-*.md`` -> open only specific lesson(s)
6) ``digests/YYYY-MM.digest.md`` -> before raw journal
7) ``journal/YYYY-MM.md`` -> only for archaeology

## Files

- Hot rules: ``hot-rules.md``
- Active context: ``active-context.md``
- Memo: ``memo.md``
- Lessons: ``lessons/``
- Lesson index (generated): ``lessons/index.md`` + ``lessons-index.json``
- Journal monthly: ``journal/YYYY-MM.md``
- Journal index (generated): ``journal-index.md`` + ``journal-index.json``
- Digests (generated): ``digests/YYYY-MM.digest.md``
- Tag vocabulary: ``tag-vocabulary.md``
- Regression checklist: ``regression-checklist.md``
- ADRs: ``adr/``

## Maintenance commands

Helper scripts:
- Add lesson: ``scripts/memory/add-lesson.ps1 -Title "..." -Tags "..." -Rule "..."``
- Add journal: ``scripts/memory/add-journal-entry.ps1 -Tags "..." -Title "..."``
- Rebuild indexes: ``scripts/memory/rebuild-memory-index.ps1``
- Lint: ``scripts/memory/lint-memory.ps1``
- Query (grep): ``scripts/memory/query-memory.ps1 -Query "..."``
- Query (SQLite): ``scripts/memory/query-memory.ps1 -Query "..." -UseSqlite``
- Clear session: ``scripts/memory/clear-active.ps1``
"@

  $hotRules = @"
# Hot Rules (MUST READ)

Keep this file under ~20 lines. If it grows, move content into memo or lessons.

## Authority Order (highest to lowest)
1) Lessons override EVERYTHING (including active-context)
2) active-context.md overrides memo/journal (but NOT lessons)
3) memo.md is long-term project truth
4) journal is history

## Retrieval Rules
5) Do NOT scan raw journals. Use indexes/digests first.
6) Reuse existing patterns. Check memo.md ownership before creating new systems.
7) When done: clear active-context.md, add journal entry if significant.
"@

  $activeContext = @"
# Active Context (Session Scratchpad)

Priority: this overrides older journal history *for this session only*.

CLEAR this file when the task is done:
- Run ``scripts/memory/clear-active.ps1``

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
"@

  $memo = @"
# Project Memo - $ProjectName

Last updated: $today

## Ownership map (fill early)

- UI / Frontend owner: <path/module>
- Backend / Server owner: <path/module>
- Data parsing / protocol owner: <path/module>
- Build/CI owner: <path/module>

## Current truth (high-signal)

- <invariants that must stay true>
- <important defaults/toggles>
- <timing/lifecycle rules>
- <anything that prevents regressions>

## Open questions / TODO
- <unknowns / risks>
"@

  $journalMonth = @"
# Development Journal - $ProjectName ($month)

## $today

- [Process] Initialized memory system (Mnemo v$MnemoVersion)
  - Why: token-safe AI memory + indexed retrieval + portable hooks
  - Key files:
    - ``.cursor/memory/*``
    - ``.cursor/rules/00-memory-system.mdc``
    - ``scripts/memory/*``
"@

  $memoryRule = @"
---
description: Memory System v$MnemoVersion - Authority + Atomic Retrieval + Token Safety
globs:
  - "**/*"
alwaysApply: true
---

# Memory System (MANDATORY)

## Authority Order (highest to lowest)
1) Lessons override EVERYTHING (including active-context)
2) ``active-context.md`` overrides memo/journal (but NOT lessons)
3) ``memo.md`` is long-term project truth
4) Journal is history
5) Existing codebase
6) New suggestions (lowest priority)

## Token-Safe Retrieval

ALWAYS READ (in order):
1. ``.cursor/memory/hot-rules.md`` (tiny, <20 lines)
2. ``.cursor/memory/active-context.md`` (current session state)
3. ``.cursor/memory/memo.md`` (project truth + ownership)

SEARCH FIRST, THEN FETCH:
4. ``.cursor/memory/lessons/index.md`` -> find relevant lesson ID
5. ``.cursor/memory/lessons/L-XXX-title.md`` -> load ONLY the specific file
6. ``.cursor/memory/digests/YYYY-MM.digest.md`` -> before raw journal
7. ``.cursor/memory/journal/YYYY-MM.md`` -> only for archaeology

## After Any Feature/Fix

1. Update ``active-context.md`` during work (scratchpad)
2. Add journal entry to ``journal/YYYY-MM.md`` when done
3. Create ``lessons/L-XXX-title.md`` if you discovered a pitfall
4. Update ``memo.md`` if project truth changed
5. Clear ``active-context.md`` when task is merged

## Helper Scripts

- Add lesson: ``scripts/memory/add-lesson.ps1 -Title "..." -Tags "..." -Rule "..."``
- Add journal: ``scripts/memory/add-journal-entry.ps1 -Tags "..." -Title "..."``
- Rebuild: ``scripts/memory/rebuild-memory-index.ps1``
- Lint: ``scripts/memory/lint-memory.ps1``
- Query: ``scripts/memory/query-memory.ps1 -Query "..." [-UseSqlite]``
- Clear: ``scripts/memory/clear-active.ps1``

## AI Behavior

- When user says "I'm done" or "merge this" -> remind to clear active-context
- When you discover a bug pattern -> suggest creating a lesson
- When unsure about architecture -> check lessons/index.md first
- Don't create parallel systems -> check memo.md ownership map
"@

  $static = @{
    (Join-Path $Ctx.MemoryDir "index.md")                      = $indexMd
    (Join-Path $Ctx.MemoryDir "hot-rules.md")                  = $hotRules
    (Join-Path $Ctx.MemoryDir "active-context.md")             = $activeContext
    (Join-Path $Ctx.MemoryDir "memo.md")                       = $memo
    (Join-Path $Ctx.JournalDir "$month.md")                    = $journalMonth
    (Join-Path $Ctx.RulesDir "00-memory-system.mdc")           = $memoryRule
  }

  foreach ($kv in $static.GetEnumerator()) {
    Write-MnemoFile -Path $kv.Key -Content $kv.Value -ForceWrite:$Force
  }

  # Static content files (small enough to keep inline)
  Write-MnemoFile (Join-Path $Ctx.LessonsDir "README.md") @"
# Lessons (Atomic)

Each lesson is a separate file with strict YAML frontmatter.

Naming: ``L-001-short-title.md``

Create: ``scripts/memory/add-lesson.ps1 -Title "..." -Tags "..." -Rule "..."``
"@ -ForceWrite:$Force

  Write-MnemoFile (Join-Path $Ctx.LessonsDir "index.md") @"
# Lessons Index (generated)

Generated by ``scripts/memory/rebuild-memory-index.ps1``.

Format: ID | [Tags] | AppliesTo | Rule | File

(No lessons yet.)
"@ -ForceWrite:$Force

  Write-MnemoFile (Join-Path $Ctx.JournalDir "README.md") @"
# Journal

Monthly file: ``YYYY-MM.md``

Rules:
- Each date appears ONCE per file: ``## YYYY-MM-DD``
- Put multiple entries under that header as bullets.
- Keep it high-signal: what changed, why, key files.

Add entries via: ``scripts/memory/add-journal-entry.ps1 -Tags "UI,Fix" -Title "..."``
"@ -ForceWrite:$Force

  Write-MnemoFile (Join-Path $Ctx.DigestsDir "README.md") @"
# Digests

Generated summaries of journal months.
AI should read digests before raw journal.

Generated by: ``scripts/memory/rebuild-memory-index.ps1``
"@ -ForceWrite:$Force

  Write-MnemoFile (Join-Path $Ctx.AdrDir "README.md") @"
# ADRs

Architecture Decision Records: why we did it this way.

Naming: ``ADR-001-short-title.md``
Format: Context / Decision / Consequences
"@ -ForceWrite:$Force

  Write-MnemoFile (Join-Path $Ctx.MemoryDir "tag-vocabulary.md") @"
# Tag Vocabulary (fixed set)

Use a small vocabulary so retrieval stays reliable.
Linter validates tags against this list.

- [UI] - UI behavior, rendering, interaction
- [Layout] - layout groups, anchors, sizing, rects
- [Input] - mouse/keyboard/controller input rules
- [Data] - parsing, payloads, formats, state sync
- [Server] - server-side logic and lifecycle
- [Init] - initialization / load order / startup
- [Build] - compilation, MSBuild, project files
- [CI] - automation, pipelines
- [Release] - packaging, artifacts, uploads
- [Compat] - IL2CPP, runtime constraints, environment quirks
- [Integration] - optional plugins, reflection bridges, external systems
- [Docs] - documentation and changelog work
- [Architecture] - module boundaries, refactors, ownership
- [DX] - developer experience, tooling, maintainability
- [Reliability] - crash prevention, guardrails, self-healing
- [Process] - workflow, memory system, tooling changes

# Common "type" tags
- [Fix] - bug fixes, regressions, patches
- [Feature] - new behavior/capability
- [Refactor] - restructuring without behavior changes
"@ -ForceWrite:$Force

  Write-MnemoFile (Join-Path $Ctx.MemoryDir "regression-checklist.md") @"
# Regression Checklist

Run only what is relevant.

## Build
- [ ] Build solution / affected projects
- [ ] No new warnings (or documented)

## Runtime (if applicable)
- [ ] Core UI renders
- [ ] Core interactions work
- [ ] No obvious errors/log spam

## Data (if applicable)
- [ ] Parsing works on known payloads
- [ ] State updates do not regress

## Docs (if applicable)
- [ ] Journal updated
- [ ] Memo updated (if truth changed)
- [ ] Lesson added (if pitfall discovered)
"@ -ForceWrite:$Force

  # Template files
  Write-MnemoFile (Join-Path $Ctx.TemplatesDir "lesson.template.md") @"
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
What broke / what was observed.

## Root cause
The real reason.

## Wrong approach (DO NOT REPEAT)
- What not to do

## Correct approach
- What to do instead

## References
- Files: ``path/to/file``
- Journal: ``journal/YYYY-MM.md#YYYY-MM-DD``
"@ -ForceWrite:$Force

  Write-MnemoFile (Join-Path $Ctx.TemplatesDir "journal-entry.template.md") @"
# Journal Entry Template (paste under an existing date header)

- [Area][Type] Title
  - Why: ...
  - Key files:
    - ``path/to/file``
  - Notes: <optional>
  - Verification: Build PASS/FAIL/NOT RUN; Runtime PASS/FAIL/NOT RUN
  - Related: Lesson L-XXX; ADR ADR-XXX
"@ -ForceWrite:$Force

  Write-MnemoFile (Join-Path $Ctx.TemplatesDir "adr.template.md") @"
# ADR-XXX - Title

Date: YYYY-MM-DD
Status: Proposed | Accepted | Deprecated

## Context
What problem are we solving?

## Decision
What did we choose?

## Consequences
Tradeoffs, risks, follow-ups.
"@ -ForceWrite:$Force

  # Agent bridge rules
  $geminiRule = @"
---
description: Mnemo memory system - structured AI memory in .cursor/memory/
alwaysApply: true
---

# Memory System (Mnemo)

This project uses Mnemo for structured AI memory. All memory lives in ``.cursor/memory/``.

## Read Order (ALWAYS)
1. ``.cursor/memory/hot-rules.md`` - tiny invariants (read first)
2. ``.cursor/memory/active-context.md`` - current session state
3. ``.cursor/memory/memo.md`` - project truth + ownership

## Authority Order
1. Lessons override everything
2. active-context overrides memo/journal (but NOT lessons)
3. memo.md is long-term truth
4. Journal is history

## After Any Task
- Update active-context.md during work
- Add journal entry when done
- Create lesson if you discovered a pitfall
- Clear active-context.md when task is merged
"@

  Write-MnemoFile (Join-Path $Ctx.MnemoRulesAgentDir "00-memory-system.md") $geminiRule -ForceWrite:$Force

  Write-Host "`nMemory scaffold installed." -ForegroundColor Cyan
}

function Install-MemoryScripts {
  param(
    [Parameter(Mandatory=$true)][hashtable]$Ctx,
    [Parameter(Mandatory=$true)][string]$InstallerRoot,
    [switch]$Force,
    [switch]$EnableVector,
    [string]$VectorProvider = "openai"
  )

  $scripts = @(
    @{ Name = "rebuild-memory-index.ps1"; LineEndings = "CRLF" },
    @{ Name = "lint-memory.ps1";          LineEndings = "CRLF" },
    @{ Name = "query-memory.ps1";         LineEndings = "CRLF" },
    @{ Name = "build-memory-sqlite.py";   LineEndings = "LF"   },
    @{ Name = "query-memory-sqlite.py";   LineEndings = "LF"   },
    @{ Name = "clear-active.ps1";         LineEndings = "CRLF" },
    @{ Name = "add-lesson.ps1";           LineEndings = "CRLF" },
    @{ Name = "add-journal-entry.ps1";    LineEndings = "CRLF" },
    @{ Name = "customization.md";         LineEndings = "CRLF" }
  )

  foreach ($s in $scripts) {
    Install-TemplateFile `
      -TemplateName $s.Name `
      -DestPath (Join-Path $Ctx.MemScripts $s.Name) `
      -InstallerRoot $InstallerRoot `
      -LineEndings $s.LineEndings `
      -ForceWrite:$Force
  }

  $cursorSkillTemplates = @("SKILL.md", "reference.md")
  foreach ($f in $cursorSkillTemplates) {
    Install-TemplateFile `
      -TemplateName "skills\mnemo-codebase-optimizer\$f" `
      -DestPath (Join-Path $Ctx.CursorDir "skills\mnemo-codebase-optimizer\$f") `
      -InstallerRoot $InstallerRoot `
      -LineEndings "LF" `
      -ForceWrite:$Force
  }

  if ($EnableVector) {
    Install-TemplateFile `
      -TemplateName "mnemo_vector.py" `
      -DestPath (Join-Path $Ctx.MemScripts "mnemo_vector.py") `
      -InstallerRoot $InstallerRoot `
      -LineEndings "LF" `
      -ForceWrite:$Force

    # Install autonomy modules
    Install-AutonomyModules -Ctx $Ctx -InstallerRoot $InstallerRoot -Force:$Force
  }
}

function Install-AutonomyModules {
  param(
    [Parameter(Mandatory=$true)][hashtable]$Ctx,
    [Parameter(Mandatory=$true)][string]$InstallerRoot,
    [switch]$Force
  )

  $autonomyTemplates = @("__init__.py", "schema.py", "runner.py", "ingest_pipeline.py",
    "lifecycle_engine.py", "entity_resolver.py", "retrieval_router.py",
    "reranker.py", "context_safety.py", "vault_policy.py")
  $policyTemplates = @("policies.yaml")

  foreach ($f in $autonomyTemplates) {
    $src = Join-Path $InstallerRoot "scripts\memory\installer\templates\autonomy\$f"
    if (Test-Path $src) {
      Install-TemplateFile `
        -TemplateName "autonomy\$f" `
        -DestPath (Join-Path $Ctx.AutonomyDir $f) `
        -InstallerRoot $InstallerRoot `
        -LineEndings "LF" `
        -ForceWrite:$Force
    }
  }
  foreach ($f in $policyTemplates) {
    $src = Join-Path $InstallerRoot "scripts\memory\installer\templates\autonomy\$f"
    if (Test-Path $src) {
      Install-TemplateFile `
        -TemplateName "autonomy\$f" `
        -DestPath (Join-Path $Ctx.AutonomyDir $f) `
        -InstallerRoot $InstallerRoot `
        -LineEndings "LF" `
        -ForceWrite:$Force
    }
  }
}
