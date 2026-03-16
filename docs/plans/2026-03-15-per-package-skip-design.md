# Per-Package Rebuild Skip Design

**Date:** 2026-03-15

## Goal

Skip rebuilding packages whose desired source version already matches the published GitHub repo version, while still rebuilding packages whose source version has changed.

## Problems

1. The current workflow decides rebuild need only at the whole-repo level.
2. Once a rebuild starts, `scripts/rebuild.sh` rebuilds every listed package.
3. Long package lists waste time rebuilding packages that are already published at the correct version.
4. AUR packages need a version check against both the live AUR state and the published GitHub manifest.

## Approaches

### 1. Compare only local `dist/` artifacts
- Skip if a matching package file already exists in `dist/`.
- Fast, but wrong after clean runs or on a new machine.
- Does not use GitHub as the published source of truth.

### 2. Compare only GitHub `manifest.json`
- Skip if the published manifest already has the same version.
- Better, but still incomplete unless desired versions are resolved from current package sources.
- Needs separate desired-version lookup for core and AUR packages.

### 3. Compare desired source versions against published GitHub versions
- Resolve the desired package version from local core PKGBUILDs or AUR/current fallback metadata.
- Read published versions from GitHub Pages `manifest.json`.
- Skip build when desired version equals published version.
- Rebuild when versions differ or the package is absent remotely.

## Recommendation

Use approach 3.

That gives the exact behavior requested:
- published `access-launcher = 1.1`, desired `1.1` -> skip
- published `access-launcher = 1.1`, desired `1.2` -> rebuild and publish

## Design

### Version resolution

Use one desired-version lookup per package before building:
- core packages: parse local package metadata from `PKGBUILD` or generated `.SRCINFO`
- AUR packages: resolve current desired version using the same logic as `scripts/gen-manifest.sh`
  - live AUR when available
  - saved fallback snapshot only when the package is gone from AUR

Fetch the published manifest once per run from GitHub Pages and cache it in memory.

### Build decision

For each package:
- look up `desired_version`
- look up `published_version`
- if `desired_version == published_version`, log a skip message and do not run `makepkg`
- otherwise build and publish incrementally as today

Packages missing from the published manifest are treated as needing a build.

### Failure behavior

- If GitHub manifest cannot be fetched, fail back to current conservative behavior: build everything.
- If desired version cannot be resolved for a package, do not skip it; build it.
- Never skip on uncertain data.

### Scope

This change affects build-time skipping only.

It does not change:
- manifest generation logic
- removed-from-AUR tracking policy
- incremental release upload behavior
- final metadata/snapshot commit behavior

## Expected outcome

Repeated local publish runs stop rebuilding unchanged packages. Only packages whose source version changed, or which are missing remotely, are rebuilt and republished.
