# access-os-packages

Two pacman repositories for Access OS (Arch Linux based):

- `access-os-core`: Access OS maintained packages (PKGBUILDs live in this repo)
- `access-os-extra`: AUR packages built locally on your Arch system

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

Minimum packages to install:

```bash
./scripts/bootstrap-builder.sh
```

Equivalent manual package list:

```bash
sudo pacman -S --needed base-devel git curl jq pacman-contrib devtools github-cli
```

Recommended extras:

```bash
sudo pacman -S --needed ccache reflector rsync
```

Required one-time setup:

1. Enable `multilib` in `/etc/pacman.conf`.
2. Authenticate GitHub CLI with `gh auth login`.
3. In GitHub repo settings, configure **Pages** to deploy from the `gh-pages` branch.

Preflight check:

```bash
./scripts/check-builder.sh
./scripts/publish-local.sh --preflight
```

Local publish entrypoint:

```bash
./scripts/publish-local.sh
```

Useful modes:

```bash
./scripts/publish-local.sh --build-only
./scripts/publish-local.sh --publish-only
./scripts/publish-local.sh --no-push
```

Recovery after an interrupted build:

```bash
./scripts/rebuild.sh --stage-only
./scripts/publish-local.sh --publish-only
```

What `scripts/publish-local.sh` does:
- refreshes removed-AUR tracking metadata
- runs `scripts/rebuild.sh` on your Arch system
- uploads package files to the moving GitHub Release tags as each package finishes building
- commits updated `pkgbuilds/` and `metadata/` unless `--skip-commit` is used
- pushes generated `site/` content to the `gh-pages` branch for GitHub Pages

If you run `./scripts/publish-local.sh --publish-only` and `site/` is missing or
incomplete, it will automatically regenerate the staged repo metadata from the
existing `dist/` package artifacts before publishing.

During a normal `./scripts/publish-local.sh` run, each successfully built
package is uploaded immediately and Pages metadata is refreshed from the current
`dist/` contents. If a later package fails, GitHub Releases and GitHub Pages
still reflect everything that finished successfully up to that point.

Local builds also harden source downloads inside `scripts/rebuild.sh` by using
repo-local `makepkg` download settings with `curl --http1.1` and retries. This
helps with flaky upstream TLS endpoints used by some AUR packages.

`scripts/rebuild.sh` also authenticates `sudo` once at startup and keeps the
timestamp alive during the build, so mid-build `sudo pacman -U` steps do not
keep asking for your password.

Local builds also auto-tune `makepkg` parallel jobs from CPU cores and total
RAM, then cap the result at `15` by default. You can override that at runtime:

```bash
MAKEPKG_JOBS=5 ./scripts/rebuild.sh
MAKEPKG_JOBS=8 ./scripts/publish-local.sh
```

## Adding packages

### AUR (`access-os-extra`)
- Edit `package-lists/access-os-extra.txt`.
- If a package is later **removed from the AUR**, CI will only fall back to a
  saved snapshot in `pkgbuilds/<pkgname>/`.
- Confirmed removed packages are tracked automatically in
  `metadata/removed-from-aur.json` and `metadata/removed-from-aur.txt`.
- If a removed package later returns to AUR, CI removes it from the removed
  tracking files automatically.
- If a listed package is missing from AUR and no saved snapshot exists, the
  workflow fails so the package list does not silently drift.

### Core (`access-os-core`)
- Add a PKGBUILD under `packages/core/<pkgname>/PKGBUILD` (plus any needed files/patches).
- Local publishing will build every core package in `packages/core/*`.

## PKGBUILDs

The `pkgbuilds/` directory stores saved AUR packaging snapshots automatically
committed during local publishing after each successful AUR package build. These snapshots are
used only when a package is no longer available from AUR. The saved snapshots
keep packaging files only; downloaded source payloads are excluded.

## Removed AUR tracking

Removed-but-preserved AUR packages are tracked in:

- `metadata/removed-from-aur.json`: canonical machine-readable registry
- `metadata/removed-from-aur.txt`: generated package-name list

Local publishing refreshes these files automatically, and CI validates them:
- when a listed package disappears from AUR but still has a saved fallback in
  `pkgbuilds/`
- when a previously removed package returns to AUR

If a package disappears from AUR and no saved fallback exists, the workflow
fails instead of silently dropping it.

You can also add a PKGBUILD manually (e.g. for a package recently removed from
the AUR before CI had a chance to save it):

1. Create `pkgbuilds/<pkgname>/` with `PKGBUILD` and any other files that the
   package build needs.
2. Commit the directory.
3. CI will use it to continue building the package.

## Automation

GitHub Actions is validation-only. It does not build or publish packages.

Actions checks:
- shell script syntax
- workflow YAML validity
- AUR metadata and removed-package tracking
- manifest generation and update detection
- `scripts/rebuild.sh --dry-run`

Package building and publishing now happens locally on your Arch system through
`scripts/publish-local.sh`.

## One-time GitHub setup

1. Repo **Settings → Pages → Build and deployment**: set **Source** to **Deploy from a branch**.
2. Select branch `gh-pages` and folder `/ (root)`.
