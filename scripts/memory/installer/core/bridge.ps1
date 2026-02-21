<#
bridge.ps1 - Canonical path bridge helpers for Mnemo.
Dot-sourced by bootstrap.ps1. Depends on io.ps1 functions.
#>

function Get-MnemoFullPath {
  param([Parameter(Mandatory=$true)][string]$Path)
  return [System.IO.Path]::GetFullPath($Path)
}

function Test-MnemoPathEqual {
  param(
    [Parameter(Mandatory=$true)][string]$A,
    [Parameter(Mandatory=$true)][string]$B
  )
  $aFull = Get-MnemoFullPath -Path $A
  $bFull = Get-MnemoFullPath -Path $B
  $comparison = if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
    [System.StringComparison]::OrdinalIgnoreCase
  } else {
    [System.StringComparison]::Ordinal
  }
  return [string]::Equals($aFull, $bFull, $comparison)
}

function Test-MnemoReparsePoint {
  param([Parameter(Mandatory=$true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $false }
  $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
  if ($null -eq $item) { return $false }
  return (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Copy-MnemoDirectoryContent {
  param(
    [Parameter(Mandatory=$true)][string]$SourceDir,
    [Parameter(Mandatory=$true)][string]$TargetDir
  )

  if (-not (Test-Path -LiteralPath $SourceDir)) { return 0 }
  New-MnemoDirectory -Path $TargetDir

  $sourceFull = Get-MnemoFullPath -Path $SourceDir
  $copied = 0
  $files = Get-ChildItem -LiteralPath $SourceDir -Recurse -Force -File -ErrorAction SilentlyContinue
  foreach ($src in $files) {
    $relative = $src.FullName.Substring($sourceFull.Length).TrimStart('\', '/')
    if ([string]::IsNullOrWhiteSpace($relative)) { continue }
    $dst = Join-Path $TargetDir $relative
    $dstDir = Split-Path -Parent $dst
    if ($dstDir -and -not (Test-Path -LiteralPath $dstDir)) {
      if ($script:DryRun) {
        Write-Host "[DRY RUN] WOULD CREATE DIR: $dstDir" -ForegroundColor DarkCyan
      } else {
        New-Item -ItemType Directory -Force -Path $dstDir | Out-Null
      }
    }

    $needsCopy = $true
    if (Test-Path -LiteralPath $dst) {
      $dstInfo = Get-Item -LiteralPath $dst -Force
      if (($dstInfo.Length -eq $src.Length) -and ($dstInfo.LastWriteTimeUtc -ge $src.LastWriteTimeUtc)) {
        $needsCopy = $false
      }
    }
    if (-not $needsCopy) { continue }

    if ($script:DryRun) {
      Write-Host "[DRY RUN] WOULD COPY: $($src.FullName) -> $dst" -ForegroundColor DarkCyan
      $copied++
      continue
    }
    Copy-Item -LiteralPath $src.FullName -Destination $dst -Force
    $copied++
  }
  return $copied
}

function New-MnemoDirectoryLink {
  param(
    [Parameter(Mandatory=$true)][string]$LinkPath,
    [Parameter(Mandatory=$true)][string]$TargetPath
  )

  $parent = Split-Path -Parent $LinkPath
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-MnemoDirectory -Path $parent
  }

  if ($script:DryRun) {
    Write-Host "[DRY RUN] WOULD LINK DIR: $LinkPath -> $TargetPath" -ForegroundColor DarkCyan
    return "dry-run-link"
  }

  try {
    New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    return "symlink"
  } catch {}

  if ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT) {
    try {
      $null = & cmd /c "mklink /J ""$LinkPath"" ""$TargetPath""" 2>$null
      if ($LASTEXITCODE -eq 0 -and (Test-Path -LiteralPath $LinkPath)) {
        return "junction"
      }
    } catch {}
  }
  return $null
}

function New-MnemoFileLink {
  param(
    [Parameter(Mandatory=$true)][string]$LinkPath,
    [Parameter(Mandatory=$true)][string]$TargetPath
  )

  $parent = Split-Path -Parent $LinkPath
  if ($parent -and -not (Test-Path -LiteralPath $parent)) {
    New-MnemoDirectory -Path $parent
  }

  if ($script:DryRun) {
    Write-Host "[DRY RUN] WOULD LINK FILE: $LinkPath -> $TargetPath" -ForegroundColor DarkCyan
    return "dry-run-link"
  }

  try {
    New-Item -ItemType SymbolicLink -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    return "symlink"
  } catch {}

  try {
    New-Item -ItemType HardLink -Path $LinkPath -Target $TargetPath -Force -ErrorAction Stop | Out-Null
    return "hardlink"
  } catch {}

  return $null
}

function Ensure-MnemoDirectoryBridge {
  param(
    [Parameter(Mandatory=$true)][string]$CanonicalDir,
    [Parameter(Mandatory=$true)][string]$BridgeDir
  )

  New-MnemoDirectory -Path $CanonicalDir

  if (-not (Test-Path -LiteralPath $BridgeDir)) {
    $mode = New-MnemoDirectoryLink -LinkPath $BridgeDir -TargetPath $CanonicalDir
    if ($mode) {
      Write-Host "BRIDGE ($mode): $BridgeDir -> $CanonicalDir" -ForegroundColor Green
      return $mode
    }

    New-MnemoDirectory -Path $BridgeDir
    $copied = Copy-MnemoDirectoryContent -SourceDir $CanonicalDir -TargetDir $BridgeDir
    Write-Host "BRIDGE (mirror): $BridgeDir <-> $CanonicalDir (copied $copied files)" -ForegroundColor Yellow
    return "mirror"
  }

  $bridgeResolved = (Resolve-Path -LiteralPath $BridgeDir -ErrorAction SilentlyContinue).Path
  if ($bridgeResolved -and (Test-MnemoPathEqual -A $bridgeResolved -B $CanonicalDir)) {
    Write-Host "BRIDGE (linked): $BridgeDir -> $CanonicalDir" -ForegroundColor DarkGreen
    return "linked"
  }

  if (Test-MnemoReparsePoint -Path $BridgeDir) {
    if ($script:DryRun) {
      Write-Host "[DRY RUN] WOULD REPAIR BRIDGE: $BridgeDir -> $CanonicalDir" -ForegroundColor DarkCyan
      return "repair-dry-run"
    }
    Remove-Item -LiteralPath $BridgeDir -Recurse -Force -ErrorAction SilentlyContinue
    $mode = New-MnemoDirectoryLink -LinkPath $BridgeDir -TargetPath $CanonicalDir
    if ($mode) {
      Write-Host "BRIDGE (repaired-$mode): $BridgeDir -> $CanonicalDir" -ForegroundColor Green
      return "repaired-$mode"
    }
  }

  $toCanonical = Copy-MnemoDirectoryContent -SourceDir $BridgeDir -TargetDir $CanonicalDir
  $toBridge = Copy-MnemoDirectoryContent -SourceDir $CanonicalDir -TargetDir $BridgeDir
  Write-Host "BRIDGE (mirror): $BridgeDir <-> $CanonicalDir (sync $toCanonical/$toBridge files)" -ForegroundColor Yellow
  return "mirror"
}

function Ensure-MnemoFileBridge {
  param(
    [Parameter(Mandatory=$true)][string]$CanonicalPath,
    [Parameter(Mandatory=$true)][string]$BridgePath
  )

  $canonicalDir = Split-Path -Parent $CanonicalPath
  if ($canonicalDir) { New-MnemoDirectory -Path $canonicalDir }

  if ((-not (Test-Path -LiteralPath $CanonicalPath)) -and (Test-Path -LiteralPath $BridgePath)) {
    if ($script:DryRun) {
      Write-Host "[DRY RUN] WOULD COPY: $BridgePath -> $CanonicalPath" -ForegroundColor DarkCyan
    } else {
      Copy-Item -LiteralPath $BridgePath -Destination $CanonicalPath -Force
    }
  }

  if (-not (Test-Path -LiteralPath $CanonicalPath)) {
    return "missing-canonical"
  }

  if (-not (Test-Path -LiteralPath $BridgePath)) {
    $mode = New-MnemoFileLink -LinkPath $BridgePath -TargetPath $CanonicalPath
    if ($mode) {
      Write-Host "BRIDGE ($mode): $BridgePath -> $CanonicalPath" -ForegroundColor Green
      return $mode
    }
    if ($script:DryRun) {
      Write-Host "[DRY RUN] WOULD COPY: $CanonicalPath -> $BridgePath" -ForegroundColor DarkCyan
      return "mirror-dry-run"
    }
    Copy-Item -LiteralPath $CanonicalPath -Destination $BridgePath -Force
    Write-Host "BRIDGE (mirror): $BridgePath <- $CanonicalPath" -ForegroundColor Yellow
    return "mirror"
  }

  $bridgeItem = Get-Item -LiteralPath $BridgePath -Force -ErrorAction SilentlyContinue
  if ($null -ne $bridgeItem -and ($bridgeItem.PSObject.Properties.Name -contains "LinkType") -and $bridgeItem.LinkType) {
    $targets = @()
    if ($bridgeItem.PSObject.Properties.Name -contains "Target" -and $bridgeItem.Target) {
      $targets = @($bridgeItem.Target)
    }
    foreach ($target in $targets) {
      if ($target -and (Test-MnemoPathEqual -A ([string]$target) -B $CanonicalPath)) {
        Write-Host "BRIDGE (linked): $BridgePath -> $CanonicalPath" -ForegroundColor DarkGreen
        return "linked"
      }
    }
  }

  $bridgeResolved = (Resolve-Path -LiteralPath $BridgePath -ErrorAction SilentlyContinue).Path
  if ($bridgeResolved -and (Test-MnemoPathEqual -A $bridgeResolved -B $CanonicalPath)) {
    Write-Host "BRIDGE (linked): $BridgePath -> $CanonicalPath" -ForegroundColor DarkGreen
    return "linked"
  }

  if (Test-MnemoReparsePoint -Path $BridgePath) {
    if ($script:DryRun) {
      Write-Host "[DRY RUN] WOULD REPAIR FILE BRIDGE: $BridgePath -> $CanonicalPath" -ForegroundColor DarkCyan
      return "repair-dry-run"
    }
    Remove-Item -LiteralPath $BridgePath -Force -ErrorAction SilentlyContinue
    $mode = New-MnemoFileLink -LinkPath $BridgePath -TargetPath $CanonicalPath
    if ($mode) {
      Write-Host "BRIDGE (repaired-$mode): $BridgePath -> $CanonicalPath" -ForegroundColor Green
      return "repaired-$mode"
    }
  }

  if ($script:DryRun) {
    Write-Host "[DRY RUN] WOULD MIRROR FILE: $CanonicalPath <-> $BridgePath" -ForegroundColor DarkCyan
    return "mirror-dry-run"
  }

  $canonicalInfo = Get-Item -LiteralPath $CanonicalPath -Force
  $bridgeInfo = Get-Item -LiteralPath $BridgePath -Force
  if ($bridgeInfo.LastWriteTimeUtc -gt $canonicalInfo.LastWriteTimeUtc) {
    Copy-Item -LiteralPath $BridgePath -Destination $CanonicalPath -Force
  }
  Copy-Item -LiteralPath $CanonicalPath -Destination $BridgePath -Force
  Write-Host "BRIDGE (mirror): $BridgePath <-> $CanonicalPath" -ForegroundColor Yellow
  return "mirror"
}

function Ensure-MnemoCanonicalBridges {
  param(
    [Parameter(Mandatory=$true)][hashtable]$Ctx
  )

  # Directory bridges
  $null = Ensure-MnemoDirectoryBridge -CanonicalDir $Ctx.MemoryDir -BridgeDir $Ctx.CursorMemoryDir
  $null = Ensure-MnemoDirectoryBridge -CanonicalDir $Ctx.RulesDir -BridgeDir $Ctx.CursorRulesDir
  $null = Ensure-MnemoDirectoryBridge -CanonicalDir $Ctx.MnemoRulesAgentDir -BridgeDir $Ctx.AgentRulesDir

  # File bridge for Cursor MCP config (if either side exists).
  if ((Test-Path -LiteralPath $Ctx.MnemoCursorMcpPath) -or (Test-Path -LiteralPath $Ctx.CursorMcpPath)) {
    $null = Ensure-MnemoFileBridge -CanonicalPath $Ctx.MnemoCursorMcpPath -BridgePath $Ctx.CursorMcpPath
  }
}

