# Access OS Package Repositories (Core + Extra) — Design

**Date:** 2026-03-05  
**Status:** Approved: GitHub Releases (packages) + GitHub Pages (repo DB + manifest)

## Goal
Create an `access-os` package repository system (Arch Linux based) hosted in a GitHub repo, with:

- `access-os-core`: Access OS maintained packages (custom PKGBUILDs/sources stored in this repo)
- `access-os-extra`: AUR-built packages (start with the small set needed by the ISO)

Automate rebuilds via GitHub Actions and publish the pacman repositories via GitHub Pages.

## Non-goals (for initial version)
- Package signing / key distribution (add later)
- Building the full `a-list.txt` AUR set (start small)
- Replacing the ISO build pipeline (this repo just produces pacman repos)

## Inputs and starting point
We’ll reuse ideas from `../access-os`:
- `aur-and-custom-packages.md`: canonical “AUR vs custom” list (keep custom/not-in-AUR here for now)
- `scripts/build.sh`: reference for build loop + `repo-add` logic (but avoid `paru` in CI)

Initial `access-os-extra` AUR package list:
- `neofetch`
- `mkinitcpio-firmware`
- `reiserfsprogs`

## Repository layout (this repo)
- `packages/core/<pkgname>/PKGBUILD` (+ files/patches): sources for `access-os-core`
- `package-lists/access-os-extra.txt`: newline-separated AUR package names
- `aur-and-custom-packages.md`: keep “not in AUR” list here until we convert those to PKGBUILDs
- `scripts/`: local + CI entrypoints
  - `scripts/rebuild.sh`: main entrypoint used by GitHub Actions; can also be run locally
  - `scripts/check-updates.sh`: determine if rebuild is needed (used by workflow)
- `.github/workflows/build-repos.yml`: scheduled + manual build, deploy to Pages
- `site/` (CI-only staging): output tree deployed to Pages

## GitHub Pages publishing layout
Publish standard pacman repo paths:
- `site/access-os-core/os/x86_64/`
- `site/access-os-extra/os/x86_64/`

Each contains:
- repo DB files (e.g. `access-os-core.db*`, `access-os-core.files*`)
- a small `manifest.json` used for update detection

Packages (`*.pkg.tar.zst`) are stored in **GitHub Releases** (as release assets), not on Pages.

Note: GitHub Pages deployment artifacts must not contain symlinks; after `repo-add` we will ensure `.db` and `.files` are real files (not symlinks to `*.tar.*`).

Pacman consumers can use:
```
[access-os-core]
Server = https://<owner>.github.io/<repo>/$repo/os/$arch
Server = https://github.com/<owner>/<repo>/releases/download/$repo-$arch/
SigLevel = Optional TrustAll

[access-os-extra]
Server = https://<owner>.github.io/<repo>/$repo/os/$arch
Server = https://github.com/<owner>/<repo>/releases/download/$repo-$arch/
SigLevel = Optional TrustAll
```

## Build and update-detection design
### When to rebuild
On a schedule (and manual dispatch), the workflow will:
1. Fetch currently-published version metadata from GitHub Pages (a small `manifest.json` published alongside the repos; if missing, treat as first build).
2. Compute the “desired” versions:
   - `access-os-extra` versions from AUR metadata (AUR RPC API) **or** by cloning AUR and reading `.SRCINFO`
   - `access-os-core` versions from the local PKGBUILDs / `.SRCINFO`
3. If any package version differs (or DB missing), rebuild **all** packages and republish.
4. If no versions differ, exit without deploying (no-op run).

### How to build in CI (Arch container)
- Run builds inside an `archlinux:latest` container job.
- Create an unprivileged `builder` user (makepkg refuses to run as root).
- Install build requirements: `base-devel`, `git`, `curl`, `jq`, `sudo`.
- Allow `builder` passwordless pacman (CI-only) so `makepkg --syncdeps` can install deps.
- Build outputs go to per-repo staging directories.
- `repo-add` generates DBs from the staged packages; the DBs are written to `site/<repo>/os/<arch>/`.
- Package files are uploaded as **GitHub Release assets** to moving tags:
  - `access-os-core-x86_64`
  - `access-os-extra-x86_64`
- Output is written to a fresh `site/` tree so old DBs are not retained.

## Deployment
Use the official GitHub Pages Actions flow:
- `actions/upload-pages-artifact` to upload `site/`
- `actions/deploy-pages` to publish

Use GitHub Releases for package hosting:
- Create/update the release tag(s) per repo+arch each rebuild.
- Upload the built `*.pkg.tar.zst` files as release assets.

Workflow triggers:
- `workflow_dispatch` (manual)
- `schedule` (e.g. nightly)
- `push` to default branch for changes affecting packaging/scripts

## Limitations / risks
- GitHub Pages is best for **small** repos; it has size/bandwidth constraints. As `access-os-extra` grows (especially with very large proprietary AUR packages), we may need to move artifacts to an object store (R2/S3) and keep Pages only for metadata and/or index files.
- Unsigned packages are acceptable to bootstrap, but long-term we should sign packages and ship the public key in the ISO/keyring package.

## Next steps
Create an implementation plan and then implement:
1. Skeleton repo structure + package lists
2. CI build scripts for core + extra
3. GitHub Actions workflow + Pages publishing
4. Minimal docs for adding packages and consuming repos
