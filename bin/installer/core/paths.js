"use strict";
/**
 * paths.js — Path context builder for Mnemo installer.
 * Computes all directory/file paths used throughout the installation.
 */

const path = require("path");

/**
 * Build the full path context for a Mnemo installation.
 * @param {string} repoRoot - absolute path to the target repository
 * @returns {object} ctx - all canonical and bridge paths
 */
function buildPaths(repoRoot) {
  const abs = (...segs) => path.join(repoRoot, ...segs);

  // ── Canonical Mnemo identity root ───────────────────────────────────────
  const mnemoDir          = abs(".mnemo");
  const memoryDir         = abs(".mnemo", "memory");
  const rulesDir          = abs(".mnemo", "rules");
  const rulesCursorDir    = abs(".mnemo", "rules", "cursor");
  const rulesAgentDir     = abs(".mnemo", "rules", "agent");
  const mcpDir            = abs(".mnemo", "mcp");
  const cursorMcpPath     = abs(".mnemo", "mcp", "cursor.mcp.json");

  // ── Memory sub-directories ──────────────────────────────────────────────
  const journalDir        = abs(".mnemo", "memory", "journal");
  const digestsDir        = abs(".mnemo", "memory", "digests");
  const adrDir            = abs(".mnemo", "memory", "adr");
  const lessonsDir        = abs(".mnemo", "memory", "lessons");
  const templatesDir      = abs(".mnemo", "memory", "templates");
  const vaultDir          = abs(".mnemo", "memory", "vault");

  // ── IDE integration bridge targets ──────────────────────────────────────
  const cursorDir         = abs(".cursor");
  const cursorMemoryDir   = abs(".cursor", "memory");
  const cursorRulesDir    = abs(".cursor", "rules");
  const cursorMcpBridge   = abs(".cursor", "mcp.json");
  const agentDir          = abs(".agent");
  const agentRulesDir     = abs(".agent", "rules");

  // ── Scripts ─────────────────────────────────────────────────────────────
  const scriptsDir        = abs("scripts");
  const memScriptsDir     = abs("scripts", "memory");
  const autonomyDir       = abs("scripts", "memory", "autonomy");

  // ── Git ─────────────────────────────────────────────────────────────────
  const gitDir            = abs(".git");
  const gitHooksDir       = abs(".git", "hooks");
  const githooksDir       = abs(".githooks");

  // ── All directories that must exist ─────────────────────────────────────
  const allDirs = [
    mnemoDir, memoryDir, rulesDir, rulesCursorDir, rulesAgentDir, mcpDir,
    journalDir, digestsDir, adrDir, lessonsDir, templatesDir,
    cursorDir, agentDir,
    scriptsDir, memScriptsDir, githooksDir,
  ];

  return {
    repoRoot,
    mnemoDir, memoryDir, rulesDir, rulesCursorDir, rulesAgentDir,
    mcpDir, cursorMcpPath,
    journalDir, digestsDir, adrDir, lessonsDir, templatesDir, vaultDir,
    cursorDir, cursorMemoryDir, cursorRulesDir, cursorMcpBridge,
    agentDir, agentRulesDir,
    scriptsDir, memScriptsDir, autonomyDir,
    gitDir, gitHooksDir, githooksDir,
    allDirs,
  };
}

module.exports = { buildPaths };
