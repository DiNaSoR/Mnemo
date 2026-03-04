"use strict";
/**
 * helperScripts.js — Installs platform-specific helper scripts and skills.
 * Copies .sh/.ps1 helpers + Python scripts from templates.
 */

const fs   = require("fs");
const path = require("path");
const { copyFile } = require("../core/writer");

const IS_WIN = process.platform === "win32";

/**
 * Install helper scripts (shell/PowerShell) and Python utilities.
 * @param {object} ctx - path context
 * @param {object} opts - { force, dryRun, installerRoot, enableVector, vectorProvider }
 */
function installHelperScripts(ctx, opts) {
  const tplDir = path.join(opts.installerRoot, "scripts", "memory", "installer", "templates");
  const wo     = { force: opts.force, dryRun: opts.dryRun };

  // ── Platform helper scripts ─────────────────────────────────────────
  const psScripts = [
    "add-journal-entry.ps1", "add-lesson.ps1", "clear-active.ps1",
    "lint-memory.ps1", "query-memory.ps1", "rebuild-memory-index.ps1",
  ];

  // Shell helper scripts are embedded in memory_mac.sh and generated there.
  // For Node.js installs, we copy the PS1 templates, and on POSIX the
  // shell helper scripts are generated later by the sh wrapper or already
  // exist from a previous install.
  for (const script of psScripts) {
    const src  = path.join(tplDir, script);
    const dest = path.join(ctx.memScriptsDir, script);
    copyFile(src, dest, wo);
  }

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
      const modules = [
        "__init__.py", "common.py", "schema.py", "runner.py",
        "ingest_pipeline.py", "lifecycle_engine.py", "entity_resolver.py",
        "retrieval_router.py", "reranker.py", "context_safety.py",
        "vault_policy.py", "policies.yaml",
      ];

      let missing = false;
      for (const m of modules) {
        if (!fs.existsSync(path.join(autoDest, m))) { missing = true; break; }
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
  const custSrc = path.join(tplDir, "content", "customization.md");
  // Fall back to writing inline if template doesn't exist
  const custDest = path.join(ctx.memScriptsDir, "customization.md");
  if (fs.existsSync(custSrc)) {
    copyFile(custSrc, custDest, wo);
  }
}

module.exports = { installHelperScripts };
