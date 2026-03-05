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

CORE_REPO="${CORE_REPO:-access-os-core}"
EXTRA_REPO="${EXTRA_REPO:-access-os-extra}"
EXTRA_LIST_FILE="${EXTRA_LIST_FILE:-${REPO_ROOT}/package-lists/access-os-extra.txt}"

require_cmd jq
require_cmd curl

core_packages_json='{}'
extra_packages_json='{}'
aur_missing=()
aur_query_failed=()

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
  epoch="$(awk -F' = ' '$1=="epoch"{print $2; exit}' <<<"${srcinfo_text}" || true)"
  pkgver="$(awk -F' = ' '$1=="pkgver"{print $2; exit}' <<<"${srcinfo_text}")"
  pkgrel="$(awk -F' = ' '$1=="pkgrel"{print $2; exit}' <<<"${srcinfo_text}")"

  if [[ -z "${pkgver}" || -z "${pkgrel}" ]]; then
    die "failed to parse pkgver/pkgrel from .SRCINFO"
  fi

  if [[ -n "${epoch}" && "${epoch}" != "0" ]]; then
    version="${epoch}:${pkgver}-${pkgrel}"
  else
    version="${pkgver}-${pkgrel}"
  fi

  local -a pkgnames=()
  mapfile -t pkgnames < <(awk -F' = ' '$1=="pkgname"{print $2}' <<<"${srcinfo_text}" | sort -u)
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

# access-os-extra (AUR)
if [[ -f "${EXTRA_LIST_FILE}" ]]; then
  while IFS= read -r line; do
    pkg="${line%%#*}"
    pkg="${pkg#"${pkg%%[![:space:]]*}"}"
    pkg="${pkg%"${pkg##*[![:space:]]}"}"
    [[ -z "${pkg}" ]] && continue

    aur_json="$(
      curl -fsSLG \
        --retry 3 \
        --retry-all-errors \
        --connect-timeout 10 \
        --max-time 30 \
        --data-urlencode "v=5" \
        --data-urlencode "type=info" \
        --data-urlencode "arg[]=${pkg}" \
        "https://aur.archlinux.org/rpc/" || true
    )"
    if [[ -z "${aur_json}" ]]; then
      aur_query_failed+=("${pkg}")
      continue
    fi

    ver="$(jq -r '.results[0].Version // empty' <<<"${aur_json}")"
    if [[ -z "${ver}" || "${ver}" == "null" ]]; then
      aur_missing+=("${pkg}")
      continue
    fi

    extra_packages_json="$(jq -c --arg name "${pkg}" --arg ver "${ver}" '. + {($name): $ver}' <<<"${extra_packages_json}")"
  done <"${EXTRA_LIST_FILE}"
fi

if [[ "${#aur_query_failed[@]}" -gt 0 ]]; then
  {
    echo "Error: failed to query AUR for:"
    printf '  - %s\n' "${aur_query_failed[@]}"
  } >&2
  exit 1
fi

if [[ "${#aur_missing[@]}" -gt 0 ]]; then
  {
    echo "Error: AUR package(s) not found or missing version:"
    printf '  - %s\n' "${aur_missing[@]}"
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
