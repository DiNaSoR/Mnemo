# Contributing to Mnemo

Thank you for your interest in contributing. This document explains how to report issues, propose changes, and get your contributions merged quickly and safely.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Ways to Contribute](#ways-to-contribute)
- [Reporting Bugs](#reporting-bugs)
- [Requesting Features](#requesting-features)
- [Development Setup](#development-setup)
- [Making Changes](#making-changes)
- [Pull Request Guidelines](#pull-request-guidelines)
- [Versioning Policy](#versioning-policy)
- [Support Matrix](#support-matrix)

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). By participating you agree to abide by its terms. Please report unacceptable behavior to the maintainer (see [SECURITY.md](SECURITY.md) for contact details).

## Ways to Contribute

| Type | How |
|------|-----|
| Bug report | Open a GitHub issue using the **Bug report** template |
| Feature request | Open a GitHub issue using the **Feature request** template |
| Documentation fix | PR directly against `main` |
| Code change | Fork → branch → PR — see below |
| New agent integration | Open an issue first to discuss before coding |

## Reporting Bugs

Please use the [Bug report](.github/ISSUE_TEMPLATE/bug_report.yml) template. Include:

- Mnemo version (run the installer with `-Force` and check the `VERSION` file or the console output)
- OS, PowerShell or shell version
- Full console output (use code blocks)
- Minimal reproduction steps

## Requesting Features

Use the [Feature request](.github/ISSUE_TEMPLATE/feature_request.yml) template. Describe the problem you want solved, not the implementation. We prefer one focused feature per issue.

## Development Setup

```powershell
# Clone the repo
git clone https://github.com/DiNaSoR/Mnemo.git
cd Mnemo

# Run the installer in a temp directory to verify it works
mkdir ../mnemo-test
node .\bin\mnemo.js --yes --repo-root ..\mnemo-test --project-name TestProject

# Run linter on the result
powershell -ExecutionPolicy Bypass -File ..\mnemo-test\scripts\memory\lint-memory.ps1
```

macOS / Linux:

```sh
mkdir ../mnemo-test
node ./bin/mnemo.js --yes --repo-root ../mnemo-test --project-name TestProject
sh ../mnemo-test/scripts/memory/lint-memory.sh
```

No extra tooling is required beyond Node.js 18+. PowerShell 5.1+ (Windows) and a POSIX shell (macOS/Linux) are only needed if you want to run the platform-specific helper scripts after install.

### Optional: Python for SQLite + vector tests

```sh
python3 -m pip install openai sqlite-vec "mcp[cli]>=1.2.0,<2.0"
```

## Making Changes

1. **Fork** the repository and create a branch:
   ```sh
   git checkout -b fix/description-of-change
   ```
   Branch naming: `fix/`, `feat/`, `docs/`, `refactor/`, `ci/`, `test/`

2. **Edit** the relevant file(s). The primary installer sources of truth are:
   - [`bin/mnemo.js`](bin/mnemo.js) — CLI entry point + wizard
   - [`bin/installer/`](bin/installer/) — unified installer modules
   - [`scripts/memory/installer/templates/`](scripts/memory/installer/templates/) — generated helper/template content
   - [`VERSION`](VERSION) — single version source

   If you change generated installer output, update the corresponding templates and helper scripts across supported platforms.

3. **Test** your change locally (see [Development Setup](#development-setup)).

4. **Bump the version** in [`VERSION`](VERSION) if your change affects installed output or user-visible behaviour:
   - Patch (`3.3.x`): bug fixes only
   - Minor (`3.x.0`): backward-compatible new features
   - Major (`x.0.0`): breaking changes (requires a migration note in `CHANGELOG.md`)

5. **Add a `CHANGELOG.md` entry** under `[Unreleased]`.

6. Commit with a short imperative message:
   ```
   fix: prevent duplicate .gitignore entries on re-run
   feat: add --dry-run flag to installers
   ```

## Pull Request Guidelines

- Fill in all sections of the [PR template](.github/PULL_REQUEST_TEMPLATE.md).
- Keep PRs focused: one bug or one feature per PR.
- CI must pass before review.
- A maintainer will review within **7 days**. If you haven't heard back in 14 days, ping the thread.
- Breaking changes require a `BREAKING CHANGE:` line in the commit body and a migration section in `CHANGELOG.md`.

## Versioning Policy

Mnemo follows [Semantic Versioning](https://semver.org/). The single source of truth for the version is the [`VERSION`](VERSION) file at repo root. The unified Node installer reads this file and embeds the version into generated output.

Breaking changes at the CLI parameter level are avoided within a major version. Additions to generated file templates are considered non-breaking.

## Support Matrix

| Platform | Installer | Min version |
|----------|-----------|-------------|
| Windows | `node bin/mnemo.js --yes --repo-root ... --project-name ...` | Node.js 18+ |
| macOS | `node bin/mnemo.js --yes --repo-root ... --project-name ...` | Node.js 18+ |
| Linux | `node bin/mnemo.js --yes --repo-root ... --project-name ...` | Node.js 18+ |

Python is optional (SQLite index + vector layer). Minimum Python 3.9 (SQLite), 3.10+ (vector mode).
