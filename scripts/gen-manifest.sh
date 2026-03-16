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

AUR_BATCH_SIZE="${AUR_BATCH_SIZE:-50}"

core_packages_json='{}'
extra_packages_json='{}'
aur_missing=()
aur_query_failed=()

read_extra_packages() {
  [[ -f "${EXTRA_LIST_FILE}" ]] || return 0

  while IFS= read -r line; do
    pkg="${line%%#*}"
    pkg="${pkg#"${pkg%%[![:space:]]*}"}"
    pkg="${pkg%"${pkg##*[![:space:]]}"}"
    [[ -z "${pkg}" ]] && continue
    printf '%s\n' "${pkg}"
  done <"${EXTRA_LIST_FILE}"
}

fetch_aur_info_batches() {
  local -a pkgs=("$@")
  local total index end pkg aur_json
  local combined='{}'

  total="${#pkgs[@]}"
  index=0

  while [[ "${index}" -lt "${total}" ]]; do
    end=$(( index + AUR_BATCH_SIZE ))
    if [[ "${end}" -gt "${total}" ]]; then
      end="${total}"
    fi

    local -a curl_args=(
      -fsSLG
      --retry 3
      --retry-all-errors
      --connect-timeout 10
      --max-time 30
      --data-urlencode "v=5"
      --data-urlencode "type=info"
    )

    for pkg in "${pkgs[@]:index:end-index}"; do
      curl_args+=(--data-urlencode "arg[]=${pkg}")
    done

    aur_json="$(curl "${curl_args[@]}" "https://aur.archlinux.org/rpc/" || true)"
    if [[ -z "${aur_json}" ]]; then
      printf '%s\n' "${pkgs[@]:index:end-index}"
      return 1
    fi

    combined="$(
      jq -c \
        --argjson old "${combined}" \
        --argjson batch "${aur_json}" \
        '
        $old + (
          ($batch.results // [])
          | map({(.Name): .Version})
          | add // {}
        )
        '
    )"

    index="${end}"
  done

  jq -S . <<<"${combined}"
}

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
mapfile -t extra_packages < <(read_extra_packages)
aur_versions='{}'
if [[ "${#extra_packages[@]}" -gt 0 ]]; then
  set +e
  aur_versions="$(fetch_aur_info_batches "${extra_packages[@]}")"
  aur_fetch_rc="$?"
  set -e
  if [[ "${aur_fetch_rc}" -ne 0 ]]; then
    mapfile -t aur_query_failed < <(printf '%s\n' "${aur_versions}")
  fi
fi

if [[ "${#extra_packages[@]}" -gt 0 && "${#aur_query_failed[@]}" -eq 0 ]]; then
  for pkg in "${extra_packages[@]}"; do
    ver="$(jq -r --arg pkg "${pkg}" '.[$pkg] // empty' <<<"${aur_versions}")"
    if [[ -z "${ver}" || "${ver}" == "null" ]]; then
      local_pkgbuild_dir="${REPO_ROOT}/pkgbuilds/${pkg}"
      if [[ -d "${local_pkgbuild_dir}" && -f "${local_pkgbuild_dir}/PKGBUILD" ]]; then
        echo "Warning: ${pkg} is unavailable from AUR; falling back to saved snapshot in pkgbuilds/${pkg}" >&2
        pkgbuild_srcinfo="$(srcinfo_from_dir "${local_pkgbuild_dir}")"
        add_srcinfo_packages extra_packages_json "${pkgbuild_srcinfo}"
      else
        aur_missing+=("${pkg}")
      fi
      continue
    fi

    extra_packages_json="$(jq -c --arg name "${pkg}" --arg ver "${ver}" '. + {($name): $ver}' <<<"${extra_packages_json}")"
  done
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
    echo "Error: AUR package(s) not found and no saved fallback is available:"
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
