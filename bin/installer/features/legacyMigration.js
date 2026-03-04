"use strict";
/**
 * legacyMigration.js — Migrates legacy IDE paths into canonical .mnemo.
 * Handles .cursor/memory → .mnemo/memory, .cursor/rules → .mnemo/rules/cursor, etc.
 */

const fs   = require("fs");
const path = require("path");
const { syncOneWay, pathsEqual } = require("../core/bridge");

/**
 * Migrate legacy paths into canonical .mnemo structure.
 * Only copies files that don't already exist in the target.
 *
 * @param {object} ctx - path context
 * @param {object} opts - { dryRun }
 */
function migrateLegacyPaths(ctx, opts) {
  if (opts.dryRun) return;

  const migrations = [
    { src: ctx.cursorMemoryDir, dst: ctx.memoryDir,      label: ".cursor/memory -> .mnemo/memory" },
    { src: ctx.cursorRulesDir,  dst: ctx.rulesCursorDir,  label: ".cursor/rules -> .mnemo/rules/cursor" },
    { src: ctx.agentRulesDir,   dst: ctx.rulesAgentDir,   label: ".agent/rules -> .mnemo/rules/agent" },
  ];

  for (const { src, dst, label } of migrations) {
    if (!fs.existsSync(src)) continue;

    // Skip if src is already a symlink pointing to dst (or vice versa)
    try {
      const resolved = fs.realpathSync(src);
      if (pathsEqual(resolved, dst)) continue;
    } catch { /* ignore */ }

    const copied = syncOneWay(src, dst);
    if (copied > 0) {
      console.log(`Migrated ${copied} files (${label})`);
    }
  }
}

module.exports = { migrateLegacyPaths };
