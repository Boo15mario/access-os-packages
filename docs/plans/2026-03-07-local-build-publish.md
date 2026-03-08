# Local Build and Publish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move package building and publishing to a local Arch Linux system while retaining GitHub Actions as a validation-only workflow.

**Architecture:** `scripts/rebuild.sh` remains the package build engine. A new `scripts/publish-local.sh` will orchestrate local building, release uploads, metadata publication, and optional git commits/pushes. GitHub Actions will be reduced to repository validation and dry-run checks only.

**Tech Stack:** Bash, pacman/makepkg, repo-add, GitHub CLI, GitHub Actions, GitHub Pages, GitHub Releases

---

### Task 1: Document minimum local requirements

**Files:**
- Modify: `README.md`

**Step 1: Add a local builder requirements section**

Document the minimum Arch packages required:
- `base-devel`
- `git`
- `curl`
- `jq`
- `pacman-contrib`
- `devtools`
- `github-cli`

Also document recommended extras and required system configuration:
- `multilib`
- `gh auth login`

**Step 2: Document the new operating model**

Explain that package builds happen locally and GitHub only hosts Releases, Pages, and validation workflows.

**Step 3: Verify formatting/readability**

Run: `sed -n '1,240p' README.md`
Expected: local workflow and required packages are clearly described.

**Step 4: Commit**

Run:
```bash
git add README.md
git commit -m "Document local build requirements"
```

### Task 2: Add local publish script

**Files:**
- Create: `scripts/publish-local.sh`
- Modify: `README.md`

**Step 1: Write the script skeleton**

Add a Bash script that:
- validates required commands
- validates GitHub authentication
- validates `multilib` presence
- supports flags:
  - `--build-only`
  - `--publish-only`
  - `--no-push`
  - `--skip-commit`

**Step 2: Implement local build invocation**

Call `scripts/rebuild.sh` unless `--publish-only` is set.

**Step 3: Implement release upload flow**

Upload built package files from:
- `dist/access-os-core/x86_64/`
- `dist/access-os-extra/x86_64/`

To release tags:
- `access-os-core-x86_64`
- `access-os-extra-x86_64`

Create releases if missing.

**Step 4: Implement commit/push handling**

If `pkgbuilds/` or `metadata/` changed:
- commit them unless `--skip-commit`
- push unless `--no-push`

**Step 5: Update README usage examples**

Add sample commands for:
- full local publish
- build only
- publish only

**Step 6: Verify script syntax**

Run: `bash -n scripts/publish-local.sh`
Expected: exit 0

**Step 7: Verify dry-run-friendly help output**

Run: `bash scripts/publish-local.sh --help`
Expected: usage text with all supported flags.

**Step 8: Commit**

Run:
```bash
git add scripts/publish-local.sh README.md
git commit -m "Add local publish workflow script"
```

### Task 3: Demote Actions to validation-only CI

**Files:**
- Modify: `.github/workflows/build-repos.yml`

**Step 1: Remove package-build and upload responsibilities**

Delete or replace the steps that:
- build packages in Docker
- upload release assets
- configure and upload Pages artifacts from CI-built packages

**Step 2: Add validation steps**

Run validation steps such as:
- `bash -n scripts/*.sh`
- `scripts/rebuild.sh --dry-run`
- `scripts/sync-removed-from-aur.sh` with temp metadata outputs
- `scripts/check-updates.sh` in a safe validation mode

**Step 3: Keep meaningful workflow outputs**

Ensure Actions still fail on:
- broken shell scripts
- missing package fallbacks
- malformed metadata workflow assumptions

**Step 4: Verify YAML validity**

Run:
```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build-repos.yml"); puts "ok"'
```
Expected: `ok`

**Step 5: Commit**

Run:
```bash
git add .github/workflows/build-repos.yml
git commit -m "Convert CI to validation workflow"
```

### Task 4: Add local site publication path

**Files:**
- Modify: `scripts/publish-local.sh`
- Modify: `README.md`

**Step 1: Choose publication mechanism already compatible with repo**

Implement the simplest supported Pages publication path, likely one of:
- push generated `site/` content to a Pages publishing branch/worktree
- or keep using Actions deployment but driven by tracked content changes instead of CI-built packages

**Step 2: Implement site publication command(s)**

The local publish script should publish the already-generated `site/` payload without rebuilding packages.

**Step 3: Document exact operator workflow**

Document:
- how Pages gets updated
- what the operator runs after a successful local build

**Step 4: Verify script syntax again**

Run: `bash -n scripts/publish-local.sh`
Expected: exit 0

**Step 5: Commit**

Run:
```bash
git add scripts/publish-local.sh README.md
git commit -m "Add local site publication flow"
```

### Task 5: End-to-end validation

**Files:**
- Modify as needed from previous tasks only

**Step 1: Run syntax verification**

Run:
```bash
bash -n scripts/rebuild.sh
bash -n scripts/check-updates.sh
bash -n scripts/sync-removed-from-aur.sh
bash -n scripts/publish-local.sh
```
Expected: all exit 0

**Step 2: Run workflow validation**

Run:
```bash
ruby -e 'require "yaml"; YAML.load_file(".github/workflows/build-repos.yml"); puts "ok"'
```
Expected: `ok`

**Step 3: Run rebuild dry run**

Run:
```bash
scripts/rebuild.sh --dry-run
```
Expected: prints configured paths and exits 0

**Step 4: Run local publish help**

Run:
```bash
bash scripts/publish-local.sh --help
```
Expected: usage text and documented flags

**Step 5: Review diff for accidental scope creep**

Run:
```bash
git diff --check
```
Expected: no diff formatting issues

**Step 6: Commit final changes**

Run:
```bash
git add README.md scripts/publish-local.sh .github/workflows/build-repos.yml
git commit -m "Switch to local package publishing workflow"
```
