#!/usr/bin/env bash
set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
CORE_DIR="${REPO_ROOT}/packages/core"

[[ -d "${CORE_DIR}" ]] || die "no packages/core/ directory"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_cmd curl
require_cmd jq
require_cmd makepkg

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" || "${1:-}" == "-n" ]]; then
  DRY_RUN=1
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'EOF'
Usage: update-core-packages.sh [--dry-run]

Check each core package for upstream updates on GitHub.
Compares the version in the upstream Cargo.toml against the local PKGBUILD.
If a new version is found, updates pkgver, _commit, pkgrel, and .SRCINFO.

  --dry-run, -n   Show what would change without modifying files
EOF
  exit 0
fi

updated=0
checked=0

for pkg_dir in "${CORE_DIR}"/*/; do
  [[ -f "${pkg_dir}/PKGBUILD" ]] || continue
  pkg_name="$(basename "${pkg_dir}")"

  # Extract GitHub URL and current version from PKGBUILD
  pkg_url="$(sed -n "s/^url='\(.*\)'/\1/p" "${pkg_dir}/PKGBUILD")"
  [[ "${pkg_url}" == https://github.com/* ]] || continue

  current_ver="$(sed -n 's/^pkgver=//p' "${pkg_dir}/PKGBUILD")"
  current_commit="$(sed -n "s/^_commit='\(.*\)'/\1/p" "${pkg_dir}/PKGBUILD")"
  [[ -n "${current_ver}" && -n "${current_commit}" ]] || continue

  # Parse owner/repo from URL
  gh_repo="${pkg_url#https://github.com/}"
  gh_repo="${gh_repo%.git}"

  checked=$((checked + 1))
  echo "Checking ${pkg_name} (current: ${current_ver})..."

  # Get latest commit on default branch
  latest_commit="$(curl -fsSL "https://api.github.com/repos/${gh_repo}/commits/main" 2>/dev/null | jq -r '.sha // empty')" || true
  if [[ -z "${latest_commit}" ]]; then
    echo "  Warning: could not fetch latest commit for ${gh_repo}" >&2
    continue
  fi

  if [[ "${latest_commit}" == "${current_commit}" ]]; then
    echo "  up to date (commit ${current_commit:0:8})"
    continue
  fi

  # Fetch upstream Cargo.toml to get new version
  upstream_ver="$(curl -fsSL "https://raw.githubusercontent.com/${gh_repo}/${latest_commit}/Cargo.toml" 2>/dev/null \
    | sed -n 's/^version = "\(.*\)"/\1/p' | head -1)" || true
  if [[ -z "${upstream_ver}" ]]; then
    echo "  Warning: could not parse version from upstream Cargo.toml" >&2
    continue
  fi

  if [[ "${upstream_ver}" == "${current_ver}" ]]; then
    # Same version but different commit — bump pkgrel
    current_pkgrel="$(sed -n 's/^pkgrel=//p' "${pkg_dir}/PKGBUILD")"
    new_pkgrel=$((current_pkgrel + 1))
    echo "  new commit ${latest_commit:0:8} (same version ${upstream_ver}, pkgrel ${current_pkgrel} -> ${new_pkgrel})"

    if [[ "${DRY_RUN}" == "1" ]]; then
      updated=$((updated + 1))
      continue
    fi

    sed -i "s/^_commit='.*'/_commit='${latest_commit}'/" "${pkg_dir}/PKGBUILD"
    sed -i "s/^pkgrel=.*/pkgrel=${new_pkgrel}/" "${pkg_dir}/PKGBUILD"
  else
    echo "  new version ${current_ver} -> ${upstream_ver} (commit ${latest_commit:0:8})"

    if [[ "${DRY_RUN}" == "1" ]]; then
      updated=$((updated + 1))
      continue
    fi

    sed -i "s/^pkgver=.*/pkgver=${upstream_ver}/" "${pkg_dir}/PKGBUILD"
    sed -i "s/^_commit='.*'/_commit='${latest_commit}'/" "${pkg_dir}/PKGBUILD"
    sed -i "s/^pkgrel=.*/pkgrel=1/" "${pkg_dir}/PKGBUILD"
  fi

  # Regenerate .SRCINFO
  (cd "${pkg_dir}" && makepkg --printsrcinfo > .SRCINFO)
  updated=$((updated + 1))
  echo "  updated PKGBUILD and .SRCINFO"
done

echo ""
echo "Checked ${checked} package(s), ${updated} updated."
if [[ "${updated}" -gt 0 && "${DRY_RUN}" == "0" ]]; then
  echo "Run ./scripts/publish.sh to build and publish."
elif [[ "${updated}" -gt 0 && "${DRY_RUN}" == "1" ]]; then
  echo "(dry run — no files changed)"
fi
