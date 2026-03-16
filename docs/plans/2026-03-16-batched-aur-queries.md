# Batched AUR Queries Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace one-request-per-package AUR RPC behavior with batched info requests in manifest generation and removed-AUR sync.

**Architecture:** Both `scripts/gen-manifest.sh` and `scripts/sync-removed-from-aur.sh` will gather package names, query the AUR RPC in batches via repeated `arg[]` parameters, and build a local lookup map used by the existing fallback/missing logic.

**Tech Stack:** Bash, curl, jq

---

## Chunk 1: Batch query helper in manifest generation

### Task 1: Add batched AUR lookup to `scripts/gen-manifest.sh`

**Files:**
- Modify: `scripts/gen-manifest.sh`

- [ ] Gather all `access-os-extra` package names before querying.
- [ ] Query AUR in batches using repeated `arg[]` values.
- [ ] Build a lookup table from returned results.
- [ ] Reuse the current fallback logic for absent packages.

## Chunk 2: Batch query helper in removed-AUR sync

### Task 2: Add batched AUR lookup to `scripts/sync-removed-from-aur.sh`

**Files:**
- Modify: `scripts/sync-removed-from-aur.sh`

- [ ] Gather all packages before querying.
- [ ] Query AUR in batches.
- [ ] Build a lookup table from returned results.
- [ ] Reuse the current removed/fallback logic for absent packages.

## Chunk 3: Verification

### Task 3: Verify and commit

**Files:**
- Modify only files from prior tasks

- [ ] Run `bash -n scripts/gen-manifest.sh scripts/sync-removed-from-aur.sh`.
- [ ] Run `git diff --check`.
- [ ] Commit only the intended files.
