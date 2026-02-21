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

  $ignoreLines = @(
    ".mnemo/memory/memory.sqlite",
    ".cursor/memory/memory.sqlite",
    ".mnemo/mcp/cursor.mcp.json",
    ".cursor/mcp.json"
  )
  if ($EnableVector) {
    $ignoreLines += @(
      ".mnemo/memory/mnemo_vector.sqlite",
      ".mnemo/memory/mnemo_vector.sqlite-journal",
      ".mnemo/memory/mnemo_vector.sqlite-wal",
      ".mnemo/memory/mnemo_vector.sqlite-shm",
      ".mnemo/memory/.sync.lock",
      ".mnemo/memory/.autonomy/",
      ".cursor/memory/mnemo_vector.sqlite",
      ".cursor/memory/mnemo_vector.sqlite-journal",
      ".cursor/memory/mnemo_vector.sqlite-wal",
      ".cursor/memory/mnemo_vector.sqlite-shm",
      ".cursor/memory/.sync.lock",
      ".cursor/memory/.autonomy/"
    )
  }

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
