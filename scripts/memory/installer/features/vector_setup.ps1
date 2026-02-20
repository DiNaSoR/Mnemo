<#
vector_setup.ps1 - Vector engine installation and dependency management.
Dot-sourced by bootstrap.ps1.
#>

function Resolve-VectorPython {
  $candidates = @(
    @{ Kind = "python";  Args = @() },
    @{ Kind = "py";      Args = @("-3") },
    @{ Kind = "py";      Args = @() },
    @{ Kind = "python3"; Args = @() }
  )
  foreach ($c in $candidates) {
    $cmd = Get-Command $c.Kind -ErrorAction SilentlyContinue
    if ($null -eq $cmd) { continue }
    try {
      $ver = & $cmd.Source @($c.Args) -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')" 2>$null
      if ($LASTEXITCODE -eq 0 -and [version]$ver -ge [version]"3.10") {
        return @{ Path = $cmd.Source; Args = @($c.Args) }
      }
    } catch {}
  }
  return $null
}

function Install-VectorEngine {
  param(
    [Parameter(Mandatory=$true)][hashtable]$Ctx,
    [Parameter(Mandatory=$true)][string]$InstallerRoot,
    [switch]$Force,
    [string]$VectorProvider = "openai"
  )

  Write-Host "Vector mode enabled (provider: $VectorProvider)" -ForegroundColor Cyan

  if ($script:DryRun) {
    Write-Host "[DRY RUN] Skipping vector dependency install and MCP wiring." -ForegroundColor DarkCyan
    return $null
  }

  $vectorPython = Resolve-VectorPython
  if ($null -eq $vectorPython) {
    throw "Vector mode requires Python 3.10+ (python/py launcher not found or version too old)."
  }

  $deps = @("openai", "sqlite-vec", "mcp[cli]>=1.2.0,<2.0")
  if ($VectorProvider -eq "gemini") { $deps += "google-genai" }
  $requiredModules = @("openai", "sqlite_vec", "mcp")
  if ($VectorProvider -eq "gemini") { $requiredModules += "google.genai" }

  $moduleListPy = ($requiredModules | ForEach-Object { "'$_'" }) -join ", "
  $depCheck = "import importlib.util, sys; mods=[$moduleListPy]; missing=[m for m in mods if importlib.util.find_spec(m) is None]; print(','.join(missing)); sys.exit(0 if not missing else 1)"

  $depsSatisfied = $false
  if (-not $Force) {
    & $vectorPython.Path @($vectorPython.Args) -c $depCheck 2>$null | Out-Null
    $depsSatisfied = ($LASTEXITCODE -eq 0)
  }

  if ($depsSatisfied) {
    Write-Host "SKIP (deps installed): vector dependency install" -ForegroundColor DarkYellow
  } else {
    Write-Host "Installing vector dependencies..." -ForegroundColor Cyan
    & $vectorPython.Path @($vectorPython.Args) -m pip install --quiet @deps
    if ($LASTEXITCODE -ne 0) {
      throw "Failed to install vector dependencies. Try: python -m pip install $($deps -join ' ')"
    }
  }

  # Add vector cursor rule
  $vectorRule = @"
---
description: Mnemo vector semantic retrieval layer (optional)
globs:
  - "**/*"
alwaysApply: true
---

# Vector Memory Layer (Optional)

This rule supplements ``00-memory-system.mdc`` and does not replace governance.

## Use vector tools when:
- You do not know the exact keyword for prior context.
- Keyword/FTS search did not find relevant history.

## MCP tools
- ``vector_search`` - semantic retrieval with authority-aware reranking.
- ``vector_sync`` - incremental indexing.
- ``vector_forget`` - remove stale entries.
- ``vector_health`` - DB/API health check.
- ``memory_status`` - JSON summary for autonomous monitoring.

## Fallback
If vector search is unavailable, keep using:
- ``scripts/memory/query-memory.ps1 -Query "..."``
- ``scripts/memory/query-memory.ps1 -Query "..." -UseSqlite``
"@

  Write-MnemoFile (Join-Path $Ctx.RulesDir "01-vector-search.mdc") $vectorRule -ForceWrite:$Force

  return $vectorPython
}
