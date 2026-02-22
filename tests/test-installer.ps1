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
    $allOk = $true
    foreach ($d in $expectedDirs) {
      if (!(Test-Path (Join-Path $dest $d))) {
        Write-Fail "scratch" "Missing directory: $d"
        $allOk = $false
        break
      }
    }
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
      "scripts\memory\lint-memory.ps1"
    )
    foreach ($f in $expectedFiles) {
      if (!(Test-Path (Join-Path $dest $f))) {
        Write-Fail "scratch" "Missing file: $f"
        $allOk = $false
        break
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

# ─── TEST: vector-env-from-dotenv ──────────────────────────────────────────────
if (ShouldRun "vector-env-from-dotenv") {
  $dest = New-TestDir
  try {
    $r = Run-Installer $dest @("-EnableVector", "-VectorProvider", "gemini")
    if ($r.ExitCode -ne 0) {
      Write-Skip "vector-env-from-dotenv" "vector bootstrap unavailable in this runtime"
    } else {
      $envPath = Join-Path $dest ".env"
      [System.IO.File]::WriteAllText(
        $envPath,
        "GEMINI_API_KEY=dotenv-test-key`n",
        (New-Object System.Text.UTF8Encoding($false))
      )

      $probePath = Join-Path $dest "scripts\memory\mnemo_env_probe.py"
      $py = @"
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
      [System.IO.File]::WriteAllText($probePath, $py, (New-Object System.Text.UTF8Encoding($false)))

      $oldGemini = $env:GEMINI_API_KEY
      $oldProvider = $env:MNEMO_PROVIDER
      try {
        # Simulate unresolved placeholder arriving from MCP env wiring.
        $env:GEMINI_API_KEY = '${env:GEMINI_API_KEY}'
        Remove-Item Env:MNEMO_PROVIDER -ErrorAction SilentlyContinue
        $env:MNEMO_VECTOR_SCRIPT = (Join-Path $dest "scripts\memory\mnemo_vector.py")
        $lines = (& python $probePath 2>$null | ForEach-Object { $_.ToString().Trim() })
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
    } elseif (!(Test-Path (Join-Path $dest ".mnemo\memory\hot-rules.md"))) {
      Write-Fail "path-with-spaces" "Expected canonical files not created in spaced path"
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
    # First do a clean install so canonical + bridge dirs exist
    Run-Installer $dest | Out-Null
    # Write a corrupt mcp.json
    $mcpPath = Join-Path $dest ".cursor\mcp.json"
    [System.IO.File]::WriteAllText($mcpPath, "{ INVALID JSON !!!", [System.Text.Encoding]::UTF8)
    # Re-run (no vector required): bridge repair should not crash
    $r = Run-Installer $dest @("-Force")
    $canonicalMcp = Join-Path $dest ".mnemo\mcp\cursor.mcp.json"
    if ($r.ExitCode -ne 0) {
      Write-Fail "malformed-mcp-json" "Installer crashed with exit code $($r.ExitCode) on malformed mcp.json"
    } elseif (!(Test-Path $canonicalMcp)) {
      Write-Fail "malformed-mcp-json" "Canonical MCP bridge target was not created"
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
    $cursorCount = ([regex]::Matches($content, [regex]::Escape(".cursor/memory/memory.sqlite"))).Count
    $mnemoCount = ([regex]::Matches($content, [regex]::Escape(".mnemo/memory/memory.sqlite"))).Count
    if ($cursorCount -gt 1 -or $mnemoCount -gt 1) {
      Write-Fail "gitignore-dedup" "Duplicate managed ignores (cursor=$cursorCount, mnemo=$mnemoCount)"
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

# ─── TEST: legacy-migration-bridge ────────────────────────────────────────────
if (ShouldRun "legacy-migration-bridge") {
  $dest = New-TestDir
  try {
    New-Item -ItemType Directory -Force -Path (Join-Path $dest ".cursor\memory"), (Join-Path $dest ".cursor\rules"), (Join-Path $dest ".agent\rules") | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $dest ".cursor\memory\legacy-note.md"), "# legacy note", [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $dest ".cursor\rules\legacy-rule.mdc"), "legacy cursor rule", [System.Text.Encoding]::UTF8)
    [System.IO.File]::WriteAllText((Join-Path $dest ".agent\rules\legacy-agent.md"), "legacy agent rule", [System.Text.Encoding]::UTF8)

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
    } else {
      Write-Pass "legacy-migration-bridge"
    }
  } finally { Remove-TestDir $dest }
}

# ─── TEST: bridge-repair-idempotent ───────────────────────────────────────────
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

# ─── Summary ─────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "Results: $passed passed, $failed failed, $skipped skipped" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })

if ($failed -gt 0) { exit 1 } else { exit 0 }
