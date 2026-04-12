---
name: release
description: "Release workflow for ChattyLittleNpc addon. Bumps the .toc version, commits and pushes to GitHub, then runs release.py to create a GitHub release. Activates for: release, bump version, publish, ship, tag, new version, deploy addon, push release."
---

# Release Workflow

Steps to release a new version of ChattyLittleNpc. Execute them in order — each step depends on the previous one.

## Prerequisites

- Working directory: repo root (`c:\repos\Addon\ChattyLittleNpc`)
- Git working tree is clean (no uncommitted changes unrelated to the release)
- GitHub CLI (`gh`) is installed and authenticated
- Python venv is activated (`.venv\Scripts\Activate.ps1`)

## Step 1 — Bump the TOC version

The version lives on line 5 of `ChattyLittleNpc/ChattyLittleNpc.toc`:

```
## Version: X.Y.Z
```

Ask the user what the new version should be (patch, minor, or major bump) unless they already specified it. Update **only** that line.

## Step 2 — Commit and push

Stage all pending changes (the version bump plus any feature/fix files that are part of this release), commit with a clear message, and push to the current branch:

```powershell
git add -A
git commit -m "Release vX.Y.Z — <short summary of changes>"
git push
```

**Important:** Never force-push or rewrite history (per repo conventions in `copilot-instructions.md`).

## Step 3 — Run the release script

```powershell
python release.py --create
```

This does three things automatically:
1. Reads the version from the `.toc` file
2. Creates and pushes a `vX.Y.Z` git tag
3. Creates a GitHub Release with auto-generated notes via `gh release create`

If the tag already exists and the user confirms they want to overwrite, add `--force`.

### Dry run

If unsure, run without `--create` first to preview:

```powershell
python release.py
```

## After release

Tell the user:
- The GitHub Actions workflow will build and attach the addon ZIP to the release.
- Confirm the release appeared at the repo's Releases page.
