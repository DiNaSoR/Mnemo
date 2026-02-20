<#
bootstrap.ps1 - Dot-sources all Mnemo installer modules in dependency order.
Call this from memory.ps1 AFTER setting $DryRun, $Force, $EnableVector, $VectorProvider.
#>
param(
  [Parameter(Mandatory=$true)][string]$InstallerRoot
)

$modulesBase = Join-Path $InstallerRoot "scripts\memory\installer"

# Core layer
. (Join-Path $modulesBase "core\io.ps1")
. (Join-Path $modulesBase "core\paths.ps1")

# Feature layer
. (Join-Path $modulesBase "features\memory_scaffold.ps1")
. (Join-Path $modulesBase "features\vector_setup.ps1")
. (Join-Path $modulesBase "features\mcp_setup.ps1")
. (Join-Path $modulesBase "features\hooks_setup.ps1")
. (Join-Path $modulesBase "features\gitignore_setup.ps1")
