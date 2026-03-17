#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: refresh-extra-package.sh [--apply] <pkgname>

Review or apply upstream mirror changes for one curated packages/extra package.

Default mode is read-only review.

Flags:
  --apply    Replace the curated package with the normalized mirror snapshot
  -h, --help Show this help

Environment overrides:
  AUR_MIRROR_DIR   (default: ~/aur-mirror)
  PACKAGES_DIR     (default: packages)
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/aur-packaging.sh"

PACKAGES_DIR="${PACKAGES_DIR:-${REPO_ROOT}/packages}"
AUR_MIRROR_DIR="${AUR_MIRROR_DIR:-${HOME}/aur-mirror}"

APPLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      die "unknown argument: $1"
      ;;
    *)
      break
      ;;
  esac
  shift
done

[[ $# -eq 1 ]] || die "expected exactly one package name"
pkg="$1"

curated_dir="$(aur_curated_extra_dir "${pkg}")"
mirror_dir="$(aur_local_mirror_pkg_dir "${pkg}")"

if [[ ! -d "${curated_dir}" || ! -f "${curated_dir}/PKGBUILD" ]]; then
  die "curated package is missing: ${curated_dir}"
fi

if [[ ! -d "${mirror_dir}" || ! -f "${mirror_dir}/PKGBUILD" ]]; then
  die "mirror package is missing: ${mirror_dir}"
fi

mkdir -p "${REPO_ROOT}/work"
curated_tmp="$(aur_prepare_normalized_snapshot "${curated_dir}" "${REPO_ROOT}/work" "refresh-curated.${pkg}")"
mirror_tmp="$(aur_prepare_normalized_snapshot "${mirror_dir}" "${REPO_ROOT}/work" "refresh-mirror.${pkg}")"
cleanup() {
  rm -rf -- "${curated_tmp}" "${mirror_tmp}"
}
trap cleanup EXIT

if diff -qr "${curated_tmp}" "${mirror_tmp}" >/dev/null 2>&1; then
  echo "${pkg}: up-to-date"
  exit 0
fi

if [[ "${APPLY}" -eq 0 ]]; then
  echo "${pkg}: changed"
  diff -ru --label "packages/extra/${pkg}" --label "aur-mirror/${pkg}" "${curated_tmp}" "${mirror_tmp}" || true
  exit 0
fi

echo "${pkg}: applying mirror snapshot to curated package"
copy_packaging_snapshot "${mirror_dir}" "${curated_dir}"
