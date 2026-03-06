"use strict";
/**
 * bridges.js — Orchestrates all canonical ↔ IDE bridges.
 */

const { ensureDirBridge, ensureFileBridge } = require("../core/bridge");
const fs = require("fs");
const path = require("path");

function isCursorRuleEntry(srcPath, entry) {
  return entry.isDirectory() || path.extname(srcPath).toLowerCase() === ".mdc";
}

/**
 * Ensure all canonical ↔ IDE bridges are healthy.
 * @param {object} ctx - path context
 * @param {object} opts - { dryRun }
 */
function ensureAllBridges(ctx, opts) {
  // Directory bridges: .mnemo/* → .cursor/* / .agent/*
  ensureDirBridge(ctx.memoryDir, ctx.cursorMemoryDir, opts);
  ensureDirBridge(ctx.rulesCursorDir, ctx.cursorRulesDir, {
    ...opts,
    filter: isCursorRuleEntry,
  });
  ensureDirBridge(ctx.rulesAgentDir, ctx.agentRulesDir, opts);

  // File bridge: .mnemo/mcp/cursor.mcp.json → .cursor/mcp.json
  if (fs.existsSync(ctx.cursorMcpPath) || fs.existsSync(ctx.cursorMcpBridge)) {
    ensureFileBridge(ctx.cursorMcpPath, ctx.cursorMcpBridge, opts);
  }
}

module.exports = { ensureAllBridges };
