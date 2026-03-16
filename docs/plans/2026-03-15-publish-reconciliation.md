# Publish Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Verify at the end of a normal publish run that GitHub Releases and GitHub Pages are in sync, retry the Pages push once if they are not, and fail loudly if they still disagree.

**Architecture:** `scripts/publish-local.sh` will gain reconciliation helpers that read the staged manifest, inspect the published manifest and repo DB, and confirm that matching release assets exist. A mismatch will trigger one retry of `gh-pages` publication before the script exits with failure.

**Tech Stack:** Bash, curl, jq, gh, tar, awk

---

## Chunk 1: Add reconciliation helpers

### Task 1: Read published Pages state

**Files:**
- Modify: `scripts/publish-local.sh`

- [ ] Add a helper to fetch the published `manifest.json`.
- [ ] Add a helper to inspect the published repo DB for package presence.
- [ ] Use existing Pages URL conventions.

### Task 2: Read release asset state

**Files:**
- Modify: `scripts/publish-local.sh`

- [ ] Add a helper to list release assets for a repo tag.
- [ ] Verify that expected package filenames exist for staged package versions.

## Chunk 2: Retry and fail loudly on mismatch

### Task 3: Add final reconciliation flow

**Files:**
- Modify: `scripts/publish-local.sh`

- [ ] Run reconciliation at the end of normal publish flows.
- [ ] Retry `publish_pages_branch` once on mismatch.
- [ ] Recheck after retry.
- [ ] Exit non-zero if still mismatched.

## Chunk 3: Verification

### Task 4: Verify and commit

**Files:**
- Modify only files from prior tasks

- [ ] Run `bash -n scripts/publish-local.sh`.
- [ ] Run `bash scripts/publish-local.sh --help`.
- [ ] Run `git diff --check`.
- [ ] Commit only the intended files.
