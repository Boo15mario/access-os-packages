# pkgbuilds

This directory stores PKGBUILD snapshots automatically saved by CI after each
successful AUR package build.

## Purpose

- **AUR removal safety**: If a package is later removed from the AUR, the saved
  PKGBUILD here is used as a fallback so CI can continue building and serving
  the package without interruption.
- **Audit trail**: Each subdirectory contains the exact `PKGBUILD` (and
  `.SRCINFO` when available) that produced the last successful build.

## Layout

```
pkgbuilds/
  <pkgname>/
    PKGBUILD      # Saved from last successful build
    .SRCINFO      # Saved from last successful build (if present)
```

## Adding a manual PKGBUILD

If a package has been removed from the AUR and no saved PKGBUILD exists yet,
you can add one manually:

1. Create `pkgbuilds/<pkgname>/PKGBUILD` (and optionally `.SRCINFO`).
2. Commit the file.
3. CI will use it as a fallback to continue building the package.
