# Access OS Package Repositories Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build and publish two pacman repositories (`access-os-core`, `access-os-extra`) via GitHub Actions, storing package files in GitHub Releases and publishing repo DB + update metadata to GitHub Pages. Rebuild only when upstream versions change.

**Architecture:** A small set of Bash scripts computes a stable `manifest.json` of desired package versions (core PKGBUILDs + AUR RPC versions). GitHub Actions compares it to the currently published `manifest.json` on Pages; if different, it runs an Arch Linux Docker container to build packages with `makepkg`, generates repo DBs with `repo-add`, uploads the built `*.pkg.tar.zst` as GitHub Release assets under moving tags (`$repo-$arch`), stages `site/` with just repo DB + manifest, and deploys to GitHub Pages.

**Tech Stack:** Bash, GitHub Actions, Docker (archlinux container), Arch tools (`makepkg`, `repo-add`), `curl`, `jq`.

---

### Task 1: Initialize repo skeleton + docs folders

**Files:**
- Create: `README.md`
- Create: `aur-and-custom-packages.md`
- Create: `package-lists/access-os-extra.txt`
- Create: `packages/core/.gitkeep` (or placeholder README)
- Create: `scripts/.gitkeep`
- Create: `.github/workflows/.gitkeep` (optional)

**Step 1: Create core directories**

Run:
- `mkdir -p package-lists packages/core scripts .github/workflows`

Expected: directories exist.

**Step 2: Copy the current package notes**

Copy `../access-os/aur-and-custom-packages.md` into `aur-and-custom-packages.md` unchanged.

**Step 3: Create the initial AUR list**

`package-lists/access-os-extra.txt`:
```
# AUR packages for access-os-extra (one per line)
neofetch
mkinitcpio-firmware
reiserfsprogs
```

**Step 4: Document usage**

`README.md` should include:
- Pages URL pattern: `https://<owner>.github.io/<repo>/$repo/os/$arch`
- Releases download pattern (packages): `https://github.com/<owner>/<repo>/releases/download/$repo-$arch/<pkgfile>`
- How to add new AUR packages (edit the list file)
- How to add core packages (drop PKGBUILDs under `packages/core/<pkgname>/`)
- How CI decides whether to rebuild (manifest compare)

**Step 5: Commit**

Run:
- `git add README.md aur-and-custom-packages.md package-lists/access-os-extra.txt packages/core scripts .github`
- `git commit -m "chore: scaffold access-os package repos"`

---

### Task 2: Add a “manifest” generator (desired state)

**Files:**
- Create: `scripts/gen-manifest.sh`

**Step 1: Implement `scripts/gen-manifest.sh`**

This script must print stable JSON to stdout:
- No timestamps.
- Sorted keys (`jq -S`).

Pseudo-output shape:
```json
{
  "version": 1,
  "repos": {
    "access-os-core": { "packages": { "pkg": "1.2.3-1" } },
    "access-os-extra": { "packages": { "neofetch": "7.1.0-1" } }
  }
}
```

Core version extraction (per directory under `packages/core/*` containing a `PKGBUILD`):
- Run `makepkg --printsrcinfo` and parse:
  - `epoch` (optional), `pkgver`, `pkgrel`
  - all `pkgname` entries
- Compute version string:
  - if `epoch` is set and not `0`: `${epoch}:${pkgver}-${pkgrel}`
  - else: `${pkgver}-${pkgrel}`

Extra (AUR) version extraction:
- Read package names from `package-lists/access-os-extra.txt` (ignore blank lines + `#` comments).
- Query AUR RPC per package:
  - URL: `https://aur.archlinux.org/rpc/?v=5&type=info&arg[]=$pkg`
  - Parse `.results[0].Version` with `jq -r`

**Step 2: Add a basic smoke check**

Run:
- `bash -n scripts/gen-manifest.sh`

Expected: no output, exit 0.

**Step 3: Manual run**

Run:
- `scripts/gen-manifest.sh | jq .`

Expected: valid JSON with the two repos.

**Step 4: Commit**

Run:
- `git add scripts/gen-manifest.sh`
- `git commit -m "feat: generate desired manifest"`

---

### Task 3: Add update-check script (compare to published Pages)

**Files:**
- Create: `scripts/check-updates.sh`

**Step 1: Implement `scripts/check-updates.sh`**

Inputs (env):
- `PAGES_BASE_URL` (optional). Default: `https://${GITHUB_REPOSITORY_OWNER}.github.io/${GITHUB_REPOSITORY#*/}`

Behavior:
- Fetch `${PAGES_BASE_URL}/manifest.json` (if 404 or missing → treat as empty).
- Compute desired manifest via `scripts/gen-manifest.sh`.
- Compare canonical JSON (`jq -S`) and decide:
  - `rebuild_required=true|false`
- If running in Actions (`GITHUB_OUTPUT` is set), append:
  - `rebuild_required=<value>` to `$GITHUB_OUTPUT`
- Always print a human-readable summary (which packages changed).

**Step 2: Local test (no published manifest)**

Run:
- `PAGES_BASE_URL="https://example.invalid" scripts/check-updates.sh`

Expected: indicates rebuild required (since manifest fetch fails).

**Step 3: Commit**

Run:
- `git add scripts/check-updates.sh`
- `git commit -m "feat: detect when repo rebuild is needed"`

---

### Task 4: Implement the rebuild script (build + stage `site/`)

**Files:**
- Create: `scripts/rebuild.sh`

**Step 1: Implement `scripts/rebuild.sh`**

Inputs (env):
- `SITE_DIR` default `site`
- `ARCH` default `x86_64`
- `CORE_REPO` default `access-os-core`
- `EXTRA_REPO` default `access-os-extra`

Behavior:
- Create a fresh staging tree:
  - `${SITE_DIR}/.nojekyll`
  - `${SITE_DIR}/${CORE_REPO}/os/${ARCH}/`
  - `${SITE_DIR}/${EXTRA_REPO}/os/${ARCH}/`
- Create build output directories (not under `site/`) to hold the package files for upload:
  - `dist/${CORE_REPO}/${ARCH}/`
  - `dist/${EXTRA_REPO}/${ARCH}/`
- Build core packages:
  - iterate `packages/core/*/PKGBUILD`
  - run `makepkg --syncdeps --noconfirm --clean --cleanbuild --needed`
  - set `PKGDEST` to `dist/${CORE_REPO}/${ARCH}/`
- Build AUR packages:
  - for each package in `package-lists/access-os-extra.txt`:
    - `git clone --depth 1 https://aur.archlinux.org/<pkg>.git`
    - `makepkg --syncdeps --noconfirm --clean --cleanbuild --needed`
    - set `PKGDEST` to `dist/${EXTRA_REPO}/${ARCH}/`
- Generate repo DBs with `repo-add`:
  - in each `dist/<repo>/<arch>/` dir: `repo-add -R "<repo>.db.tar.gz" ./*.pkg.tar.zst`
  - ensure **no symlinks** remain (Pages artifacts reject symlinks):
    - replace `<repo>.db` and `<repo>.files` symlinks with real files (copy the `*.tar.gz` payload)
    - copy `.db` / `.files` into `${SITE_DIR}/<repo>/os/<arch>/`
    - optionally remove `*.db.tar.gz` / `*.files.tar.gz` after copying to `.db`/`.files`
- Write `${SITE_DIR}/manifest.json` as the desired manifest (`scripts/gen-manifest.sh`).
- Write `${SITE_DIR}/BUILD_INFO.txt` with commit SHA + build timestamp (optional; not used for compare).

**Step 2: Add `--help` / `--dry-run` (optional but useful)**

If added, ensure `--dry-run` prints the build plan and exits without building.

**Step 3: Commit**

Run:
- `git add scripts/rebuild.sh`
- `git commit -m "feat: rebuild and stage pacman repos"`

---

### Task 5: Add GitHub Actions workflow (schedule + Pages deploy)

**Files:**
- Create: `.github/workflows/build-repos.yml`

**Step 1: Implement `.github/workflows/build-repos.yml`**

Requirements:
- Triggers:
  - `workflow_dispatch`
  - nightly `schedule`
  - `push` limited to relevant paths (`scripts/**`, `packages/**`, `package-lists/**`, `aur-and-custom-packages.md`)
- Permissions:
  - `contents: read`
  - `pages: write`
  - `id-token: write`
- Concurrency group for Pages.

Suggested structure (single job):
1. Checkout
2. Run `scripts/check-updates.sh` (sets `rebuild_required`)
3. If rebuild required:
   - Build inside Docker `archlinux:latest` so we have `pacman/makepkg/repo-add`
   - Example:
     - `docker run --rm -v "$GITHUB_WORKSPACE:/work" -w /work archlinux:latest bash -lc '<install deps; create builder; run scripts/rebuild.sh>'`
   - Upload packages to GitHub Releases:
     - create/update tags:
       - `${CORE_REPO}-${ARCH}`
       - `${EXTRA_REPO}-${ARCH}`
     - upload assets from:
       - `dist/${CORE_REPO}/${ARCH}/*.pkg.tar.zst`
       - `dist/${EXTRA_REPO}/${ARCH}/*.pkg.tar.zst`
     - use `gh release create` / `gh release upload --clobber` with `GH_TOKEN=${{ github.token }}`
4. Upload Pages artifact (`actions/upload-pages-artifact@v4`) from `site/`
5. Deploy (`actions/deploy-pages@v4`)

Key CI details in the container command:
- `pacman -Syu --noconfirm --needed base-devel git sudo curl jq pacman-contrib`
- create `builder` user and passwordless sudo for pacman:
  - `useradd -m builder`
  - `echo 'builder ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/builder`
  - `chown -R builder:builder /work`
- run rebuild as `builder`:
  - `sudo -u builder bash -lc './scripts/rebuild.sh'`

**Step 2: Verify YAML formatting**

Run:
- `python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/build-repos.yml')); print('ok')"`

Expected: `ok`

**Step 3: Commit**

Run:
- `git add .github/workflows/build-repos.yml`
- `git commit -m "ci: build and publish pacman repos to GitHub Pages"`

---

### Task 6: Wire Access OS ISO to consume the repos (follow-up in `../access-os`)

**Files:**
- Modify: `../access-os/iso/access-os/releng/pacman.conf` (in the other repo)

**Step 1: Add repo entries**

Uncomment/add:
```
[access-os-core]
SigLevel = Optional TrustAll
Server = https://<owner>.github.io/<repo>/$repo/os/$arch

[access-os-extra]
SigLevel = Optional TrustAll
Server = https://<owner>.github.io/<repo>/$repo/os/$arch
```

**Step 2: Validate `mkarchiso` still runs**

Run in `../access-os`:
- `./scripts/build-iso-distrobox.sh --dry-run`

Expected: prints build command, exits 0.

---

## Execution handoff
Plan complete and saved to `docs/plans/2026-03-05-access-os-package-repos.md`. Two execution options:

1. Subagent-Driven (this session) — I implement task-by-task with checkpoints.
2. Parallel Session (separate) — open a new session and execute the plan in a dedicated worktree.

Which approach?
