# Local AUR Mirror Design

## Goal

Remove live AUR availability from the normal `access-os-extra` build and publish path.

After this change, the local build workflow should use a locally maintained AUR mirror as the primary packaging source, keep `pkgbuilds/` as the in-repo packaging snapshot, and reserve live AUR access for explicit mirror refresh operations only.

## Problem Statement

The current repo has already reduced AUR dependence in `--stage-only` and `--publish-only` flows, but normal `access-os-extra` builds still rely on live AUR state for several tasks:

- refreshing removed-package tracking
- resolving current package metadata for manifest generation
- cloning AUR repos during builds

That creates three operational problems:

1. AUR rate limiting (`429`) can block normal local publishing.
2. AUR package disappearance can interrupt builds unless `pkgbuilds/` is already populated.
3. Build reproducibility depends on a live external service during the main publish workflow.

The desired state is closer to a packaging-maintainer model: refresh upstream packaging deliberately, then build and publish from locally controlled inputs.

## Scope

In scope:

- add a local AUR mirror outside the repo, defaulting to `~/aur-mirror`
- add scripts to sync that mirror and import packaging snapshots into `pkgbuilds/`
- make `rebuild.sh` prefer the local mirror for `access-os-extra`
- make `gen-manifest.sh` prefer the local mirror for package metadata
- make `publish-local.sh` skip live removed-AUR sync when a local mirror is available
- document the mirror workflow

Out of scope:

- mirroring upstream source tarballs referenced by PKGBUILDs
- full AUR-wide mirroring infrastructure
- replacing `pkgbuilds/` with a generated or ephemeral cache
- changing the GitHub Releases / GitHub Pages publish model

## Design Overview

### Source precedence

For `access-os-extra`, packaging sources will resolve in this order:

1. local AUR mirror clone in `AUR_MIRROR_DIR/<pkg>/`
2. in-repo snapshot in `pkgbuilds/<pkg>/`
3. fail with a clear error

Live AUR will no longer be used implicitly by normal build and publish commands.

### Mirror root

A new environment variable controls the mirror root:

- `AUR_MIRROR_DIR="${AUR_MIRROR_DIR:-$HOME/aur-mirror}"`

This location is intentionally outside the git repo so that:

- mirror sync does not dirty the working tree
- large histories stay out of the project repository
- the same mirror can be reused across runs

### New scripts

#### `scripts/sync-aur-mirror.sh`

Purpose:

- ensure every package in `package-lists/access-os-extra.txt` has a local working clone under `AUR_MIRROR_DIR`
- update existing clones from AUR

Behavior:

- create `AUR_MIRROR_DIR` if missing
- for each package in `package-lists/access-os-extra.txt`:
  - clone `https://aur.archlinux.org/<pkg>.git` if absent
  - otherwise fetch and fast-forward the local clone
- fail loudly if any requested package cannot be refreshed

This script is the only place where the normal workflow still contacts live AUR by default.

#### `scripts/import-aur-snapshots.sh`

Purpose:

- copy packaging-only files from `AUR_MIRROR_DIR/<pkg>/` into `pkgbuilds/<pkg>/`

Behavior:

- use the same include/exclude policy as the saved post-build snapshots
- preserve `PKGBUILD`, `.SRCINFO`, patches, install files, and similar packaging inputs
- exclude downloaded sources, build outputs, `.git`, and large binary payloads

This keeps the in-repo fallback snapshot aligned with the mirror.

## Build Path Changes

### `scripts/rebuild.sh`

For `access-os-extra` packages:

- prefer copying packaging files from `AUR_MIRROR_DIR/<pkg>/` into the temporary build dir
- fall back to `pkgbuilds/<pkg>/` if the mirror entry is missing
- stop attempting live `git clone` from the AUR during normal builds

This means:

- normal `publish-local.sh` runs are no longer blocked by AUR RPC limits or transient AUR outages
- build inputs are stable for the duration of the run

### `scripts/gen-manifest.sh`

Manifest generation should resolve package version metadata from:

1. local mirror `.SRCINFO` / `PKGBUILD`
2. `pkgbuilds/<pkg>/`
3. fail

This removes live AUR queries from normal manifest generation when the mirror exists.

### `scripts/publish-local.sh`

When `AUR_MIRROR_DIR` exists and contains package clones:

- skip `scripts/sync-removed-from-aur.sh` during normal publish runs
- rely on mirror-first manifest/build resolution

When no mirror exists:

- current behavior remains available as a fallback path

## Packaging Snapshot Policy

The repo now needs one consistent packaging-only filter used by:

- post-build saved snapshots in `rebuild.sh`
- mirror import in `import-aur-snapshots.sh`

Included examples:

- `PKGBUILD`
- `.SRCINFO`
- `*.patch`
- `*.install`
- small helper scripts or config files referenced by the PKGBUILD

Excluded examples:

- `src/`
- `pkg/`
- downloaded archives and ISOs
- build outputs
- `.git/`
- generated package files

The purpose is to preserve rebuildable packaging context without reintroducing oversized git objects.

## Error Handling

### Mirror sync failures

`scripts/sync-aur-mirror.sh` should fail if a requested package cannot be cloned or updated. That is a maintenance operation and should not silently drift.

### Normal build failures

`rebuild.sh` should fail with a clear package-specific error when neither:

- `AUR_MIRROR_DIR/<pkg>/`
- nor `pkgbuilds/<pkg>/`

exists.

### Partial mirror state

If some packages exist in the mirror and others do not:

- the existing mirror entries are used
- missing ones fall back to `pkgbuilds/`
- only packages missing in both locations fail

## Documentation Changes

`README.md` should document:

- mirror root location
- how to run `scripts/sync-aur-mirror.sh`
- how to run `scripts/import-aur-snapshots.sh`
- that normal builds are mirror-first
- that live AUR is only needed when refreshing the mirror

`pkgbuilds/README.md` should document:

- snapshots can be imported from the local mirror
- `pkgbuilds/` remains the in-repo fallback and audit trail

## Verification Plan

Implementation should verify at least:

- shell syntax for the new scripts and changed scripts
- `rebuild.sh --dry-run`
- a mirror sync smoke test against the configured package list
- a snapshot import smoke test into `pkgbuilds/`
- a manifest generation check using mirror-backed metadata

## Expected Outcome

After implementation:

- `./scripts/publish-local.sh` no longer depends on live AUR during normal operation
- `./scripts/rebuild.sh` builds `access-os-extra` from local mirror or local snapshots
- `pkgbuilds/` remains the durable in-repo fallback for removed packages
- AUR outages and rate limits stop blocking routine local publishing
