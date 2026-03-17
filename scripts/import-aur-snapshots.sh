#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: import-aur-snapshots.sh

Import packaging-only snapshots from the local AUR mirror into pkgbuilds/.

Environment overrides:
  AUR_MIRROR_DIR   (default: ~/aur-mirror)
  EXTRA_LIST_FILE  (default: package-lists/access-os-extra.txt)
  PKGBUILDS_DIR    (default: pkgbuilds)
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
PKGBUILDS_DIR="${PKGBUILDS_DIR:-${REPO_ROOT}/pkgbuilds}"
AUR_MIRROR_DIR="$(aur_resolve_mirror_dir)"

mkdir -p "${PKGBUILDS_DIR}"
mkdir -p "${REPO_ROOT}/work"

mapfile -t packages < <(aur_read_extra_packages_file "${EXTRA_LIST_FILE}")
[[ "${#packages[@]}" -gt 0 ]] || die "no packages found in ${EXTRA_LIST_FILE}"

for pkg in "${packages[@]}"; do
  src_dir="${AUR_MIRROR_DIR}/${pkg}"
  dst_dir="${PKGBUILDS_DIR}/${pkg}"

  if [[ ! -d "${src_dir}" || ! -f "${src_dir}/PKGBUILD" ]]; then
    die "mirror entry is missing for ${pkg}: ${src_dir}"
  fi

  tmp_dir="$(mktemp -d "${REPO_ROOT%/}/work/import.${pkg}.XXXXXXXX")"
  copy_packaging_snapshot "${src_dir}" "${tmp_dir}"

  if [[ -d "${dst_dir}" ]] && diff -qr "${tmp_dir}" "${dst_dir}" >/dev/null 2>&1; then
    echo "Unchanged ${pkg}"
    rm -rf -- "${tmp_dir}"
    continue
  fi

  echo "Importing ${pkg} -> ${dst_dir}"
  rm -rf -- "${dst_dir}"
  mkdir -p -- "$(dirname -- "${dst_dir}")"
  mv -- "${tmp_dir}" "${dst_dir}"
done
