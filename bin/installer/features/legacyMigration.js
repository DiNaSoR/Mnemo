"use strict";
/**
 * legacyMigration.js — Migrates legacy IDE paths into canonical .mnemo.
 * Handles .cursor/memory → .mnemo/memory, .cursor/rules → .mnemo/rules/cursor, etc.
 */

const fs   = require("fs");
const path = require("path");
const { syncOneWay, pathsEqual } = require("../core/bridge");

function isCursorRuleEntry(srcPath, entry) {
  return entry.isDirectory() || path.extname(srcPath).toLowerCase() === ".mdc";
}

function moveNonCursorRuleFiles(srcRoot, backupRoot) {
  if (!fs.existsSync(srcRoot)) return 0;
  try {
    if (fs.lstatSync(srcRoot).isSymbolicLink()) return 0;
  } catch {
    return 0;
  }

  let moved = 0;

  function uniqueBackupPath(destPath) {
    if (!fs.existsSync(destPath)) return destPath;
    const parsed = path.parse(destPath);
    return path.join(parsed.dir, `${parsed.name}.backup-${Date.now()}-${moved}${parsed.ext}`);
  }

  function pruneEmptyDirs(dirPath) {
    if (!fs.existsSync(dirPath)) return;
    for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
      if (entry.isDirectory()) {
        pruneEmptyDirs(path.join(dirPath, entry.name));
      }
    }
    if (dirPath !== srcRoot && fs.readdirSync(dirPath).length === 0) {
      fs.rmdirSync(dirPath);
    }
  }

  function walk(dirPath) {
    for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
      const srcPath = path.join(dirPath, entry.name);
      if (entry.isDirectory()) {
        walk(srcPath);
        continue;
      }
      if (isCursorRuleEntry(srcPath, entry)) {
        continue;
      }

      const relPath = path.relative(srcRoot, srcPath);
      let backupPath = path.join(backupRoot, relPath);
      backupPath = uniqueBackupPath(backupPath);
      fs.mkdirSync(path.dirname(backupPath), { recursive: true });
      fs.renameSync(srcPath, backupPath);
      moved += 1;
    }
  }

  walk(srcRoot);
  pruneEmptyDirs(srcRoot);
  return moved;
}

/**
 * Migrate legacy paths into canonical .mnemo structure.
 * Only copies files that don't already exist in the target.
 *
 * @param {object} ctx - path context
 * @param {object} opts - { dryRun }
 */
function migrateLegacyPaths(ctx, opts) {
  if (opts.dryRun) return;

  const backupBase = path.join(ctx.mnemoDir, "legacy", "cursor-rules-non-mdc");
  const movedFromBridge = moveNonCursorRuleFiles(
    ctx.cursorRulesDir,
    path.join(backupBase, "bridge"),
  );
  const movedFromCanonical = moveNonCursorRuleFiles(
    ctx.rulesCursorDir,
    path.join(backupBase, "canonical"),
  );
  if (movedFromBridge > 0) {
    console.log(`Moved ${movedFromBridge} non-.mdc file(s) out of .cursor/rules -> ${path.join(backupBase, "bridge")}`);
  }
  if (movedFromCanonical > 0) {
    console.log(`Moved ${movedFromCanonical} non-.mdc file(s) out of .mnemo/rules/cursor -> ${path.join(backupBase, "canonical")}`);
  }

  const migrations = [
    { src: ctx.cursorMemoryDir, dst: ctx.memoryDir,      label: ".cursor/memory -> .mnemo/memory" },
    {
      src: ctx.cursorRulesDir,
      dst: ctx.rulesCursorDir,
      label: ".cursor/rules -> .mnemo/rules/cursor",
      filter: isCursorRuleEntry,
    },
    { src: ctx.agentRulesDir,   dst: ctx.rulesAgentDir,   label: ".agent/rules -> .mnemo/rules/agent" },
  ];

  for (const { src, dst, label, filter } of migrations) {
    if (!fs.existsSync(src)) continue;

    // Skip if src is already a symlink pointing to dst (or vice versa)
    try {
      const resolved = fs.realpathSync(src);
      if (pathsEqual(resolved, dst)) continue;
    } catch { /* ignore */ }

    const copied = syncOneWay(src, dst, filter ? { filter } : undefined);
    if (copied > 0) {
      console.log(`Migrated ${copied} files (${label})`);
    }
  }
}

module.exports = { migrateLegacyPaths };
