"use strict";
/**
 * gitHooks.js — Git hook installation (pre-commit + post-commit vector).
 */

const fs   = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");
const { writeFile, copyFile } = require("../core/writer");
const { render, renderFile }  = require("../core/template");

/**
 * Install git hooks.
 * @param {object} ctx - path context
 * @param {object} opts - { enableVector, vectorProvider, force, dryRun, installerRoot }
 */
function installGitHooks(ctx, opts) {
  const wo       = { force: opts.force, dryRun: opts.dryRun };
  const hooksDir = path.join(opts.installerRoot, "scripts", "memory", "installer", "templates", "hooks");

  // ── Pre-commit hook ─────────────────────────────────────────────────
  const preCommitSrc = path.join(hooksDir, "pre-commit.sh");
  const preCommitDst = path.join(ctx.githooksDir, "pre-commit");
  if (fs.existsSync(preCommitSrc)) {
    const content = fs.readFileSync(preCommitSrc, "utf8");
    writeFile(preCommitDst, content, wo);
  }

  // Also write to .git/hooks/ for immediate effect (best effort)
  if (!opts.dryRun && fs.existsSync(ctx.gitDir)) {
    const legacyHook = path.join(ctx.gitHooksDir, "pre-commit");
    if (fs.existsSync(legacyHook) && !opts.force) {
      try {
        const existing = fs.readFileSync(legacyHook, "utf8");
        if (existing.includes("Mnemo")) {
          console.log(`SKIP (exists): ${legacyHook}`);
        } else {
          // Append to existing hook
          fs.appendFileSync(legacyHook, "\n\n" + fs.readFileSync(preCommitDst, "utf8"));
          console.log(`Updated: ${legacyHook}`);
        }
      } catch { /* ignore */ }
    } else if (fs.existsSync(preCommitDst)) {
      try {
        fs.copyFileSync(preCommitDst, legacyHook);
      } catch { /* ignore */ }
    }
  }

  // ── Post-commit hook (vector mode only) ─────────────────────────────
  if (opts.enableVector) {
    const postCommitTmpl = path.join(hooksDir, "post-commit-vector.sh.tmpl");
    const postCommitDst  = path.join(ctx.githooksDir, "post-commit");

    if (fs.existsSync(postCommitTmpl)) {
      // Build the API key guard
      const guard = opts.vectorProvider === "gemini"
        ? '[ -z "${GEMINI_API_KEY:-}" ] && exit 0'
        : '[ -z "${OPENAI_API_KEY:-}" ] && exit 0';

      const content = renderFile(postCommitTmpl, { API_KEY_GUARD: guard });

      // Backup existing post-commit hook
      if (!opts.dryRun && fs.existsSync(postCommitDst)) {
        const existing = fs.readFileSync(postCommitDst, "utf8");
        if (!existing.includes("Mnemo Vector Hook Wrapper")) {
          const backup = path.join(ctx.githooksDir, "post-commit.before-mnemo-vector");
          try { fs.copyFileSync(postCommitDst, backup); } catch { /* ignore */ }
        }
      }

      writeFile(postCommitDst, content, wo);

      // Copy to .git/hooks/ too
      if (!opts.dryRun && fs.existsSync(ctx.gitDir)) {
        const legacyPost = path.join(ctx.gitHooksDir, "post-commit");
        try { fs.copyFileSync(postCommitDst, legacyPost); } catch { /* ignore */ }
      }
    }
  }

  // ── Make hooks executable (POSIX) ───────────────────────────────────
  if (!opts.dryRun && process.platform !== "win32") {
    for (const f of ["pre-commit", "post-commit"]) {
      const hookPath = path.join(ctx.githooksDir, f);
      try { fs.chmodSync(hookPath, 0o755); } catch { /* ignore */ }
    }
  }

  // ── Configure portable hooks path ───────────────────────────────────
  if (!opts.dryRun && fs.existsSync(ctx.gitDir)) {
    try {
      const current = spawnSync("git", ["-C", ctx.repoRoot, "config", "core.hooksPath"], {
        encoding: "utf8", timeout: 5000, windowsHide: true,
      });
      const currentPath = (current.stdout || "").trim();
      if (currentPath !== ".githooks") {
        const result = spawnSync("git", ["-C", ctx.repoRoot, "config", "core.hooksPath", ".githooks"], {
          encoding: "utf8", timeout: 5000, windowsHide: true,
        });
        if (result.status === 0) {
          console.log("Configured: git config core.hooksPath .githooks");
        }
      }
    } catch { /* ignore */ }
  }
}

module.exports = { installGitHooks };
