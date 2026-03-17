# Local AUR Mirror Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make normal `access-os-extra` build and publish operations use a local AUR mirror first, with `pkgbuilds/` as the in-repo fallback and live AUR reserved for explicit mirror refresh operations.

**Architecture:** Introduce a mirror root outside the repo, add explicit mirror sync/import scripts, and route `gen-manifest.sh`, `rebuild.sh`, and `publish-local.sh` through a shared mirror-aware packaging layer. Keep `pkgbuilds/` as the durable packaging snapshot and audit trail, and keep `--publish-only` / `--stage-only` fully independent of live AUR.

**Tech Stack:** Bash, git, curl, jq, makepkg, repo-add, GitHub CLI

---

## File Structure

**Create:**
- `scripts/sync-aur-mirror.sh` — clones/updates per-package AUR working clones under `AUR_MIRROR_DIR`
- `scripts/import-aur-snapshots.sh` — imports packaging-only files from the mirror into `pkgbuilds/<pkg>/`
- `scripts/lib/aur-packaging.sh` — shared helpers for reading AUR package lists, resolving mirror paths, and copying packaging-only files
- `docs/superpowers/plans/2026-03-16-local-aur-mirror.md` — this implementation plan

**Modify:**
- `scripts/rebuild.sh` — switch `access-os-extra` package sourcing to mirror-first / snapshot-second
- `scripts/gen-manifest.sh` — resolve AUR package versions from mirror metadata first, then `pkgbuilds/`
- `scripts/publish-local.sh` — skip live removed-AUR sync when a usable local mirror exists and export mirror config to rebuilds
- `README.md` — document mirror setup and workflow
- `pkgbuilds/README.md` — document mirror import and snapshot role

**Verification commands used throughout:**
- `bash -n scripts/lib/aur-packaging.sh scripts/sync-aur-mirror.sh scripts/import-aur-snapshots.sh scripts/gen-manifest.sh scripts/rebuild.sh scripts/publish-local.sh`
- `./scripts/rebuild.sh --dry-run`
- `AUR_MIRROR_DIR=/tmp/access-os-aur-mirror ./scripts/sync-aur-mirror.sh`
- `AUR_MIRROR_DIR=/tmp/access-os-aur-mirror ./scripts/import-aur-snapshots.sh`

## Chunk 1: Shared mirror helpers and maintenance scripts

### Task 1: Add shared AUR packaging helper library

**Files:**
- Create: `scripts/lib/aur-packaging.sh`
- Modify: `scripts/rebuild.sh`
- Modify: `scripts/gen-manifest.sh`
- Modify: `scripts/publish-local.sh`

- [ ] **Step 1: Create `scripts/lib/aur-packaging.sh` with mirror/path helpers**

Implement helpers for:
- `read_extra_packages_file <file>`
- `resolve_aur_mirror_dir`
- `local_aur_mirror_pkg_dir <pkg>`
- `pkgbuild_snapshot_dir <pkg>`
- `copy_packaging_snapshot <src> <dst>`
- `mirror_has_package <pkg>`

The copy helper must preserve packaging-only files and exclude:
- `.git/`
- `src/`
- `pkg/`
- `*.pkg.tar.*`
- `*.iso`
- downloaded archives and other large binary payloads

- [ ] **Step 2: Run shell syntax check for the new helper**

Run: `bash -n scripts/lib/aur-packaging.sh`
Expected: command exits `0`

- [ ] **Step 3: Source the helper from existing scripts without changing behavior yet**

Wire `scripts/rebuild.sh`, `scripts/gen-manifest.sh`, and `scripts/publish-local.sh` to source `scripts/lib/aur-packaging.sh` near the top, but keep current behavior intact for this step.

- [ ] **Step 4: Re-run syntax checks on touched scripts**

Run: `bash -n scripts/lib/aur-packaging.sh scripts/gen-manifest.sh scripts/rebuild.sh scripts/publish-local.sh`
Expected: command exits `0`

- [ ] **Step 5: Commit the helper-layer change**

```bash
git add scripts/lib/aur-packaging.sh scripts/gen-manifest.sh scripts/rebuild.sh scripts/publish-local.sh
git commit -m "Add shared AUR packaging helpers"
```

### Task 2: Add the mirror sync script

**Files:**
- Create: `scripts/sync-aur-mirror.sh`
- Modify: `README.md`

- [ ] **Step 1: Implement mirror sync behavior**

Create `scripts/sync-aur-mirror.sh` to:
- read `package-lists/access-os-extra.txt`
- default `AUR_MIRROR_DIR` to `~/aur-mirror`
- clone `https://aur.archlinux.org/<pkg>.git` into `AUR_MIRROR_DIR/<pkg>/` when missing
- otherwise fetch and fast-forward the existing clone
- fail if any package cannot be refreshed

- [ ] **Step 2: Add `--help` output and clear error text**

Document:
- default mirror directory
- required commands (`git`)
- expected usage and failure behavior

- [ ] **Step 3: Smoke-test mirror sync against a temp mirror root**

Run: `AUR_MIRROR_DIR=/tmp/access-os-aur-mirror ./scripts/sync-aur-mirror.sh`
Expected: all listed AUR package repos exist under `/tmp/access-os-aur-mirror/`

- [ ] **Step 4: Document the mirror sync command in `README.md`**

Add a small “Local AUR mirror” section with:
- mirror root
- sync command
- note that this is the only normal operation that contacts live AUR

- [ ] **Step 5: Commit the mirror sync script**

```bash
git add scripts/sync-aur-mirror.sh README.md
git commit -m "Add local AUR mirror sync script"
```

### Task 3: Add the snapshot import script

**Files:**
- Create: `scripts/import-aur-snapshots.sh`
- Modify: `pkgbuilds/README.md`
- Modify: `README.md`

- [ ] **Step 1: Implement mirror-to-`pkgbuilds/` import**

Create `scripts/import-aur-snapshots.sh` to:
- iterate the AUR package list
- look up each package in `AUR_MIRROR_DIR/<pkg>/`
- copy packaging-only files into `pkgbuilds/<pkg>/` using `copy_packaging_snapshot`
- fail if a listed package is missing from the mirror

- [ ] **Step 2: Add a dry-run or no-op-friendly message path**

The script should emit clear output for:
- imported package
- unchanged package
- missing mirror entry

- [ ] **Step 3: Smoke-test snapshot import against the temp mirror root**

Run: `AUR_MIRROR_DIR=/tmp/access-os-aur-mirror ./scripts/import-aur-snapshots.sh`
Expected: `pkgbuilds/<pkg>/` contains packaging files only, with no large source payloads

- [ ] **Step 4: Update `README.md` and `pkgbuilds/README.md`**

Document:
- how to import snapshots from the mirror
- that `pkgbuilds/` remains the in-repo fallback when the mirror is unavailable or a package disappears

- [ ] **Step 5: Commit the snapshot import work**

```bash
git add scripts/import-aur-snapshots.sh README.md pkgbuilds/README.md
git commit -m "Add mirror snapshot import script"
```

## Chunk 2: Mirror-first build and manifest resolution

### Task 4: Make manifest generation mirror-first

**Files:**
- Modify: `scripts/gen-manifest.sh`
- Test: manual command output from `scripts/gen-manifest.sh`

- [ ] **Step 1: Replace direct AUR-first version lookup with mirror-first resolution**

Refactor the `access-os-extra` path so it resolves package metadata in this order:
1. `AUR_MIRROR_DIR/<pkg>/`
2. `pkgbuilds/<pkg>/`
3. fail

Use `.SRCINFO` or `makepkg --printsrcinfo` from the mirror clone when available.

- [ ] **Step 2: Keep failure behavior explicit**

If a package is missing from both the mirror and `pkgbuilds/`, fail with:
- package name
- checked locations
- action hint to run `scripts/sync-aur-mirror.sh`

- [ ] **Step 3: Verify manifest generation without live AUR**

Run: `./scripts/gen-manifest.sh | jq -e '.version == 1'`
Expected: exits `0` and returns a manifest with the expected `repos` structure

- [ ] **Step 4: Verify shell syntax and no regressions in dry-run mode**

Run:
- `bash -n scripts/gen-manifest.sh scripts/rebuild.sh`
- `./scripts/rebuild.sh --dry-run`
Expected: both commands exit `0`

- [ ] **Step 5: Commit the mirror-first manifest logic**

```bash
git add scripts/gen-manifest.sh scripts/rebuild.sh
git commit -m "Use local AUR mirror for manifest generation"
```

### Task 5: Make `rebuild.sh` build from mirror clones first

**Files:**
- Modify: `scripts/rebuild.sh`
- Test: `./scripts/rebuild.sh --dry-run`

- [ ] **Step 1: Refactor `build_extra()` source preparation**

Change the package source resolution so each `access-os-extra` package is prepared from:
1. `AUR_MIRROR_DIR/<pkg>/`
2. `pkgbuilds/<pkg>/`
3. fail

Stop performing implicit `git clone https://aur.archlinux.org/<pkg>.git` in the normal build path.

- [ ] **Step 2: Reuse the shared snapshot filter for post-build saves**

Refactor `save_pkgbuild_snapshot()` to call the shared `copy_packaging_snapshot` helper so mirror imports and post-build snapshots use the same policy.

- [ ] **Step 3: Improve package-specific error messages**

When a package cannot be sourced, report:
- package name
- missing mirror path
- missing `pkgbuilds/` path
- next action (`./scripts/sync-aur-mirror.sh` or `./scripts/import-aur-snapshots.sh`)

- [ ] **Step 4: Verify dry-run behavior and syntax**

Run:
- `bash -n scripts/rebuild.sh scripts/lib/aur-packaging.sh`
- `./scripts/rebuild.sh --dry-run`
Expected: both commands exit `0`

- [ ] **Step 5: Commit the mirror-first rebuild flow**

```bash
git add scripts/rebuild.sh scripts/lib/aur-packaging.sh
git commit -m "Build access-os-extra from local mirror first"
```

## Chunk 3: Publish integration and documentation finish

### Task 6: Make `publish-local.sh` mirror-aware

**Files:**
- Modify: `scripts/publish-local.sh`
- Modify: `README.md`

- [ ] **Step 1: Detect usable mirror state near the top of `publish-local.sh`**

Implement a helper that treats the mirror as usable when:
- `AUR_MIRROR_DIR` exists
- at least one expected package directory is present

- [ ] **Step 2: Skip live removed-AUR sync when the mirror is usable**

Adjust the normal publish path so:
- mirror present → skip `scripts/sync-removed-from-aur.sh`
- mirror absent → preserve current behavior

Also export `AUR_MIRROR_DIR` to `scripts/rebuild.sh` so normal publishes inherit the same mirror root.

- [ ] **Step 3: Keep `--publish-only` and `--stage-only` offline**

Verify that neither path calls live AUR after the mirror-first changes.

- [ ] **Step 4: Update operator documentation in `README.md`**

Add:
- mirror-first build note
- explicit recommended flow:
  - `./scripts/sync-aur-mirror.sh`
  - `./scripts/import-aur-snapshots.sh`
  - `./scripts/publish-local.sh`

- [ ] **Step 5: Commit the publish integration**

```bash
git add scripts/publish-local.sh README.md
git commit -m "Teach local publish to use the AUR mirror"
```

### Task 7: Final verification and cleanup

**Files:**
- Modify: `README.md`
- Modify: `pkgbuilds/README.md`
- Modify: `scripts/*.sh` as needed for any follow-up fixes discovered during verification

- [ ] **Step 1: Run full shell syntax verification**

Run:
`bash -n scripts/lib/aur-packaging.sh scripts/sync-aur-mirror.sh scripts/import-aur-snapshots.sh scripts/gen-manifest.sh scripts/rebuild.sh scripts/publish-local.sh`
Expected: exits `0`

- [ ] **Step 2: Run mirror-backed smoke checks**

Run:
- `AUR_MIRROR_DIR=/tmp/access-os-aur-mirror ./scripts/sync-aur-mirror.sh`
- `AUR_MIRROR_DIR=/tmp/access-os-aur-mirror ./scripts/import-aur-snapshots.sh`
- `AUR_MIRROR_DIR=/tmp/access-os-aur-mirror ./scripts/gen-manifest.sh >/tmp/access-os-manifest.json`
- `AUR_MIRROR_DIR=/tmp/access-os-aur-mirror ./scripts/rebuild.sh --dry-run`
Expected: all commands exit `0`

- [ ] **Step 3: Review docs for consistency**

Confirm that `README.md` and `pkgbuilds/README.md` agree on:
- mirror root
- snapshot purpose
- live AUR no longer being part of normal publish

- [ ] **Step 4: Run final diff hygiene checks**

Run:
- `git diff --check`
- `git status --short`
Expected:
- no whitespace errors
- only intended files changed

- [ ] **Step 5: Commit final cleanup**

```bash
git add README.md pkgbuilds/README.md scripts
git commit -m "Document and verify local AUR mirror workflow"
```
