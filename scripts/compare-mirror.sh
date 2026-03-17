#!/usr/bin/env bash
set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
MIRROR_DIR="${MIRROR_DIR:-${REPO_ROOT}/aur-mirror}"
EXTRA_DIR="${EXTRA_DIR:-${REPO_ROOT}/packages/extra}"
LIST_FILE="${LIST_FILE:-${REPO_ROOT}/packages/extra.list}"

[[ -d "${MIRROR_DIR}" ]] || die "mirror directory not found: ${MIRROR_DIR} (run option 5 first)"
[[ -f "${LIST_FILE}" ]] || die "package list not found: ${LIST_FILE}"

read_list() {
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "${line}" ]] && printf '%s\n' "${line}"
  done <"${LIST_FILE}"
}

version_from_srcinfo() {
  local srcinfo="$1"
  local epoch pkgver pkgrel
  [[ -f "${srcinfo}" ]] || return 1
  epoch="$(awk -F' = ' '/^\t*epoch/{print $2; exit}' "${srcinfo}" || true)"
  pkgver="$(awk -F' = ' '/^\t*pkgver/{print $2; exit}' "${srcinfo}")"
  pkgrel="$(awk -F' = ' '/^\t*pkgrel/{print $2; exit}' "${srcinfo}")"
  [[ -n "${pkgver}" ]] || return 1
  if [[ -n "${epoch}" && "${epoch}" != "0" ]]; then
    printf '%s:%s-%s\n' "${epoch}" "${pkgver}" "${pkgrel}"
  else
    printf '%s-%s\n' "${pkgver}" "${pkgrel}"
  fi
}

# Strip pkgver= line for -git package comparison (pkgver changes at build time).
normalize_pkgbuild() {
  local file="$1" pkg="$2"
  if [[ "${pkg}" == *-git ]]; then
    sed '/^pkgver=/d' "${file}"
  else
    cat "${file}"
  fi
}

declare -a updates=() build_changes=() new_pkgs=() missing=()

while IFS= read -r pkg; do
  mirror_dir="${MIRROR_DIR}/${pkg}"
  extra_dir="${EXTRA_DIR}/${pkg}"

  if [[ ! -d "${mirror_dir}" ]]; then
    missing+=("${pkg}")
    continue
  fi

  if [[ ! -f "${extra_dir}/PKGBUILD" ]]; then
    new_pkgs+=("${pkg}")
    continue
  fi

  mirror_ver="$(version_from_srcinfo "${mirror_dir}/.SRCINFO" 2>/dev/null || echo "?")"
  extra_ver="$(version_from_srcinfo "${extra_dir}/.SRCINFO" 2>/dev/null || echo "?")"

  # For non-git packages: flag if the AUR version is different from our saved copy.
  if [[ "${pkg}" != *-git ]]; then
    if [[ "${mirror_ver}" != "${extra_ver}" ]]; then
      updates+=("${pkg}|${extra_ver}|${mirror_ver}")
      continue
    fi
  fi

  # For all packages: check if PKGBUILD changed (ignoring pkgver for -git).
  mirror_norm="$(normalize_pkgbuild "${mirror_dir}/PKGBUILD" "${pkg}")"
  extra_norm="$(normalize_pkgbuild "${extra_dir}/PKGBUILD" "${pkg}")"
  if [[ "${mirror_norm}" != "${extra_norm}" ]]; then
    build_changes+=("${pkg}|${extra_ver}|${mirror_ver}")
  fi
done < <(read_list)

# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

total=0

if [[ "${#updates[@]}" -gt 0 ]]; then
  echo "Version updates (${#updates[@]}):"
  for entry in "${updates[@]}"; do
    IFS='|' read -r pkg old new <<<"${entry}"
    echo "  ${pkg}  ${old} -> ${new}"
  done
  echo ""
  total=$(( total + ${#updates[@]} ))
fi

if [[ "${#build_changes[@]}" -gt 0 ]]; then
  echo "PKGBUILD changes (same version) (${#build_changes[@]}):"
  for entry in "${build_changes[@]}"; do
    IFS='|' read -r pkg old new <<<"${entry}"
    echo "  ${pkg}  (${old})"
  done
  echo ""
  total=$(( total + ${#build_changes[@]} ))
fi

if [[ "${#new_pkgs[@]}" -gt 0 ]]; then
  echo "New packages (no saved copy) (${#new_pkgs[@]}):"
  for pkg in "${new_pkgs[@]}"; do
    echo "  ${pkg}"
  done
  echo ""
  total=$(( total + ${#new_pkgs[@]} ))
fi

if [[ "${#missing[@]}" -gt 0 ]]; then
  echo "Not in mirror (${#missing[@]}):"
  for pkg in "${missing[@]}"; do
    echo "  ${pkg}"
  done
  echo ""
fi

if [[ "${total}" -eq 0 ]]; then
  echo "All packages are in sync with the AUR mirror."
else
  echo "${total} package(s) may need a rebuild."
fi
