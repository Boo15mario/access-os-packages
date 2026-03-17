# pkgbuilds

This directory stores saved AUR packaging snapshots automatically created by CI
after each successful AUR package build.

## Purpose

- **AUR removal safety**: If a package is later removed from the AUR, the saved
  snapshot here is used as a fallback so CI can continue building it.
- **Build context preservation**: Each subdirectory may contain `PKGBUILD`,
  `.SRCINFO`, patches, install files, or other packaging files needed for a
  rebuild.
- **Removed package tracking**: Packages using these fallbacks are also recorded
  in `metadata/removed-from-aur.json` and `metadata/removed-from-aur.txt`.
- **Mirror import target**: Local AUR mirror snapshots can be imported here with
  `./scripts/import-aur-snapshots.sh`.

## Layout

```
pkgbuilds/
  <pkgname>/
    PKGBUILD
    .SRCINFO
    *.patch
    *.install
    ...
```

## Adding a manual PKGBUILD

If a package has been removed from the AUR and no saved PKGBUILD exists yet,
you can add one manually:

1. Create `pkgbuilds/<pkgname>/` with `PKGBUILD` and any other required
   packaging files.
2. Commit the directory.
3. CI will use it as a fallback to continue building the package.

## Importing from the local AUR mirror

If you maintain a local mirror under `~/aur-mirror` (or another
`AUR_MIRROR_DIR`), import packaging snapshots into this directory with:

```bash
./scripts/import-aur-snapshots.sh
```

These imported snapshots remain the in-repo fallback and audit trail when the
mirror is unavailable or a package later disappears upstream.
