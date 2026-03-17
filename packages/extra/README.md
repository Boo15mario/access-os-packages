# packages/extra

This directory holds curated `access-os-extra` package definitions.

## Purpose

- **Primary source of truth**: reviewed `access-os-extra` packages should live
  in `packages/extra/<pkg>/`.
- **Normal build source**: normal `scripts/rebuild.sh` and
  `scripts/publish-local.sh` runs prefer this directory over `pkgbuilds/`.
- **Maintained packaging**: packages here are treated like first-class distro
  packaging, not ad-hoc upstream snapshots.

## Layout

```text
packages/extra/
  <pkgname>/
    PKGBUILD
    .SRCINFO
    *.patch
    *.install
    ...
```

## Relationship to other package sources

- `packages/extra/<pkg>/` — curated, reviewed source of truth
- `pkgbuilds/<pkg>/` — transition / fallback / archive layer
- `~/aur-mirror/<pkg>/` — maintenance intake source for explicit upstream sync

## Maintenance flow

Promote a package into this directory with:

```bash
./scripts/promote-extra-package.sh <pkgname>
```

Review a curated package against the local AUR mirror with:

```bash
./scripts/refresh-extra-package.sh <pkgname>
```

Apply a reviewed upstream mirror update to a curated package with:

```bash
./scripts/refresh-extra-package.sh --apply <pkgname>
```

Review all curated packages at once with:

```bash
./scripts/review-extra-packages.sh
./scripts/review-extra-packages.sh --diff
```

Find transition-list packages that are mirrored but not yet curated with:

```bash
./scripts/review-extra-packages.sh --uncurated
```
