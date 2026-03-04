"use strict";
/**
 * writer.js — Cross-platform safe file writer for Mnemo installer.
 * Handles skip-if-exists, force overwrite, dry-run, and atomic writes.
 */

const fs   = require("fs");
const path = require("path");

/**
 * Ensure a directory exists (recursive).
 * @param {string} dirPath
 * @param {object} opts - { dryRun }
 */
function mkdirp(dirPath, opts = {}) {
  if (fs.existsSync(dirPath)) return;
  if (opts.dryRun) {
    console.log(`[DRY RUN] WOULD CREATE DIR: ${dirPath}`);
    return;
  }
  fs.mkdirSync(dirPath, { recursive: true });
}

/**
 * Write a file safely with skip/force/dry-run semantics.
 * Uses atomic write (tmp + rename) to prevent partial writes.
 *
 * @param {string} filePath
 * @param {string} content
 * @param {object} opts - { force, dryRun }
 * @returns {string} "WROTE" | "SKIP" | "DRY_RUN"
 */
function writeFile(filePath, content, opts = {}) {
  const exists = fs.existsSync(filePath);

  if (exists && !opts.force) {
    console.log(`SKIP (exists): ${filePath}`);
    return "SKIP";
  }

  if (opts.dryRun) {
    console.log(`[DRY RUN] WOULD WRITE: ${filePath}`);
    return "DRY_RUN";
  }

  // Ensure parent directory
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  // Atomic write: write to temp file, then rename
  const tmp = `${filePath}.tmp.${process.pid}`;
  try {
    fs.writeFileSync(tmp, content, "utf8");
    fs.renameSync(tmp, filePath);
  } catch (err) {
    // Clean up temp file on failure
    try { fs.unlinkSync(tmp); } catch { /* ignore */ }
    throw err;
  }

  console.log(`WROTE: ${filePath}`);
  return "WROTE";
}

/**
 * Copy a file with skip/force/dry-run semantics.
 *
 * @param {string} src - source file path
 * @param {string} dest - destination file path
 * @param {object} opts - { force, dryRun }
 * @returns {string} "WROTE" | "SKIP" | "DRY_RUN" | "MISSING"
 */
function copyFile(src, dest, opts = {}) {
  if (!fs.existsSync(src)) {
    console.log(`WARNING: Template not found: ${src}`);
    return "MISSING";
  }

  if (fs.existsSync(dest) && !opts.force) {
    console.log(`SKIP (exists): ${dest}`);
    return "SKIP";
  }

  if (opts.dryRun) {
    console.log(`[DRY RUN] WOULD WRITE: ${dest}`);
    return "DRY_RUN";
  }

  const dir = path.dirname(dest);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }

  fs.copyFileSync(src, dest);
  console.log(`WROTE: ${dest}`);
  return "WROTE";
}

/**
 * Copy an entire directory recursively with skip/force/dry-run.
 *
 * @param {string} srcDir
 * @param {string} destDir
 * @param {object} opts - { force, dryRun }
 * @returns {number} count of files copied
 */
function copyDir(srcDir, destDir, opts = {}) {
  if (!fs.existsSync(srcDir)) return 0;

  mkdirp(destDir, opts);

  let count = 0;
  const entries = fs.readdirSync(srcDir, { withFileTypes: true });

  for (const entry of entries) {
    const srcPath  = path.join(srcDir, entry.name);
    const destPath = path.join(destDir, entry.name);

    if (entry.isDirectory()) {
      count += copyDir(srcPath, destPath, opts);
    } else {
      const result = copyFile(srcPath, destPath, opts);
      if (result === "WROTE" || result === "DRY_RUN") count++;
    }
  }

  return count;
}

module.exports = { mkdirp, writeFile, copyFile, copyDir };
