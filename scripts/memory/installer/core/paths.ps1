<#
paths.ps1 - Path resolution for Mnemo installer.
Dot-sourced by bootstrap.ps1.
#>

function Initialize-MnemoPaths {
  param(
    [Parameter(Mandatory=$true)][string]$RepoRoot
  )

  # Canonical Mnemo identity root
  $MnemoDir               = Join-Path $RepoRoot ".mnemo"
  $MnemoMemoryDir         = Join-Path $MnemoDir "memory"
  $MnemoRulesDir          = Join-Path $MnemoDir "rules"
  $MnemoRulesCursorDir    = Join-Path $MnemoRulesDir "cursor"
  $MnemoRulesAgentDir     = Join-Path $MnemoRulesDir "agent"
  $MnemoMcpDir            = Join-Path $MnemoDir "mcp"
  $MnemoCursorMcpPath     = Join-Path $MnemoMcpDir "cursor.mcp.json"

  # IDE bridge targets
  $CursorDir              = Join-Path $RepoRoot ".cursor"
  $CursorMemoryDir        = Join-Path $CursorDir "memory"
  $CursorRulesDir         = Join-Path $CursorDir "rules"
  $CursorMcpPath          = Join-Path $CursorDir "mcp.json"
  $AgentDir               = Join-Path $RepoRoot ".agent"
  $AgentRulesDir          = Join-Path $AgentDir "rules"

  # Backward-compatible aliases used by existing feature modules.
  # During migration these point to canonical .mnemo locations.
  $MemoryDir      = $MnemoMemoryDir
  $RulesDir       = $MnemoRulesCursorDir
  $JournalDir     = Join-Path $MemoryDir "journal"
  $DigestsDir     = Join-Path $MemoryDir "digests"
  $AdrDir         = Join-Path $MemoryDir "adr"
  $LessonsDir     = Join-Path $MemoryDir "lessons"
  $TemplatesDir   = Join-Path $MemoryDir "templates"
  $ScriptsDir     = Join-Path $RepoRoot "scripts"
  $MemScripts     = Join-Path $ScriptsDir "memory"
  $AutonomyDir    = Join-Path $MemScripts "autonomy"
  $GitDir         = Join-Path $RepoRoot ".git"
  $GitHooksDir    = Join-Path $GitDir "hooks"
  $PortableHooksDir = Join-Path $RepoRoot ".githooks"

  $AllDirs = @(
    $MnemoDir, $MnemoMemoryDir, $MnemoRulesDir, $MnemoRulesCursorDir, $MnemoRulesAgentDir,
    $MnemoMcpDir,
    $CursorDir, $AgentDir,
    $MemoryDir, $RulesDir, $JournalDir, $DigestsDir, $AdrDir, $LessonsDir, $TemplatesDir,
    $ScriptsDir, $MemScripts, $AutonomyDir, $PortableHooksDir
  )
  $AllDirs = $AllDirs | Select-Object -Unique

  return @{
    RepoRoot         = $RepoRoot
    MnemoDir         = $MnemoDir
    MnemoMemoryDir   = $MnemoMemoryDir
    MnemoRulesDir    = $MnemoRulesDir
    MnemoRulesCursorDir = $MnemoRulesCursorDir
    MnemoRulesAgentDir  = $MnemoRulesAgentDir
    MnemoMcpDir      = $MnemoMcpDir
    MnemoCursorMcpPath = $MnemoCursorMcpPath
    CursorDir        = $CursorDir
    CursorMemoryDir  = $CursorMemoryDir
    CursorRulesDir   = $CursorRulesDir
    CursorMcpPath    = $CursorMcpPath
    AgentDir         = $AgentDir
    MemoryDir        = $MemoryDir
    RulesDir         = $RulesDir
    JournalDir       = $JournalDir
    DigestsDir       = $DigestsDir
    AdrDir           = $AdrDir
    LessonsDir       = $LessonsDir
    TemplatesDir     = $TemplatesDir
    ScriptsDir       = $ScriptsDir
    MemScripts       = $MemScripts
    AutonomyDir      = $AutonomyDir
    GitDir           = $GitDir
    GitHooksDir      = $GitHooksDir
    PortableHooksDir = $PortableHooksDir
    AgentRulesDir    = $AgentRulesDir
    AllDirs          = $AllDirs
  }
}
