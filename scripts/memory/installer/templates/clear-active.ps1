<#
clear-active.ps1
Resets active-context.md to blank template.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($PSScriptRoot) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..\..")).Path
} else {
  $RepoRoot = (Get-Location).Path
}

function Resolve-MnemoMemoryDir([string]$Root) {
  $candidates = @(
    (Join-Path $Root ".mnemo\memory"),
    (Join-Path $Root ".cursor\memory")
  )
  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) { return $candidate }
  }
  return $candidates[0]
}

$ActivePath = Join-Path (Resolve-MnemoMemoryDir -Root $RepoRoot) "active-context.md"

$Template = @"
# Active Context (Session Scratchpad)

Priority: this overrides older journal history *for this session only*.

CLEAR this file when the task is done:
- Run ``scripts/memory/clear-active.sh`` or ``scripts/memory/clear-active.ps1``

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

$enc = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ActivePath, ($Template -replace "`r?`n", "`r`n"), $enc)

Write-Host "Cleared: $ActivePath" -ForegroundColor Green
