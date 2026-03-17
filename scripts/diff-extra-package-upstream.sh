#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: diff-extra-package-upstream.sh <pkgname>

Diff a curated packages/extra/<pkg>/ package against the local AUR mirror copy.

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

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ $# -eq 1 ]] || die "expected exactly one package name"
pkg="$1"

curated_dir="$(aur_curated_extra_dir "${pkg}")"
mirror_dir="$(aur_local_mirror_pkg_dir "${pkg}")"

[[ -d "${curated_dir}" && -f "${curated_dir}/PKGBUILD" ]] || die "curated package is missing: ${curated_dir}"
[[ -d "${mirror_dir}" && -f "${mirror_dir}/PKGBUILD" ]] || die "mirror package is missing: ${mirror_dir}"

mkdir -p "${REPO_ROOT}/work"
curated_tmp="$(mktemp -d "${REPO_ROOT%/}/work/diff-curated.${pkg}.XXXXXXXX")"
mirror_tmp="$(mktemp -d "${REPO_ROOT%/}/work/diff-mirror.${pkg}.XXXXXXXX")"
cleanup() {
  rm -rf -- "${curated_tmp}" "${mirror_tmp}"
}
trap cleanup EXIT

copy_packaging_snapshot "${curated_dir}" "${curated_tmp}"
copy_packaging_snapshot "${mirror_dir}" "${mirror_tmp}"

echo "Diffing curated package against mirror for ${pkg}"
diff -ru --label "packages/extra/${pkg}" --label "aur-mirror/${pkg}" "${curated_tmp}" "${mirror_tmp}" || true
