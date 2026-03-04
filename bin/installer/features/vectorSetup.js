"use strict";
/**
 * vectorSetup.js — Vector engine setup: Python deps + rules.
 */

const { spawnSync } = require("child_process");
const fs   = require("fs");
const path = require("path");
const { writeFile }       = require("../core/writer");
const { renderFile, buildVars } = require("../core/template");

const IS_WIN = process.platform === "win32";

/**
 * Find a working Python >= 3.10
 * @returns {{ cmd: string|null, ver: string|null, ok: boolean }}
 */
function findPython() {
  const candidates = IS_WIN ? ["py", "python", "python3"] : ["python3", "python"];
  for (const cmd of candidates) {
    const args = IS_WIN && cmd === "py" ? ["-3", "--version"] : ["--version"];
    const r = spawnSync(cmd, args, { encoding: "utf8", timeout: 10000, windowsHide: true });
    if (r.status !== 0) continue;
    const m = (r.stdout || r.stderr || "").match(/Python (\d+)\.(\d+)\.(\d+)/);
    if (!m) continue;
    const [, maj, min, patch] = m.map(Number);
    return { cmd, ver: `${maj}.${min}.${patch}`, ok: maj > 3 || (maj === 3 && min >= 10) };
  }
  return { cmd: null, ver: null, ok: false };
}

/**
 * Install Python dependencies for vector mode.
 * @param {object} ctx - path context
 * @param {object} opts - { vectorProvider, force, dryRun, installerRoot }
 * @returns {string|null} python command if successful
 */
function installVectorDeps(ctx, opts) {
  if (opts.dryRun) {
    console.log("[DRY RUN] WOULD INSTALL: vector Python dependencies");
    return null;
  }

  const py = findPython();
  if (!py.ok) {
    console.log(`WARNING: Python 3.10+ not found (found: ${py.ver || "none"}). Skipping vector dependencies.`);
    return null;
  }

  const baseArgs = IS_WIN && py.cmd === "py" ? ["-3"] : [];
  const packages = ["openai", "sqlite-vec>=0.1.1", "mcp[cli]>=1.2.0,<2.0", "pyyaml>=6.0"];
  if (opts.vectorProvider === "gemini") packages.push("google-genai");

  console.log(`Installing vector dependencies (${opts.vectorProvider} mode)...`);
  const r = spawnSync(py.cmd, [...baseArgs, "-m", "pip", "install", "--quiet", ...packages], {
    encoding: "utf8",
    stdio: "inherit",
    timeout: 120000,
  });

  if (r.status !== 0) {
    console.log("WARNING: pip install failed. Vector tools may not work until dependencies are installed.");
  }

  return py.cmd;
}

/**
 * Install vector search rules (Cursor + Agent).
 * @param {object} ctx - path context
 * @param {object} opts - { version, force, dryRun, installerRoot }
 */
function installVectorRules(ctx, opts) {
  const vars    = buildVars(opts);
  const rulesDir = path.join(opts.installerRoot, "scripts", "memory", "installer", "templates", "rules");
  const wo       = { force: opts.force, dryRun: opts.dryRun };

  // Cursor rule
  const cursorSrc = path.join(rulesDir, "01-vector-search.mdc.tmpl");
  if (fs.existsSync(cursorSrc)) {
    const content = renderFile(cursorSrc, vars);
    writeFile(path.join(ctx.rulesCursorDir, "01-vector-search.mdc"), content, wo);
  }

  // Agent rule
  const agentSrc = path.join(rulesDir, "01-vector-search-agent.md");
  if (fs.existsSync(agentSrc)) {
    const content = fs.readFileSync(agentSrc, "utf8");
    writeFile(path.join(ctx.rulesAgentDir, "01-vector-search.md"), content, wo);
  }
}

module.exports = { findPython, installVectorDeps, installVectorRules };
