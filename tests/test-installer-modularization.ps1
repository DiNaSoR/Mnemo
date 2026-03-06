<#
test-installer-modularization.ps1
Guardrails for the unified Node.js Mnemo installer.

USAGE:
  powershell -ExecutionPolicy Bypass -File .\tests\test-installer-modularization.ps1
#>

[CmdletBinding()]
param(
  [string]$CliPath = "",
  [string]$InstallerIndexPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($CliPath)) {
  $CliPath = Join-Path $RepoRoot "bin\mnemo.js"
}
if ([string]::IsNullOrWhiteSpace($InstallerIndexPath)) {
  $InstallerIndexPath = Join-Path $RepoRoot "bin\installer\index.js"
}

$passed = 0
$failed = 0

function Write-Pass([string]$name) {
  Write-Host "  PASS  $name" -ForegroundColor Green
  $script:passed++
}

function Write-Fail([string]$name, [string]$reason) {
  Write-Host "  FAIL  $name : $reason" -ForegroundColor Red
  $script:failed++
}

function New-TestDir() {
  $path = Join-Path $env:TEMP "mnemo-modtest-$([System.IO.Path]::GetRandomFileName())"
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  return $path
}

function Remove-TestDir([string]$path) {
  if (Test-Path $path) {
    Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue
  }
}

function Normalize-Text([string]$Path) {
  return ((Get-Content $Path -Raw) -replace "`r?`n", "`n").Trim()
}

Write-Host "Mnemo modularization guardrail tests" -ForegroundColor Cyan
Write-Host "CLI: $CliPath" -ForegroundColor Gray
Write-Host "Installer index: $InstallerIndexPath" -ForegroundColor Gray
Write-Host ""

$cliLoc = (Get-Content $CliPath).Count
if ($cliLoc -gt 700) {
  Write-Fail "cli-loc-hard" "bin/mnemo.js has $cliLoc lines (hard limit is 700)"
} elseif ($cliLoc -gt 600) {
  Write-Fail "cli-loc-soft" "bin/mnemo.js has $cliLoc lines (soft target is 600)"
} else {
  Write-Pass "cli-loc"
}

$installerLoc = (Get-Content $InstallerIndexPath).Count
if ($installerLoc -gt 250) {
  Write-Fail "installer-index-loc" "bin/installer/index.js has $installerLoc lines (hard limit is 250)"
} else {
  Write-Pass "installer-index-loc"
}

$expectedModules = @(
  "bin\mnemo.js",
  "bin\installer\index.js",
  "bin\installer\core\bridge.js",
  "bin\installer\core\paths.js",
  "bin\installer\core\template.js",
  "bin\installer\core\writer.js",
  "bin\installer\features\bridges.js",
  "bin\installer\features\gitHooks.js",
  "bin\installer\features\gitignore.js",
  "bin\installer\features\helperScripts.js",
  "bin\installer\features\legacyMigration.js",
  "bin\installer\features\mcpConfig.js",
  "bin\installer\features\scaffold.js",
  "bin\installer\features\vectorSetup.js"
)
$allOk = $true
foreach ($m in $expectedModules) {
  if (-not (Test-Path (Join-Path $RepoRoot $m))) {
    Write-Fail "module-files-present" "Missing module: $m"
    $allOk = $false
    break
  }
}
if ($allOk) { Write-Pass "module-files-present" }

$expectedTemplates = @(
  "scripts\memory\installer\templates\add-journal-entry.ps1",
  "scripts\memory\installer\templates\add-journal-entry.sh",
  "scripts\memory\installer\templates\add-lesson.ps1",
  "scripts\memory\installer\templates\add-lesson.sh",
  "scripts\memory\installer\templates\build-memory-sqlite.py",
  "scripts\memory\installer\templates\clear-active.ps1",
  "scripts\memory\installer\templates\clear-active.sh",
  "scripts\memory\installer\templates\customization.md",
  "scripts\memory\installer\templates\lint-memory.ps1",
  "scripts\memory\installer\templates\lint-memory.sh",
  "scripts\memory\installer\templates\mnemo_vector.py",
  "scripts\memory\installer\templates\query-memory-sqlite.py",
  "scripts\memory\installer\templates\query-memory.ps1",
  "scripts\memory\installer\templates\query-memory.sh",
  "scripts\memory\installer\templates\rebuild-memory-index.ps1",
  "scripts\memory\installer\templates\rebuild-memory-index.sh",
  "scripts\memory\installer\templates\content\memo.md.tmpl",
  "scripts\memory\installer\templates\content\journal-entry.md.tmpl",
  "scripts\memory\installer\templates\hooks\pre-commit.sh",
  "scripts\memory\installer\templates\hooks\post-commit-vector.sh.tmpl",
  "scripts\memory\installer\templates\rules\00-memory-system.mdc.tmpl",
  "scripts\memory\installer\templates\rules\01-vector-search.mdc.tmpl",
  "scripts\memory\installer\templates\skills\mnemo-codebase-optimizer\SKILL.md",
  "scripts\memory\installer\templates\skills\mnemo-codebase-optimizer\reference.md",
  "scripts\memory\installer\templates\autonomy\contradiction.py",
  "scripts\memory\installer\templates\autonomy\token_counter.py"
)
$allOk = $true
foreach ($t in $expectedTemplates) {
  if (-not (Test-Path (Join-Path $RepoRoot $t))) {
    Write-Fail "template-files-present" "Missing template: $t"
    $allOk = $false
    break
  }
}
if ($allOk) { Write-Pass "template-files-present" }

$dest = New-TestDir
try {
  $savedEAP = $ErrorActionPreference
  $ErrorActionPreference = "SilentlyContinue"
  try {
    $installOut = & node $CliPath --yes --repo-root $dest --project-name ModTest 2>&1
    $installEc = $LASTEXITCODE
  } finally {
    $ErrorActionPreference = $savedEAP
  }

  if ($installEc -ne 0) {
    Write-Fail "installed-scripts-match-templates" "Installer failed: $($installOut -join ' ')"
  } else {
    $checks = @(
      @{ Template = "add-journal-entry.ps1"; Installed = "scripts\memory\add-journal-entry.ps1" },
      @{ Template = "add-journal-entry.sh"; Installed = "scripts\memory\add-journal-entry.sh" },
      @{ Template = "add-lesson.ps1"; Installed = "scripts\memory\add-lesson.ps1" },
      @{ Template = "add-lesson.sh"; Installed = "scripts\memory\add-lesson.sh" },
      @{ Template = "clear-active.ps1"; Installed = "scripts\memory\clear-active.ps1" },
      @{ Template = "clear-active.sh"; Installed = "scripts\memory\clear-active.sh" },
      @{ Template = "lint-memory.ps1"; Installed = "scripts\memory\lint-memory.ps1" },
      @{ Template = "lint-memory.sh"; Installed = "scripts\memory\lint-memory.sh" },
      @{ Template = "query-memory.ps1"; Installed = "scripts\memory\query-memory.ps1" },
      @{ Template = "query-memory.sh"; Installed = "scripts\memory\query-memory.sh" },
      @{ Template = "rebuild-memory-index.ps1"; Installed = "scripts\memory\rebuild-memory-index.ps1" },
      @{ Template = "rebuild-memory-index.sh"; Installed = "scripts\memory\rebuild-memory-index.sh" },
      @{ Template = "customization.md"; Installed = "scripts\memory\customization.md" },
      @{ Template = "skills\mnemo-codebase-optimizer\SKILL.md"; Installed = ".cursor\skills\mnemo-codebase-optimizer\SKILL.md" },
      @{ Template = "skills\mnemo-codebase-optimizer\reference.md"; Installed = ".cursor\skills\mnemo-codebase-optimizer\reference.md" }
    )

    $allOk = $true
    foreach ($c in $checks) {
      $tplPath = Join-Path $RepoRoot "scripts\memory\installer\templates\$($c.Template)"
      $instPath = Join-Path $dest $c.Installed
      if (-not (Test-Path $instPath)) {
        Write-Fail "installed-scripts-match-templates" "Installed file missing: $($c.Installed)"
        $allOk = $false
        break
      }
      if ((Normalize-Text $tplPath) -ne (Normalize-Text $instPath)) {
        Write-Fail "installed-scripts-match-templates" "Content mismatch: $($c.Template) vs installed $($c.Installed)"
        $allOk = $false
        break
      }
    }
    if ($allOk) {
      $installedSkillDir = Join-Path $dest ".cursor\skills\mnemo-codebase-optimizer"
      $installedSkillEntries = @(
        Get-ChildItem -Path $installedSkillDir -Force -ErrorAction SilentlyContinue |
          ForEach-Object { $_.Name } |
          Sort-Object
      )
      if (($installedSkillEntries -join ",") -ne "reference.md,SKILL.md") {
        Write-Fail "installed-scripts-match-templates" "Installed skill directory contains unexpected entries: $($installedSkillEntries -join ', ')"
      } else {
      $hookTemplate = Join-Path $RepoRoot "scripts\memory\installer\templates\hooks\pre-commit.sh"
      $hookInstalled = Join-Path $dest ".githooks\pre-commit"
      if (-not (Test-Path $hookInstalled)) {
        Write-Fail "installed-scripts-match-templates" "Installed git hook missing: .githooks\pre-commit"
      } elseif ((Normalize-Text $hookTemplate) -ne (Normalize-Text $hookInstalled)) {
        Write-Fail "installed-scripts-match-templates" "Content mismatch: hooks\pre-commit.sh vs installed .githooks\pre-commit"
      } else {
        Write-Pass "installed-scripts-match-templates"
      }
      }
    }
  }
} finally {
  Remove-TestDir $dest
}

$savedEAP = $ErrorActionPreference
$ErrorActionPreference = "SilentlyContinue"
try {
  $packOut = & npm pack --dry-run --json 2>&1
  $packEc = $LASTEXITCODE
} finally {
  $ErrorActionPreference = $savedEAP
}
if ($packEc -ne 0) {
  Write-Fail "npm-pack-includes-required-templates" "npm pack --dry-run failed"
} else {
  $packJson = ($packOut | ForEach-Object { $_.ToString() }) -join "`n"
  $packData = ConvertFrom-Json $packJson
  $packPaths = @($packData[0].files | ForEach-Object { $_.path })
  $requiredPackEntries = @(
    "scripts/memory/installer/templates/add-journal-entry.sh",
    "scripts/memory/installer/templates/add-lesson.sh",
    "scripts/memory/installer/templates/clear-active.sh",
    "scripts/memory/installer/templates/lint-memory.sh",
    "scripts/memory/installer/templates/query-memory.sh",
    "scripts/memory/installer/templates/rebuild-memory-index.sh",
    "scripts/memory/installer/templates/content/memo.md.tmpl",
    "scripts/memory/installer/templates/content/journal-entry.md.tmpl",
    "scripts/memory/installer/templates/hooks/pre-commit.sh",
    "scripts/memory/installer/templates/hooks/post-commit-vector.sh.tmpl",
    "scripts/memory/installer/templates/rules/00-memory-system.mdc.tmpl",
    "scripts/memory/installer/templates/rules/01-vector-search.mdc.tmpl",
    "scripts/memory/installer/templates/skills/mnemo-codebase-optimizer/SKILL.md",
    "scripts/memory/installer/templates/skills/mnemo-codebase-optimizer/reference.md",
    "scripts/memory/installer/templates/autonomy/contradiction.py",
    "scripts/memory/installer/templates/autonomy/token_counter.py"
  )
  $missing = @($requiredPackEntries | Where-Object { $_ -notin $packPaths })
  $junk = @($packPaths | Where-Object { $_ -like "*__pycache__*" -or $_ -like "*.pyc" })
  $skillPackEntries = @($packPaths | Where-Object { $_ -like "scripts/memory/installer/templates/skills/mnemo-codebase-optimizer/*" })
  $unexpectedSkillEntries = @($skillPackEntries | Where-Object {
    $_ -notin @(
      "scripts/memory/installer/templates/skills/mnemo-codebase-optimizer/SKILL.md",
      "scripts/memory/installer/templates/skills/mnemo-codebase-optimizer/reference.md"
    )
  })
  if ($missing.Count -gt 0) {
    Write-Fail "npm-pack-includes-required-templates" "Packed artifact is missing: $($missing -join ', ')"
  } elseif ($junk.Count -gt 0) {
    Write-Fail "npm-pack-includes-required-templates" "Packed artifact unexpectedly includes cache files: $($junk -join ', ')"
  } elseif ($unexpectedSkillEntries.Count -gt 0) {
    Write-Fail "npm-pack-includes-required-templates" "Packed artifact unexpectedly includes stale skill entries: $($unexpectedSkillEntries -join ', ')"
  } else {
    Write-Pass "npm-pack-includes-required-templates"
  }
}

Write-Host ""
Write-Host "Results: $passed passed, $failed failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
if ($failed -gt 0) { exit 1 } else { exit 0 }
