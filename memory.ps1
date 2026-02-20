<#
memory.ps1 - Mnemo Windows Installer (modular orchestrator)
Windows-first, token-safe, scalable repo memory for AI coding agents.

Version is read from VERSION file at repo root.

Features:
- Curated "always read" memory: hot-rules.md + active-context.md + memo.md
- Atomic lessons (individual files) with strict YAML frontmatter
- Monthly journal + auto-generated digest + journal index
- Cursor rule (.mdc) to enforce behavior
- Helper scripts: rebuild, query (SQLite+grep), lint, add-lesson, add-journal-entry
- Tag validation against tag-vocabulary.md
- BOM-tolerant parsing
- Portable hooks via .githooks/ + .git/hooks/ (auto-configured)
- Lint runs on pre-commit
- Optional semantic vector layer (OpenAI / Gemini)
- Autonomous memory runtime (no-human-in-the-loop) when EnableVector

USAGE (from repo root):
  powershell -ExecutionPolicy Bypass -File .\memory.ps1
  powershell -ExecutionPolicy Bypass -File .\memory.ps1 -ProjectName "MyProject"
  powershell -ExecutionPolicy Bypass -File .\memory.ps1 -Force
  powershell -ExecutionPolicy Bypass -File .\memory.ps1 -DryRun
  powershell -ExecutionPolicy Bypass -File .\memory.ps1 -EnableVector
  powershell -ExecutionPolicy Bypass -File .\memory.ps1 -EnableVector -VectorProvider gemini
#>

[CmdletBinding()]
param(
  [string]$RepoRoot = (Get-Location).Path,
  [string]$ProjectName = "",
  [switch]$Force,
  [switch]$DryRun,
  [switch]$EnableVector,
  [ValidateSet("openai","gemini")][string]$VectorProvider = "openai"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Expose DryRun at script scope so modules can read it
$script:DryRun = $DryRun.IsPresent

# Read version from VERSION file (single source of truth)
$InstallerRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$_versionFile  = Join-Path $InstallerRoot "VERSION"
$MnemoVersion  = if (Test-Path $_versionFile) { (Get-Content $_versionFile -Raw).Trim() } else { "0.0.0" }

if ($DryRun) {
  Write-Host "[DRY RUN] No files will be written. Showing what would happen." -ForegroundColor Cyan
}

# Bootstrap installer modules (dot-sources core + feature modules)
. (Join-Path $InstallerRoot "scripts\memory\installer\bootstrap.ps1") -InstallerRoot $InstallerRoot

# Resolve paths
$RepoRoot = (Resolve-Path $RepoRoot).Path
if ([string]::IsNullOrWhiteSpace($ProjectName)) {
  $ProjectName = Split-Path -Leaf $RepoRoot
}

# Initialize path context
$ctx = Initialize-MnemoPaths -RepoRoot $RepoRoot

# Create directory structure
foreach ($dir in $ctx.AllDirs) { New-MnemoDirectory -Path $dir }

# Install memory content scaffold (hot-rules, memo, journal, rules, multi-agent bridges)
Install-MemoryScaffold -Ctx $ctx -ProjectName $ProjectName -MnemoVersion $MnemoVersion -Force:$Force

# Install helper scripts from templates (and autonomy modules if vector enabled)
Install-MemoryScripts -Ctx $ctx -InstallerRoot $InstallerRoot -Force:$Force -EnableVector:$EnableVector -VectorProvider $VectorProvider

# Vector engine setup (Python deps, installs mnemo_vector.py + autonomy modules)
$vectorPython = $null
if ($EnableVector) {
  $vectorPython = Install-VectorEngine -Ctx $ctx -InstallerRoot $InstallerRoot -Force:$Force -VectorProvider $VectorProvider

  if (-not $DryRun -and $null -ne $vectorPython) {
    Install-McpConfig -Ctx $ctx -VectorPython $vectorPython -VectorProvider $VectorProvider -Force:$Force
  }
}

# Git hooks (pre-commit lint/rebuild + optional post-commit vector sync)
Install-GitHooks -Ctx $ctx -VectorPython $vectorPython -EnableVector:$EnableVector -Force:$Force

# Auto-configure portable hooks path (removes the manual 'git config' step)
if (-not $DryRun -and (Test-Path $ctx.GitDir)) {
  $currentHooksPath = & git -C $RepoRoot config core.hooksPath 2>$null
  if ($currentHooksPath -ne ".githooks") {
    & git -C $RepoRoot config core.hooksPath .githooks 2>$null
    Write-Host "Configured: git config core.hooksPath .githooks" -ForegroundColor Green
  }
}

# Token budget check
Test-MnemoTokenBudget -Ctx $ctx

# Auto-managed .gitignore block
Update-MnemoGitignore -Ctx $ctx -EnableVector:$EnableVector

# Setup complete
Write-Host ""
Write-Host "Setup complete. (Mnemo v$MnemoVersion)" -ForegroundColor Green
Write-Host ""
Write-Host "Memory system installed to: $($ctx.MemoryDir)" -ForegroundColor Cyan
Write-Host ""
Write-Host "Helper scripts:" -ForegroundColor Cyan
Write-Host "  Add lesson:  scripts\memory\add-lesson.ps1 -Title ""..."" -Tags ""..."" -Rule ""...""" -ForegroundColor DarkGray
Write-Host "  Add journal: scripts\memory\add-journal-entry.ps1 -Tags ""..."" -Title ""...""" -ForegroundColor DarkGray
Write-Host "  Query:       scripts\memory\query-memory.ps1 -Query ""..."" [-UseSqlite]" -ForegroundColor DarkGray
Write-Host "  Lint:        scripts\memory\lint-memory.ps1" -ForegroundColor DarkGray
Write-Host "  Clear:       scripts\memory\clear-active.ps1" -ForegroundColor DarkGray
Write-Host "  Rebuild:     scripts\memory\rebuild-memory-index.ps1" -ForegroundColor DarkGray
Write-Host ""

if ($EnableVector -and (-not $DryRun)) {
  Write-Host "Vector tools enabled ($VectorProvider):" -ForegroundColor Cyan
  Write-Host "  MCP tools: vector_search, vector_sync, vector_forget, vector_health, memory_status" -ForegroundColor DarkGray
  Write-Host "  Rule: .cursor/rules/01-vector-search.mdc" -ForegroundColor DarkGray
  Write-Host "  MCP:  .cursor/mcp.json -> MnemoVector server" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "Autonomous memory runtime:" -ForegroundColor Cyan
  Write-Host "  Engine: scripts\memory\autonomy\runner.py" -ForegroundColor DarkGray
  Write-Host "  Auto-triggers: post-commit, post-merge, post-checkout hooks" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "Important: export API key in your shell profile." -ForegroundColor Yellow
  if ($VectorProvider -eq "gemini") {
    Write-Host "  `$env:GEMINI_API_KEY = '<your-key>'" -ForegroundColor White
  } else {
    Write-Host "  `$env:OPENAI_API_KEY = '<your-key>'" -ForegroundColor White
  }
  Write-Host "  (MCP env in mcp.json is used by Cursor tools, not git hooks.)" -ForegroundColor DarkGray
  Write-Host ""
  Write-Host "Next steps:" -ForegroundColor Cyan
  Write-Host "  1) Set API key environment variable" -ForegroundColor White
  Write-Host "  2) Restart Cursor, then run: vector_health" -ForegroundColor White
  Write-Host "  3) Run: vector_sync (first-time index build)" -ForegroundColor White
  Write-Host "  4) Memory system is now autonomous (auto-syncs on every commit)" -ForegroundColor White
} elseif ($EnableVector -and $DryRun) {
  Write-Host "Vector tools previewed (dry run):" -ForegroundColor Cyan
  Write-Host "  No dependencies installed and no MCP/hooks were modified." -ForegroundColor DarkGray
  Write-Host ""
} else {
  Write-Host "Next steps:" -ForegroundColor Cyan
  Write-Host "  1) Run: powershell -ExecutionPolicy Bypass -File scripts/memory/rebuild-memory-index.ps1" -ForegroundColor White
  Write-Host "  2) Run: powershell -ExecutionPolicy Bypass -File scripts/memory/lint-memory.ps1" -ForegroundColor White
  Write-Host "  3) Git hooks are pre-configured (auto-rebuilds on commit)" -ForegroundColor White
  Write-Host "  4) For semantic search: re-run with -EnableVector [-VectorProvider gemini]" -ForegroundColor White
}

if ($DryRun) {
  Write-Host ""
  Write-Host "[DRY RUN] No changes were made." -ForegroundColor Cyan
}
