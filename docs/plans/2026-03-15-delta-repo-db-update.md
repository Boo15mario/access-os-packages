# Delta Repo DB Update Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make incremental publish update repo metadata using only the newly built package files, instead of reprocessing every package already in that repo.

**Architecture:** `scripts/publish-local.sh` will keep full repo staging for recovery paths and add a delta staging helper for incremental publish mode. Delta staging will call `repo-add -R` with only the newly built package files, then refresh Pages-facing `.db`/`.files`, `manifest.json`, and `BUILD_INFO.txt`.

**Tech Stack:** Bash, repo-add, git, gh

---

## Chunk 1: Add delta staging helper

### Task 1: Normalize and apply only changed package files

**Files:**
- Modify: `scripts/publish-local.sh`

- [ ] Add a helper that accepts repo name and explicit package file paths.
- [ ] Normalize filenames with `:` if needed.
- [ ] Ensure repo DB tarballs exist before delta updates.
- [ ] Call `repo-add -R` with only those files.

### Task 2: Keep full staging for recovery

**Files:**
- Modify: `scripts/publish-local.sh`

- [ ] Leave full repo staging available for `--publish-only` and recovery.
- [ ] Share common copy-out logic for `.db` and `.files` where possible.

## Chunk 2: Wire incremental publish to delta staging

### Task 3: Replace current incremental staging call

**Files:**
- Modify: `scripts/publish-local.sh`

- [ ] In `--publish-package` mode, use delta staging with the package file list already provided.
- [ ] Keep manifest and BUILD_INFO refresh unchanged.
- [ ] Do not change the external CLI flow.

## Chunk 3: Verification

### Task 4: Verify and commit

**Files:**
- Modify only files from prior tasks

- [ ] Run `bash -n scripts/publish-local.sh`.
- [ ] Run `bash scripts/publish-local.sh --help`.
- [ ] Run `git diff --check`.
- [ ] Commit only the intended files.
