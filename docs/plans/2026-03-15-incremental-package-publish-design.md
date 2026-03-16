# Incremental Package Publish Design

**Date:** 2026-03-15

## Goal

Publish successfully built packages to GitHub Releases and update GitHub Pages metadata as each package completes, instead of waiting for the full rebuild to finish.

## Problems

1. `scripts/publish-local.sh` currently publishes only after the entire rebuild finishes.
2. Long builds mean a late failure leaves already-built packages unpublished.
3. Recovery works, but it still requires a second publish step and manual operator attention.
4. Release assets and repo metadata can lag behind local `dist/` for many hours during large rebuilds.

## Approaches

### 1. End-of-run publishing only
- Keep the current model.
- Simplest implementation.
- Does not solve the user's problem.

### 2. Incremental release uploads only
- Upload package files to GitHub Releases after each successful package.
- Still defer repo DB and `manifest.json` publication until the end.
- Better than current behavior, but pacman clients would not see packages until later because Pages metadata stays stale.

### 3. Incremental package and metadata publishing
- After each successful package build:
  - upload the new package file(s) to the matching GitHub Release
  - rebuild the affected repo database and staged `site/` metadata
  - publish the updated Pages content
- Keep `pkgbuilds/` and removed-AUR metadata commits batched near the end of the run.
- This gives the best recovery behavior and keeps pacman metadata aligned with uploaded packages.

## Recommendation

Use approach 3.

The repo already has the pieces required for this:
- package outputs land in `dist/`
- repo metadata can be regenerated from `dist/`
- Releases uploads already exist in `scripts/publish-local.sh`
- `gh-pages` publishing already exists in `scripts/publish-local.sh`

The missing piece is a publish hook that can safely run after each successful package.

## Design

### `scripts/rebuild.sh`

Add optional incremental publish integration:
- introduce an environment-driven hook or direct function call after each successful package build in `build_core()` and `build_extra()`
- identify newly built package files using the package's `makepkg --packagelist` output filtered to existing files
- after a successful build, invoke a publish helper with:
  - repo name
  - package name
  - built package file paths

If the publish step fails, fail the rebuild immediately. The remote repo must not silently diverge from the local build state.

### `scripts/publish-local.sh`

Refactor publish logic into reusable helpers:
- upload a specific set of package files to the correct GitHub Release
- regenerate repo DBs and `site/manifest.json` from current `dist/`
- publish the refreshed `site/` tree to `gh-pages`

Normal `./scripts/publish-local.sh` runs should enable incremental publishing during rebuilds.

`--build-only` should keep builds local and disable incremental publishing.

`--publish-only` should keep its current behavior: publish what already exists in `dist/` and `site/`.

### Git commit behavior

Do not create a git commit after each package. That would create noisy history and slow the run.

Keep committing:
- `pkgbuilds/`
- `metadata/removed-from-aur.*`

as one batched commit after the build/publish run, or skip it when requested.

### Failure handling

- If package build fails: keep already published packages and already updated metadata.
- If incremental publish fails after a package build: stop the run and report the exact failing step.
- If `gh-pages` publish fails, stop the run. The operator can retry with `./scripts/publish-local.sh --publish-only`.

## Expected outcome

After this change, a partial run still leaves GitHub Releases and GitHub Pages reflecting all packages built successfully up to the failure point. That makes long rebuilds much more useful and reduces recovery work.
