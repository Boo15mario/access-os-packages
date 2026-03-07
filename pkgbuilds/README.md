# pkgbuilds

This directory stores saved AUR packaging snapshots automatically created by CI
after each successful AUR package build.

## Purpose

- **AUR removal safety**: If a package is later removed from the AUR, the saved
  snapshot here is used as a fallback so CI can continue building it.
- **Build context preservation**: Each subdirectory may contain `PKGBUILD`,
  `.SRCINFO`, patches, install files, or other packaging files needed for a
  rebuild.

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
