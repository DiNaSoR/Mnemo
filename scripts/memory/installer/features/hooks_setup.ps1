<#
hooks_setup.ps1 - Git hooks setup for Mnemo (pre-commit + optional post-commit vector sync).
Dot-sourced by bootstrap.ps1.
#>

function Install-GitHooks {
  param(
    [Parameter(Mandatory=$true)][hashtable]$Ctx,
    [object]$VectorPython = $null,
    [switch]$EnableVector,
    [switch]$Force
  )

  $hookBody = @'
#!/bin/sh
# Mnemo: auto-rebuild indexes + lint before commit

set -e

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

echo "[Mnemo] Rebuilding indexes + lint..."
if command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -ExecutionPolicy Bypass -File "./scripts/memory/rebuild-memory-index.ps1"
  powershell.exe -ExecutionPolicy Bypass -File "./scripts/memory/lint-memory.ps1"
elif command -v pwsh >/dev/null 2>&1; then
  pwsh -ExecutionPolicy Bypass -File "./scripts/memory/rebuild-memory-index.ps1"
  pwsh -ExecutionPolicy Bypass -File "./scripts/memory/lint-memory.ps1"
else
  echo "[Mnemo] PowerShell not found; skipping memory rebuild/lint."
fi

git add .cursor/memory/lessons/index.md 2>/dev/null || true
git add .cursor/memory/lessons-index.json 2>/dev/null || true
git add .cursor/memory/journal-index.md 2>/dev/null || true
git add .cursor/memory/journal-index.json 2>/dev/null || true
git add .cursor/memory/digests/*.digest.md 2>/dev/null || true

exit 0
'@

  $githookPath = Join-Path $Ctx.PortableHooksDir "pre-commit"
  Write-MnemoFile $githookPath $hookBody -ForceWrite:$Force -LineEndings "LF"

  if (Test-Path $Ctx.GitHooksDir) {
    $legacyHookPath = Join-Path $Ctx.GitHooksDir "pre-commit"
    if ((Test-Path $legacyHookPath) -and (-not $Force)) {
      $existing = Get-Content -Raw -ErrorAction SilentlyContinue $legacyHookPath
      if ($existing -match "Mnemo: auto-rebuild" -or $existing -match "Cursor Memory: auto-rebuild") {
        Write-Host "SKIP (exists): $legacyHookPath" -ForegroundColor DarkYellow
      } else {
        $combined = ($existing.TrimEnd() + "`n`n" + $hookBody)
        Write-MnemoFile $legacyHookPath $combined -ForceWrite:$true -LineEndings "LF"
      }
    } else {
      Write-MnemoFile $legacyHookPath $hookBody -ForceWrite:$Force -LineEndings "LF"
    }
  }

  if ($EnableVector -and (-not $script:DryRun) -and $null -ne $VectorPython) {
    _Install-PostCommitVectorHook -Ctx $Ctx -VectorPython $VectorPython -VectorProvider $VectorProvider -Force:$Force
  } elseif ($EnableVector -and $script:DryRun) {
    Write-Host "[DRY RUN] WOULD CONFIGURE: .githooks/post-commit (MnemoVector wrapper)" -ForegroundColor DarkCyan
  }
}

function _Install-PostCommitVectorHook {
  param(
    [hashtable]$Ctx,
    [object]$VectorPython,
    [string]$VectorProvider,
    [switch]$Force
  )

  $apiGuard = if ($VectorProvider -eq "gemini") {
    '[ -z "${GEMINI_API_KEY:-}" ] && exit 0'
  } else {
    '[ -z "${OPENAI_API_KEY:-}" ] && exit 0'
  }

  $pyHookPath = ($VectorPython.Path -replace '\\', '/')
  $backupName = "post-commit.before-mnemo-vector"
  $postMarker = "Mnemo Vector Hook Wrapper"

  $postHookBody = @"
#!/bin/sh
# Mnemo Vector Hook Wrapper
set -e

ROOT="`$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "`$ROOT" || exit 0

if [ -f ".githooks/$backupName" ]; then
  sh ".githooks/$backupName" || true
fi

$apiGuard

LOCKDIR="`$ROOT/.cursor/memory/.sync.lock"
if [ -d "`$LOCKDIR" ]; then
  NOW=`$(date +%s 2>/dev/null || echo 0)
  MTIME=`$(stat -c %Y "`$LOCKDIR" 2>/dev/null || stat -f %m "`$LOCKDIR" 2>/dev/null || echo 0)
  AGE=`$((NOW - MTIME))
  if [ "`$AGE" -gt 600 ] 2>/dev/null; then
    rmdir "`$LOCKDIR" 2>/dev/null || true
  fi
fi

if mkdir "`$LOCKDIR" 2>/dev/null; then
  trap 'rmdir "`$LOCKDIR" 2>/dev/null || true' EXIT INT TERM
  "$pyHookPath" -c "import sys; sys.path.insert(0, 'scripts/memory'); from mnemo_vector import vector_sync; print('[MnemoVector]', vector_sync())" 2>&1 | tail -1 || true
fi

exit 0
"@

  $postHookPath = Join-Path $Ctx.PortableHooksDir "post-commit"
  $backupPath = Join-Path $Ctx.PortableHooksDir $backupName

  if (Test-Path $postHookPath) {
    $existingPost = Get-Content -Raw -ErrorAction SilentlyContinue $postHookPath
    if ($existingPost -and $existingPost -notmatch [regex]::Escape($postMarker)) {
      if (!(Test-Path $backupPath) -or $Force) {
        [System.IO.File]::WriteAllText($backupPath, $existingPost, (New-Object System.Text.UTF8Encoding $false))
      }
    }
  }

  Write-MnemoFile $postHookPath $postHookBody -ForceWrite:$Force -LineEndings "LF"

  if (Test-Path $Ctx.GitHooksDir) {
    $legacyPost = Join-Path $Ctx.GitHooksDir "post-commit"
    if ((Test-Path $legacyPost) -and (-not $Force)) {
      $legacyExisting = Get-Content -Raw -ErrorAction SilentlyContinue $legacyPost
      if ($legacyExisting -and $legacyExisting -notmatch [regex]::Escape($postMarker)) {
        Write-Host "SKIP (legacy post-commit exists): $legacyPost" -ForegroundColor DarkYellow
      } else {
        Write-MnemoFile $legacyPost $postHookBody -ForceWrite:$Force -LineEndings "LF"
      }
    } else {
      Write-MnemoFile $legacyPost $postHookBody -ForceWrite:$Force -LineEndings "LF"
    }
  }
}
