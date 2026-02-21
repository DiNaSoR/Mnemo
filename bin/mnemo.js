#!/usr/bin/env node

const { spawnSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const packageRoot = path.resolve(__dirname, "..");
const cwd = process.cwd();
const rawArgs = process.argv.slice(2);
const wantsHelp = rawArgs.includes("--help") || rawArgs.includes("-h");

function printHelp() {
  console.log(`Mnemo CLI

Usage:
  npx @dinasor/mnemo-cli@latest [options]

Options:
  --dry-run
  --force
  --enable-vector
  --vector-provider <openai|gemini>
  --project-name <name>
  --repo-root <path>   (defaults to current directory)
  --help
`);
}

function fail(message) {
  console.error(`[mnemo] ${message}`);
  process.exit(1);
}

function mapWindowsArgs(args) {
  const mapped = [];
  let hasRepoRoot = false;

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];

    if (arg === "--dry-run") {
      mapped.push("-DryRun");
      continue;
    }
    if (arg === "--force") {
      mapped.push("-Force");
      continue;
    }
    if (arg === "--enable-vector") {
      mapped.push("-EnableVector");
      continue;
    }
    if (arg === "--vector-provider") {
      const value = args[i + 1];
      if (!value) fail("Missing value for --vector-provider");
      mapped.push("-VectorProvider", value);
      i += 1;
      continue;
    }
    if (arg === "--project-name") {
      const value = args[i + 1];
      if (!value) fail("Missing value for --project-name");
      mapped.push("-ProjectName", value);
      i += 1;
      continue;
    }
    if (arg === "--repo-root") {
      const value = args[i + 1];
      if (!value) fail("Missing value for --repo-root");
      mapped.push("-RepoRoot", value);
      hasRepoRoot = true;
      i += 1;
      continue;
    }

    if (arg.toLowerCase() === "-reporoot") {
      hasRepoRoot = true;
    }
    mapped.push(arg);
  }

  if (!hasRepoRoot && !wantsHelp) {
    mapped.push("-RepoRoot", cwd);
  }
  return mapped;
}

function mapPosixArgs(args) {
  const mapped = [];
  let hasRepoRoot = false;

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];
    mapped.push(arg);

    if (arg === "--repo-root") {
      if (!args[i + 1]) fail("Missing value for --repo-root");
      mapped.push(args[i + 1]);
      hasRepoRoot = true;
      i += 1;
    }
  }

  if (!hasRepoRoot && !wantsHelp) {
    mapped.push("--repo-root", cwd);
  }
  return mapped;
}

if (wantsHelp) {
  printHelp();
  process.exit(0);
}

if (process.platform === "win32") {
  const installer = path.join(packageRoot, "memory.ps1");
  if (!fs.existsSync(installer)) {
    fail(`Installer not found at ${installer}`);
  }

  const args = [
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    installer,
    ...mapWindowsArgs(rawArgs)
  ];
  const result = spawnSync("powershell", args, { stdio: "inherit" });
  process.exit(result.status ?? 1);
}

const installer = path.join(packageRoot, "memory_mac.sh");
if (!fs.existsSync(installer)) {
  fail(`Installer not found at ${installer}`);
}
const result = spawnSync("sh", [installer, ...mapPosixArgs(rawArgs)], {
  stdio: "inherit"
});
process.exit(result.status ?? 1);
