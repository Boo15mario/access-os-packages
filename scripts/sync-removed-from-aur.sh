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

EXTRA_LIST_FILE="${EXTRA_LIST_FILE:-${REPO_ROOT}/package-lists/access-os-extra.txt}"
PKGBUILDS_DIR="${PKGBUILDS_DIR:-${REPO_ROOT}/pkgbuilds}"
REMOVED_AUR_JSON="${REMOVED_AUR_JSON:-${REPO_ROOT}/metadata/removed-from-aur.json}"
REMOVED_AUR_TXT="${REMOVED_AUR_TXT:-${REPO_ROOT}/metadata/removed-from-aur.txt}"
AUR_RPC_URL="${AUR_RPC_URL:-https://aur.archlinux.org/rpc/}"

require_cmd jq
require_cmd curl

AUR_BATCH_SIZE="${AUR_BATCH_SIZE:-50}"

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

  die "fallback package at ${pkg_dir} is missing .SRCINFO and makepkg is not available"
}

version_from_srcinfo() {
  local srcinfo_text="$1"
  local epoch pkgver pkgrel

  epoch="$(awk -F' = ' '$1=="epoch"{print $2; exit}' <<<"${srcinfo_text}" || true)"
  pkgver="$(awk -F' = ' '$1=="pkgver"{print $2; exit}' <<<"${srcinfo_text}")"
  pkgrel="$(awk -F' = ' '$1=="pkgrel"{print $2; exit}' <<<"${srcinfo_text}")"

  if [[ -z "${pkgver}" || -z "${pkgrel}" ]]; then
    die "failed to parse pkgver/pkgrel from .SRCINFO"
  fi

  if [[ -n "${epoch}" && "${epoch}" != "0" ]]; then
    printf '%s:%s-%s\n' "${epoch}" "${pkgver}" "${pkgrel}"
  else
    printf '%s-%s\n' "${pkgver}" "${pkgrel}"
  fi
}

mkdir -p "$(dirname -- "${REMOVED_AUR_JSON}")" "$(dirname -- "${REMOVED_AUR_TXT}")"

if [[ -f "${REMOVED_AUR_JSON}" ]]; then
  existing_json="$(jq -c '.' "${REMOVED_AUR_JSON}")"
else
  existing_json='[]'
fi

new_json='[]'
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

    aur_json="$(curl "${curl_args[@]}" "${AUR_RPC_URL}" || true)"
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
    if [[ -n "${ver}" && "${ver}" != "null" ]]; then
      continue
    fi

    local_pkgbuild_dir="${PKGBUILDS_DIR}/${pkg}"
    if [[ ! -d "${local_pkgbuild_dir}" || ! -f "${local_pkgbuild_dir}/PKGBUILD" ]]; then
      aur_missing+=("${pkg}")
      continue
    fi

    pkgbuild_srcinfo="$(srcinfo_from_dir "${local_pkgbuild_dir}")"
    last_known_version="$(version_from_srcinfo "${pkgbuild_srcinfo}")"
    detected_at="$(
      jq -r --arg pkg "${pkg}" '
        map(select(.package == $pkg))[0].detected_at // empty
      ' <<<"${existing_json}"
    )"
    if [[ -z "${detected_at}" ]]; then
      detected_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    fi

    entry="$(
      jq -cn \
        --arg package "${pkg}" \
        --arg detected_at "${detected_at}" \
        --arg fallback_path "pkgbuilds/${pkg}" \
        --arg last_known_version "${last_known_version}" \
        '{
          package: $package,
          detected_at: $detected_at,
          fallback_path: $fallback_path,
          last_known_version: $last_known_version
        }'
    )"
    new_json="$(jq -c --argjson entry "${entry}" '. + [$entry]' <<<"${new_json}")"
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

new_json="$(jq -S 'sort_by(.package)' <<<"${new_json}")"
printf '%s\n' "${new_json}" >"${REMOVED_AUR_JSON}"
jq -r '.[].package' <<<"${new_json}" >"${REMOVED_AUR_TXT}"
