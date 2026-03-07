# Removed AUR Package Tracking — Design

**Date:** 2026-03-07  
**Status:** Approved

## Goal
Keep building packages that were previously built from AUR even after they are removed from AUR, while automatically documenting those removals in both a machine-readable file and a simple text list.

## Requirements
- If a package disappears from AUR and a saved fallback exists in `pkgbuilds/<pkg>/`, CI continues building it from the saved snapshot.
- Removed packages are automatically recorded.
- The record lives in:
  - `metadata/removed-from-aur.json` as the source of truth
  - `metadata/removed-from-aur.txt` as a generated, human-readable list
- If a package later returns to AUR, it is removed from both tracking files and treated as a normal AUR package again.
- If a package disappears from AUR and no fallback exists, the workflow still fails loudly.

## Source of truth
Use `metadata/removed-from-aur.json` as the canonical registry.

Each entry stores:
- `package`
- `detected_at`
- `fallback_path`
- `last_known_version`

The generated `metadata/removed-from-aur.txt` contains one package name per line, sorted alphabetically.

## Detection model
There are two relevant states:

1. **AUR package present**
   - Package remains in `package-lists/access-os-extra.txt`
   - Package must not appear in removed tracking files

2. **AUR package missing**
   - If `pkgbuilds/<pkg>/PKGBUILD` exists, use fallback and record the package in removed tracking
   - If no fallback exists, fail the workflow

Returned packages are not tracked historically in the first version. They are removed from the tracking files entirely.

## Where the logic lives
- `scripts/gen-manifest.sh`
  - already determines whether a package is present in AUR or falling back to `pkgbuilds/`
  - should emit enough information for tracking updates, or share logic with a new helper
- `scripts/rebuild.sh`
  - already uses fallback only when the package is confirmed gone from AUR
  - should continue saving packaging snapshots after successful builds
- New helper script
  - recommended: `scripts/sync-removed-from-aur.sh`
  - updates `metadata/removed-from-aur.json`
  - regenerates `metadata/removed-from-aur.txt`

## Update flow
On each CI run:

1. Read `package-lists/access-os-extra.txt`
2. Query AUR status for each listed package
3. For each package:
   - if AUR exists: ensure it is absent from removed tracking
   - if AUR is missing and fallback exists: ensure it is present in removed tracking
   - if AUR is missing and fallback does not exist: fail
4. Regenerate `metadata/removed-from-aur.txt`
5. Commit metadata changes in the same workflow that already commits `pkgbuilds/`

## Repository changes
- Create `metadata/`
- Add:
  - `metadata/removed-from-aur.json`
  - `metadata/removed-from-aur.txt`
  - optional `metadata/README.md` if needed later

## Failure policy
- Network failure or ambiguous AUR response is not treated as removal.
- Only confirmed AUR absence may enter the removed registry.
- This preserves the current policy of failing on transient AUR/network issues.

## Documentation
Update:
- `README.md`
- `pkgbuilds/README.md`

Document:
- what the removed registry means
- how packages are added and removed from it automatically
- that returned AUR packages are automatically removed from the registry

## Non-goals
- Historical archive of every removal/return event
- Separate manual review queue
- Automatic package-list editing outside the existing `access-os-extra.txt`

