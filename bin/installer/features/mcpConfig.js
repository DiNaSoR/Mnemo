"use strict";
/**
 * mcpConfig.js — MCP (Model Context Protocol) config generation.
 * Creates .mnemo/mcp/cursor.mcp.json with MnemoVector server config.
 */

const fs   = require("fs");
const path = require("path");

/**
 * Install/update the MCP config for Cursor.
 * @param {object} ctx - path context
 * @param {object} opts - { vectorProvider, vectorPython, force, dryRun }
 */
function installMcpConfig(ctx, opts) {
  const mcpPath = ctx.cursorMcpPath;

  if (opts.dryRun) {
    console.log(`[DRY RUN] WOULD WRITE: ${mcpPath} (MnemoVector MCP config)`);
    return;
  }

  // Read existing config (if any)
  let root = {};
  if (fs.existsSync(mcpPath)) {
    try {
      root = JSON.parse(fs.readFileSync(mcpPath, "utf8"));
      if (typeof root !== "object" || root === null) root = {};
    } catch {
      root = {};
    }
  }

  // Build server config
  const pythonCmd = opts.vectorPython || "python3";
  const enginePath = path.resolve(ctx.repoRoot, "scripts", "memory", "mnemo_vector.py");

  const env = { MNEMO_PROVIDER: opts.vectorProvider };
  if (opts.vectorProvider === "gemini") {
    env.GEMINI_API_KEY = "${env:GEMINI_API_KEY}";
  } else {
    env.OPENAI_API_KEY = "${env:OPENAI_API_KEY}";
  }

  const servers = root.mcpServers || {};
  const existingEntry = servers.MnemoVector;

  servers.MnemoVector = {
    command: pythonCmd,
    args: [enginePath],
    env,
  };
  root.mcpServers = servers;

  // Check if unchanged
  if (!opts.force && existingEntry) {
    const oldStr = JSON.stringify(existingEntry);
    const newStr = JSON.stringify(servers.MnemoVector);
    if (oldStr === newStr) {
      console.log(`SKIP (exists): ${mcpPath} (MnemoVector MCP unchanged)`);
      return;
    }
  }

  // Backup existing config
  if (fs.existsSync(mcpPath)) {
    try { fs.copyFileSync(mcpPath, mcpPath + ".bak"); } catch { /* best effort */ }
  }

  // Atomic write
  const dir = path.dirname(mcpPath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  const tmp = mcpPath + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(root, null, 2), "utf8");
  fs.renameSync(tmp, mcpPath);

  console.log(`WROTE: ${mcpPath}`);
}

module.exports = { installMcpConfig };
