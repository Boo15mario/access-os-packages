#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/aur-packaging.sh"

CORE_REPO="${CORE_REPO:-access-os-core}"
EXTRA_REPO="${EXTRA_REPO:-access-os-extra}"
EXTRA_LIST_FILE="${EXTRA_LIST_FILE:-${REPO_ROOT}/package-lists/access-os-extra.txt}"
PKGBUILDS_DIR="${PKGBUILDS_DIR:-${REPO_ROOT}/pkgbuilds}"
AUR_MIRROR_DIR="${AUR_MIRROR_DIR:-${HOME}/aur-mirror}"

require_cmd jq
aur_require_cmd jq

core_packages_json='{}'
extra_packages_json='{}'
aur_missing=()

srcinfo_from_dir() {
  local pkg_dir="$1"

  if [[ -f "${pkg_dir}/.SRCINFO" ]]; then
    cat "${pkg_dir}/.SRCINFO"
    return 0
  fi

  if command -v makepkg >/dev/null 2>&1; then
    (cd "${pkg_dir}" && makepkg --printsrcinfo)
    return 0
  fi

  die "core package at ${pkg_dir} is missing .SRCINFO and makepkg is not available (run in Arch env or add .SRCINFO)"
}

add_srcinfo_packages() {
  local -n repo_json="$1"
  local srcinfo_text="$2"

  local epoch pkgver pkgrel version
  epoch="$(awk -F' = ' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)} $1=="epoch"{print $2; exit}' <<<"${srcinfo_text}" || true)"
  pkgver="$(awk -F' = ' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)} $1=="pkgver"{print $2; exit}' <<<"${srcinfo_text}")"
  pkgrel="$(awk -F' = ' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)} $1=="pkgrel"{print $2; exit}' <<<"${srcinfo_text}")"

  if [[ -z "${pkgver}" || -z "${pkgrel}" ]]; then
    die "failed to parse pkgver/pkgrel from .SRCINFO"
  fi

  if [[ -n "${epoch}" && "${epoch}" != "0" ]]; then
    version="${epoch}:${pkgver}-${pkgrel}"
  else
    version="${pkgver}-${pkgrel}"
  fi

  local -a pkgnames=()
  mapfile -t pkgnames < <(awk -F' = ' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)} $1=="pkgname"{print $2}' <<<"${srcinfo_text}" | sort -u)
  if [[ "${#pkgnames[@]}" -eq 0 ]]; then
    die "failed to parse pkgname entries from .SRCINFO"
  fi

  local json="${repo_json}"
  for pkgname in "${pkgnames[@]}"; do
    json="$(jq -c --arg name "${pkgname}" --arg ver "${version}" '. + {($name): $ver}' <<<"${json}")"
  done

  repo_json="${json}"
}

# access-os-core (local PKGBUILDs)
if [[ -d "${REPO_ROOT}/packages/core" ]]; then
  while IFS= read -r -d '' pkgbuild; do
    pkg_dir="$(cd -- "$(dirname -- "${pkgbuild}")" && pwd)"
    srcinfo="$(srcinfo_from_dir "${pkg_dir}")"
    add_srcinfo_packages core_packages_json "${srcinfo}"
  done < <(find "${REPO_ROOT}/packages/core" -mindepth 2 -maxdepth 2 -type f -name PKGBUILD -print0 | sort -z)
fi

# access-os-extra (local mirror first, pkgbuild snapshots second)
mapfile -t extra_packages < <(aur_read_extra_packages_file "${EXTRA_LIST_FILE}")
for pkg in "${extra_packages[@]}"; do
  if ! pkg_source_dir="$(aur_resolve_package_source_dir "${pkg}")"; then
    aur_missing+=("${pkg}")
    continue
  fi

  pkgbuild_srcinfo="$(srcinfo_from_dir "${pkg_source_dir}")"
  add_srcinfo_packages extra_packages_json "${pkgbuild_srcinfo}"
done

if [[ "${#aur_missing[@]}" -gt 0 ]]; then
  {
    echo "Error: package source(s) not found in the local mirror or pkgbuild snapshots:"
    printf '  - %s\n' "${aur_missing[@]}"
    echo "Hint: run ./scripts/sync-aur-mirror.sh and ./scripts/import-aur-snapshots.sh"
  } >&2
  exit 1
fi

jq -n \
  --argjson core "${core_packages_json}" \
  --argjson extra "${extra_packages_json}" \
  --arg core_repo "${CORE_REPO}" \
  --arg extra_repo "${EXTRA_REPO}" \
  '{
    version: 1,
    repos: {
      ($core_repo): { packages: $core },
      ($extra_repo): { packages: $extra }
    }
  }' | jq -S .
