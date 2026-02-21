<#
mcp_setup.ps1 - MCP configuration for Mnemo vector engine.
Dot-sourced by bootstrap.ps1.
#>

function Install-McpConfig {
  param(
    [Parameter(Mandatory=$true)][hashtable]$Ctx,
    [Parameter(Mandatory=$true)][object]$VectorPython,
    [string]$VectorProvider = "openai",
    [switch]$Force
  )

  if ($script:DryRun) {
    Write-Host "[DRY RUN] WOULD CONFIGURE: .mnemo/mcp/cursor.mcp.json (+ .cursor/mcp.json bridge)" -ForegroundColor DarkCyan
    return
  }

  $mcpPath = $Ctx.MnemoCursorMcpPath
  $engineAbsPath = (Resolve-Path (Join-Path $Ctx.MemScripts "mnemo_vector.py")).Path
  $mcpRoot = [ordered]@{}

  if (Test-Path $mcpPath) {
    try {
      $existingMcp = Get-Content -Raw -Encoding UTF8 $mcpPath | ConvertFrom-Json
      if ($existingMcp) {
        foreach ($prop in $existingMcp.PSObject.Properties) {
          $mcpRoot[$prop.Name] = $prop.Value
        }
      }
    } catch {
      Write-Host "WARNING: Could not parse .cursor/mcp.json, rebuilding mcpServers block." -ForegroundColor Yellow
    }
  }

  $servers = [ordered]@{}
  if ($mcpRoot.Contains("mcpServers") -and $mcpRoot["mcpServers"]) {
    foreach ($prop in $mcpRoot["mcpServers"].PSObject.Properties) {
      $servers[$prop.Name] = $prop.Value
    }
  }

  $envBlock = @{ MNEMO_PROVIDER = $VectorProvider }
  if ($VectorProvider -eq "gemini") {
    $envBlock["GEMINI_API_KEY"] = '${env:GEMINI_API_KEY}'
  } else {
    $envBlock["OPENAI_API_KEY"] = '${env:OPENAI_API_KEY}'
  }

  $argsList = @()
  if ($VectorPython.Args) { $argsList += $VectorPython.Args }
  $argsList += $engineAbsPath

  $servers["MnemoVector"] = @{
    command = $VectorPython.Path
    args    = $argsList
    env     = $envBlock
  }
  $mcpRoot["mcpServers"] = $servers
  $mcpJson = $mcpRoot | ConvertTo-Json -Depth 15

  $writeMcp = $true
  if ((-not $Force) -and (Test-Path $mcpPath)) {
    try {
      $existingCanonical = (Get-Content -Raw -Encoding UTF8 $mcpPath | ConvertFrom-Json | ConvertTo-Json -Depth 15)
      $existingNorm = ($existingCanonical -replace "`r?`n", "`n").Trim()
      $newNorm = ($mcpJson -replace "`r?`n", "`n").Trim()
      if ($existingNorm -eq $newNorm) {
        $writeMcp = $false
        Write-Host "SKIP (exists): $mcpPath (MnemoVector MCP unchanged)" -ForegroundColor DarkYellow
      }
    } catch {}
  }

  if ($writeMcp) {
    if (Test-Path $mcpPath) {
      Copy-Item -Path $mcpPath -Destination "$mcpPath.bak" -Force
    }
    $mcpTmp = "$mcpPath.tmp"
    [System.IO.File]::WriteAllText($mcpTmp, $mcpJson, (New-Object System.Text.UTF8Encoding $false))
    Move-Item -Path $mcpTmp -Destination $mcpPath -Force
    Write-Host "WROTE: $mcpPath" -ForegroundColor Green
  }

  # Keep Cursor integration path in sync as a bridge target.
  Ensure-MnemoFileBridge -CanonicalPath $mcpPath -BridgePath $Ctx.CursorMcpPath | Out-Null
}
