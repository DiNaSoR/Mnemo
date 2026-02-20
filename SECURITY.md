# Security Policy

## Supported Versions

Only the latest release of Mnemo receives security fixes. We do not backport to older versions.

| Version | Supported |
|---------|-----------|
| Latest (main) | Yes |
| Older releases | No |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Please report security issues privately using one of these methods:

1. **GitHub private vulnerability reporting** (preferred): Go to the [Security tab](https://github.com/DiNaSoR/Mnemo/security/advisories/new) of the repository and open a draft advisory.
2. **Email**: Contact the maintainer directly by looking up the email on the [GitHub profile](https://github.com/DiNaSoR).

### What to include

- A description of the vulnerability
- Steps to reproduce (or a proof-of-concept)
- Affected version(s)
- Potential impact in your assessment

### Response timeline

| Stage | Target |
|-------|--------|
| Acknowledgement | Within 3 business days |
| Initial triage | Within 7 days |
| Fix or mitigation | Within 30 days (critical), 90 days (others) |
| Public disclosure | After a fix is available |

We will credit you in the release notes unless you request otherwise.

## Security Scope

Mnemo is a local developer tooling system. The primary security concerns are:

- **File write safety**: The installers write files inside the repo. A malicious `--repo-root` path could cause writes outside the intended directory. Always run installers from a trusted working directory.
- **API key exposure**: Vector mode uses `OPENAI_API_KEY` or `GEMINI_API_KEY`. These are read from environment variables and must not be committed to version control. Mnemo's `.gitignore` ensures `.cursor/mcp.json` (which references key placeholders) is excluded.
- **Pre/post-commit hooks**: The installed hooks run PowerShell/shell scripts on every commit. Review `.githooks/pre-commit` and `.githooks/post-commit` before enabling with `git config core.hooksPath .githooks`.
- **Dependency supply chain** (vector mode): The Python packages `openai`, `sqlite-vec`, and `mcp[cli]` are installed at setup time. Pin versions in your environment if reproducibility is required.

## Out of Scope

- Issues in AI provider APIs (OpenAI, Google) themselves
- Issues in Cursor IDE itself
- Social engineering attacks
