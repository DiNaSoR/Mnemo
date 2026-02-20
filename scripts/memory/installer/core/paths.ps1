<#
paths.ps1 - Path resolution for Mnemo installer.
Dot-sourced by bootstrap.ps1.
#>

function Initialize-MnemoPaths {
  param(
    [Parameter(Mandatory=$true)][string]$RepoRoot
  )

  $CursorDir      = Join-Path $RepoRoot ".cursor"
  $MemoryDir      = Join-Path $CursorDir "memory"
  $RulesDir       = Join-Path $CursorDir "rules"
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
  $AgentRulesDir  = Join-Path $RepoRoot ".agent\rules"

  $AllDirs = @(
    $CursorDir, $MemoryDir, $RulesDir, $JournalDir, $DigestsDir,
    $AdrDir, $LessonsDir, $TemplatesDir, $ScriptsDir, $MemScripts,
    $AutonomyDir, $PortableHooksDir, $AgentRulesDir
  )

  return @{
    RepoRoot         = $RepoRoot
    CursorDir        = $CursorDir
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
