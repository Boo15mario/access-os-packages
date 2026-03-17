#!/usr/bin/env bash
set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
MIRROR_DIR="${MIRROR_DIR:-${REPO_ROOT}/aur-mirror}"
EXTRA_DIR="${EXTRA_DIR:-${REPO_ROOT}/packages/extra}"
LIST_FILE="${LIST_FILE:-${REPO_ROOT}/packages/extra.list}"

APPLY=0
INTERACTIVE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --interactive) INTERACTIVE=1 ;;
    -h|--help)
      cat <<'EOF'
Usage: compare-mirror.sh [--apply] [--interactive]

Compare saved packages/extra/ PKGBUILDs against the synced aur-mirror/.

Flags:
  --apply        Copy changed PKGBUILDs from mirror to packages/extra/
  --interactive  Show changes then prompt before applying (used by menu)
  -h, --help     Show this help
EOF
      exit 0
      ;;
    *) die "unknown argument: $1" ;;
  esac
  shift
done

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

# Collect packages that need updating into parallel arrays.
declare -a updates=() build_changes=() new_pkgs=() missing=()
# All packages that have actionable changes (for --apply).
declare -a actionable_pkgs=()

while IFS= read -r pkg; do
  mirror_dir="${MIRROR_DIR}/${pkg}"
  extra_dir="${EXTRA_DIR}/${pkg}"

  if [[ ! -d "${mirror_dir}" ]]; then
    missing+=("${pkg}")
    continue
  fi

  if [[ ! -f "${extra_dir}/PKGBUILD" ]]; then
    new_pkgs+=("${pkg}")
    actionable_pkgs+=("${pkg}")
    continue
  fi

  mirror_ver="$(version_from_srcinfo "${mirror_dir}/.SRCINFO" 2>/dev/null || echo "?")"
  extra_ver="$(version_from_srcinfo "${extra_dir}/.SRCINFO" 2>/dev/null || echo "?")"

  # For non-git packages: flag if the AUR version is different from our saved copy.
  if [[ "${pkg}" != *-git ]]; then
    if [[ "${mirror_ver}" != "${extra_ver}" ]]; then
      updates+=("${pkg}|${extra_ver}|${mirror_ver}")
      actionable_pkgs+=("${pkg}")
      continue
    fi
  fi

  # For all packages: check if PKGBUILD changed (ignoring pkgver for -git).
  mirror_norm="$(normalize_pkgbuild "${mirror_dir}/PKGBUILD" "${pkg}")"
  extra_norm="$(normalize_pkgbuild "${extra_dir}/PKGBUILD" "${pkg}")"
  if [[ "${mirror_norm}" != "${extra_norm}" ]]; then
    build_changes+=("${pkg}|${extra_ver}|${mirror_ver}")
    actionable_pkgs+=("${pkg}")
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
  exit 0
fi

echo "${total} package(s) may need a rebuild."

# ---------------------------------------------------------------------------
# Apply: copy updated PKGBUILDs from mirror to packages/extra/
# ---------------------------------------------------------------------------

apply_changes() {
  local pkg mirror_dir extra_dir
  for pkg in "${actionable_pkgs[@]}"; do
    mirror_dir="${MIRROR_DIR}/${pkg}"
    extra_dir="${EXTRA_DIR}/${pkg}"
    echo "  syncing ${pkg}"
    mkdir -p "${extra_dir}"
    rsync -a --delete \
      --exclude='.git' \
      --exclude='src/' \
      --exclude='pkg/' \
      --exclude='*.pkg.tar.*' \
      --exclude='*.src.tar.*' \
      --exclude='*.log' \
      "${mirror_dir}/" "${extra_dir}/"
  done
  echo ""
  echo "Updated ${#actionable_pkgs[@]} package(s) in packages/extra/."
  echo "Run a build to rebuild the changed packages."
}

if [[ "${APPLY}" -eq 1 ]]; then
  echo ""
  apply_changes
elif [[ "${INTERACTIVE}" -eq 1 ]]; then
  echo ""
  read -rp "Apply changes from mirror to packages/extra/? [y/N]: " answer
  case "${answer}" in
    y|Y|yes|YES)
      apply_changes
      ;;
    *)
      echo "No changes applied."
      ;;
  esac
fi
