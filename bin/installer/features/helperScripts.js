"use strict";
/**
 * helperScripts.js — Installs platform-specific helper scripts and skills.
 * Copies .sh/.ps1 helpers + Python scripts from templates.
 */

const fs   = require("fs");
const path = require("path");
const { copyFile } = require("../core/writer");

function formatLegacyTimestamp(date = new Date()) {
  const pad = (value) => String(value).padStart(2, "0");
  return [
    date.getFullYear(),
    pad(date.getMonth() + 1),
    pad(date.getDate()),
  ].join("") + "-" + [
    pad(date.getHours()),
    pad(date.getMinutes()),
    pad(date.getSeconds()),
  ].join("");
}

function uniqueDestination(destPath) {
  if (!fs.existsSync(destPath)) return destPath;
  const parsed = path.parse(destPath);
  return path.join(parsed.dir, `${parsed.name}.backup-${Date.now()}${parsed.ext}`);
}

function quarantineSkillOrphans(skillDir, ctx, opts) {
  if (!fs.existsSync(skillDir)) return 0;

  const expectedEntries = new Set(["SKILL.md", "reference.md"]);
  const unexpectedEntries = fs.readdirSync(skillDir, { withFileTypes: true })
    .filter((entry) => !expectedEntries.has(entry.name));

  if (unexpectedEntries.length === 0) return 0;

  const legacyDir = path.join(
    ctx.mnemoDir,
    "legacy",
    "skill-orphans",
    "mnemo-codebase-optimizer",
    formatLegacyTimestamp(),
  );

  if (opts.dryRun) {
    console.log(`[DRY RUN] WOULD MOVE ${unexpectedEntries.length} skill orphan(s) -> ${legacyDir}`);
    return unexpectedEntries.length;
  }

  fs.mkdirSync(legacyDir, { recursive: true });
  for (const entry of unexpectedEntries) {
    const srcPath = path.join(skillDir, entry.name);
    const destPath = uniqueDestination(path.join(legacyDir, entry.name));
    fs.renameSync(srcPath, destPath);
  }

  console.log(`Moved ${unexpectedEntries.length} skill orphan(s) -> ${legacyDir}`);
  return unexpectedEntries.length;
}

function collectRelativeFiles(rootDir, currentDir = rootDir) {
  if (!fs.existsSync(currentDir)) return [];

  const files = [];
  const entries = fs.readdirSync(currentDir, { withFileTypes: true });
  for (const entry of entries) {
    if (entry.name === "__pycache__") continue;

    const absolutePath = path.join(currentDir, entry.name);
    if (entry.isDirectory()) {
      files.push(...collectRelativeFiles(rootDir, absolutePath));
      continue;
    }
    if (entry.name.endsWith(".pyc")) continue;
    files.push(path.relative(rootDir, absolutePath));
  }
  return files;
}

function installScriptSet(scriptNames, tplDir, destDir, opts) {
  const installed = [];
  for (const script of scriptNames) {
    const src  = path.join(tplDir, script);
    const dest = path.join(destDir, script);
    copyFile(src, dest, opts);
    installed.push(dest);
  }
  return installed;
}

function chmodExecutable(filePaths) {
  if (process.platform === "win32") return;

  for (const filePath of filePaths) {
    try {
      if (fs.existsSync(filePath)) fs.chmodSync(filePath, 0o755);
    } catch {
      // Best effort only; shell users can still invoke via `sh script.sh`.
    }
  }
}

/**
 * Install helper scripts (shell/PowerShell) and Python utilities.
 * @param {object} ctx - path context
 * @param {object} opts - { force, dryRun, installerRoot, enableVector, vectorProvider }
 */
function installHelperScripts(ctx, opts) {
  const tplDir = path.join(opts.installerRoot, "scripts", "memory", "installer", "templates");
  const wo     = { force: opts.force, dryRun: opts.dryRun };

  // ── Platform helper scripts ─────────────────────────────────────────
  const shScripts = [
    "add-journal-entry.sh", "add-lesson.sh", "clear-active.sh",
    "lint-memory.sh", "query-memory.sh", "rebuild-memory-index.sh",
  ];
  const psScripts = [
    "add-journal-entry.ps1", "add-lesson.ps1", "clear-active.ps1",
    "lint-memory.ps1", "query-memory.ps1", "rebuild-memory-index.ps1",
  ];

  const installedHelperScripts = [
    ...installScriptSet(shScripts, tplDir, ctx.memScriptsDir, wo),
    ...installScriptSet(psScripts, tplDir, ctx.memScriptsDir, wo),
  ];
  if (!opts.dryRun) chmodExecutable(installedHelperScripts.filter((filePath) => filePath.endsWith(".sh")));

  // ── Python helpers (cross-platform) ──────────────────────────────────
  const pyHelpers = ["build-memory-sqlite.py", "query-memory-sqlite.py"];
  for (const py of pyHelpers) {
    const src  = path.join(tplDir, py);
    const dest = path.join(ctx.memScriptsDir, py);
    copyFile(src, dest, wo);
  }

  // ── Skills ───────────────────────────────────────────────────────────
  const skillsDir = path.join(tplDir, "skills", "mnemo-codebase-optimizer");
  const skillsDest = path.join(ctx.cursorDir, "skills", "mnemo-codebase-optimizer");
  quarantineSkillOrphans(skillsDest, ctx, opts);
  for (const f of ["SKILL.md", "reference.md"]) {
    const src  = path.join(skillsDir, f);
    const dest = path.join(skillsDest, f);
    copyFile(src, dest, wo);
  }

  // ── Vector-mode scripts ──────────────────────────────────────────────
  if (opts.enableVector) {
    const mvSrc  = path.join(tplDir, "mnemo_vector.py");
    const mvDest = path.join(ctx.memScriptsDir, "mnemo_vector.py");
    copyFile(mvSrc, mvDest, wo);

    // Install autonomy modules
    const autoSrc  = path.join(tplDir, "autonomy");
    const autoDest = ctx.autonomyDir;

    if (fs.existsSync(autoSrc)) {
      const runtimeFiles = collectRelativeFiles(autoSrc);

      let missing = false;
      for (const runtimeFile of runtimeFiles) {
        if (!fs.existsSync(path.join(autoDest, runtimeFile))) {
          missing = true;
          break;
        }
      }

      if (opts.force || missing) {
        const { copyDir } = require("../core/writer");
        copyDir(autoSrc, autoDest, wo);
      } else {
        console.log(`SKIP (exists): ${autoDest} (autonomy runtime modules)`);
      }
    }
  }

  // ── Customization guide ──────────────────────────────────────────────
  const custSrc = path.join(tplDir, "customization.md");
  const custDest = path.join(ctx.memScriptsDir, "customization.md");
  if (fs.existsSync(custSrc)) {
    copyFile(custSrc, custDest, wo);
  }
}

module.exports = { installHelperScripts };
