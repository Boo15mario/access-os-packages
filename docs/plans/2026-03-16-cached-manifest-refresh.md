# Cached Manifest Refresh Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reuse a manifest snapshot generated once per build run so incremental publish does not repeatedly query the AUR.

**Architecture:** `scripts/rebuild.sh` will create a run-scoped desired-manifest file before building packages and export its path. `scripts/publish-local.sh` will prefer that cached manifest during incremental publish and fall back to full `gen-manifest.sh` refresh only when no cache is available.

**Tech Stack:** Bash, jq, curl, makepkg

---

## Chunk 1: Generate and expose a cached manifest

### Task 1: Add run-scoped manifest cache

**Files:**
- Modify: `scripts/rebuild.sh`

- [ ] Generate the desired manifest once at the start of a normal build run.
- [ ] Store it under the run work directory.
- [ ] Export the cache path for incremental publish helpers.
- [ ] Fail early if the initial manifest generation fails.

## Chunk 2: Reuse cached manifest during incremental publish

### Task 2: Prefer cached manifest in site refresh

**Files:**
- Modify: `scripts/publish-local.sh`

- [ ] Update manifest refresh logic to use the cached manifest when present.
- [ ] Fall back to `scripts/gen-manifest.sh` only when cache is absent.
- [ ] Keep full publish-only and recovery flows working.

## Chunk 3: Verification

### Task 3: Verify and commit

**Files:**
- Modify only files from prior tasks

- [ ] Run `bash -n scripts/rebuild.sh scripts/publish-local.sh`.
- [ ] Run `./scripts/rebuild.sh --dry-run`.
- [ ] Run `git diff --check`.
- [ ] Commit only the intended files.
