<#
test-installer.ps1
Regression tests for the unified Node.js Mnemo installer on Windows.

USAGE:
  powershell -ExecutionPolicy Bypass -File .\tests\test-installer.ps1
  powershell -ExecutionPolicy Bypass -File .\tests\test-installer.ps1 -TestName dry-run
#>

[CmdletBinding()]
param(
  [string]$TestName = "",
  [string]$CliPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CliPath)) {
  $CliPath = Join-Path $RepoRoot "bin\mnemo.js"
}

$passed = 0
$failed = 0
$skipped = 0

function Write-Pass([string]$name) {
  Write-Host "  PASS  $name" -ForegroundColor Green
  $script:passed++
}

function Write-Fail([string]$name, [string]$reason) {
  Write-Host "  FAIL  $name : $reason" -ForegroundColor Red
  $script:failed++
}

function Write-Skip([string]$name, [string]$reason) {
  Write-Host "  SKIP  $name : $reason" -ForegroundColor DarkYellow
  $script:skipped++
}

function ShouldRun([string]$name) {
  return ([string]::IsNullOrWhiteSpace($TestName) -or $TestName -eq $name)
}

function New-TestDir([string]$suffix = "") {
  $path = Join-Path $env:TEMP "mnemo-test-$([System.IO.Path]::GetRandomFileName())$suffix"
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  return $path
}

function Remove-TestDir([string]$path) {
  if (Test-Path $path) {
    Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
  }
}

function Detect-PythonCommand() {
  foreach ($candidate in @("python", "py", "python3")) {
    $cmd = Get-Command $candidate -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { continue }
    $pathValue = if ($cmd.PSObject.Properties.Match("Path").Count -gt 0) { $cmd.Path } else { "" }
    $sourceValue = if ($cmd.PSObject.Properties.Match("Source").Count -gt 0) { $cmd.Source } else { "" }
    $executable = if (-not [string]::IsNullOrWhiteSpace($pathValue)) {
      $pathValue
    } elseif (-not [string]::IsNullOrWhiteSpace($sourceValue)) {
      $sourceValue
    } else {
      $candidate
    }
    try {
      if ($candidate -eq "py") {
        & $executable -3 --version 1>$null 2>$null
      } else {
        & $executable --version 1>$null 2>$null
      }
      if ($LASTEXITCODE -eq 0) { return $candidate }
    } catch {}
  }
  return ""
}

$PythonCommand = Detect-PythonCommand

function Invoke-Python {
  param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Args
  )
  if ([string]::IsNullOrWhiteSpace($PythonCommand)) {
    throw "Python is unavailable"
  }
  if ($PythonCommand -eq "py") {
    & py -3 @Args
  } else {
    & $PythonCommand @Args
  }
}

function Test-SqliteVecAvailable() {
  if ([string]::IsNullOrWhiteSpace($PythonCommand)) { return $false }
  try {
    if ($PythonCommand -eq "py") {
      & py -3 -c "import sqlite_vec" 1>$null 2>$null
    } else {
      & $PythonCommand -c "import sqlite_vec" 1>$null 2>$null
    }
    return ($LASTEXITCODE -eq 0)
  } catch {
    return $false
  }
}

function Run-Installer([string]$dest, [string[]]$ExtraArgs = @()) {
  $args = @($CliPath, "--yes", "--repo-root", $dest, "--project-name", "TestProject") + $ExtraArgs
  $savedEAP = $ErrorActionPreference
  $ErrorActionPreference = "SilentlyContinue"
  try {
    $result = & node @args 2>&1
    $ec = $LASTEXITCODE
  } catch {
    $result = @($_.ToString())
    $ec = 1
  } finally {
    $ErrorActionPreference = $savedEAP
  }
  return @{ Output = ($result -join "`n"); ExitCode = $ec }
}

function Run-NativeCommand([scriptblock]$Command) {
  $savedEAP = $ErrorActionPreference
  $ErrorActionPreference = "SilentlyContinue"
  try {
    $result = & $Command 2>&1
    $ec = $LASTEXITCODE
  } catch {
    $result = @($_.ToString())
    $ec = 1
  } finally {
    $ErrorActionPreference = $savedEAP
  }
  return @{ Output = (($result | ForEach-Object { $_.ToString() }) -join "`n"); ExitCode = $ec }
}

function Test-CursorRulesOnlyMdc([string]$RepoRootPath) {
  $rulesDir = Join-Path $RepoRootPath ".cursor\rules"
  if (!(Test-Path $rulesDir)) { return $false }
  $invalid = @(
    Get-ChildItem -Path $rulesDir -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object { $_.Extension.ToLowerInvariant() -ne ".mdc" }
  )
  return $invalid.Count -eq 0
}

function Test-ManagedSkillDir([string]$RepoRootPath) {
  $skillDir = Join-Path $RepoRootPath ".cursor\skills\mnemo-codebase-optimizer"
  if (!(Test-Path $skillDir)) { return $false }
  $entries = @(Get-ChildItem -Path $skillDir -Force -ErrorAction SilentlyContinue)
  if ($entries.Count -ne 2) { return $false }
  $names = @($entries | ForEach-Object { $_.Name } | Sort-Object)
  return (($names -join ",") -eq "reference.md,SKILL.md")
}

Write-Host "Mnemo installer regression tests (Windows)" -ForegroundColor Cyan
Write-Host "CLI: $CliPath" -ForegroundColor Gray
Write-Host ""

if (ShouldRun "scratch") {
  $dest = New-TestDir
  try {
    $r = Run-Installer $dest
    $expectedDirs = @(
      ".mnemo\memory",
      ".mnemo\rules\cursor",
      ".mnemo\rules\agent",
      ".cursor\memory",
      ".cursor\rules",
      ".cursor\skills\mnemo-codebase-optimizer",
      ".agent\rules",
      ".mnemo\memory\lessons",
      ".mnemo\memory\journal",
      ".mnemo\memory\templates",
      "scripts\memory"
    )
    $expectedFiles = @(
      ".mnemo\memory\hot-rules.md",
      ".mnemo\memory\memo.md",
      ".mnemo\memory\active-context.md",
      ".mnemo\rules\cursor\00-memory-system.mdc",
      ".cursor\memory\hot-rules.md",
      ".cursor\rules\00-memory-system.mdc",
      ".cursor\skills\mnemo-codebase-optimizer\SKILL.md",
      ".cursor\skills\mnemo-codebase-optimizer\reference.md",
      ".agent\rules\00-memory-system.md",
      "scripts\memory\add-journal-entry.sh",
      "scripts\memory\add-journal-entry.ps1",
      "scripts\memory\add-lesson.sh",
      "scripts\memory\add-lesson.ps1",
      "scripts\memory\clear-active.sh",
      "scripts\memory\clear-active.ps1",
      "scripts\memory\lint-memory.sh",
      "scripts\memory\lint-memory.ps1",
      "scripts\memory\query-memory.sh",
      "scripts\memory\query-memory.ps1",
      "scripts\memory\rebuild-memory-index.sh",
      "scripts\memory\rebuild-memory-index.ps1",
      "scripts\memory\customization.md"
    )
    $allOk = $true
    if ($r.ExitCode -ne 0) {
      Write-Fail "scratch" "Installer exited with code $($r.ExitCode): $($r.Output)"
      $allOk = $false
    }
    foreach ($d in $expectedDirs) {
      if ($allOk -and !(Test-Path (Join-Path $dest $d))) {
        Write-Fail "scratch" "Missing directory: $d"
        $allOk = $false
      }
    }
    foreach ($f in $expectedFiles) {
      if ($allOk -and !(Test-Path (Join-Path $dest $f))) {
        Write-Fail "scratch" "Missing file: $f"
        $allOk = $false
      }
    }
    if ($allOk) {
      $canonicalHot = Get-Content -Raw (Join-Path $dest ".mnemo\memory\hot-rules.md")
      $bridgeHot = Get-Content -Raw (Join-Path $dest ".cursor\memory\hot-rules.md")
      if ($canonicalHot -ne $bridgeHot) {
        Write-Fail "scratch" "Canonical and Cursor bridge hot-rules content differ"
        $allOk = $false
      }
    }
    if ($allOk -and -not (Test-CursorRulesOnlyMdc $dest)) {
      Write-Fail "scratch" ".cursor\\rules contains non-.mdc files"
      $allOk = $false
    }
    if ($allOk -and -not (Test-ManagedSkillDir $dest)) {
      Write-Fail "scratch" ".cursor\\skills\\mnemo-codebase-optimizer contains unexpected entries"
      $allOk = $false
    }
    if ($allOk) { Write-Pass "scratch" }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "idempotent-no-force") {
  $dest = New-TestDir
  try {
    Run-Installer $dest | Out-Null
    $r = Run-Installer $dest
    if ($r.Output -match "(?m)^WROTE:") {
      Write-Fail "idempotent-no-force" "Installer wrote files on second run without --force"
    } else {
      Write-Pass "idempotent-no-force"
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "idempotent-force") {
  $dest = New-TestDir
  try {
    Run-Installer $dest | Out-Null
    $r = Run-Installer $dest @("--force")
    if ($r.Output -notmatch "(?m)^WROTE:") {
      Write-Fail "idempotent-force" "--force had no effect; no files were written"
    } else {
      Write-Pass "idempotent-force"
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "dry-run") {
  $dest = New-TestDir
  try {
    $r = Run-Installer $dest @("--dry-run")
    $files = Get-ChildItem -Recurse -File $dest -ErrorAction SilentlyContinue
    if ($r.ExitCode -ne 0) {
      Write-Fail "dry-run" "Installer exited with code $($r.ExitCode)"
    } elseif ($files) {
      Write-Fail "dry-run" "Dry-run created $($files.Count) file(s)"
    } else {
      Write-Pass "dry-run"
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "dry-run-vector") {
  $dest = New-TestDir
  try {
    $r = Run-Installer $dest @("--dry-run", "--enable-vector")
    $files = Get-ChildItem -Recurse -File $dest -ErrorAction SilentlyContinue
    if ($r.ExitCode -ne 0) {
      Write-Fail "dry-run-vector" "Installer exited with code $($r.ExitCode)"
    } elseif ($files) {
      Write-Fail "dry-run-vector" "Dry-run with vector created $($files.Count) file(s)"
    } else {
      Write-Pass "dry-run-vector"
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "path-with-spaces") {
  $dest = New-TestDir " with spaces"
  try {
    $r = Run-Installer $dest
    if ($r.ExitCode -ne 0) {
      Write-Fail "path-with-spaces" "Installer exited with code $($r.ExitCode)"
    } elseif (!(Test-Path (Join-Path $dest ".mnemo\memory\hot-rules.md"))) {
      Write-Fail "path-with-spaces" "Expected canonical files not created in spaced path"
    } elseif (!(Test-Path (Join-Path $dest ".cursor\memory\hot-rules.md"))) {
      Write-Fail "path-with-spaces" "Expected bridge files not created in spaced path"
    } else {
      Write-Pass "path-with-spaces"
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "helper-smoke") {
  $dest = New-TestDir
  try {
    $r = Run-Installer $dest
    $allOk = $r.ExitCode -eq 0
    if (-not $allOk) {
      Write-Fail "helper-smoke" "Installer exited with code $($r.ExitCode)"
    }
    if ($allOk) {
      Add-Content -Path (Join-Path $dest ".mnemo\memory\active-context.md") -Value "temporary scratch"
      $clearScript = Join-Path $dest "scripts\memory\clear-active.ps1"
      $clear = Run-NativeCommand { powershell -ExecutionPolicy Bypass -File $clearScript }
      if ($clear.ExitCode -ne 0) {
        Write-Fail "helper-smoke" "clear-active.ps1 failed: $($clear.Output)"
        $allOk = $false
      }
    }
    if ($allOk) {
      $lessonScript = Join-Path $dest "scripts\memory\add-lesson.ps1"
      $lesson = Run-NativeCommand {
        powershell -ExecutionPolicy Bypass -File $lessonScript `
          -Title "Smoke lesson" `
          -Tags "Process" `
          -Rule "Keep helper scripts working"
      }
      if ($lesson.ExitCode -ne 0) {
        Write-Fail "helper-smoke" "add-lesson.ps1 failed: $($lesson.Output)"
        $allOk = $false
      }
    }
    if ($allOk) {
      $journalScript = Join-Path $dest "scripts\memory\add-journal-entry.ps1"
      $journal = Run-NativeCommand {
        powershell -ExecutionPolicy Bypass -File $journalScript `
          -Tags "Process" `
          -Title "Smoke journal entry" `
          -Files "scripts/memory/lint-memory.ps1"
      }
      if ($journal.ExitCode -ne 0) {
        Write-Fail "helper-smoke" "add-journal-entry.ps1 failed: $($journal.Output)"
        $allOk = $false
      }
    }
    if ($allOk) {
      $rebuildScript = Join-Path $dest "scripts\memory\rebuild-memory-index.ps1"
      $lintScript = Join-Path $dest "scripts\memory\lint-memory.ps1"
      $queryScript = Join-Path $dest "scripts\memory\query-memory.ps1"
      $rebuild = Run-NativeCommand { powershell -ExecutionPolicy Bypass -File $rebuildScript -RepoRoot $dest }
      $lint = Run-NativeCommand { powershell -ExecutionPolicy Bypass -File $lintScript -RepoRoot $dest }
      $query = Run-NativeCommand {
        powershell -ExecutionPolicy Bypass -File $queryScript `
          -Query "Smoke lesson" `
          -Area "Lessons" `
          -Format "AI"
      }
      if ($rebuild.ExitCode -ne 0) {
        Write-Fail "helper-smoke" "rebuild-memory-index.ps1 failed: $($rebuild.Output)"
        $allOk = $false
      } elseif ($lint.ExitCode -ne 0) {
        Write-Fail "helper-smoke" "lint-memory.ps1 failed: $($lint.Output)"
        $allOk = $false
      } elseif ($query.Output -notmatch "lessons") {
        Write-Fail "helper-smoke" "query-memory.ps1 did not return lesson references: $($query.Output)"
        $allOk = $false
      }
    }
    if ($allOk -and (Test-Path (Join-Path $dest ".mnemo\memory\lessons\index.md")) -and (Test-Path (Join-Path $dest ".mnemo\memory\journal-index.md"))) {
      Write-Pass "helper-smoke"
    } elseif ($allOk) {
      Write-Fail "helper-smoke" "Expected rebuilt indexes were not created"
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "malformed-mcp-json") {
  $dest = New-TestDir
  try {
    $r1 = Run-Installer $dest @("--enable-vector")
    if ($r1.ExitCode -ne 0) {
      Write-Fail "malformed-mcp-json" "Vector installer exited with code $($r1.ExitCode)"
    } else {
      $mcpPath = Join-Path $dest ".cursor\mcp.json"
      $mcpDir = Split-Path -Parent $mcpPath
      if (!(Test-Path $mcpDir)) { New-Item -ItemType Directory -Force -Path $mcpDir | Out-Null }
      [System.IO.File]::WriteAllText($mcpPath, "{ INVALID JSON !!!", (New-Object System.Text.UTF8Encoding($false)))
      $r2 = Run-Installer $dest @("--enable-vector", "--force")
      $canonicalMcp = Join-Path $dest ".mnemo\mcp\cursor.mcp.json"
      if ($r2.ExitCode -ne 0) {
        Write-Fail "malformed-mcp-json" "Installer crashed with exit code $($r2.ExitCode)"
      } elseif (!(Test-Path $canonicalMcp)) {
        Write-Fail "malformed-mcp-json" "Canonical MCP config was not created"
      } else {
        Write-Pass "malformed-mcp-json"
      }
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "gitignore-dedup") {
  $dest = New-TestDir
  try {
    Run-Installer $dest | Out-Null
    Run-Installer $dest @("--force") | Out-Null
    $giPath = Join-Path $dest ".gitignore"
    $content = Get-Content $giPath -Raw -ErrorAction SilentlyContinue
    $cursorCount = ([regex]::Matches($content, [regex]::Escape(".cursor/memory/memory.sqlite"))).Count
    $mnemoCount = ([regex]::Matches($content, [regex]::Escape(".mnemo/memory/memory.sqlite"))).Count
    if ($cursorCount -gt 1 -or $mnemoCount -gt 1) {
      Write-Fail "gitignore-dedup" "Duplicate managed ignores (cursor=$cursorCount, mnemo=$mnemoCount)"
    } else {
      Write-Pass "gitignore-dedup"
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "version-in-output") {
  $dest = New-TestDir
  try {
    $expectedVersion = (Get-Content (Join-Path $RepoRoot "VERSION") -Raw).Trim()
    Run-Installer $dest | Out-Null
    $journalFiles = Get-ChildItem (Join-Path $dest ".mnemo\memory\journal") -Filter "????-??.md" -ErrorAction SilentlyContinue
    $allOk = $true
    foreach ($jf in $journalFiles) {
      $content = Get-Content $jf.FullName -Raw
      if ($content -notmatch [regex]::Escape("Mnemo v$expectedVersion")) {
        Write-Fail "version-in-output" "Journal $($jf.Name) does not contain 'Mnemo v$expectedVersion'"
        $allOk = $false
        break
      }
    }
    if ($allOk) { Write-Pass "version-in-output" }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "legacy-migration-bridge") {
  $dest = New-TestDir
  try {
    New-Item -ItemType Directory -Force -Path (Join-Path $dest ".cursor\memory"), (Join-Path $dest ".cursor\rules"), (Join-Path $dest ".agent\rules") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dest ".cursor\memory\legacy-note.md"), "# legacy note", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $dest ".cursor\rules\legacy-rule.mdc"), "legacy cursor rule", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $dest ".cursor\rules\legacy-note.md"), "legacy cursor note", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $dest ".agent\rules\legacy-agent.md"), "legacy agent rule", (New-Object System.Text.UTF8Encoding($false)))
    $r = Run-Installer $dest
    if ($r.ExitCode -ne 0) {
      Write-Fail "legacy-migration-bridge" "Installer exited with code $($r.ExitCode)"
    } elseif (!(Test-Path (Join-Path $dest ".mnemo\memory\legacy-note.md"))) {
      Write-Fail "legacy-migration-bridge" "Legacy memory file was not migrated to .mnemo"
    } elseif (!(Test-Path (Join-Path $dest ".mnemo\rules\cursor\legacy-rule.mdc"))) {
      Write-Fail "legacy-migration-bridge" "Legacy cursor rule was not migrated to .mnemo"
    } elseif (!(Test-Path (Join-Path $dest ".mnemo\rules\agent\legacy-agent.md"))) {
      Write-Fail "legacy-migration-bridge" "Legacy agent rule was not migrated to .mnemo"
    } elseif (!(Test-Path (Join-Path $dest ".cursor\memory\legacy-note.md"))) {
      Write-Fail "legacy-migration-bridge" "Legacy memory file is not visible via .cursor bridge"
    } elseif (Test-Path (Join-Path $dest ".cursor\rules\legacy-note.md")) {
      Write-Fail "legacy-migration-bridge" "Non-.mdc file remained inside .cursor\\rules"
    } elseif (Test-Path (Join-Path $dest ".mnemo\rules\cursor\legacy-note.md")) {
      Write-Fail "legacy-migration-bridge" "Non-.mdc file leaked into canonical cursor rules"
    } elseif (!(Test-Path (Join-Path $dest ".mnemo\legacy\cursor-rules-non-mdc\bridge\legacy-note.md"))) {
      Write-Fail "legacy-migration-bridge" "Non-.mdc cursor rule was not preserved in backup"
    } elseif (-not (Test-CursorRulesOnlyMdc $dest)) {
      Write-Fail "legacy-migration-bridge" ".cursor\\rules contains non-.mdc files after install"
    } else {
      Write-Pass "legacy-migration-bridge"
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "bridge-repair-idempotent") {
  $dest = New-TestDir
  try {
    Run-Installer $dest | Out-Null
    $cursorMemory = Join-Path $dest ".cursor\memory"
    if (Test-Path $cursorMemory) {
      Remove-Item -Recurse -Force $cursorMemory -ErrorAction SilentlyContinue
    }
    $r = Run-Installer $dest
    if ($r.ExitCode -ne 0) {
      Write-Fail "bridge-repair-idempotent" "Installer exited with code $($r.ExitCode)"
    } elseif (!(Test-Path (Join-Path $dest ".cursor\memory\hot-rules.md"))) {
      Write-Fail "bridge-repair-idempotent" "Cursor bridge was not repaired after deletion"
    } else {
      Write-Pass "bridge-repair-idempotent"
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "skill-orphan-quarantine") {
  $dest = New-TestDir
  try {
    Run-Installer $dest | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $dest ".cursor\skills\mnemo-codebase-optimizer\drafts"), (Join-Path $dest ".cursor\skills\other-skill") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dest ".cursor\skills\mnemo-codebase-optimizer\notes.md"), "legacy note", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $dest ".cursor\skills\mnemo-codebase-optimizer\drafts\todo.txt"), "todo", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $dest ".cursor\skills\other-skill\keep.txt"), "keep me", (New-Object System.Text.UTF8Encoding($false)))
    $r = Run-Installer $dest
    $quarantineRoot = Join-Path $dest ".mnemo\legacy\skill-orphans\mnemo-codebase-optimizer"
    $quarantineNotes = @(Get-ChildItem -Path $quarantineRoot -Filter "notes.md" -Recurse -ErrorAction SilentlyContinue)
    $quarantineTodo = @(Get-ChildItem -Path $quarantineRoot -Filter "todo.txt" -Recurse -ErrorAction SilentlyContinue)
    if ($r.ExitCode -ne 0) {
      Write-Fail "skill-orphan-quarantine" "Installer exited with code $($r.ExitCode)"
    } elseif (Test-Path (Join-Path $dest ".cursor\skills\mnemo-codebase-optimizer\notes.md")) {
      Write-Fail "skill-orphan-quarantine" "Skill orphan file was not quarantined"
    } elseif (Test-Path (Join-Path $dest ".cursor\skills\mnemo-codebase-optimizer\drafts")) {
      Write-Fail "skill-orphan-quarantine" "Skill orphan directory was not quarantined"
    } elseif ($quarantineNotes.Count -lt 1) {
      Write-Fail "skill-orphan-quarantine" "Quarantine copy for notes.md missing"
    } elseif ($quarantineTodo.Count -lt 1) {
      Write-Fail "skill-orphan-quarantine" "Quarantine copy for drafts\\todo.txt missing"
    } elseif (!(Test-Path (Join-Path $dest ".cursor\skills\other-skill\keep.txt"))) {
      Write-Fail "skill-orphan-quarantine" "Sibling skill was modified"
    } elseif (-not (Test-ManagedSkillDir $dest)) {
      Write-Fail "skill-orphan-quarantine" "Managed skill directory still contains unexpected entries"
    } elseif ($r.Output -notmatch "Moved .*skill orphan") {
      Write-Fail "skill-orphan-quarantine" "Installer did not report quarantined skill orphans"
    } else {
      Write-Pass "skill-orphan-quarantine"
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "skill-orphan-dry-run") {
  $dest = New-TestDir
  try {
    Run-Installer $dest | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $dest ".cursor\skills\mnemo-codebase-optimizer\drafts") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dest ".cursor\skills\mnemo-codebase-optimizer\notes.md"), "legacy note", (New-Object System.Text.UTF8Encoding($false)))
    [System.IO.File]::WriteAllText((Join-Path $dest ".cursor\skills\mnemo-codebase-optimizer\drafts\todo.txt"), "todo", (New-Object System.Text.UTF8Encoding($false)))
    $r = Run-Installer $dest @("--dry-run")
    if ($r.ExitCode -ne 0) {
      Write-Fail "skill-orphan-dry-run" "Installer exited with code $($r.ExitCode)"
    } elseif (!(Test-Path (Join-Path $dest ".cursor\skills\mnemo-codebase-optimizer\notes.md"))) {
      Write-Fail "skill-orphan-dry-run" "Dry-run removed orphan file"
    } elseif (!(Test-Path (Join-Path $dest ".cursor\skills\mnemo-codebase-optimizer\drafts\todo.txt"))) {
      Write-Fail "skill-orphan-dry-run" "Dry-run removed orphan directory contents"
    } elseif (Test-Path (Join-Path $dest ".mnemo\legacy\skill-orphans")) {
      Write-Fail "skill-orphan-dry-run" "Dry-run created quarantine directory"
    } elseif ($r.Output -notmatch "WOULD MOVE .*skill orphan") {
      Write-Fail "skill-orphan-dry-run" "Dry-run did not report skill orphan quarantine"
    } else {
      Write-Pass "skill-orphan-dry-run"
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "vector-autonomy-upgrade") {
  $dest = New-TestDir
  try {
    $autonomyDir = Join-Path $dest "scripts\memory\autonomy"
    New-Item -ItemType Directory -Force -Path $autonomyDir | Out-Null
    foreach ($file in @(
      "__init__.py", "common.py", "schema.py", "runner.py",
      "ingest_pipeline.py", "lifecycle_engine.py", "entity_resolver.py",
      "retrieval_router.py", "reranker.py", "context_safety.py",
      "vault_policy.py", "policies.yaml"
    )) {
      [System.IO.File]::WriteAllText((Join-Path $autonomyDir $file), "", (New-Object System.Text.UTF8Encoding($false)))
    }
    $r = Run-Installer $dest @("--enable-vector")
    if ($r.ExitCode -ne 0) {
      Write-Fail "vector-autonomy-upgrade" "Vector installer exited with code $($r.ExitCode)"
    } elseif (!(Test-Path (Join-Path $autonomyDir "contradiction.py"))) {
      Write-Fail "vector-autonomy-upgrade" "contradiction.py was not installed on upgrade"
    } elseif (!(Test-Path (Join-Path $autonomyDir "token_counter.py"))) {
      Write-Fail "vector-autonomy-upgrade" "token_counter.py was not installed on upgrade"
    } else {
      Write-Pass "vector-autonomy-upgrade"
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "vector-env-from-dotenv") {
  $dest = New-TestDir
  try {
    if (-not (Test-SqliteVecAvailable)) {
      Write-Skip "vector-env-from-dotenv" "python/python3 with sqlite_vec unavailable"
    } else {
      $r = Run-Installer $dest @("--enable-vector", "--vector-provider", "gemini")
      if ($r.ExitCode -ne 0) {
        Write-Fail "vector-env-from-dotenv" "Vector installer exited with code $($r.ExitCode)"
      } else {
        $envPath = Join-Path $dest ".env"
        [System.IO.File]::WriteAllText($envPath, "GEMINI_API_KEY=dotenv-test-key`n", (New-Object System.Text.UTF8Encoding($false)))
        $probePath = Join-Path $dest "scripts\memory\mnemo_env_probe.py"
        $probe = @"
import importlib.util
import os
import pathlib

script_path = pathlib.Path(os.environ["MNEMO_VECTOR_SCRIPT"])
spec = importlib.util.spec_from_file_location("mnemo_vector_test", str(script_path))
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(mod.PROVIDER)
print(os.getenv("GEMINI_API_KEY", ""))
"@
        [System.IO.File]::WriteAllText($probePath, $probe, (New-Object System.Text.UTF8Encoding($false)))
        $oldGemini = $env:GEMINI_API_KEY
        $oldProvider = $env:MNEMO_PROVIDER
        try {
          $env:GEMINI_API_KEY = '${env:GEMINI_API_KEY}'
          Remove-Item Env:MNEMO_PROVIDER -ErrorAction SilentlyContinue
          $env:MNEMO_VECTOR_SCRIPT = (Join-Path $dest "scripts\memory\mnemo_vector.py")
          $lines = @(Invoke-Python $probePath 2>$null | ForEach-Object { $_.ToString().Trim() })
        } finally {
          if ($null -ne $oldGemini) { $env:GEMINI_API_KEY = $oldGemini } else { Remove-Item Env:GEMINI_API_KEY -ErrorAction SilentlyContinue }
          if ($null -ne $oldProvider) { $env:MNEMO_PROVIDER = $oldProvider } else { Remove-Item Env:MNEMO_PROVIDER -ErrorAction SilentlyContinue }
          Remove-Item Env:MNEMO_VECTOR_SCRIPT -ErrorAction SilentlyContinue
        }
        if ($lines.Count -lt 2) {
          Write-Fail "vector-env-from-dotenv" "Could not read provider/env output from mnemo_vector.py"
        } elseif ($lines[0] -ne "gemini") {
          Write-Fail "vector-env-from-dotenv" "Expected provider=gemini from .env fallback, got '$($lines[0])'"
        } elseif ($lines[1] -ne "dotenv-test-key") {
          Write-Fail "vector-env-from-dotenv" "Expected GEMINI_API_KEY from .env fallback, got '$($lines[1])'"
        } else {
          Write-Pass "vector-env-from-dotenv"
        }
      }
    }
  } finally { Remove-TestDir $dest }
}

if (ShouldRun "vector-cli-empty-query") {
  if (-not (Test-SqliteVecAvailable)) {
    Write-Skip "vector-cli-empty-query" "python/python3 with sqlite_vec unavailable"
  } else {
    $dest = New-TestDir
    try {
      Run-Installer $dest @("--enable-vector") | Out-Null
      $vectorPath = Join-Path $dest "scripts\memory\mnemo_vector.py"
      if (!(Test-Path $vectorPath)) {
        Write-Skip "vector-cli-empty-query" "vector install did not produce mnemo_vector.py"
      } else {
        Push-Location $dest
        try {
          $savedEAP = $ErrorActionPreference
          $ErrorActionPreference = "SilentlyContinue"
          try {
            $out = @(Invoke-Python $vectorPath "search" "   " "--top-k" "3" 2>&1)
          } finally {
            $ErrorActionPreference = $savedEAP
          }
        } finally {
          Pop-Location
        }
        $text = ($out -join "`n")
        if ($text -match "provide a search query|please provide") {
          Write-Pass "vector-cli-empty-query"
        } else {
          Write-Fail "vector-cli-empty-query" "Empty query did not return user-friendly message: $text"
        }
      }
    } finally { Remove-TestDir $dest }
  }
}

if (ShouldRun "vector-cli-topk-bounds") {
  if (-not (Test-SqliteVecAvailable)) {
    Write-Skip "vector-cli-topk-bounds" "python/python3 with sqlite_vec unavailable"
  } else {
    $dest = New-TestDir
    try {
      Run-Installer $dest @("--enable-vector") | Out-Null
      $vectorPath = Join-Path $dest "scripts\memory\mnemo_vector.py"
      if (!(Test-Path $vectorPath)) {
        Write-Skip "vector-cli-topk-bounds" "vector install did not produce mnemo_vector.py"
      } else {
        Push-Location $dest
        try {
          $savedEAP = $ErrorActionPreference
          $ErrorActionPreference = "SilentlyContinue"
          try {
            $out = @(Invoke-Python @($vectorPath, "search", "test", "--top-k", "-5") 2>&1)
          } finally {
            $ErrorActionPreference = $savedEAP
          }
        } finally {
          Pop-Location
        }
        $text = ($out -join "`n")
        if ($text -match "error|traceback") {
          Write-Fail "vector-cli-topk-bounds" "Negative top_k caused a crash: $text"
        } else {
          Write-Pass "vector-cli-topk-bounds"
        }
      }
    } finally { Remove-TestDir $dest }
  }
}

Write-Host ""
Write-Host "Results: $passed passed, $failed failed, $skipped skipped" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
if ($failed -gt 0) { exit 1 } else { exit 0 }
