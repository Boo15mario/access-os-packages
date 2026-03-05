# access-os-packages

Two pacman repositories for Access OS (Arch Linux based):

- `access-os-core`: Access OS maintained packages (PKGBUILDs live in this repo)
- `access-os-extra`: AUR packages built by CI (start small, grow intentionally)

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

## Adding packages

### AUR (`access-os-extra`)
- Edit `package-lists/access-os-extra.txt`.

### Core (`access-os-core`)
- Add a PKGBUILD under `packages/core/<pkgname>/PKGBUILD` (plus any needed files/patches).
- CI will build every core package in `packages/core/*`.

## Automation

GitHub Actions runs on a schedule and:
- Computes the desired `manifest.json` (core PKGBUILDs + AUR versions).
- Compares it to the published Pages `manifest.json`.
- If anything changed, rebuilds everything, uploads packages to Releases, and updates Pages DBs.

## One-time GitHub setup

1. Repo **Settings → Pages → Build and deployment**: set **Source** to **GitHub Actions**.
2. Repo **Settings → Actions → General → Workflow permissions**: set to **Read and write**.
