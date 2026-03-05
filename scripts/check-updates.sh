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

require_cmd jq
require_cmd curl

if [[ -n "${PAGES_BASE_URL:-}" ]]; then
  base_url="${PAGES_BASE_URL%/}"
elif [[ -n "${GITHUB_REPOSITORY_OWNER:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
  repo_name="${GITHUB_REPOSITORY#*/}"
  base_url="https://${GITHUB_REPOSITORY_OWNER}.github.io/${repo_name}"
else
  die "set PAGES_BASE_URL (or run in GitHub Actions with GITHUB_REPOSITORY_OWNER/GITHUB_REPOSITORY)"
fi

remote_url="${base_url}/manifest.json"

remote_manifest_raw=""
if remote_manifest_raw="$(curl -fsSL "${remote_url}" 2>/dev/null)"; then
  :
else
  remote_manifest_raw=""
fi

if [[ -n "${remote_manifest_raw}" ]]; then
  if ! remote_manifest="$(jq -S . <<<"${remote_manifest_raw}" 2>/dev/null)"; then
    echo "Warning: remote manifest exists but is invalid JSON; forcing rebuild" >&2
    remote_manifest='{}'
  fi
else
  remote_manifest='{}'
fi

desired_manifest="$("${REPO_ROOT}/scripts/gen-manifest.sh" | jq -S .)"

remote_hash="$(printf '%s' "${remote_manifest}" | sha256sum | awk '{print $1}')"
desired_hash="$(printf '%s' "${desired_manifest}" | sha256sum | awk '{print $1}')"

rebuild_required="false"
if [[ "${remote_hash}" != "${desired_hash}" ]]; then
  rebuild_required="true"
fi

echo "Pages base URL: ${base_url}"
echo "Remote manifest: ${remote_url}"
echo "Rebuild required: ${rebuild_required}"

if [[ "${rebuild_required}" == "true" ]]; then
  echo
  echo "Changes:"
  jq -r \
    --arg core "${CORE_REPO}" \
    --arg extra "${EXTRA_REPO}" \
    --argjson old "${remote_manifest}" \
    --argjson new "${desired_manifest}" \
    '
    def pkgs($m; $r): ($m.repos[$r].packages // {});
    [$core, $extra] as $repos
    | $repos[]
    | . as $r
    | (pkgs($old; $r)) as $o
    | (pkgs($new; $r)) as $n
    | (((($o|keys) + ($n|keys)) | unique | sort)[])
    | . as $p
    | select(($o[$p] // "-") != ($n[$p] // "-"))
    | "\($r)\t\($p)\t\($o[$p] // "-") -> \($n[$p] // "-")"
    ' | sed 's/^/  - /'
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    echo "rebuild_required=${rebuild_required}"
    echo "pages_base_url=${base_url}"
  } >>"${GITHUB_OUTPUT}"
fi
