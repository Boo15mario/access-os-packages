# Targeted Incremental Staging Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make incremental publish restage only the affected repo metadata after each successful package build, instead of rerunning full `rebuild.sh --stage-only`.

**Architecture:** `scripts/publish-local.sh` will gain a targeted staging helper that rebuilds only one repo DB/files from current `dist/`, refreshes `manifest.json` and `BUILD_INFO.txt`, and then publishes `gh-pages`. Full `rebuild.sh --stage-only` recovery remains unchanged.

**Tech Stack:** Bash, repo-add, git, gh, jq

---

## Chunk 1: Extract targeted staging helpers

### Task 1: Add repo-local staging helper

**Files:**
- Modify: `scripts/publish-local.sh`
- Reference: `scripts/rebuild.sh`

- [ ] Reuse the existing repo DB generation logic for a single repo.
- [ ] Stage only the requested repo under `site/<repo>/os/<arch>`.
- [ ] Keep symlink-free `.db`/`.files` output compatible with GitHub Pages.

### Task 2: Refresh shared site metadata

**Files:**
- Modify: `scripts/publish-local.sh`

- [ ] Regenerate `site/manifest.json` after targeted repo staging.
- [ ] Refresh `site/BUILD_INFO.txt`.
- [ ] Leave the untouched repo DB/files in place.

## Chunk 2: Wire incremental publish to targeted staging

### Task 3: Replace full stage-only call in incremental mode

**Files:**
- Modify: `scripts/publish-local.sh`

- [ ] Incremental `--publish-package` mode should call targeted staging for the affected repo.
- [ ] `--publish-only` recovery should continue using full `rebuild.sh --stage-only` when `site/` is missing.
- [ ] Do not change normal final publish behavior.

## Chunk 3: Verification and docs

### Task 4: Update docs

**Files:**
- Modify: `README.md` if needed

- [ ] Document the lighter targeted incremental staging behavior only if it improves operator understanding.

### Task 5: Verification

**Files:**
- Modify only files from prior tasks

- [ ] Run `bash -n scripts/publish-local.sh`.
- [ ] Run `bash scripts/publish-local.sh --help`.
- [ ] Run `git diff --check`.
- [ ] Commit only the intended files.
