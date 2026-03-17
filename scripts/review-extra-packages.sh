#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: review-extra-packages.sh [--diff] [--uncurated]

Review curated extra packages against the local AUR mirror.

Flags:
  --diff       Print full diffs for changed curated packages
  --uncurated  Report transition-list packages that are not yet curated
  -h, --help   Show this help

Environment overrides:
  AUR_MIRROR_DIR   (default: ~/aur-mirror)
  PACKAGES_DIR     (default: packages)
  PKGBUILDS_DIR    (default: pkgbuilds)
  EXTRA_LIST_FILE  (default: package-lists/access-os-extra.txt)
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/aur-packaging.sh"

PACKAGES_DIR="${PACKAGES_DIR:-${REPO_ROOT}/packages}"
PKGBUILDS_DIR="${PKGBUILDS_DIR:-${REPO_ROOT}/pkgbuilds}"
EXTRA_LIST_FILE="${EXTRA_LIST_FILE:-${REPO_ROOT}/package-lists/access-os-extra.txt}"
AUR_MIRROR_DIR="${AUR_MIRROR_DIR:-${HOME}/aur-mirror}"

SHOW_DIFF=0
SHOW_UNCURATED=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --diff) SHOW_DIFF=1 ;;
    --uncurated) SHOW_UNCURATED=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

if [[ "${SHOW_DIFF}" -eq 1 && "${SHOW_UNCURATED}" -eq 1 ]]; then
  die "--diff cannot be combined with --uncurated"
fi

mkdir -p "${REPO_ROOT}/work"

report_curated() {
  local pkg curated_dir mirror_dir curated_tmp mirror_tmp
  local -a changed_pkgs=()

  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] || continue
    curated_dir="$(aur_curated_extra_dir "${pkg}")"
    mirror_dir="$(aur_local_mirror_pkg_dir "${pkg}")"

    if [[ ! -d "${mirror_dir}" || ! -f "${mirror_dir}/PKGBUILD" ]]; then
      echo "${pkg}: missing-from-mirror"
      continue
    fi

    curated_tmp="$(aur_prepare_normalized_snapshot "${curated_dir}" "${REPO_ROOT}/work" "review-curated.${pkg}")"
    mirror_tmp="$(aur_prepare_normalized_snapshot "${mirror_dir}" "${REPO_ROOT}/work" "review-mirror.${pkg}")"

    if diff -qr "${curated_tmp}" "${mirror_tmp}" >/dev/null 2>&1; then
      echo "${pkg}: up-to-date"
    else
      echo "${pkg}: changed"
      changed_pkgs+=("${pkg}")
    fi

    rm -rf -- "${curated_tmp}" "${mirror_tmp}"
  done < <(aur_list_curated_extra_packages)

  if [[ "${SHOW_DIFF}" -eq 1 && "${#changed_pkgs[@]}" -gt 0 ]]; then
    local changed_pkg
    for changed_pkg in "${changed_pkgs[@]}"; do
      echo
      "${REPO_ROOT}/scripts/diff-extra-package-upstream.sh" "${changed_pkg}"
    done
  fi
}

report_uncurated() {
  local pkg state
  while IFS= read -r pkg; do
    [[ -n "${pkg}" ]] || continue
    if aur_curated_extra_has_package "${pkg}"; then
      continue
    fi

    if aur_mirror_has_package "${pkg}" && [[ -d "$(aur_pkgbuild_snapshot_dir "${pkg}")" && -f "$(aur_pkgbuild_snapshot_dir "${pkg}")/PKGBUILD" ]]; then
      state="mirror+pkgbuilds"
    elif aur_mirror_has_package "${pkg}"; then
      state="mirror-only"
    elif [[ -d "$(aur_pkgbuild_snapshot_dir "${pkg}")" && -f "$(aur_pkgbuild_snapshot_dir "${pkg}")/PKGBUILD" ]]; then
      state="pkgbuilds-only"
    else
      state="missing"
    fi

    echo "${pkg}: ${state}"
  done < <(aur_read_extra_packages_file "${EXTRA_LIST_FILE}")
}

if [[ "${SHOW_UNCURATED}" -eq 1 ]]; then
  report_uncurated
else
  report_curated
fi
