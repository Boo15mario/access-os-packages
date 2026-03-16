# NVChecker Integration Design

**Date:** 2026-03-16

## Goal

Add CachyOS-style update tracking to `access-os-packages` using `nvchecker`, covering both local/custom packages and the AUR package list, without changing the existing local build/publish pipeline.

## Problems

1. Current update detection is tightly coupled to manifest generation and AUR RPC logic.
2. There is no separate upstream-oriented package update reporting layer.
3. The repo now needs a cleaner, lower-churn way to track package updates similar to CachyOS.
4. The package set spans both local/custom packages and AUR-driven packages.

## Approaches

### 1. Keep the current manifest/AUR-only update detection
- Already works for build decisions.
- Does not provide CachyOS-style upstream update reporting.

### 2. Add `nvchecker` only for local/custom packages
- Easier start.
- Misses most of the package set.

### 3. Add unified `nvchecker`-style tracking for both local/custom and AUR packages
- Best fit.
- Introduces a dedicated update-reporting layer without replacing the current build logic.

## Recommendation

Use approach 3.

## Design

### Scope

`nvchecker` integration should be used for update reporting and maintenance visibility, not as the build source of truth.

Keep existing systems for:
- build/publish orchestration
- package skip logic
- repo metadata generation
- removed-from-AUR handling

Add a parallel update-tracking system for:
- local/custom packages under `packages/`
- AUR packages listed in `package-lists/access-os-extra.txt`

### Configuration model

Use centralized config files instead of scattering `.nvchecker.toml` into every package directory.

Proposed files:
- `metadata/nvchecker/local.toml`
- `metadata/nvchecker/aur.toml`
- optional generated/indexed mapping files for local package metadata

This keeps package tracking policy explicit and easy to review.

### Local/custom package tracking

For packages under `packages/`:
- define upstream source rules explicitly in `metadata/nvchecker/local.toml`
- compare upstream version against the local package version from `.SRCINFO` or `PKGBUILD`

### AUR package tracking

For packages in `package-lists/access-os-extra.txt`:
- first implementation can use `source = "aur"` style package tracking where possible, or a small wrapper that compares current AUR version to local/published version
- keep AUR package enumeration generated from the package list so the config does not drift manually

### Outputs

Generate update-tracking artifacts such as:
- `metadata/upstream-updates.json`
- `metadata/upstream-updates.md`

These should list:
- package name
- source type (`local`, `aur`)
- current local version
- detected upstream/latest version
- status (`up-to-date`, `update-available`, `check-failed`)

### CI workflow

Add a scheduled GitHub Actions workflow dedicated to update reporting:
- install `nvchecker`
- run a new script such as `scripts/check-upstream-updates.sh`
- publish the JSON/Markdown report as workflow artifacts or commit/update metadata

This workflow should be separate from the current validation workflow.

## Expected outcome

The repo gains a CachyOS-style maintenance layer for package updates, covering both local/custom and AUR packages, while keeping the current local publish pipeline intact.
