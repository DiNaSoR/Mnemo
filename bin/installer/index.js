"use strict";
/**
 * installer/index.js — Main Mnemo installer orchestrator.
 *
 * This is the unified, cross-platform installer behind `bin/mnemo.js`.
 *
 * All file creation, bridge setup, vector configuration, and hook
 * installation happens here via modular Node.js code.
 */

const fs   = require("fs");
const path = require("path");

// Core
const { buildPaths }   = require("./core/paths");
const { mkdirp }       = require("./core/writer");
const { buildVars }    = require("./core/template");
const { writeFile }    = require("./core/writer");
const { renderFile }   = require("./core/template");

// Features
const { migrateLegacyPaths }   = require("./features/legacyMigration");
const { installScaffold }      = require("./features/scaffold");
const { installHelperScripts } = require("./features/helperScripts");
const { installVectorDeps, installVectorRules } = require("./features/vectorSetup");
const { installMcpConfig }     = require("./features/mcpConfig");
const { installGitHooks }      = require("./features/gitHooks");
const { updateGitignore }      = require("./features/gitignore");
const { ensureAllBridges }     = require("./features/bridges");

/**
 * Run the full Mnemo installation.
 *
 * @param {object} flags - parsed CLI flags
 * @param {string} flags.repoRoot - target repository path
 * @param {string} flags.projectName - project name
 * @param {boolean} flags.enableVector - enable vector/semantic search
 * @param {string} flags.vectorProvider - "openai" | "gemini"
 * @param {boolean} flags.force - overwrite existing files
 * @param {boolean} flags.dryRun - preview without writing
 * @param {string} installerRoot - path to the Mnemo package root
 * @returns {number} exit code (0 = success)
 */
function install(flags, installerRoot) {
  const repoRoot    = path.resolve(flags.repoRoot || process.cwd());
  const projectName = flags.projectName || path.basename(repoRoot);

  // Read version
  const versionFile = path.join(installerRoot, "VERSION");
  const version = fs.existsSync(versionFile)
    ? fs.readFileSync(versionFile, "utf8").trim()
    : "0.0.0";

  if (flags.dryRun) {
    console.log("[DRY RUN] No files will be written. Showing what would happen.");
  }

  // ── Build path context ────────────────────────────────────────────────
  const ctx = buildPaths(repoRoot);

  // ── Create directory structure ────────────────────────────────────────
  for (const dir of ctx.allDirs) {
    mkdirp(dir, { dryRun: flags.dryRun });
  }

  // ── Common opts passed to all feature modules ─────────────────────────
  const opts = {
    projectName,
    version,
    force:          flags.force,
    dryRun:         flags.dryRun,
    enableVector:   flags.enableVector,
    vectorProvider: flags.vectorProvider || "openai",
    installerRoot,
  };

  // ── 1. Migrate legacy paths ───────────────────────────────────────────
  migrateLegacyPaths(ctx, opts);

  // ── 2. Install memory scaffold ────────────────────────────────────────
  installScaffold(ctx, opts);

  // ── 3. Install rules ──────────────────────────────────────────────────
  installRules(ctx, opts);

  // ── 4. Install helper scripts + autonomy modules ──────────────────────
  installHelperScripts(ctx, opts);

  // ── 5. Vector engine setup ────────────────────────────────────────────
  let vectorPython = null;
  if (flags.enableVector) {
    vectorPython = installVectorDeps(ctx, opts);
    installVectorRules(ctx, opts);

    if (!flags.dryRun && vectorPython) {
      installMcpConfig(ctx, {
        ...opts,
        vectorPython,
      });
    }
  }

  // ── 6. Git hooks ──────────────────────────────────────────────────────
  installGitHooks(ctx, {
    ...opts,
    vectorPython,
  });

  // ── 7. Bridges ────────────────────────────────────────────────────────
  ensureAllBridges(ctx, opts);

  // ── 8. .gitignore ─────────────────────────────────────────────────────
  updateGitignore(ctx, opts);

  // ── Done ──────────────────────────────────────────────────────────────
  console.log("");
  console.log(`Setup complete. (Mnemo v${version})`);
  printSummary(ctx, flags, version);

  return 0;
}

/**
 * Install Cursor and Agent rule files.
 */
function installRules(ctx, opts) {
  const rulesDir = path.join(opts.installerRoot, "scripts", "memory", "installer", "templates", "rules");
  const vars     = buildVars(opts);
  const wo       = { force: opts.force, dryRun: opts.dryRun };

  // Cursor rule
  const cursorTmpl = path.join(rulesDir, "00-memory-system.mdc.tmpl");
  if (fs.existsSync(cursorTmpl)) {
    const content = renderFile(cursorTmpl, vars);
    writeFile(path.join(ctx.rulesCursorDir, "00-memory-system.mdc"), content, wo);
  }

  // Agent rule
  const agentSrc = path.join(rulesDir, "00-memory-system-agent.md");
  if (fs.existsSync(agentSrc)) {
    const content = fs.readFileSync(agentSrc, "utf8");
    writeFile(path.join(ctx.rulesAgentDir, "00-memory-system.md"), content, wo);
  }
}

/**
 * Print the installation summary.
 */
function printSummary(ctx, flags, version) {
  console.log("");
  console.log(`Memory system installed to: ${ctx.memoryDir}`);
  console.log(`Cursor bridge path:        ${ctx.cursorMemoryDir}`);
  console.log("");

  if (flags.enableVector && !flags.dryRun) {
    console.log("Vector tools enabled:");
    console.log("  MCP tools: vector_search, vector_sync, vector_forget, vector_health, memory_status");
    console.log("");
    console.log("Next steps:");
    console.log("  1) Set API key environment variable");
    console.log("  2) Restart your IDE, then run: vector_health");
    console.log("  3) Run: vector_sync (first-time index build)");
    console.log("  4) Memory system is now autonomous (auto-syncs on every commit)");
  } else if (flags.enableVector && flags.dryRun) {
    console.log("Vector tools previewed (dry run):");
    console.log("  No dependencies installed and no MCP/hooks were modified.");
  } else {
    console.log("Next steps:");
    console.log("  1) Run: scripts/memory/rebuild-memory-index.sh (or .ps1)");
    console.log("  2) Run: scripts/memory/lint-memory.sh (or .ps1)");
    console.log("  3) Git hooks are pre-configured (auto-rebuilds on commit)");
    console.log("  4) For semantic search: re-run with --enable-vector");
  }

  if (flags.dryRun) {
    console.log("");
    console.log("[DRY RUN] No changes were made.");
  }
}

module.exports = { install };
