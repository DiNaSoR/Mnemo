## Summary

<!-- What does this PR do? One or two sentences. -->

## Type of change

- [ ] Bug fix (non-breaking, fixes an issue)
- [ ] New feature (non-breaking, adds functionality)
- [ ] Breaking change (changes existing CLI flags or generated file structure)
- [ ] Documentation update
- [ ] Refactor / internal improvement
- [ ] CI / tooling change

## Related issues

Closes #<!-- issue number -->

## Changes

<!-- List the files changed and why. For installer changes, note which unified installer modules/templates were updated. -->

- 
- 

## Testing

<!-- How did you test this? Paste the commands you ran and their output. -->

- [ ] Ran `node bin/mnemo.js --yes --repo-root <temp-dir> --project-name <name>` from scratch in a clean directory
- [ ] Ran installer a second time (idempotency — should skip existing files)
- [ ] Ran installer with `--force` (should overwrite files)
- [ ] Ran `scripts/memory/lint-memory.ps1` / `lint-memory.sh` — passed
- [ ] Ran `scripts/memory/rebuild-memory-index.ps1` / `rebuild-memory-index.sh` — passed

## Compatibility checklist

- [ ] Change is reflected in the unified Node installer and any affected generated helper templates (`.ps1` / `.sh`), **or** the change is intentionally platform-specific (explain below)
- [ ] No new required dependencies added without updating `CONTRIBUTING.md` support matrix
- [ ] `VERSION` bumped if user-visible output changed
- [ ] `CHANGELOG.md` updated under `[Unreleased]`

## Breaking change migration notes

<!-- Fill in if "Breaking change" is checked above. Describe what users must do when upgrading. -->
