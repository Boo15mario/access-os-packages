# Incremental Package Publish Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish each successfully built package to GitHub Releases and refresh GitHub Pages metadata during the rebuild, instead of waiting for the full run to complete.

**Architecture:** `scripts/rebuild.sh` will emit package-level publish events after successful builds. `scripts/publish-local.sh` will expose reusable helpers for uploading selected package files and publishing refreshed repo metadata from current `dist/`. The final metadata/snapshot git commit remains batched near the end.

**Tech Stack:** Bash, makepkg, repo-add, git, gh, jq

---

## Chunk 1: Refactor publishing helpers

### Task 1: Extract reusable publish primitives

**Files:**
- Modify: `scripts/publish-local.sh`

- [ ] Add a helper that uploads a provided list of package files to the matching release tag.
- [ ] Add a helper that regenerates staged repo metadata from `dist/` without rebuilding.
- [ ] Add a helper that publishes staged `site/` content to `gh-pages`.
- [ ] Keep `--publish-only` behavior working through the same helpers.

### Task 2: Define incremental publish interface

**Files:**
- Modify: `scripts/publish-local.sh`
- Modify: `scripts/rebuild.sh`

- [ ] Choose an interface that `rebuild.sh` can call after each package succeeds.
- [ ] Prefer environment-driven integration so `rebuild.sh` stays usable standalone.
- [ ] Ensure `--build-only` disables the hook cleanly.

## Chunk 2: Publish after each package

### Task 3: Capture built files per package

**Files:**
- Modify: `scripts/rebuild.sh`

- [ ] Reuse `makepkg --packagelist` output to identify actual built package files for each package.
- [ ] Filter to existing files only.
- [ ] Keep the current install-after-build behavior working from the same file list.

### Task 4: Invoke incremental publish hook

**Files:**
- Modify: `scripts/rebuild.sh`

- [ ] After a successful package build, call the publish hook with repo name and built package file paths.
- [ ] Do this in both core and extra package flows where applicable.
- [ ] Fail the rebuild immediately if the publish hook fails.

## Chunk 3: Preserve operator behavior and docs

### Task 5: Wire normal publish flow

**Files:**
- Modify: `scripts/publish-local.sh`

- [ ] Normal `./scripts/publish-local.sh` should enable incremental publishing during rebuilds.
- [ ] `--build-only` should skip incremental publishing.
- [ ] `--publish-only` should still publish existing outputs without rebuilding.

### Task 6: Update docs

**Files:**
- Modify: `README.md`

- [ ] Document that normal publish runs upload packages incrementally.
- [ ] Document what happens on partial failures.
- [ ] Keep recovery instructions accurate.

## Chunk 4: Verify and commit

### Task 7: Verification

**Files:**
- Modify only files from prior tasks

- [ ] Run `bash -n scripts/rebuild.sh scripts/publish-local.sh`.
- [ ] Run `./scripts/rebuild.sh --dry-run`.
- [ ] Run `bash scripts/publish-local.sh --help`.
- [ ] Run `git diff --check`.
- [ ] Commit only the intended files.
