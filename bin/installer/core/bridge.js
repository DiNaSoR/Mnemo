"use strict";
/**
 * bridge.js — Cross-platform symlink/junction/mirror bridge logic.
 *
 * .mnemo/ is the canonical store. IDE-specific paths (.cursor/, .agent/)
 * are bridges — either symlinks (preferred) or mirror copies (fallback).
 */

const fs   = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

const IS_WIN = process.platform === "win32";

// ─── Helpers ──────────────────────────────────────────────────────────────────

function pathsEqual(a, b) {
  const na = path.resolve(a);
  const nb = path.resolve(b);
  return IS_WIN
    ? na.toLowerCase() === nb.toLowerCase()
    : na === nb;
}

function isSymlink(p) {
  try {
    const st = fs.lstatSync(p);
    return st.isSymbolicLink();
  } catch { return false; }
}

function readlinkSafe(p) {
  try { return fs.readlinkSync(p); } catch { return null; }
}

/**
 * Sync files one-way: src → dst. Only copies files that don't exist in dst
 * or are newer in src.
 */
function syncOneWay(src, dst) {
  if (!fs.existsSync(src)) return 0;
  fs.mkdirSync(dst, { recursive: true });

  let count = 0;
  const entries = fs.readdirSync(src, { withFileTypes: true });

  for (const entry of entries) {
    const srcPath = path.join(src, entry.name);
    const dstPath = path.join(dst, entry.name);

    if (entry.isDirectory()) {
      count += syncOneWay(srcPath, dstPath);
    } else {
      let needsCopy = !fs.existsSync(dstPath);
      if (!needsCopy) {
        const srcStat = fs.statSync(srcPath);
        const dstStat = fs.statSync(dstPath);
        needsCopy = srcStat.mtimeMs > dstStat.mtimeMs;
      }
      if (needsCopy) {
        fs.mkdirSync(path.dirname(dstPath), { recursive: true });
        fs.copyFileSync(srcPath, dstPath);
        count++;
      }
    }
  }
  return count;
}

// ─── Symlink creation ─────────────────────────────────────────────────────────

function trySymlink(target, linkPath, type) {
  try {
    fs.symlinkSync(target, linkPath, type);
    return "symlink";
  } catch { return null; }
}

function tryJunction(target, linkPath) {
  if (!IS_WIN) return null;
  try {
    // Junction — works without admin on Windows
    fs.symlinkSync(target, linkPath, "junction");
    return "junction";
  } catch { return null; }
}

// ─── Directory bridge ─────────────────────────────────────────────────────────

/**
 * Ensure a directory bridge exists: canonical ↔ bridge.
 * Strategy: symlink → junction (Win) → mirror copy
 *
 * @param {string} canonical - the canonical directory (e.g. .mnemo/memory)
 * @param {string} bridge - the bridge directory (e.g. .cursor/memory)
 * @param {object} opts - { dryRun }
 * @returns {string} bridge mode: "symlink"|"junction"|"mirror"|"linked"
 */
function ensureDirBridge(canonical, bridge, opts = {}) {
  fs.mkdirSync(canonical, { recursive: true });
  fs.mkdirSync(path.dirname(bridge), { recursive: true });

  // Already a valid symlink?
  if (isSymlink(bridge)) {
    const target = readlinkSafe(bridge);
    if (target && pathsEqual(target, canonical)) {
      console.log(`BRIDGE (linked): ${bridge} -> ${canonical}`);
      return "linked";
    }
    // Stale symlink — repair
    if (opts.dryRun) {
      console.log(`[DRY RUN] WOULD REPAIR BRIDGE: ${bridge} -> ${canonical}`);
      return "dry-run";
    }
    fs.rmSync(bridge, { recursive: true, force: true });
  }

  // Existing real directory — merge and mirror
  if (fs.existsSync(bridge) && !isSymlink(bridge)) {
    if (opts.dryRun) {
      console.log(`[DRY RUN] WOULD MIRROR: ${bridge} <-> ${canonical}`);
      return "dry-run";
    }
    syncOneWay(bridge, canonical);
    syncOneWay(canonical, bridge);
    console.log(`BRIDGE (mirror): ${bridge} <-> ${canonical}`);
    return "mirror";
  }

  // Nothing exists at bridge — try symlink/junction first
  if (!fs.existsSync(bridge)) {
    if (opts.dryRun) {
      console.log(`[DRY RUN] WOULD CREATE SYMLINK: ${bridge} -> ${canonical}`);
      return "dry-run";
    }

    const mode = trySymlink(canonical, bridge, "dir") || tryJunction(canonical, bridge);
    if (mode) {
      console.log(`BRIDGE (${mode}): ${bridge} -> ${canonical}`);
      return mode;
    }

    // Fallback: mirror copy
    fs.mkdirSync(bridge, { recursive: true });
    syncOneWay(canonical, bridge);
    console.log(`BRIDGE (mirror): ${bridge} <-> ${canonical}`);
    return "mirror";
  }

  return "mirror";
}

// ─── File bridge ──────────────────────────────────────────────────────────────

/**
 * Ensure a file bridge exists: canonical ↔ bridge.
 * Strategy: symlink → hard link → copy
 *
 * @param {string} canonical - canonical file path
 * @param {string} bridge - bridge file path
 * @param {object} opts - { dryRun }
 * @returns {string} bridge mode
 */
function ensureFileBridge(canonical, bridge, opts = {}) {
  fs.mkdirSync(path.dirname(canonical), { recursive: true });
  fs.mkdirSync(path.dirname(bridge), { recursive: true });

  // If canonical doesn't exist but bridge does, copy bridge → canonical
  if (!fs.existsSync(canonical) && fs.existsSync(bridge)) {
    if (opts.dryRun) {
      console.log(`[DRY RUN] WOULD COPY: ${bridge} -> ${canonical}`);
    } else {
      fs.copyFileSync(bridge, canonical);
    }
  }

  if (!fs.existsSync(canonical)) return "missing-canonical";

  // Already a valid symlink?
  if (isSymlink(bridge)) {
    const target = readlinkSafe(bridge);
    if (target && pathsEqual(target, canonical)) {
      console.log(`BRIDGE (linked): ${bridge} -> ${canonical}`);
      return "linked";
    }
    if (!opts.dryRun) fs.rmSync(bridge, { force: true });
  }

  if (!fs.existsSync(bridge)) {
    if (opts.dryRun) {
      console.log(`[DRY RUN] WOULD CREATE FILE SYMLINK: ${bridge} -> ${canonical}`);
      return "dry-run";
    }
    const mode = trySymlink(canonical, bridge, "file");
    if (mode) {
      console.log(`BRIDGE (${mode}): ${bridge} -> ${canonical}`);
      return mode;
    }
    // Fallback: copy
    fs.copyFileSync(canonical, bridge);
    console.log(`BRIDGE (mirror): ${bridge} <- ${canonical}`);
    return "mirror";
  }

  // Both exist as real files — sync newer → older, then ensure bridge matches
  if (!opts.dryRun) {
    const cStat = fs.statSync(canonical);
    const bStat = fs.statSync(bridge);
    if (bStat.mtimeMs > cStat.mtimeMs) {
      fs.copyFileSync(bridge, canonical);
    }
    fs.copyFileSync(canonical, bridge);
  }
  console.log(`BRIDGE (mirror): ${bridge} <-> ${canonical}`);
  return "mirror";
}

module.exports = { ensureDirBridge, ensureFileBridge, syncOneWay, pathsEqual };
