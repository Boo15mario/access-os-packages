#!/usr/bin/env bash
set -euo pipefail

# Publish script for access-os package repositories.
# Calls build.sh for building/staging, then uploads to GitHub Releases,
# pushes gh-pages, and reconciles published state.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

usage() {
  cat <<'EOF'
Usage: publish.sh [--build-only] [--publish-only] [--no-push] [--skip-commit] [--preflight]

Build and publish the access-os pacman repositories from a local Arch system.

Flags:
  --build-only    Build packages and stage site metadata only; do not upload or push
  --publish-only  Publish existing dist/ and site/ outputs; skip the rebuild
  --no-push       Do not push git commits or the gh-pages branch
  --skip-commit   Do not commit metadata/ or packages/extra/ changes
  --preflight     Run builder readiness checks and exit
  -h, --help      Show this help

Environment overrides:
  ARCH            (default: x86_64)
  CORE_REPO       (default: access-os-core)
  EXTRA_REPO      (default: access-os-extra)
  PAGES_BRANCH    (default: gh-pages)
  REMOTE_NAME     (default: origin)

Reconciliation tuning:
  PAGES_RECONCILE_ATTEMPTS    (default: 20)
  PAGES_RECONCILE_DELAY       (default: 6)
  PAGES_FETCH_CONNECT_TIMEOUT (default: 3)
  PAGES_FETCH_MAX_TIME        (default: 8)
EOF
}

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

ARCH="${ARCH:-x86_64}"
CORE_REPO="${CORE_REPO:-access-os-core}"
EXTRA_REPO="${EXTRA_REPO:-access-os-extra}"
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"
REMOTE_NAME="${REMOTE_NAME:-origin}"

PAGES_RECONCILE_ATTEMPTS="${PAGES_RECONCILE_ATTEMPTS:-20}"
PAGES_RECONCILE_DELAY="${PAGES_RECONCILE_DELAY:-6}"
PAGES_FETCH_CONNECT_TIMEOUT="${PAGES_FETCH_CONNECT_TIMEOUT:-3}"
PAGES_FETCH_MAX_TIME="${PAGES_FETCH_MAX_TIME:-8}"

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------

BUILD_ONLY=0
PUBLISH_ONLY=0
NO_PUSH=0
SKIP_COMMIT=0
PREFLIGHT_ONLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --build-only) BUILD_ONLY=1 ;;
    --publish-only) PUBLISH_ONLY=1 ;;
    --no-push) NO_PUSH=1 ;;
    --skip-commit) SKIP_COMMIT=1 ;;
    --preflight) PREFLIGHT_ONLY=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
  shift
done

if [[ "${BUILD_ONLY}" -eq 1 && "${PUBLISH_ONLY}" -eq 1 ]]; then
  die "--build-only and --publish-only cannot be used together"
fi

require_cmd git
require_cmd gh
require_cmd curl
require_cmd jq

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------

ensure_gh_auth() {
  gh auth status >/dev/null 2>&1 || die "GitHub CLI is not authenticated; run: gh auth login"
}

ensure_multilib_enabled() {
  if ! grep -Eq '^[[:space:]]*\[multilib\]' /etc/pacman.conf; then
    die "multilib is not enabled in /etc/pacman.conf"
  fi
}

ensure_gh_auth
"${REPO_ROOT}/scripts/check-builder.sh"
if [[ "${PREFLIGHT_ONLY}" -eq 1 ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Build phase: call scripts/build.sh (unless --publish-only)
# ---------------------------------------------------------------------------

if [[ "${PUBLISH_ONLY}" -eq 0 ]]; then
  ensure_multilib_enabled
  export ARCH CORE_REPO EXTRA_REPO REMOTE_NAME
  "${REPO_ROOT}/scripts/build.sh"
fi

# ---------------------------------------------------------------------------
# After build: exit if --build-only
# ---------------------------------------------------------------------------

if [[ "${BUILD_ONLY}" -eq 1 ]]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# ensure_publish_inputs: verify dist/ and site/ exist
# ---------------------------------------------------------------------------

ensure_publish_inputs() {
  local repo_dir
  for repo_dir in \
    "${REPO_ROOT}/dist/${CORE_REPO}/${ARCH}" \
    "${REPO_ROOT}/dist/${EXTRA_REPO}/${ARCH}" \
    "${REPO_ROOT}/site"; do
    [[ -d "${repo_dir}" ]] || die "required publish input is missing: ${repo_dir}"
  done
}

ensure_publish_inputs

# ---------------------------------------------------------------------------
# upload_release_assets: upload pkg.tar.* files to GitHub Releases
# ---------------------------------------------------------------------------

ensure_release_tag() {
  local repo="$1"
  local tag="${repo}-${ARCH}"

  if gh release view "${tag}" >/dev/null 2>&1; then
    return 0
  fi

  gh release create "${tag}" \
    --title "${tag}" \
    --notes "Automated package assets for ${repo} (${ARCH})."
}

upload_release_assets() {
  local repo="$1"
  local repo_dir="${REPO_ROOT}/dist/${repo}/${ARCH}"
  local -a files=()
  local file

  shopt -s nullglob
  for file in "${repo_dir}/"*.pkg.tar.*; do
    [[ "${file}" == *.sig ]] && continue
    files+=("${file}")
  done
  shopt -u nullglob

  if [[ "${#files[@]}" -eq 0 ]]; then
    echo "Info: no package files found for ${repo}; skipping release upload"
    return 0
  fi

  local tag="${repo}-${ARCH}"
  ensure_release_tag "${repo}"
  gh release upload "${tag}" "${files[@]}" --clobber
}

upload_release_assets "${CORE_REPO}"
upload_release_assets "${EXTRA_REPO}"

# ---------------------------------------------------------------------------
# commit_repo_metadata: git add packages/extra/ metadata/, commit, push
# ---------------------------------------------------------------------------

commit_repo_metadata() {
  git -C "${REPO_ROOT}" add packages/extra/ metadata/
  if git -C "${REPO_ROOT}" diff --cached --quiet; then
    echo "Info: no metadata changes to commit"
    return 0
  fi

  git -C "${REPO_ROOT}" commit -m "chore: update saved PKGBUILDs and metadata" >/dev/null
  if [[ "${NO_PUSH}" -eq 0 ]]; then
    git -C "${REPO_ROOT}" push "${REMOTE_NAME}" HEAD >/dev/null
  else
    echo "Info: metadata commit created locally but not pushed"
  fi
}

if [[ "${SKIP_COMMIT}" -eq 0 ]]; then
  commit_repo_metadata
fi

# ---------------------------------------------------------------------------
# publish_pages_branch: worktree-based gh-pages deployment
# ---------------------------------------------------------------------------

publish_pages_branch() {
  local pages_dir="${REPO_ROOT}/site"
  local worktree_dir
  mkdir -p "${REPO_ROOT}/work"

  cleanup_stale_pages_worktrees() {
    local current_path=""
    while IFS= read -r line; do
      if [[ "${line}" == worktree\ * ]]; then
        current_path="${line#worktree }"
        continue
      fi
      if [[ -n "${line}" ]]; then
        continue
      fi
      if [[ "${current_path}" == "${REPO_ROOT}"/work/pages.* ]]; then
        git -C "${REPO_ROOT}" worktree remove --force "${current_path}" >/dev/null 2>&1 || true
        rm -rf -- "${current_path}"
      fi
      current_path=""
    done < <(git -C "${REPO_ROOT}" worktree list --porcelain; printf '\n')

    git -C "${REPO_ROOT}" worktree prune >/dev/null 2>&1 || true
  }

  cleanup_stale_pages_worktrees
  worktree_dir="$(mktemp -d "${REPO_ROOT%/}/work/pages.XXXXXXXX")"

  cleanup_pages_worktree() {
    git -C "${REPO_ROOT}" worktree remove --force "${worktree_dir}" >/dev/null 2>&1 || true
    rm -rf -- "${worktree_dir}"
  }

  git fetch "${REMOTE_NAME}" "${PAGES_BRANCH}" >/dev/null 2>&1 || true
  if git show-ref --verify --quiet "refs/remotes/${REMOTE_NAME}/${PAGES_BRANCH}"; then
    git worktree add -B "${PAGES_BRANCH}" "${worktree_dir}" "${REMOTE_NAME}/${PAGES_BRANCH}" >/dev/null
  else
    git worktree add --detach "${worktree_dir}" >/dev/null
    git -C "${worktree_dir}" checkout --orphan "${PAGES_BRANCH}" >/dev/null
  fi

  find "${worktree_dir}" -mindepth 1 -maxdepth 1 ! -name .git -exec rm -rf -- {} +
  cp -a "${pages_dir}/." "${worktree_dir}/"
  touch "${worktree_dir}/.nojekyll"

  git -C "${worktree_dir}" add --all
  if git -C "${worktree_dir}" diff --cached --quiet; then
    echo "Info: no GitHub Pages changes to publish"
    cleanup_pages_worktree
    return 0
  fi

  git -C "${worktree_dir}" commit -m "chore: publish pacman metadata [skip ci]" >/dev/null
  if [[ "${NO_PUSH}" -eq 0 ]]; then
    git -C "${worktree_dir}" push "${REMOTE_NAME}" "${PAGES_BRANCH}" >/dev/null
  else
    echo "Info: gh-pages update committed locally but not pushed"
  fi

  cleanup_pages_worktree
}

publish_pages_branch

# ---------------------------------------------------------------------------
# Reconciliation: verify published state matches local
# ---------------------------------------------------------------------------

resolve_pages_base_url() {
  local remote_url parsed owner repo_name

  if [[ -n "${PAGES_BASE_URL:-}" ]]; then
    printf '%s\n' "${PAGES_BASE_URL%/}"
    return 0
  fi

  if [[ -n "${GITHUB_REPOSITORY_OWNER:-}" && -n "${GITHUB_REPOSITORY:-}" ]]; then
    repo_name="${GITHUB_REPOSITORY#*/}"
    printf 'https://%s.github.io/%s\n' "${GITHUB_REPOSITORY_OWNER}" "${repo_name}"
    return 0
  fi

  remote_url="$(git -C "${REPO_ROOT}" remote get-url "${REMOTE_NAME}" 2>/dev/null || true)"
  [[ -n "${remote_url}" ]] || return 1

  parsed="$(sed -nE 's#^.*[:/]([^/:]+)/([^/]+)(\.git)?$#\1 \2#p' <<<"${remote_url}")"
  [[ -n "${parsed}" ]] || return 1

  owner="${parsed%% *}"
  repo_name="${parsed#* }"
  repo_name="${repo_name%.git}"
  printf 'https://%s.github.io/%s\n' "${owner}" "${repo_name}"
}

fetch_remote_manifest() {
  local base_url="$1"
  echo "  fetching published manifest..." >&2
  curl -fsSL \
    --connect-timeout "${PAGES_FETCH_CONNECT_TIMEOUT}" \
    --max-time "${PAGES_FETCH_MAX_TIME}" \
    "${base_url}/manifest.json" | jq -S .
}

fetch_remote_repo_versions() {
  local base_url="$1"
  local repo="$2"
  local tmpdir db_file json

  tmpdir="$(mktemp -d "${REPO_ROOT%/}/work/reconcile.XXXXXXXX")"
  db_file="${tmpdir}/${repo}.db.tar.gz"
  json='{}'

  echo "  fetching published repo DB for ${repo}..." >&2
  curl -fsSL \
    --connect-timeout "${PAGES_FETCH_CONNECT_TIMEOUT}" \
    --max-time "${PAGES_FETCH_MAX_TIME}" \
    "${base_url}/${repo}/os/${ARCH}/${repo}.db" -o "${db_file}"
  tar -xzf "${db_file}" -C "${tmpdir}"

  while IFS=$'\t' read -r pkg ver; do
    [[ -n "${pkg}" && -n "${ver}" ]] || continue
    json="$(jq -c --arg pkg "${pkg}" --arg ver "${ver}" '. + {($pkg): $ver}' <<<"${json}")"
  done < <(
    find "${tmpdir}" -mindepth 2 -maxdepth 2 -type f -name desc -print0 | \
      xargs -0 awk '
        BEGIN { pkg=""; ver="" }
        /^%NAME%$/ { getline; pkg=$0 }
        /^%VERSION%$/ { getline; ver=$0 }
        ENDFILE {
          if (pkg != "" && ver != "") {
            printf "%s\t%s\n", pkg, ver
          }
          pkg=""
          ver=""
        }
      '
  )

  jq -S . <<<"${json}"
  rm -rf -- "${tmpdir}"
}

release_assets_json() {
  local repo="$1"
  local tag="${repo}-${ARCH}"
  gh release view "${tag}" --json assets | jq -c '[.assets[].name]'
}

check_release_assets_for_repo() {
  local repo="$1"
  local repo_dir="${REPO_ROOT}/dist/${repo}/${ARCH}"
  local assets_json file base_name
  local missing=0

  assets_json="$(release_assets_json "${repo}")"

  shopt -s nullglob
  for file in "${repo_dir}/"*.pkg.tar.*; do
    [[ "${file}" == *.sig ]] && continue
    base_name="$(basename -- "${file}")"
    if ! jq -e --arg name "${base_name}" 'index($name)' <<<"${assets_json}" >/dev/null; then
      echo "Release asset missing for ${repo}: ${base_name}" >&2
      missing=1
    fi
  done
  shopt -u nullglob

  [[ "${missing}" -eq 0 ]]
}

reconcile_repo_metadata() {
  local repo="$1"
  local local_manifest_json="$2"
  local base_url="$3"
  local local_repo_versions remote_repo_versions mismatches

  local_repo_versions="$(jq -c --arg repo "${repo}" '.repos[$repo].packages // {}' <<<"${local_manifest_json}")"
  remote_repo_versions="$(fetch_remote_repo_versions "${base_url}" "${repo}")"

  mismatches="$(
    jq -r \
      --argjson local "${local_repo_versions}" \
      --argjson remote "${remote_repo_versions}" \
      '
      ($local | keys | sort)[] as $pkg
      | select(($remote[$pkg] // "") != ($local[$pkg] // ""))
      | "\($pkg)\tlocal=\($local[$pkg])\tremote=\($remote[$pkg] // "<missing>")"
      '
  )"

  if [[ -n "${mismatches}" ]]; then
    echo "Repo DB mismatch for ${repo}:" >&2
    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      echo "  - ${line}" >&2
    done <<<"${mismatches}"
    return 1
  fi

  check_release_assets_for_repo "${repo}"
}

reconcile_published_state() {
  local base_url local_manifest_json remote_manifest_json

  [[ "${NO_PUSH}" -eq 0 ]] || return 0

  base_url="$(resolve_pages_base_url)" || {
    echo "Error: failed to determine Pages base URL for reconciliation" >&2
    return 1
  }

  local_manifest_json="$(jq -S . "${REPO_ROOT}/site/manifest.json")"
  remote_manifest_json="$(fetch_remote_manifest "${base_url}")" || {
    echo "Error: failed to fetch published manifest during reconciliation" >&2
    return 1
  }

  if [[ "${local_manifest_json}" != "${remote_manifest_json}" ]]; then
    echo "Manifest mismatch between local staged site and published Pages metadata" >&2
    return 1
  fi

  reconcile_repo_metadata "${CORE_REPO}" "${local_manifest_json}" "${base_url}" || return 1
  reconcile_repo_metadata "${EXTRA_REPO}" "${local_manifest_json}" "${base_url}" || return 1
}

reconcile_with_retry() {
  [[ "${NO_PUSH}" -eq 0 ]] || return 0

  local attempt
  for (( attempt = 1; attempt <= PAGES_RECONCILE_ATTEMPTS; attempt++ )); do
    echo "Waiting for GitHub Pages propagation (${attempt}/${PAGES_RECONCILE_ATTEMPTS})..."
    if reconcile_published_state; then
      return 0
    fi
    if (( attempt < PAGES_RECONCILE_ATTEMPTS )); then
      sleep "${PAGES_RECONCILE_DELAY}"
    fi
  done

  echo "Warning: published state mismatch detected; retrying GitHub Pages publish once" >&2
  publish_pages_branch
  for (( attempt = 1; attempt <= PAGES_RECONCILE_ATTEMPTS; attempt++ )); do
    echo "Waiting for GitHub Pages propagation after retry (${attempt}/${PAGES_RECONCILE_ATTEMPTS})..."
    if reconcile_published_state; then
      return 0
    fi
    if (( attempt < PAGES_RECONCILE_ATTEMPTS )); then
      sleep "${PAGES_RECONCILE_DELAY}"
    fi
  done

  die "published GitHub Releases and Pages metadata are still out of sync"
}

reconcile_with_retry
