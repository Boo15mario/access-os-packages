#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: promote-extra-package.sh <pkgname>

Promote a new access-os-extra package into packages/extra/.

Use this to add a package from the mirror or pkgbuild fallback into curated
packaging. For updating an already curated package from the mirror, use
refresh-extra-package.sh instead.

Source precedence:
  1. local AUR mirror in AUR_MIRROR_DIR/<pkg>/
  2. fallback snapshot in pkgbuilds/<pkg>/

Environment overrides:
  AUR_MIRROR_DIR   (default: ~/aur-mirror)
  PKGBUILDS_DIR    (default: pkgbuilds)
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/aur-packaging.sh"

PACKAGES_DIR="${PACKAGES_DIR:-${REPO_ROOT}/packages}"
PKGBUILDS_DIR="${PKGBUILDS_DIR:-${REPO_ROOT}/pkgbuilds}"
AUR_MIRROR_DIR="${AUR_MIRROR_DIR:-${HOME}/aur-mirror}"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

[[ $# -eq 1 ]] || die "expected exactly one package name"
pkg="$1"

mkdir -p "${PACKAGES_DIR}/extra"

src_dir=""
if aur_mirror_has_package "${pkg}"; then
  src_dir="$(aur_local_mirror_pkg_dir "${pkg}")"
elif [[ -d "$(aur_pkgbuild_snapshot_dir "${pkg}")" && -f "$(aur_pkgbuild_snapshot_dir "${pkg}")/PKGBUILD" ]]; then
  src_dir="$(aur_pkgbuild_snapshot_dir "${pkg}")"
else
  die "${pkg} is missing from both $(aur_local_mirror_pkg_dir "${pkg}") and $(aur_pkgbuild_snapshot_dir "${pkg}")"
fi

dst_dir="$(aur_curated_extra_dir "${pkg}")"
echo "Promoting ${pkg} from ${src_dir} to ${dst_dir}"
copy_packaging_snapshot "${src_dir}" "${dst_dir}"
