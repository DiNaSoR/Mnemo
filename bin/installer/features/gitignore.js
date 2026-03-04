"use strict";
/**
 * gitignore.js — Managed .gitignore block for Mnemo artifacts.
 */

const fs   = require("fs");
const path = require("path");

const GI_BEGIN = "# >>> Mnemo (generated) - do not edit this block manually <<<";
const GI_END   = "# <<< Mnemo (generated) >>>";

const IGNORE_LINES = `.mnemo/
.cursor/memory/
.cursor/rules/
.cursor/skills/
.cursor/mcp.json
.agent/rules/
scripts/memory/
.githooks/`;

/**
 * Update .gitignore with a managed Mnemo block.
 * @param {object} ctx - path context
 * @param {object} opts - { enableVector, dryRun }
 */
function updateGitignore(ctx, opts) {
  const gi = path.join(ctx.repoRoot, ".gitignore");
  const block = `${GI_BEGIN}\n${IGNORE_LINES}\n${GI_END}`;

  if (opts.dryRun) {
    console.log(`[DRY RUN] WOULD UPDATE: ${gi} (managed Mnemo block)`);
    return;
  }

  if (!fs.existsSync(gi)) {
    fs.writeFileSync(gi, block + "\n", "utf8");
    console.log("Created .gitignore with Mnemo managed block");
    return;
  }

  let content = fs.readFileSync(gi, "utf8");

  if (content.includes(GI_BEGIN)) {
    // Replace existing managed block
    const re = new RegExp(
      escapeRegex(GI_BEGIN) + "[\\s\\S]*?" + escapeRegex(GI_END),
      "m"
    );
    content = content.replace(re, block);
    fs.writeFileSync(gi, content, "utf8");
    console.log("Updated .gitignore managed block");
  } else {
    // Append
    const nl = content.endsWith("\n") ? "" : "\n";
    fs.appendFileSync(gi, `${nl}\n${block}\n`, "utf8");
    console.log("Added Mnemo managed block to .gitignore");
  }
}

function escapeRegex(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

module.exports = { updateGitignore };
