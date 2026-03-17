#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: sync-aur-mirror.sh

Clone or update local AUR package mirrors for access-os-extra.

Environment overrides:
  AUR_MIRROR_DIR   (default: ~/aur-mirror)
  EXTRA_LIST_FILE  (default: package-lists/access-os-extra.txt)
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/aur-packaging.sh"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

EXTRA_LIST_FILE="${EXTRA_LIST_FILE:-${REPO_ROOT}/package-lists/access-os-extra.txt}"
AUR_MIRROR_DIR="$(aur_resolve_mirror_dir)"

aur_require_cmd git

mkdir -p "${AUR_MIRROR_DIR}"

mapfile -t packages < <(aur_read_extra_packages_file "${EXTRA_LIST_FILE}")
[[ "${#packages[@]}" -gt 0 ]] || die "no packages found in ${EXTRA_LIST_FILE}"

for pkg in "${packages[@]}"; do
  pkg_dir="${AUR_MIRROR_DIR}/${pkg}"
  remote_url="https://aur.archlinux.org/${pkg}.git"

  if [[ ! -d "${pkg_dir}/.git" ]]; then
    echo "Cloning ${pkg} into ${pkg_dir}"
    git clone --origin origin "${remote_url}" "${pkg_dir}"
    continue
  fi

  echo "Updating ${pkg} in ${pkg_dir}"
  git -C "${pkg_dir}" remote set-url origin "${remote_url}"
  git -C "${pkg_dir}" fetch --prune origin
  current_branch="$(git -C "${pkg_dir}" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -z "${current_branch}" ]]; then
    current_branch="$(git -C "${pkg_dir}" remote show origin | awk '/HEAD branch/ {print $NF; exit}')"
    [[ -n "${current_branch}" ]] || current_branch="master"
    git -C "${pkg_dir}" checkout -B "${current_branch}" "origin/${current_branch}"
  fi
  git -C "${pkg_dir}" reset --hard "origin/${current_branch}"
  git -C "${pkg_dir}" clean -fdx
done
