# Curated Package Review and Refresh Design

## Goal

Add explicit review-first maintenance workflows for curated `packages/extra/` packages so upstream AUR changes can be inspected before being applied, and so uncurated mirrored packages can be reviewed for promotion.

This is an intermediate step toward a more CachyOS-like packaging model where curated package definitions in the repo are the source of truth and upstream changes are intentionally reviewed rather than implicitly consumed.

## Problem Statement

The current hybrid model already separates:

- curated package sources in `packages/extra/`
- transition/fallback sources in `pkgbuilds/`
- upstream intake sources in `~/aur-mirror/`

But maintenance is still missing two practical operator workflows:

1. reviewing changes for one curated package before updating it
2. reviewing the status of all curated packages at once
3. seeing which mirrored packages exist in the transition list but have not yet been curated

Without those workflows, updates are still too manual and the curated model is harder to operate at scale.

## Scope

In scope:

- add a single-package review and refresh workflow
- add an all-packages curated review workflow
- add reporting for uncurated mirrored packages in the transition list
- keep updates review-first and explicit

Out of scope:

- automatic bulk overwrite of curated packages
- changing build/publish behavior
- replacing the local mirror
- fully replicating CachyOS infrastructure now

## Recommended Model

### Single-package refresh

Add `scripts/refresh-extra-package.sh`.

Default behavior:

- compare `packages/extra/<pkg>/` against `~/aur-mirror/<pkg>/`
- show whether the package is:
  - up to date
  - changed
  - missing from mirror
  - missing from curated packages
- print a diff summary
- make no changes

Apply behavior:

- `scripts/refresh-extra-package.sh --apply <pkg>`
- replace the curated package contents with the mirror packaging snapshot
- still use the packaging-only copy rules

This makes refresh explicit and reviewable.

### All curated packages review

Add `scripts/review-extra-packages.sh`.

Default behavior:

- iterate all `packages/extra/<pkg>/`
- compare each one against the local mirror
- print a concise status table with one line per package:
  - `up-to-date`
  - `changed`
  - `missing-from-mirror`

Optional diff mode:

- `scripts/review-extra-packages.sh --diff`
- print full diffs for changed packages after the summary

This gives you a repo-wide update dashboard without modifying any package.

### Uncurated mirror review

Extend `scripts/review-extra-packages.sh` with a transition-list view.

Suggested mode:

- `scripts/review-extra-packages.sh --uncurated`

Behavior:

- read `package-lists/access-os-extra.txt`
- show packages that:
  - exist in the local mirror
  - do not yet exist in `packages/extra/`
- report whether they still only live in:
  - mirror only
  - mirror + `pkgbuilds/`

This gives you a clean way to identify packages that are candidates for promotion into curated packaging.

## Script Responsibilities

### `scripts/refresh-extra-package.sh`

Purpose:

- operator tool for one package at a time

Required behavior:

- `--help`
- review mode by default
- `--apply` mode for explicit overwrite of curated package files
- clear errors when either side is missing

### `scripts/review-extra-packages.sh`

Purpose:

- repo-wide review/report tool

Required behavior:

- summary mode by default
- `--diff` for detailed changed-package diffs
- `--uncurated` for promotion candidates

## Safety Model

The scripts should follow these rules:

- no mass overwrite mode for all packages
- `--apply` only works for a single named package
- default mode is always read-only review
- all comparisons use packaging-only normalized snapshots, not raw repo directories

This keeps the model intentional and avoids accidentally replacing local curated packaging changes.

## Operator Workflow

### Update one curated package

```bash
./scripts/sync-aur-mirror.sh
./scripts/refresh-extra-package.sh niri-git
./scripts/refresh-extra-package.sh --apply niri-git
```

Then review and commit the curated changes before rebuilding.

### Review all curated packages

```bash
./scripts/sync-aur-mirror.sh
./scripts/review-extra-packages.sh
./scripts/review-extra-packages.sh --diff
```

### Find promotion candidates

```bash
./scripts/review-extra-packages.sh --uncurated
```

### Promote a new package

```bash
./scripts/promote-extra-package.sh <pkgname>
```

## Long-Term Direction

This is intentionally moving toward a more CachyOS-like operating model:

- curated package definitions in the repo are the source of truth
- upstream AUR changes are reviewed, not consumed directly
- repo-wide maintenance uses explicit reporting and curation workflows
- binary builds come from maintained local packaging definitions

This change does not finish that transition, but it closes a key operational gap needed to maintain curated packages at scale.

## Documentation Impact

`README.md` should document:

- one-package refresh workflow
- all-packages review workflow
- uncurated package review workflow

`packages/extra/README.md` should document:

- refresh vs promote roles
- review-first expectation before applying upstream packaging changes

## Expected Outcome

After implementation:

- updating one curated package becomes a clear review-first process
- reviewing the whole curated set becomes easy
- finding packages that should be promoted next becomes easy
- the repo moves further away from ad-hoc AUR consumption and closer to curated package maintenance
