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

<!-- List the files changed and why. For installers, note if the same change was applied to both memory.ps1 AND memory_mac.sh. -->

- 
- 

## Testing

<!-- How did you test this? Paste the commands you ran and their output. -->

- [ ] Ran `memory.ps1` / `memory_mac.sh` from scratch in a clean directory
- [ ] Ran installer a second time (idempotency — should skip existing files)
- [ ] Ran installer with `-Force` / `--force` (should overwrite files)
- [ ] Ran `scripts/memory/lint-memory.ps1` / `lint-memory.sh` — passed
- [ ] Ran `scripts/memory/rebuild-memory-index.ps1` / `rebuild-memory-index.sh` — passed

## Compatibility checklist

- [ ] Change applies equally to both `memory.ps1` (Windows) and `memory_mac.sh` (macOS/Linux), **or** the change is platform-specific and that is intentional (explain below)
- [ ] No new required dependencies added without updating `CONTRIBUTING.md` support matrix
- [ ] `VERSION` bumped if user-visible output changed
- [ ] `CHANGELOG.md` updated under `[Unreleased]`

## Breaking change migration notes

<!-- Fill in if "Breaking change" is checked above. Describe what users must do when upgrading. -->
