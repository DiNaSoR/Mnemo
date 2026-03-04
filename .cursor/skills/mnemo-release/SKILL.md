---
name: mnemo-release
description: Step-by-step release workflow for publishing a new Mnemo version to GitHub + npm
---

# Mnemo Release Skill

Publish a new version of `@dinasor/mnemo-cli` to **GitHub Releases** and **npm**.

> The release is fully automated via `.github/workflows/release.yml`. Your job is to prepare the repo, then push a tag. The pipeline handles the rest.

---

## Pre-flight Checklist

Before releasing, verify ALL of these:

- [ ] All changes are committed and pushed to `main`
- [ ] All CI checks pass on `main` (check GitHub Actions)
- [ ] `VERSION` file contains the target version (e.g. `0.0.8`)
- [ ] `package.json` version matches `VERSION`
- [ ] `CHANGELOG.md` has a `## [X.Y.Z] - YYYY-MM-DD` section with release notes
- [ ] `NPM_TOKEN` secret is configured in GitHub repo settings

---

## Step-by-step

### 1. Decide the new version

Follow [semver](https://semver.org/):
- **Patch** (`0.0.X`): bug fixes, docs, non-breaking tweaks
- **Minor** (`0.X.0`): new features, backward-compatible
- **Major** (`X.0.0`): breaking changes

### 2. Update version files

```sh
# Set the version (replace X.Y.Z with your version)
echo "X.Y.Z" > VERSION
```

Then update `package.json`:

```sh
npm version X.Y.Z --no-git-tag-version
```

### 3. Update CHANGELOG.md

Add a new section **above** `[Unreleased]` content:

```markdown
## [X.Y.Z] - YYYY-MM-DD

### Added
- New feature description

### Changed
- Changed behavior description

### Fixed
- Bug fix description
```

Move relevant items from `[Unreleased]` into the new version section.

### 4. Commit the version bump

```sh
git add VERSION package.json CHANGELOG.md
git commit -m "chore: bump version to vX.Y.Z"
git push origin main
```

### 5. Wait for CI to pass

Go to **https://github.com/DiNaSoR/Mnemo/actions** and confirm the CI workflow passes on your commit.

### 6. Create and push the release tag

```sh
git tag vX.Y.Z
git push origin main --tags
```

> **This triggers the release pipeline.** Do NOT create the tag until CI is green.

### 7. Monitor the release

Watch the pipeline at **https://github.com/DiNaSoR/Mnemo/actions**:

| Stage | What it does |
|---|---|
| `preflight` | Validates VERSION matches tag, CHANGELOG has entry |
| `test-windows` | Runs installer on Windows |
| `test-posix` | Runs installer on macOS + Ubuntu |
| `autonomy-syntax` | Python syntax check on autonomy modules |
| `publish` | Creates GitHub Release with changelog notes |
| `publish-npm` | Publishes `@dinasor/mnemo-cli@X.Y.Z` to npm |

### 8. Verify the release

```sh
# Check npm
npm view @dinasor/mnemo-cli version

# Test install from npm
npx @dinasor/mnemo-cli@X.Y.Z --help
```

Check the GitHub Release page: **https://github.com/DiNaSoR/Mnemo/releases**

---

## Troubleshooting

| Problem | Fix |
|---|---|
| `NPM_TOKEN secret is not configured` | Add an npm automation token at repo Settings → Secrets → Actions |
| `VERSION file does not match git tag` | Edit `VERSION` to match, commit, delete the tag, re-tag, push |
| `CHANGELOG.md has no entry for version` | Add `## [X.Y.Z]` section, commit, delete tag, re-tag, push |
| `Package @dinasor/mnemo-cli@X.Y.Z is already published` | npm doesn't allow republishing — bump to next patch version |
| CI tests fail on tag push | Fix the issue, delete the remote tag (`git push origin :refs/tags/vX.Y.Z`), commit fix, re-tag, push |

### Deleting a bad tag

```sh
# Delete locally
git tag -d vX.Y.Z

# Delete on remote
git push origin :refs/tags/vX.Y.Z
```

---

## Quick release (copy-paste)

For a patch release, replace `X.Y.Z` and run:

```sh
VER=X.Y.Z
echo "$VER" > VERSION
npm version $VER --no-git-tag-version
# (edit CHANGELOG.md with release notes)
git add -A
git commit -m "chore: bump version to v$VER"
git push origin main
# wait for CI green, then:
git tag "v$VER"
git push origin main --tags
```
