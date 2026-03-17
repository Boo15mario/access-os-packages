# Hybrid Curated Extra Packages Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Introduce curated `packages/extra/` as the source of truth for approved `access-os-extra` packages, keep `pkgbuilds/` as the transition/fallback layer, and preserve explicit AUR inspection and mirror refresh workflows.

**Architecture:** Extend the existing mirror-first Bash tooling to understand a new curated package root, then make build, manifest, and publish logic resolve `access-os-extra` packages from `packages/extra/` first and `pkgbuilds/` second. Keep the local AUR mirror and package list for maintenance intake during transition rather than as the build source of truth.

**Tech Stack:** Bash, git, curl, jq, makepkg, repo-add, GitHub CLI, nvchecker

---

## File Structure

**Create:**
- `packages/extra/README.md` — documents curated extra package ownership and layout
- `scripts/promote-extra-package.sh` — promotes a package from the local mirror or `pkgbuilds/` into `packages/extra/`
- `scripts/diff-extra-package-upstream.sh` — compares a curated `packages/extra/<pkg>/` directory against the local mirror copy
- `docs/superpowers/plans/2026-03-16-hybrid-extra-packages.md` — this plan

**Modify:**
- `scripts/lib/aur-packaging.sh` — add helpers for `packages/extra/` source resolution
- `scripts/rebuild.sh` — resolve `access-os-extra` from `packages/extra/` first, `pkgbuilds/` second
- `scripts/gen-manifest.sh` — resolve extra package metadata from `packages/extra/` first, `pkgbuilds/` second
- `scripts/publish-local.sh` — commit curated extra packages if changed and document transition behavior
- `scripts/check-upstream-updates.sh` — treat curated `packages/extra/` as the local package source for version comparison
- `README.md` — document `packages/extra/` and the new maintenance workflow
- `pkgbuilds/README.md` — redefine `pkgbuilds/` as transition/fallback/archive
- `package-lists/access-os-extra.txt` — remains the transition registry during migration; document that it still drives mirror intake until all packages are curated

**Verification commands used throughout:**
- `bash -n scripts/lib/aur-packaging.sh scripts/promote-extra-package.sh scripts/diff-extra-package-upstream.sh scripts/gen-manifest.sh scripts/rebuild.sh scripts/publish-local.sh scripts/check-upstream-updates.sh`
- `./scripts/rebuild.sh --dry-run`
- `./scripts/gen-manifest.sh | jq -e '.repos["access-os-extra"] != null'`
- `git diff --check`

## Chunk 1: Introduce curated extra package root and shared resolution

### Task 1: Add curated `packages/extra/` structure and resolution helpers

**Files:**
- Create: `packages/extra/README.md`
- Modify: `scripts/lib/aur-packaging.sh`
- Modify: `README.md`

- [ ] **Step 1: Create `packages/extra/README.md`**

Document:
- directory purpose
- `packages/extra/<pkg>/` layout
- this directory being the curated source of truth for approved `access-os-extra` packages
- relationship to `pkgbuilds/` and the AUR mirror

- [ ] **Step 2: Extend shared packaging helpers**

Add helpers to `scripts/lib/aur-packaging.sh` for:
- `aur_curated_extra_dir <pkg>`
- `aur_curated_extra_has_package <pkg>`
- `aur_resolve_extra_package_source_dir <pkg>` with precedence:
  1. `packages/extra/<pkg>/`
  2. `pkgbuilds/<pkg>/`
  3. fail

Keep mirror helpers in place for maintenance scripts.

- [ ] **Step 3: Update top-level docs to introduce `packages/extra/`**

Adjust `README.md` so it distinguishes:
- `packages/core/` as curated core packages
- `packages/extra/` as curated extra packages
- `pkgbuilds/` as transition/fallback storage

- [ ] **Step 4: Verify shell syntax and doc references**

Run:
- `bash -n scripts/lib/aur-packaging.sh`
- `rg -n "packages/extra|pkgbuilds" README.md packages/extra/README.md scripts/lib/aur-packaging.sh`
Expected: syntax check passes and docs mention the new structure consistently.

- [ ] **Step 5: Commit the curated extra root setup**

```bash
git add packages/extra/README.md scripts/lib/aur-packaging.sh README.md
git commit -m "Add curated extra package root"
```

### Task 2: Switch manifest generation to curated extra precedence

**Files:**
- Modify: `scripts/gen-manifest.sh`
- Test: `./scripts/gen-manifest.sh`

- [ ] **Step 1: Replace extra package source lookup with curated precedence**

Use `aur_resolve_extra_package_source_dir <pkg>` instead of the current mirror/snapshot resolver.

- [ ] **Step 2: Improve failure messaging**

If a package is missing from both `packages/extra/<pkg>/` and `pkgbuilds/<pkg>/`, fail with:
- the package name
- both checked locations
- a hint to promote or import the package

- [ ] **Step 3: Verify manifest output**

Run: `./scripts/gen-manifest.sh | jq -e '.repos["access-os-extra"] != null'`
Expected: exits `0`

- [ ] **Step 4: Verify syntax and deterministic output shape**

Run:
- `bash -n scripts/gen-manifest.sh`
- `./scripts/gen-manifest.sh | jq -e '.version == 1 and (.repos | has("access-os-extra"))'`
Expected: both exit `0`

- [ ] **Step 5: Commit manifest precedence changes**

```bash
git add scripts/gen-manifest.sh scripts/lib/aur-packaging.sh
git commit -m "Prefer curated extra packages in manifest generation"
```

## Chunk 2: Make normal builds use curated extra packages

### Task 3: Change `rebuild.sh` to use curated extra packages first

**Files:**
- Modify: `scripts/rebuild.sh`
- Test: `./scripts/rebuild.sh --dry-run`

- [ ] **Step 1: Replace extra package source resolution in `build_extra()`**

Use `aur_resolve_extra_package_source_dir <pkg>` so normal builds prefer:
1. `packages/extra/<pkg>/`
2. `pkgbuilds/<pkg>/`

Do not use the mirror in normal builds anymore.

- [ ] **Step 2: Preserve the shared snapshot filter**

Keep `copy_packaging_snapshot` for temporary build dirs and post-build saved snapshots so packaging-only rules stay consistent.

- [ ] **Step 3: Update build error text**

Report missing curated/fallback package sources with an action hint that points to:
- `./scripts/promote-extra-package.sh`
- or `./scripts/import-aur-snapshots.sh`

- [ ] **Step 4: Verify dry-run behavior**

Run:
- `bash -n scripts/rebuild.sh`
- `./scripts/rebuild.sh --dry-run`
Expected: both exit `0`

- [ ] **Step 5: Commit rebuild precedence changes**

```bash
git add scripts/rebuild.sh scripts/lib/aur-packaging.sh
git commit -m "Build extra packages from curated sources first"
```

### Task 4: Update publish/update tooling to understand curated extra packages

**Files:**
- Modify: `scripts/publish-local.sh`
- Modify: `scripts/check-upstream-updates.sh`
- Modify: `README.md`

- [ ] **Step 1: Ensure publish commits include curated extra packages when changed**

Extend commit logic in `scripts/publish-local.sh` so it stages any intended curated extra package changes together with `metadata/` and `pkgbuilds/` updates during normal publish flows.

- [ ] **Step 2: Update upstream version checking**

Adjust `scripts/check-upstream-updates.sh` so, for `access-os-extra`, local version comparison prefers:
1. `packages/extra/<pkg>/`
2. `pkgbuilds/<pkg>/`
3. published manifest as last fallback

- [ ] **Step 3: Document the new normal operator workflow**

Add to `README.md`:
- curated package update flow
- mirror sync as intake only
- `packages/extra/` as the preferred place for approved extras

- [ ] **Step 4: Verify syntax and no obvious regressions**

Run:
- `bash -n scripts/publish-local.sh scripts/check-upstream-updates.sh`
- `./scripts/rebuild.sh --dry-run`
Expected: all exit `0`

- [ ] **Step 5: Commit publish/update integration**

```bash
git add scripts/publish-local.sh scripts/check-upstream-updates.sh README.md
git commit -m "Integrate curated extra packages into publish flow"
```

## Chunk 3: Add maintenance scripts for the hybrid workflow

### Task 5: Add package promotion script

**Files:**
- Create: `scripts/promote-extra-package.sh`
- Modify: `README.md`
- Modify: `packages/extra/README.md`

- [ ] **Step 1: Implement promotion from mirror or `pkgbuilds/`**

Create `scripts/promote-extra-package.sh <pkg>` to:
- prefer promoting from `~/aur-mirror/<pkg>/`
- fall back to `pkgbuilds/<pkg>/`
- copy packaging-only files into `packages/extra/<pkg>/`
- fail clearly if neither source exists

- [ ] **Step 2: Add `--help` and operator-safe messaging**

Document:
- source precedence
- destination path
- that promotion does not delete `pkgbuilds/<pkg>/`

- [ ] **Step 3: Smoke-test with a temporary curated package destination**

Run with a known package and verify the resulting `packages/extra/<pkg>/` contains only packaging files.

- [ ] **Step 4: Document promotion flow**

Update `README.md` and `packages/extra/README.md` with example usage.

- [ ] **Step 5: Commit the promotion script**

```bash
git add scripts/promote-extra-package.sh README.md packages/extra/README.md
git commit -m "Add curated extra package promotion script"
```

### Task 6: Add upstream diff script for curated packages

**Files:**
- Create: `scripts/diff-extra-package-upstream.sh`
- Modify: `README.md`

- [ ] **Step 1: Implement curated-vs-mirror diff**

Create `scripts/diff-extra-package-upstream.sh <pkg>` to compare:
- `packages/extra/<pkg>/`
- `~/aur-mirror/<pkg>/`

Use packaging-only comparisons and produce a readable diff summary.

- [ ] **Step 2: Fail clearly on missing inputs**

Handle:
- missing curated package
- missing mirror package
- both missing

- [ ] **Step 3: Add usage docs**

Document this as the recommended way to inspect upstream AUR changes for an already curated package.

- [ ] **Step 4: Verify basic script behavior**

Run the script against at least one package with both sides present and confirm it exits `0` when comparison is possible.

- [ ] **Step 5: Commit the diff script**

```bash
git add scripts/diff-extra-package-upstream.sh README.md
git commit -m "Add curated extra package upstream diff tool"
```

## Chunk 4: Documentation cleanup and transition framing

### Task 7: Reframe `pkgbuilds/` and transition docs

**Files:**
- Modify: `pkgbuilds/README.md`
- Modify: `README.md`
- Modify: `package-lists/access-os-extra.txt` comments if needed

- [ ] **Step 1: Update `pkgbuilds/README.md` to reflect transition role**

Document `pkgbuilds/` as:
- transition/fallback/archive
- no longer the preferred source once a package is promoted to `packages/extra/`

- [ ] **Step 2: Update package list comments**

Clarify in `package-lists/access-os-extra.txt` that the list is still used for mirror intake and transition tracking during migration.

- [ ] **Step 3: Ensure top-level docs explain explicit AUR use**

Document that AUR remains available only for:
- inspection on request
- mirror refresh
- upstream comparison

- [ ] **Step 4: Run final verification**

Run:
- `bash -n scripts/lib/aur-packaging.sh scripts/promote-extra-package.sh scripts/diff-extra-package-upstream.sh scripts/gen-manifest.sh scripts/rebuild.sh scripts/publish-local.sh scripts/check-upstream-updates.sh`
- `git diff --check`
- `git status --short`
Expected:
- syntax checks pass
- no whitespace errors
- only intended files changed

- [ ] **Step 5: Commit final doc cleanup**

```bash
git add pkgbuilds/README.md README.md package-lists/access-os-extra.txt scripts
git commit -m "Document hybrid curated extra package workflow"
```
