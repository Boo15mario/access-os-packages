# access-os-packages

Two pacman repositories for Access OS (Arch Linux based):

- `access-os-core`: Access OS maintained packages (PKGBUILDs live in this repo)
- `access-os-extra`: curated extra packages built locally on your Arch system

## Using the repos

In `pacman.conf`:

```
[access-os-core]
SigLevel = Optional TrustAll
Server = https://boo15mario.github.io/access-os-packages/$repo/os/$arch
Server = https://github.com/boo15mario/access-os-packages/releases/download/$repo-$arch/

[access-os-extra]
SigLevel = Optional TrustAll
Server = https://boo15mario.github.io/access-os-packages/$repo/os/$arch
Server = https://github.com/boo15mario/access-os-packages/releases/download/$repo-$arch/
```

Notes:
- Package files (`*.pkg.tar.zst`) are stored as **GitHub Release assets** under moving tags like `access-os-core-x86_64`.
- Repo databases (`$repo.db`, `$repo.files`) and `manifest.json` are published on **GitHub Pages**.

## Local builder setup

Build and publish this repo from a local Arch Linux system.

```bash
./scripts/bootstrap-builder.sh
```

Required one-time setup:

1. Enable `multilib` in `/etc/pacman.conf`.
2. Authenticate GitHub CLI with `gh auth login`.
3. In GitHub repo settings, configure **Pages** to deploy from the `gh-pages` branch.

Preflight check:

```bash
./scripts/check-builder.sh
./scripts/publish.sh --preflight
```

## Building and publishing

```bash
./scripts/publish.sh
```

Useful modes:

```bash
./scripts/publish.sh --build-only
./scripts/publish.sh --publish-only
./scripts/publish.sh --no-push
```

Recovery after an interrupted build:

```bash
./scripts/build.sh --stage-only
./scripts/publish.sh --publish-only
```

What `publish.sh` does:
- runs `build.sh` on your Arch system
- uploads package files to GitHub Release tags
- commits updated `packages/extra/` and `metadata/` unless `--skip-commit` is used
- pushes generated `site/` content to the `gh-pages` branch for GitHub Pages

Builds skip packages whose source version already matches the published version.
For skipped packages, the build reuses the matching package artifact from GitHub
so local repo metadata can still be staged correctly.

Builds auto-tune `makepkg` parallel jobs from CPU cores and total RAM, capped at
`15` by default. Override at runtime:

```bash
MAKEPKG_JOBS=5 ./scripts/publish.sh
```

## Adding packages

### Extra (`access-os-extra`)

1. Add a PKGBUILD directory: `packages/extra/<pkgname>/PKGBUILD`
2. Add the package name to `packages/extra.list`
3. Run `./scripts/publish.sh`

### Core (`access-os-core`)

1. Add a PKGBUILD under `packages/core/<pkgname>/PKGBUILD` (plus any needed files/patches)
2. Run `./scripts/publish.sh`

## Updating packages

Sync upstream AUR changes and review:

```bash
./scripts/sync-aur-mirror.sh
diff -ru aur-mirror/<pkgname> packages/extra/<pkgname>
cp -a aur-mirror/<pkgname>/. packages/extra/<pkgname>/
./scripts/publish.sh
```

## AUR mirror

The `aur-mirror/` directory (git-ignored) holds local clones of AUR repos for
upstream comparison. Sync it with:

```bash
./scripts/sync-aur-mirror.sh
```

## Update tracking

`nvchecker`-based update tracking for both:
- local/custom package definitions via `metadata/nvchecker/local.toml`
- AUR packages from `packages/extra.list`, rendered into `metadata/nvchecker/aur.toml`

```bash
./scripts/check-upstream-updates.sh
```

Outputs: `metadata/upstream-updates.json`, `metadata/upstream-updates.md`

GitHub Actions runs this on a schedule in `.github/workflows/check-upstream-updates.yml`.

## Scripts

| Script | Purpose |
|---|---|
| `scripts/sync-aur-mirror.sh` | Clone/fetch AUR repos into `aur-mirror/` |
| `scripts/build.sh` | Build all packages, create repo DBs, generate manifest |
| `scripts/publish.sh` | Top-level: build + upload + gh-pages + reconcile |
| `scripts/check-upstream-updates.sh` | nvchecker-based update reports |
| `scripts/check-builder.sh` | Preflight system checks |
| `scripts/bootstrap-builder.sh` | Install build dependencies |

## Automation

GitHub Actions is validation-only. It does not build or publish packages.

Actions checks:
- shell script syntax
- workflow YAML validity
- package list format
- `build.sh --dry-run`

## One-time GitHub setup

1. Repo **Settings -> Pages -> Build and deployment**: set **Source** to **Deploy from a branch**.
2. Select branch `gh-pages` and folder `/ (root)`.
