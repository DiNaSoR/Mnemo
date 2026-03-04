"use strict";
/**
 * scaffold.js — Installs memory content files from templates.
 * Replaces memory_scaffold.ps1 + heredocs in memory_mac.sh.
 */

const fs   = require("fs");
const path = require("path");
const { writeFile }              = require("../core/writer");
const { render, renderFile, buildVars } = require("../core/template");

/**
 * Install all memory scaffold content.
 * @param {object} ctx - path context from paths.js
 * @param {object} opts - { projectName, version, force, dryRun, installerRoot }
 */
function installScaffold(ctx, opts) {
  const vars       = buildVars(opts);
  const contentDir = path.join(opts.installerRoot, "scripts", "memory", "installer", "templates", "content");
  const wo         = { force: opts.force, dryRun: opts.dryRun };

  // ── Static content files (no variable substitution) ─────────────────
  const staticFiles = {
    "index.md":               ctx.memoryDir,
    "hot-rules.md":           ctx.memoryDir,
    "active-context.md":      ctx.memoryDir,
    "lessons-README.md":      ctx.lessonsDir,
    "lessons-index.md":       ctx.lessonsDir,
    "journal-README.md":      ctx.journalDir,
    "digests-README.md":      ctx.digestsDir,
    "adr-README.md":          ctx.adrDir,
    "tag-vocabulary.md":      ctx.memoryDir,
    "regression-checklist.md": ctx.memoryDir,
    "lesson.template.md":     ctx.templatesDir,
    "journal-entry.template.md": ctx.templatesDir,
    "adr.template.md":        ctx.templatesDir,
  };

  for (const [filename, destDir] of Object.entries(staticFiles)) {
    const src  = path.join(contentDir, filename);
    // Output filename: strip prefix (e.g. "lessons-README.md" → "README.md")
    const outName = filename.replace(/^(lessons|journal|digests|adr)-/, "");
    const dest = path.join(destDir, outName);

    if (fs.existsSync(src)) {
      const content = fs.readFileSync(src, "utf8");
      writeFile(dest, content, wo);
    }
  }

  // ── Templated content files (variable substitution) ─────────────────
  const tmplFiles = [
    { file: "memo.md.tmpl",          dest: path.join(ctx.memoryDir, "memo.md") },
    { file: "journal-entry.md.tmpl", dest: path.join(ctx.journalDir, `${vars.MONTH}.md`) },
  ];

  for (const { file, dest } of tmplFiles) {
    const src = path.join(contentDir, file);
    if (fs.existsSync(src)) {
      const content = renderFile(src, vars);
      writeFile(dest, content, wo);
    }
  }

  console.log("Memory scaffold installed.");
}

module.exports = { installScaffold };
