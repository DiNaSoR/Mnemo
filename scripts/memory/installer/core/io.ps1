<#
io.ps1 - Core I/O utilities for Mnemo installer.
Dot-sourced by bootstrap.ps1. Requires $DryRun to be set in caller scope.
#>

function New-MnemoDirectory {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (!(Test-Path $Path)) {
    if ($script:DryRun) {
      Write-Host "[DRY RUN] WOULD CREATE DIR: $Path" -ForegroundColor DarkCyan
      return
    }
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    Write-Host "DIR: $Path" -ForegroundColor Green
  }
}

function Write-MnemoFile {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [Parameter(Mandatory=$true)][string]$Content,
    [ValidateSet("CRLF","LF")][string]$LineEndings = "CRLF",
    [switch]$ForceWrite
  )

  $dir = Split-Path -Parent $Path
  if ($dir -and !(Test-Path $dir)) {
    if ($script:DryRun) { Write-Host "[DRY RUN] WOULD CREATE DIR: $dir" -ForegroundColor DarkCyan; return }
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
  }

  if ((Test-Path $Path) -and (-not $ForceWrite)) {
    Write-Host "SKIP (exists): $Path" -ForegroundColor DarkYellow
    return
  }

  if ($script:DryRun) {
    Write-Host "[DRY RUN] WOULD WRITE: $Path" -ForegroundColor DarkCyan
    return
  }

  $normalized = if ($LineEndings -eq "CRLF") {
    ($Content -replace "`r?`n", "`r`n")
  } else {
    ($Content -replace "`r?`n", "`n")
  }

  $enc = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($Path, $normalized, $enc)
  Write-Host "WROTE: $Path" -ForegroundColor Green
}

function Install-TemplateFile {
  <#
  .SYNOPSIS
  Copies a template file from the installer templates directory to the target path.
  #>
  param(
    [Parameter(Mandatory=$true)][string]$TemplateName,
    [Parameter(Mandatory=$true)][string]$DestPath,
    [Parameter(Mandatory=$true)][string]$InstallerRoot,
    [ValidateSet("CRLF","LF")][string]$LineEndings = "CRLF",
    [switch]$ForceWrite
  )

  $templatePath = Join-Path $InstallerRoot "scripts\memory\installer\templates\$TemplateName"
  if (-not (Test-Path $templatePath)) {
    Write-Host "WARNING: Template not found: $templatePath" -ForegroundColor Yellow
    return
  }

  $content = Get-Content -Raw -Encoding UTF8 $templatePath
  if ($content -and $content.Length -gt 0 -and [int]$content[0] -eq 0xFEFF) {
    $content = $content.Substring(1)
  }

  Write-MnemoFile -Path $DestPath -Content $content -LineEndings $LineEndings -ForceWrite:$ForceWrite
}

function Read-Utf8NoBom {
  param([Parameter(Mandatory=$true)][string]$Path)
  $raw = Get-Content -Raw -Encoding UTF8 $Path
  if ($raw -and $raw.Length -gt 0 -and [int]$raw[0] -eq 0xFEFF) { $raw = $raw.Substring(1) }
  return $raw
}

function Test-MnemoTokenBudget {
  param(
    [Parameter(Mandatory=$true)][hashtable]$Ctx
  )
  $alwaysRead = @(
    (Join-Path $Ctx.MemoryDir "hot-rules.md"),
    (Join-Path $Ctx.MemoryDir "active-context.md"),
    (Join-Path $Ctx.MemoryDir "memo.md")
  )
  $totalChars = 0
  foreach ($p in $alwaysRead) {
    if (Test-Path $p) {
      $t = Get-Content -Raw -ErrorAction SilentlyContinue $p
      if ($t) { $totalChars += $t.Length }
    }
  }
  $estimatedTokens = [math]::Round($totalChars / 4)
  Write-Host ""
  if ($totalChars -gt 8000) {
    Write-Host "WARNING: Always-read layer is $totalChars chars (~$estimatedTokens tokens)." -ForegroundColor Yellow
  } else {
    Write-Host "Always-read layer: $totalChars chars (~$estimatedTokens tokens) - Healthy" -ForegroundColor Green
  }
}
