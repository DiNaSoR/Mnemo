#!/usr/bin/env node
"use strict";

/**
 * Mnemo CLI — interactive wizard + unified Node.js installer.
 *
 * When stdin is a TTY (and --yes is not passed) the wizard:
 *   1. Asks whether to enable vector/semantic search mode.
 *   2. Asks which embedding provider (gemini / openai).
 *   3. Checks for an existing API key (env / .env file), or lets the user
 *      enter one now (saved to project .env) or skip.
 *   4. Checks all runtime dependencies and reports their status.
 *   5. Runs the unified Node.js installer (bin/installer/index.js).
 *
 * When --yes / -y is passed, or stdin is not a TTY, the wizard is skipped
 * and the installer runs immediately using whatever flags were supplied.
 */

const { spawnSync } = require("child_process");
const fs   = require("fs");
const path = require("path");
const rl   = require("readline");

// ─── Constants ────────────────────────────────────────────────────────────────
const PKG_ROOT = path.resolve(__dirname, "..");
const CWD      = process.cwd();
const IS_WIN   = process.platform === "win32";
const ARGV     = process.argv.slice(2);

// ─── ANSI color helpers ───────────────────────────────────────────────────────
const HAS_COLOR = !!process.stdout.isTTY && !process.env.NO_COLOR;
const esc  = (n) => HAS_COLOR ? `\x1b[${n}m` : "";

const R   = esc(0);    // reset
const BO  = esc(1);    // bold
const DI  = esc(2);    // dim
const CY  = esc(36);   // cyan
const GR  = esc(32);   // green
const YE  = esc(33);   // yellow
const RE  = esc(31);   // red
const WH  = esc(97);   // bright white
const BCY = esc(96);   // bright cyan
const BGR = esc(92);   // bright green
const BRE = esc(91);   // bright red
const BYE = esc(93);   // bright yellow
const MG  = esc(35);   // magenta

const bold   = (s) => `${BO}${s}${R}`;
const dim    = (s) => `${DI}${s}${R}`;
const cyan   = (s) => `${CY}${s}${R}`;
const green  = (s) => `${GR}${s}${R}`;
const yellow = (s) => `${YE}${s}${R}`;

const TICK  = `${BGR}✓${R}`;
const CROSS = `${BRE}✗${R}`;
const WARN  = `${BYE}⚠${R}`;
const ARROW = `${BCY}›${R}`;

// ─── Layout helpers ───────────────────────────────────────────────────────────
const W = 62; // box inner content width

function padR(s, n) { return s + " ".repeat(Math.max(0, n - s.length)); }

function banner(version) {
  const bar  = "═".repeat(W);
  const t1   = `Mnemo v${version}  ·  Memory Layer for AI Agents`;
  const t2   = `Token-safe · Cursor · Claude Code · Codex & more`;
  const pad1 = W - t1.length - 2;
  const pad2 = W - t2.length - 2;
  process.stdout.write("\n");
  process.stdout.write(`${CY}╔${bar}╗${R}\n`);
  process.stdout.write(`${CY}║${R}  ${WH}${BO}${t1}${R}${" ".repeat(Math.max(0, pad1))}${CY}║${R}\n`);
  process.stdout.write(`${CY}║${R}  ${DI}${t2}${R}${" ".repeat(Math.max(0, pad2))}${CY}║${R}\n`);
  process.stdout.write(`${CY}╚${bar}╝${R}\n`);
  process.stdout.write("\n");
}

function divider() {
  process.stdout.write(`  ${DI}${"─".repeat(W - 2)}${R}\n`);
}

function sectionHeader(title, step, total) {
  divider();
  const stepLabel = total ? `  ${DI}Step ${step}/${total}${R}` : "";
  process.stdout.write(`\n  ${BCY}${BO}${title}${R}${stepLabel}\n\n`);
}

function successBox(vectorMode) {
  const bar  = "═".repeat(W);
  const t1   = `Setup complete!`;
  const pad1 = W - t1.length - 2;
  process.stdout.write("\n");
  process.stdout.write(`${BGR}╔${bar}╗${R}\n`);
  process.stdout.write(`${BGR}║${R}  ${WH}${BO}${t1}${R}${" ".repeat(Math.max(0, pad1))}${BGR}║${R}\n`);
  if (vectorMode) {
    const t2   = `Run vector_health → vector_sync in your IDE`;
    const pad2 = W - t2.length - 2;
    process.stdout.write(`${BGR}║${R}  ${DI}${t2}${R}${" ".repeat(Math.max(0, pad2))}${BGR}║${R}\n`);
  }
  const t3   = `Skill: .cursor/skills/mnemo-codebase-optimizer/`;
  const pad3 = W - t3.length - 2;
  process.stdout.write(`${BGR}║${R}  ${DI}${t3}${R}${" ".repeat(Math.max(0, pad3))}${BGR}║${R}\n`);
  process.stdout.write(`${BGR}╚${bar}╝${R}\n`);
  process.stdout.write("\n");
}

// ─── .env utilities ───────────────────────────────────────────────────────────
function readDotEnv(dir) {
  const envPath = path.join(dir, ".env");
  const result  = {};
  if (!fs.existsSync(envPath)) return result;
  try {
    const text = fs.readFileSync(envPath, "utf8").replace(/^\uFEFF/, "");
    for (const raw of text.split(/\r?\n/)) {
      const line = raw.trim();
      if (!line || line.startsWith("#")) continue;
      const eq = line.indexOf("=");
      if (eq < 1) continue;
      const key = line.slice(0, eq).trim();
      const val = line.slice(eq + 1).trim().replace(/^['"]|['"]$/g, "");
      result[key] = val;
    }
  } catch { /* ignore */ }
  return result;
}

function appendDotEnv(dir, key, value) {
  const envPath = path.join(dir, ".env");
  try {
    if (fs.existsSync(envPath)) {
      let content = fs.readFileSync(envPath, "utf8");
      const re    = new RegExp(`^${key}=.*$`, "m");
      if (re.test(content)) {
        fs.writeFileSync(envPath, content.replace(re, `${key}=${value}`));
        return;
      }
      const nl = content.endsWith("\n") ? "" : "\n";
      fs.appendFileSync(envPath, `${nl}${key}=${value}\n`);
    } else {
      fs.writeFileSync(envPath, `${key}=${value}\n`);
    }
  } catch (e) {
    process.stdout.write(`  ${WARN} Could not write .env: ${e.message}\n`);
  }
}

/**
 * Returns true if the value is a real, usable string —
 * not empty, not an unresolved Cursor MCP placeholder like ${env:FOO}.
 */
function isRealValue(v) {
  if (!v) return false;
  const s = v.trim();
  if (!s) return false;
  if (s.startsWith("${env:") && s.endsWith("}")) return false;
  return true;
}

// ─── Dependency detection ─────────────────────────────────────────────────────
function runCmd(cmd, args, opts = {}) {
  return spawnSync(cmd, args, {
    encoding: "utf8",
    timeout: 15000,
    windowsHide: true,
    ...opts,
  });
}

function checkNode() {
  return { ver: process.version, ok: true };
}

function checkGit() {
  const r = runCmd("git", ["--version"]);
  if (r.status !== 0) return { ver: null, ok: false };
  const m = (r.stdout || "").match(/git version (.+)/);
  return { ver: m ? m[1].trim() : "?", ok: true };
}

function findPython() {
  const candidates = IS_WIN ? ["py", "python", "python3"] : ["python3", "python"];
  for (const cmd of candidates) {
    const r = runCmd(cmd, IS_WIN && cmd === "py" ? ["-3", "--version"] : ["--version"]);
    if (r.status !== 0) continue;
    const raw = (r.stdout || r.stderr || "").trim();
    const m   = raw.match(/Python (\d+)\.(\d+)\.(\d+)/);
    if (!m) continue;
    const [, maj, min] = m.map(Number);
    return {
      cmd,
      ver: `${maj}.${min}.${m[3]}`,
      ok:  maj > 3 || (maj === 3 && min >= 10),
    };
  }
  return { cmd: null, ver: null, ok: false };
}

function checkPip(pythonCmd) {
  const args = IS_WIN && pythonCmd === "py" ? ["-3", "-m", "pip", "--version"] : ["-m", "pip", "--version"];
  const r    = runCmd(pythonCmd, args);
  if (r.status !== 0) return { ver: null, ok: false };
  const m = (r.stdout || "").match(/pip (\S+)/);
  return { ver: m ? m[1] : "?", ok: true };
}

function checkPipPkg(pythonCmd, pkgName) {
  const baseArgs = IS_WIN && pythonCmd === "py" ? ["-3"] : [];
  const r = runCmd(pythonCmd, [...baseArgs, "-m", "pip", "show", pkgName]);
  if (r.status !== 0) return { installed: false, ver: null };
  const m = (r.stdout || "").match(/^Version:\s*(.+)$/m);
  return { installed: true, ver: m ? m[1].trim() : "?" };
}

function depRow(label, verStr, statusStr) {
  const lc = padR(label, 22);
  const vc = padR(verStr, 14);
  process.stdout.write(`    ${DI}${lc}${R}  ${CY}${vc}${R}  ${statusStr}\n`);
}

async function runDependencyCheck(vectorMode, provider, pythonInfo) {
  process.stdout.write("\n");
  process.stdout.write(`  ${BCY}${BO}Checking requirements${R}\n`);
  process.stdout.write(`  ${DI}${"─".repeat(50)}${R}\n`);
  process.stdout.write("\n");

  // Node.js — always present (we are running in it)
  const node = checkNode();
  depRow("Node.js", node.ver, `${TICK} ready`);

  // Git
  const git = checkGit();
  depRow("Git", git.ver || "not found", git.ok ? `${TICK} ready` : `${WARN} recommended (not found)`);

  if (vectorMode) {
    // Python
    const py = pythonInfo || findPython();
    if (!py.ok) {
      depRow(
        "Python",
        py.ver || "not found",
        py.ver ? `${CROSS} Python 3.10+ required (found ${py.ver})` : `${CROSS} Python 3.10+ required`,
      );
    } else {
      depRow("Python", py.ver, `${TICK} ready`);
    }

    if (py.cmd && py.ok) {
      // pip
      const pip = checkPip(py.cmd);
      depRow("pip", pip.ver || "not found", pip.ok ? `${TICK} ready` : `${WARN} pip missing`);

      if (pip.ok) {
        process.stdout.write("\n");
        process.stdout.write(`  ${DI}  Python packages (${provider} mode):${R}\n`);
        process.stdout.write("\n");

        const core  = ["openai", "sqlite-vec", "mcp"];
        const extra = provider === "gemini" ? ["google-genai"] : [];
        const pkgs  = [...core, ...extra];

        for (const pkg of pkgs) {
          // Show "checking…" then overwrite with result
          const label = padR(pkg, 22);
          process.stdout.write(`    ${DI}${label}${R}  ${DI}checking…${R}`);
          const res = checkPipPkg(py.cmd, pkg);
          // Overwrite the line
          process.stdout.write(`\r${" ".repeat(W)}\r`);
          depRow(
            pkg,
            res.ver || "",
            res.installed ? `${TICK} installed` : `${WARN} will be installed by installer`,
          );
        }
      }
    }
  }

  process.stdout.write("\n");
}

// ─── Interactive readline helpers ────────────────────────────────────────────
function prompt(question) {
  return new Promise((resolve) => {
    const iface = rl.createInterface({ input: process.stdin, output: process.stdout });
    iface.question(question, (answer) => {
      iface.close();
      resolve(answer.trim());
    });
  });
}

async function askYesNo(question, defaultYes = false) {
  const hint = defaultYes ? `${DI}[Y/n]${R}` : `${DI}[y/N]${R}`;
  const ans  = await prompt(`    ${ARROW} ${question} ${hint} `);
  if (!ans) return defaultYes;
  return /^y(es)?$/i.test(ans);
}

async function askChoice(question, choices, defaultIdx = 0) {
  process.stdout.write(`    ${ARROW} ${question}\n\n`);
  choices.forEach((ch, i) => {
    const active = i === defaultIdx;
    const num    = active ? `${BCY}${BO}[${i + 1}]${R}` : `${DI}[${i + 1}]${R}`;
    process.stdout.write(`        ${num} ${ch}\n`);
  });
  process.stdout.write("\n");
  const ans = await prompt(`    ${DI}Choice${R} ${DI}[${defaultIdx + 1}]${R}: `);
  const num = parseInt(ans, 10);
  if (!ans || isNaN(num) || num < 1 || num > choices.length) return defaultIdx;
  return num - 1;
}

async function askText(question, hint = "") {
  const hintStr = hint ? ` ${DI}${hint}${R}` : "";
  return prompt(`    ${ARROW} ${question}${hintStr}: `);
}

// ─── Flag parser ──────────────────────────────────────────────────────────────
function parseFlags(args) {
  const flags = {
    enableVector:   false,
    vectorProvider: null,   // null = not yet specified
    dryRun:         false,
    force:          false,
    projectName:    null,
    repoRoot:       null,
    yes:            false,
    help:           false,
  };

  for (let i = 0; i < args.length; i++) {
    const a = args[i].toLowerCase();
    switch (a) {
      case "--enable-vector":
      case "-enablevector":    flags.enableVector   = true; break;
      case "--dry-run":
      case "-dryrun":          flags.dryRun         = true; break;
      case "--force":
      case "-force":           flags.force          = true; break;
      case "--yes": case "-y": flags.yes            = true; break;
      case "--help": case "-h":flags.help           = true; break;
      case "--vector-provider":
      case "-vectorprovider":
        flags.vectorProvider = args[++i]; break;
      case "--project-name":
      case "-projectname":
        flags.projectName = args[++i]; break;
      case "--repo-root":
      case "-reporoot":
        flags.repoRoot = args[++i]; break;
      default:
        // ignore unknown flags gracefully
    }
  }
  return flags;
}

// ─── Help ─────────────────────────────────────────────────────────────────────
function printHelp(version) {
  banner(version);
  process.stdout.write(`${BO}Usage:${R}\n`);
  process.stdout.write(`  npx @dinasor/mnemo-cli@latest [options]\n\n`);
  process.stdout.write(`${BO}Options:${R}\n`);
  const opt = (f, d) =>
    process.stdout.write(`  ${CY}${padR(f, 32)}${R} ${DI}${d}${R}\n`);
  opt("--enable-vector",              "Enable semantic vector search mode");
  opt("--vector-provider <name>",     "Embedding provider: gemini | openai");
  opt("--dry-run",                    "Preview without writing any files");
  opt("--force",                      "Overwrite existing Mnemo files");
  opt("--project-name <name>",        "Override the project name");
  opt("--repo-root <path>",           "Target directory (default: cwd)");
  opt("--yes / -y",                   "Non-interactive — skip wizard prompts");
  opt("--help",                       "Show this help message");
  process.stdout.write("\n");
  process.stdout.write(`${BO}Examples:${R}\n`);
  process.stdout.write(`  ${DI}# Interactive wizard (recommended first-time install)${R}\n`);
  process.stdout.write(`  npx @dinasor/mnemo-cli@latest\n\n`);
  process.stdout.write(`  ${DI}# Non-interactive with gemini vector mode${R}\n`);
  process.stdout.write(`  npx @dinasor/mnemo-cli@latest --enable-vector --vector-provider gemini --yes\n\n`);
  process.stdout.write(`  ${DI}# Dry-run to preview changes${R}\n`);
  process.stdout.write(`  npx @dinasor/mnemo-cli@latest --dry-run\n\n`);
}



// ─── Main ─────────────────────────────────────────────────────────────────────
async function main() {
  const versionFile = path.join(PKG_ROOT, "VERSION");
  const version     = fs.existsSync(versionFile)
    ? fs.readFileSync(versionFile, "utf8").trim()
    : "?";

  const flags       = parseFlags(ARGV);
  const interactive = !flags.yes && !!process.stdin.isTTY;

  if (flags.help) {
    printHelp(version);
    process.exit(0);
  }

  banner(version);

  // ── Step 1: Vector mode ────────────────────────────────────────────────────
  let vectorMode = flags.enableVector;

  if (!vectorMode && interactive) {
    sectionHeader("Vector / Semantic Search Mode", 1, 3);
    process.stdout.write(`  ${DI}Enables semantic vector recall via embedding model APIs.${R}\n`);
    process.stdout.write(`  ${DI}Requires: Python 3.10+  ·  OpenAI or Gemini API key${R}\n\n`);
    vectorMode = await askYesNo("Enable vector / semantic search mode?", false);
    process.stdout.write("\n");
  }

  // ── Step 2: Provider ──────────────────────────────────────────────────────
  let provider = flags.vectorProvider;

  if (vectorMode && !provider && interactive) {
    sectionHeader("Embedding Provider", 2, 3);
    const choice = await askChoice("Which embedding provider do you want to use?", [
      `${BGR}Gemini${R}     ${DI}GEMINI_API_KEY  ·  google-genai  (recommended)${R}`,
      `${CY}OpenAI${R}     ${DI}OPENAI_API_KEY  ·  openai${R}`,
    ], 0);
    provider = choice === 0 ? "gemini" : "openai";
    process.stdout.write("\n");
  }

  if (vectorMode && !provider) provider = "gemini"; // default

  // ── Step 3: API key ───────────────────────────────────────────────────────
  if (vectorMode && interactive) {
    const keyName = provider === "gemini" ? "GEMINI_API_KEY" : "OPENAI_API_KEY";
    const envVal  = process.env[keyName];
    const dotEnv  = readDotEnv(flags.repoRoot || CWD);

    const hasEnvKey    = isRealValue(envVal);
    const hasDotEnvKey = isRealValue(dotEnv[keyName]);

    if (hasEnvKey || hasDotEnvKey) {
      sectionHeader("API Key", 3, 3);
      const src = hasEnvKey ? "shell environment" : ".env file";
      process.stdout.write(`  ${TICK} ${bold(keyName)} already present in ${src}\n\n`);
    } else {
      sectionHeader("API Key Setup", 3, 3);
      process.stdout.write(`  ${WARN} ${bold(keyName)} is not set in your environment.\n\n`);

      const choice = await askChoice(
        "How do you want to provide the API key?",
        [
          `Enter key now     ${DI}→ appended to .env in project root${R}`,
          `Skip (have .env)  ${DI}→ .env already contains the key${R}`,
          `Skip for now      ${DI}→ set ${bold(keyName)} manually later${R}`,
        ],
        0,
      );

      process.stdout.write("\n");

      if (choice === 0) {
        const apiKey = (await askText(`Paste your ${bold(keyName)}`)).trim();
        process.stdout.write("\n");
        if (apiKey) {
          appendDotEnv(flags.repoRoot || CWD, keyName, apiKey);
          process.env[keyName] = apiKey;
          process.stdout.write(`  ${TICK} Key appended to ${bold(".env")}\n`);
        } else {
          process.stdout.write(`  ${WARN} No key entered — set ${bold(keyName)} before using vector tools\n`);
        }
      } else if (choice === 1) {
        process.stdout.write(`  ${TICK} Will load from ${bold(".env")} automatically\n`);
      } else {
        process.stdout.write(`  ${WARN} Skipped — set ${bold(keyName)} in your shell or .env before first use\n`);
      }
      process.stdout.write("\n");
    }
  }

  // ── Dependency check ──────────────────────────────────────────────────────
  const pythonInfo = findPython();
  await runDependencyCheck(vectorMode, provider, pythonInfo);

  // ── Run installer ─────────────────────────────────────────────────────────
  flags.enableVector   = vectorMode;
  if (vectorMode) flags.vectorProvider = provider;

  divider();
  process.stdout.write(`\n  ${BCY}${BO}Running Mnemo installer…${R}\n\n`);
  divider();
  process.stdout.write("\n");

  let result;

  // Run the unified Node.js installer
  const { install } = require("./installer");
  const exitCode = install({
    repoRoot:       flags.repoRoot || CWD,
    projectName:    flags.projectName,
    enableVector:   flags.enableVector,
    vectorProvider: flags.vectorProvider,
    force:          flags.force,
    dryRun:         flags.dryRun,
  }, PKG_ROOT);
  result = { status: exitCode };

  if (result.status === 0) {
    successBox(vectorMode);
    if (vectorMode) {
      process.stdout.write(`  ${ARROW} Open your IDE, restart MCP, and run ${bold("vector_health")} → ${bold("vector_sync")}\n`);
    }
    process.stdout.write(`  ${ARROW} Use the ${bold("mnemo-codebase-optimizer")} skill to quickly seed memory for this codebase\n`);
    process.stdout.write(`     ${DI}.cursor/skills/mnemo-codebase-optimizer/SKILL.md${R}\n`);
    process.stdout.write("\n");
  }

  process.exit(result.status ?? 1);
}

main().catch((err) => {
  process.stderr.write(`\n${CROSS} Fatal error: ${err.message}\n`);
  process.exit(1);
});
