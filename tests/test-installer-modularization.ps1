<#
test-installer-modularization.ps1
Validates that memory.ps1 stays within LOC limits (anti-monolith guardrails)
and that all expected module and template files are present.

USAGE:
  powershell -ExecutionPolicy Bypass -File .\tests\test-installer-modularization.ps1
#>

[CmdletBinding()]
param(
  [string]$InstallerPath = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($InstallerPath)) {
  $InstallerPath = Join-Path $RepoRoot "memory.ps1"
}

$passed = 0
$failed = 0

function Write-Pass([string]$name) { Write-Host "  PASS  $name" -ForegroundColor Green; $script:passed++ }
function Write-Fail([string]$name, [string]$reason) { Write-Host "  FAIL  $name : $reason" -ForegroundColor Red; $script:failed++ }

Write-Host "Mnemo modularization guardrail tests" -ForegroundColor Cyan
Write-Host "Installer: $InstallerPath" -ForegroundColor Gray
Write-Host ""

# ─── TEST: memory-ps1-loc-soft ──────────────────────────────────────────────
$locCount = (Get-Content $InstallerPath -ErrorAction SilentlyContinue).Count
if ($locCount -gt 500) {
  Write-Fail "memory-ps1-loc-hard" "memory.ps1 has $locCount lines (HARD limit is 500)"
} elseif ($locCount -gt 400) {
  Write-Fail "memory-ps1-loc-soft" "memory.ps1 has $locCount lines (soft target is 400)"
} else {
  Write-Pass "memory-ps1-loc"
}

# ─── TEST: no-large-heredoc-in-entrypoint ────────────────────────────────────
$content = Get-Content $InstallerPath -Raw -ErrorAction SilentlyContinue
$heredocCount = ([regex]::Matches($content, "@'[\s\S]{400,}'@")).Count
if ($heredocCount -gt 0) {
  Write-Fail "no-large-heredoc-in-entrypoint" "Found $heredocCount large single-quote heredoc(s) (>400 chars) in memory.ps1 - move to templates/"
} else {
  Write-Pass "no-large-heredoc-in-entrypoint"
}

# ─── TEST: module-files-present ──────────────────────────────────────────────
$expectedModules = @(
  "scripts\memory\installer\bootstrap.ps1",
  "scripts\memory\installer\core\io.ps1",
  "scripts\memory\installer\core\paths.ps1",
  "scripts\memory\installer\core\bridge.ps1",
  "scripts\memory\installer\features\memory_scaffold.ps1",
  "scripts\memory\installer\features\vector_setup.ps1",
  "scripts\memory\installer\features\mcp_setup.ps1",
  "scripts\memory\installer\features\hooks_setup.ps1",
  "scripts\memory\installer\features\gitignore_setup.ps1"
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

# ─── TEST: template-files-present ────────────────────────────────────────────
$expectedTemplates = @(
  "scripts\memory\installer\templates\rebuild-memory-index.ps1",
  "scripts\memory\installer\templates\lint-memory.ps1",
  "scripts\memory\installer\templates\query-memory.ps1",
  "scripts\memory\installer\templates\build-memory-sqlite.py",
  "scripts\memory\installer\templates\query-memory-sqlite.py",
  "scripts\memory\installer\templates\mnemo_vector.py",
  "scripts\memory\installer\templates\clear-active.ps1",
  "scripts\memory\installer\templates\add-lesson.ps1",
  "scripts\memory\installer\templates\add-journal-entry.ps1",
  "scripts\memory\installer\templates\customization.md"
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

# ─── TEST: entrypoint-uses-bootstrap ─────────────────────────────────────────
if ($content -match [regex]::Escape("bootstrap.ps1")) {
  Write-Pass "entrypoint-uses-bootstrap"
} else {
  Write-Fail "entrypoint-uses-bootstrap" "memory.ps1 does not dot-source bootstrap.ps1"
}

# ─── TEST: installed-scripts-match-templates ─────────────────────────────────
# Verify that scratch install copies template content correctly
$dest = Join-Path $env:TEMP "mnemo-modtest-$([System.IO.Path]::GetRandomFileName())"
try {
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $args = @("-ExecutionPolicy", "Bypass", "-File", $InstallerPath, "-RepoRoot", $dest, "-ProjectName", "ModTest")
  & powershell @args 2>&1 | Out-Null

  $checks = @(
    @{ Template = "rebuild-memory-index.ps1"; Installed = "scripts\memory\rebuild-memory-index.ps1" },
    @{ Template = "lint-memory.ps1";          Installed = "scripts\memory\lint-memory.ps1" },
    @{ Template = "query-memory.ps1";         Installed = "scripts\memory\query-memory.ps1" },
    @{ Template = "add-lesson.ps1";           Installed = "scripts\memory\add-lesson.ps1" }
  )

  $allOk = $true
  foreach ($c in $checks) {
    $tplPath = Join-Path $RepoRoot "scripts\memory\installer\templates\$($c.Template)"
    $instPath = Join-Path $dest $c.Installed
    if (-not (Test-Path $instPath)) {
      Write-Fail "installed-scripts-match-templates" "Installed file missing: $($c.Installed)"
      $allOk = $false; break
    }
    $tplContent  = (Get-Content $tplPath -Raw).Trim() -replace "`r?`n", "`n"
    $instContent = (Get-Content $instPath -Raw).Trim() -replace "`r?`n", "`n"
    if ($tplContent -ne $instContent) {
      Write-Fail "installed-scripts-match-templates" "Content mismatch: $($c.Template) vs installed $($c.Installed)"
      $allOk = $false; break
    }
  }
  if ($allOk) { Write-Pass "installed-scripts-match-templates" }
} finally {
  if (Test-Path $dest) { Remove-Item -Recurse -Force $dest -ErrorAction SilentlyContinue }
}

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Results: $passed passed, $failed failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
if ($failed -gt 0) { exit 1 } else { exit 0 }
