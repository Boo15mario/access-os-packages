# Per-Package Rebuild Skip Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Skip rebuilding packages whose desired source version already matches the published GitHub repo version, while still rebuilding packages whose source version changed or are missing remotely.

**Architecture:** `scripts/rebuild.sh` will fetch the published manifest once, resolve a desired version for each package before building, and skip `makepkg` when desired and published versions match. Existing incremental publish behavior remains unchanged for packages that do build.

**Tech Stack:** Bash, jq, curl, makepkg, git

---

## Chunk 1: Add shared version lookup helpers

### Task 1: Load published manifest once

**Files:**
- Modify: `scripts/rebuild.sh`

- [ ] Add a helper to fetch and cache the published GitHub Pages manifest.
- [ ] Use the same Pages base URL convention already used by `scripts/check-updates.sh`.
- [ ] Fall back cleanly when the manifest cannot be fetched.

### Task 2: Resolve desired package versions

**Files:**
- Modify: `scripts/rebuild.sh`
- Reference: `scripts/gen-manifest.sh`

- [ ] Add a helper for local/core package version resolution.
- [ ] Add a helper for AUR package desired version resolution.
- [ ] Reuse existing AUR fallback rules: live AUR first, saved snapshot only when the package is actually gone.

## Chunk 2: Skip unchanged packages

### Task 3: Add package skip decision logic

**Files:**
- Modify: `scripts/rebuild.sh`

- [ ] Compare desired version against the published manifest version for each package.
- [ ] Skip only on exact version match.
- [ ] Log explicit skip/build reasons.
- [ ] Build when desired version cannot be resolved.

### Task 4: Apply skip logic to both package flows

**Files:**
- Modify: `scripts/rebuild.sh`

- [ ] Apply the skip rule to core packages.
- [ ] Apply the skip rule to AUR packages.
- [ ] Keep install-after-build and incremental publish behavior unchanged for packages that do build.

## Chunk 3: Documentation and verification

### Task 5: Update docs

**Files:**
- Modify: `README.md`

- [ ] Document that rebuilds now skip unchanged published package versions.
- [ ] Document the conservative fallback when remote/version checks fail.

### Task 6: Verification

**Files:**
- Modify only files from prior tasks

- [ ] Run `bash -n scripts/rebuild.sh`.
- [ ] Run `./scripts/rebuild.sh --dry-run`.
- [ ] Run `git diff --check`.
- [ ] Commit only the intended files.
