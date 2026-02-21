<#
gitignore_setup.ps1 - Managed .gitignore block for Mnemo generated artifacts.
Dot-sourced by bootstrap.ps1.
#>

function Update-MnemoGitignore {
  param(
    [Parameter(Mandatory=$true)][hashtable]$Ctx,
    [switch]$EnableVector
  )

  $giPath = Join-Path $Ctx.RepoRoot ".gitignore"
  $giBeginMarker = "# >>> Mnemo (generated) - do not edit this block manually <<<"
  $giEndMarker   = "# <<< Mnemo (generated) >>>"

  # User-facing default: ignore the full Mnemo generated footprint so target repos stay clean by default.
  $ignoreLines = @(
    ".mnemo/",
    ".cursor/memory/",
    ".cursor/rules/",
    ".cursor/mcp.json",
    ".agent/rules/",
    "scripts/memory/",
    ".githooks/"
  )

  $giLineEndings = "CRLF"
  $giContent = ""
  if (Test-Path $giPath) {
    $giContent = Get-Content -Raw -Encoding UTF8 -ErrorAction SilentlyContinue $giPath
    if ($null -eq $giContent) { $giContent = "" }
    if ($giContent.Length -gt 0 -and [int]$giContent[0] -eq 0xFEFF) { $giContent = $giContent.Substring(1) }
    $giLineEndings = if ($giContent -match "`r`n") { "CRLF" } else { "LF" }
  }

  $newBlock = $giBeginMarker + "`n" + ($ignoreLines -join "`n") + "`n" + $giEndMarker

  if ($script:DryRun) {
    Write-Host "[DRY RUN] WOULD UPDATE: $giPath (managed Mnemo block)" -ForegroundColor DarkCyan
    return
  }

  $beginEsc = [regex]::Escape($giBeginMarker)
  $endEsc   = [regex]::Escape($giEndMarker)
  $blockPattern = "(?s)$beginEsc.*?$endEsc"

  if ($giContent -match $blockPattern) {
    $newContent = [regex]::Replace($giContent, $blockPattern, $newBlock.Replace('$', '$$'))
    $existingNorm = $giContent -replace "`r?`n", "`n"
    $newNorm      = $newContent -replace "`r?`n", "`n"
    if ($newNorm -ne $existingNorm) {
      $enc = New-Object System.Text.UTF8Encoding($false)
      $normalized = if ($giLineEndings -eq "CRLF") { $newContent -replace "`r?`n", "`r`n" } else { $newContent -replace "`r?`n", "`n" }
      [System.IO.File]::WriteAllText($giPath, $normalized, $enc)
      Write-Host "WROTE: $giPath (updated Mnemo managed block)" -ForegroundColor Green
    } else {
      Write-Host "SKIP (exists): $giPath (Mnemo managed block unchanged)" -ForegroundColor DarkYellow
    }
  } else {
    $trimmed = $giContent.TrimEnd("`r", "`n")
    $sep = if ($trimmed.Length -gt 0) { "`n`n" } else { "" }
    $newContent = $trimmed + $sep + $newBlock + "`n"
    $enc = New-Object System.Text.UTF8Encoding($false)
    $normalized = if ($giLineEndings -eq "CRLF") { $newContent -replace "`r?`n", "`r`n" } else { $newContent -replace "`r?`n", "`n" }
    [System.IO.File]::WriteAllText($giPath, $normalized, $enc)
    Write-Host "WROTE: $giPath (added Mnemo managed block)" -ForegroundColor Green
  }
}
