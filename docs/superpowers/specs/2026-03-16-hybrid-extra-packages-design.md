# Hybrid Curated Extra Packages Design

## Goal

Move `access-os-extra` from an AUR-driven package list model to a curated packaging model where reviewed PKGBUILDs in this repo are the primary build source, while still allowing explicit AUR inspection and refresh work when requested.

## Problem Statement

The local AUR mirror removes live AUR from the normal build and publish path, but the current model still treats AUR-originated packages as a separate class of package managed by `package-lists/access-os-extra.txt` and imported snapshots.

That still leaves two structural issues:

1. The source of truth for `access-os-extra` is not fully owned by this repo.
2. Package maintenance is split between a package list, a local mirror, and `pkgbuilds/` snapshots.
3. AUR remains conceptually upstream truth rather than an intake source.

The desired model is a hybrid one:

- curated PKGBUILDs in-repo are the source of truth for approved `access-os-extra` packages
- the local AUR mirror is a maintenance intake source
- AUR itself is queried only when explicitly requested for inspection or refresh

## Scope

In scope:

- define `packages/extra/<pkg>/` as the new curated source of truth for extra packages
- define the source precedence during transition
- preserve the ability to inspect AUR packages on request
- preserve `pkgbuilds/` as a transition and fallback layer
- update the operator workflow and package intake model

Out of scope:

- migrating every current package in one step
- eliminating the local AUR mirror
- changing the GitHub Releases / Pages distribution model
- replacing `pkgbuilds/` immediately

## Recommended Model

### Source of truth

For `access-os-extra`, the new target source precedence is:

1. `packages/extra/<pkg>/`
2. `pkgbuilds/<pkg>/`
3. fail with a clear error

Normal build and publish flows must not use live AUR.

### Role of each layer

#### `packages/extra/<pkg>/`

This becomes the reviewed, curated packaging source for packages you have accepted into the distro.

Properties:

- committed in this repo
- owned and reviewed like `packages/core/`
- used directly by normal builds
- updated intentionally, not implicitly

#### `pkgbuilds/<pkg>/`

This remains an archive/fallback layer during transition.

Properties:

- used when a package has not yet been promoted into `packages/extra/`
- remains useful for removed packages and legacy packaging history
- gradually shrinks in importance as packages move into `packages/extra/`

#### `~/aur-mirror/<pkg>/`

This becomes the intake/update source.

Properties:

- used to inspect or refresh package definitions
- not used as the authoritative build source once a package is curated
- safe place to compare upstream AUR changes before importing them

## Package Intake Workflow

### New package request

1. Inspect the requested AUR package explicitly.
2. Sync it into the local mirror.
3. Import the packaging into `packages/extra/<pkg>/`.
4. Review and adjust the PKGBUILD as needed for Access OS.
5. Commit it.
6. Build/publish from the curated repo copy.

### Existing curated package update

1. Sync the local AUR mirror.
2. Diff `~/aur-mirror/<pkg>/` against `packages/extra/<pkg>/`.
3. Intentionally merge or reject upstream changes.
4. Commit the reviewed update.
5. Build/publish from the curated repo copy.

### Legacy package not yet migrated

1. Continue building from `pkgbuilds/<pkg>/`.
2. When ready, promote it into `packages/extra/<pkg>/`.
3. Update docs/state so the curated copy becomes authoritative.

## Transition Strategy

Recommended strategy: dual-source transition.

### Phase 1

Introduce `packages/extra/` and change source precedence to:

1. `packages/extra/<pkg>/`
2. `pkgbuilds/<pkg>/`
3. fail

This allows package-by-package migration without breaking the current repo.

### Phase 2

Add maintenance scripts for:

- promoting a package from mirror or `pkgbuilds/` into `packages/extra/`
- diffing mirror vs curated package

### Phase 3

Gradually migrate existing high-value or high-risk packages first, such as:

- large desktop packages
- packages with custom patches/install files
- packages that frequently break or disappear upstream
- packages central to Access OS

### Phase 4

Once most packages are curated, reduce the role of `pkgbuilds/` to:

- removed-package fallback
- historical archive

## Build and Manifest Behavior

Normal `access-os-extra` operations should ultimately resolve package sources in this order:

1. `packages/extra/<pkg>/`
2. `pkgbuilds/<pkg>/`
3. fail

Manifest generation should use the same precedence.

This makes `access-os-extra` behave much more like `access-os-core`, with the difference being package origin and maintenance process, not build behavior.

## AUR Access Policy

AUR remains allowed, but only for explicit maintenance actions.

Examples:

- “inspect this AUR package”
- “check whether this package still exists on AUR”
- “refresh the local mirror”
- “compare upstream AUR changes for this package”

AUR is no longer part of:

- normal publish
- normal rebuild
- normal stage-only recovery
- normal publish-only recovery

## Comparison to CachyOS

This model is closer to the publicly visible CachyOS approach:

- curated package definitions in a public packaging repo
- explicit upstream tracking and validation
- package maintenance as a review/curation process
- binary publishing from maintained local packaging sources

It does not require replicating their whole infrastructure. It only adopts the important structural decision: curated package definitions are the source of truth.

## Documentation Impact

`README.md` should eventually describe:

- `packages/core/` and `packages/extra/` as first-class maintained package roots
- the local AUR mirror as a maintenance tool
- AUR inspection as explicit, not implicit

`pkgbuilds/README.md` should eventually describe:

- fallback/archive role during the transition
- no longer being the preferred normal build source once a package is curated

## Expected Outcome

After this migration begins:

- `access-os-extra` becomes a curated repo, not an AUR-driven list
- the source of truth lives in this git repository
- AUR remains available for inspection and updates when requested
- normal build/publish becomes more deterministic and easier to reason about
