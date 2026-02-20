<#
test-installer.ps1
Regression tests for memory.ps1 (Windows installer).

USAGE:
  powershell -ExecutionPolicy Bypass -File .\tests\test-installer.ps1
  powershell -ExecutionPolicy Bypass -File .\tests\test-installer.ps1 -TestName dry-run
#>

[CmdletBinding()]
param(
  [string]$TestName = "",
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

function New-TestDir([string]$suffix = "") {
  $base = Join-Path $env:TEMP "mnemo-test-$([System.IO.Path]::GetRandomFileName())$suffix"
  New-Item -ItemType Directory -Force -Path $base | Out-Null
  return $base
}

function Remove-TestDir([string]$path) {
  if (Test-Path $path) { Remove-Item -Recurse -Force $path -ErrorAction SilentlyContinue }
}

function Run-Installer([string]$dest, [string[]]$extraArgs = @()) {
  $args = @("-ExecutionPolicy", "Bypass", "-File", $InstallerPath, "-RepoRoot", $dest, "-ProjectName", "TestProject") + $extraArgs
  $result = & powershell @args 2>&1
  return @{ Output = ($result -join "`n"); ExitCode = $LASTEXITCODE }
}

function ShouldRun([string]$name) {
  return ([string]::IsNullOrWhiteSpace($TestName) -or $TestName -eq $name)
}

Write-Host "Mnemo installer regression tests (Windows)" -ForegroundColor Cyan
Write-Host "Installer: $InstallerPath" -ForegroundColor Gray
Write-Host ""

# ─── TEST: scratch ────────────────────────────────────────────────────────────
if (ShouldRun "scratch") {
  $dest = New-TestDir
  try {
    $r = Run-Installer $dest
    $expectedDirs = @("\.cursor\memory", "\.cursor\rules", "\.cursor\memory\lessons", "\.cursor\memory\journal", "\.cursor\memory\templates", "scripts\memory")
    $allOk = $true
    foreach ($d in $expectedDirs) {
      if (!(Test-Path (Join-Path $dest $d))) {
        Write-Fail "scratch" "Missing directory: $d"
        $allOk = $false
        break
      }
    }
    $expectedFiles = @("\.cursor\memory\hot-rules.md", "\.cursor\memory\memo.md", "\.cursor\memory\active-context.md", "\.cursor\rules\00-memory-system.mdc", "scripts\memory\lint-memory.ps1")
    foreach ($f in $expectedFiles) {
      if (!(Test-Path (Join-Path $dest $f))) {
        Write-Fail "scratch" "Missing file: $f"
        $allOk = $false
        break
      }
    }
    if ($allOk) { Write-Pass "scratch" }
  } finally { Remove-TestDir $dest }
}

# ─── TEST: idempotent-no-force ────────────────────────────────────────────────
if (ShouldRun "idempotent-no-force") {
  $dest = New-TestDir
  try {
    Run-Installer $dest | Out-Null
    $r = Run-Installer $dest
    if ($r.Output -match "(?m)^WROTE:") {
      Write-Fail "idempotent-no-force" "Installer wrote files on second run without -Force"
    } else {
      Write-Pass "idempotent-no-force"
    }
  } finally { Remove-TestDir $dest }
}

# ─── TEST: idempotent-vector-no-force ─────────────────────────────────────────
if (ShouldRun "idempotent-vector-no-force") {
  $dest = New-TestDir
  try {
    $r1 = Run-Installer $dest @("-EnableVector")
    $r2 = Run-Installer $dest @("-EnableVector")
    if ($r1.ExitCode -ne 0 -or $r2.ExitCode -ne 0) {
      Write-Fail "idempotent-vector-no-force" "Vector installer run failed (exit1=$($r1.ExitCode), exit2=$($r2.ExitCode))"
    } elseif ($r2.Output -match "(?m)^WROTE:") {
      Write-Fail "idempotent-vector-no-force" "Vector installer wrote files on second run without -Force"
    } else {
      Write-Pass "idempotent-vector-no-force"
    }
  } finally { Remove-TestDir $dest }
}

# ─── TEST: idempotent-force ───────────────────────────────────────────────────
if (ShouldRun "idempotent-force") {
  $dest = New-TestDir
  try {
    Run-Installer $dest | Out-Null
    $r = Run-Installer $dest @("-Force")
    if ($r.Output -notmatch "(?m)^WROTE:") {
      Write-Fail "idempotent-force" "-Force had no effect; no files were written"
    } else {
      Write-Pass "idempotent-force"
    }
  } finally { Remove-TestDir $dest }
}

# ─── TEST: dry-run ────────────────────────────────────────────────────────────
if (ShouldRun "dry-run") {
  $dest = New-TestDir
  try {
    Run-Installer $dest @("-DryRun") | Out-Null
    $files = Get-ChildItem -Recurse -File $dest -ErrorAction SilentlyContinue
    if ($files) {
      Write-Fail "dry-run" "Dry-run created $($files.Count) file(s): $($files.Name -join ', ')"
    } else {
      Write-Pass "dry-run"
    }
  } finally { Remove-TestDir $dest }
}

# ─── TEST: dry-run-vector ─────────────────────────────────────────────────────
if (ShouldRun "dry-run-vector") {
  $dest = New-TestDir
  try {
    $r = Run-Installer $dest @("-DryRun", "-EnableVector")
    $files = Get-ChildItem -Recurse -File $dest -ErrorAction SilentlyContinue
    if ($r.ExitCode -ne 0) {
      Write-Fail "dry-run-vector" "Installer exited with code $($r.ExitCode)"
    } elseif ($r.Output -match "Installing vector dependencies") {
      Write-Fail "dry-run-vector" "Dry-run unexpectedly attempted vector dependency installation"
    } elseif ($files) {
      Write-Fail "dry-run-vector" "Dry-run with vector created $($files.Count) file(s): $($files.Name -join ', ')"
    } else {
      Write-Pass "dry-run-vector"
    }
  } finally { Remove-TestDir $dest }
}

# ─── TEST: path-with-spaces ───────────────────────────────────────────────────
if (ShouldRun "path-with-spaces") {
  $dest = New-TestDir " with spaces"
  try {
    $r = Run-Installer $dest
    if ($r.ExitCode -ne 0) {
      Write-Fail "path-with-spaces" "Installer exited with code $($r.ExitCode)"
    } elseif (!(Test-Path (Join-Path $dest ".cursor\memory\hot-rules.md"))) {
      Write-Fail "path-with-spaces" "Expected files not created in spaced path"
    } else {
      Write-Pass "path-with-spaces"
    }
  } finally { Remove-TestDir $dest }
}

# ─── TEST: malformed-mcp-json ─────────────────────────────────────────────────
if (ShouldRun "malformed-mcp-json") {
  $dest = New-TestDir
  try {
    # First do a clean install so .cursor dir exists
    Run-Installer $dest | Out-Null
    # Write a corrupt mcp.json
    $mcpPath = Join-Path $dest ".cursor\mcp.json"
    [System.IO.File]::WriteAllText($mcpPath, "{ INVALID JSON !!!", [System.Text.Encoding]::UTF8)
    # Run with EnableVector — installer should recover rather than crash
    $r = Run-Installer $dest @("-Force")
    # The run itself should succeed (exit 0) even if mcp.json parse warned
    if ($r.ExitCode -ne 0) {
      Write-Fail "malformed-mcp-json" "Installer crashed with exit code $($r.ExitCode) on malformed mcp.json"
    } else {
      Write-Pass "malformed-mcp-json"
    }
  } finally { Remove-TestDir $dest }
}

# ─── TEST: rebuild-lint ───────────────────────────────────────────────────────
if (ShouldRun "rebuild-lint") {
  $dest = New-TestDir
  try {
    Run-Installer $dest | Out-Null
    $rebuildArgs = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $dest "scripts\memory\rebuild-memory-index.ps1"), "-RepoRoot", $dest)
    $r1 = & powershell @rebuildArgs 2>&1
    $lintArgs = @("-ExecutionPolicy", "Bypass", "-File", (Join-Path $dest "scripts\memory\lint-memory.ps1"), "-RepoRoot", $dest)
    $r2 = & powershell @lintArgs 2>&1
    if ($LASTEXITCODE -ne 0) {
      Write-Fail "rebuild-lint" "lint-memory.ps1 failed: $($r2 -join ' ')"
    } else {
      Write-Pass "rebuild-lint"
    }
  } finally { Remove-TestDir $dest }
}

# ─── TEST: gitignore-dedup ────────────────────────────────────────────────────
if (ShouldRun "gitignore-dedup") {
  $dest = New-TestDir
  try {
    Run-Installer $dest | Out-Null
    Run-Installer $dest @("-Force") | Out-Null
    $giPath = Join-Path $dest ".gitignore"
    $content = Get-Content $giPath -Raw -ErrorAction SilentlyContinue
    $count = ([regex]::Matches($content, [regex]::Escape(".cursor/memory/memory.sqlite"))).Count
    if ($count -gt 1) {
      Write-Fail "gitignore-dedup" ".cursor/memory/memory.sqlite appears $count times in .gitignore"
    } else {
      Write-Pass "gitignore-dedup"
    }
  } finally { Remove-TestDir $dest }
}

# ─── TEST: version-in-output ─────────────────────────────────────────────────
if (ShouldRun "version-in-output") {
  $dest = New-TestDir
  try {
    $expectedVersion = (Get-Content (Join-Path $RepoRoot "VERSION") -Raw).Trim()
    Run-Installer $dest | Out-Null
    # Only check monthly journal files (YYYY-MM.md), not README.md
    $journalFiles = Get-ChildItem (Join-Path $dest ".cursor\memory\journal") -Filter "????-??.md" -ErrorAction SilentlyContinue
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

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Results: $passed passed, $failed failed, $skipped skipped" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })

if ($failed -gt 0) { exit 1 } else { exit 0 }
