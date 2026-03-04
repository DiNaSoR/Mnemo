"use strict";
/**
 * template.js — Simple {{VAR}} template engine for Mnemo.
 * Reads template files (.md.tmpl) and substitutes variables.
 */

const fs   = require("fs");
const path = require("path");

/**
 * Render a template string by replacing {{VAR}} placeholders.
 * @param {string} content - template content with {{VAR}} placeholders
 * @param {object} vars - key/value map of template variables
 * @returns {string} rendered content
 */
function render(content, vars) {
  return content.replace(/\{\{(\w+)\}\}/g, (match, key) => {
    return key in vars ? vars[key] : match;
  });
}

/**
 * Read a template file and render it with variables.
 * @param {string} templatePath - absolute path to the .tmpl file
 * @param {object} vars - template variables
 * @returns {string} rendered content
 */
function renderFile(templatePath, vars) {
  const content = fs.readFileSync(templatePath, "utf8");
  return render(content, vars);
}

/**
 * Build the standard template variables for a Mnemo installation.
 * @param {object} opts - { projectName, version }
 * @returns {object} template variables
 */
function buildVars(opts) {
  const now = new Date();
  const pad = (n) => String(n).padStart(2, "0");

  const year  = now.getFullYear();
  const month = pad(now.getMonth() + 1);
  const day   = pad(now.getDate());

  return {
    PROJECT_NAME: opts.projectName || "MyProject",
    VERSION:      opts.version || "0.0.0",
    TODAY:        `${year}-${month}-${day}`,
    MONTH:        `${year}-${month}`,
    YEAR:         String(year),
  };
}

module.exports = { render, renderFile, buildVars };
