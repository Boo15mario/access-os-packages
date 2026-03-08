#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

usage() {
  cat <<'EOF'
Usage: publish-local.sh [--build-only] [--publish-only] [--no-push] [--skip-commit] [--preflight]

Build and publish the access-os pacman repositories from a local Arch system.

Flags:
  --build-only    Build packages and site metadata only; do not upload or push
  --publish-only  Publish existing dist/ and site/ outputs; skip the rebuild
  --no-push       Do not push git commits or the gh-pages branch
  --skip-commit   Do not commit pkgbuilds/ or metadata/ changes
  --preflight     Run builder readiness checks and exit
  -h, --help      Show this help

Environment overrides:
  ARCH            (default: x86_64)
  CORE_REPO       (default: access-os-core)
  EXTRA_REPO      (default: access-os-extra)
  PAGES_BRANCH    (default: gh-pages)
  REMOTE_NAME     (default: origin)
EOF
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

ARCH="${ARCH:-x86_64}"
CORE_REPO="${CORE_REPO:-access-os-core}"
EXTRA_REPO="${EXTRA_REPO:-access-os-extra}"
PAGES_BRANCH="${PAGES_BRANCH:-gh-pages}"
REMOTE_NAME="${REMOTE_NAME:-origin}"

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

ensure_multilib_enabled() {
  if ! grep -Eq '^[[:space:]]*\[multilib\]' /etc/pacman.conf; then
    die "multilib is not enabled in /etc/pacman.conf"
  fi
}

ensure_gh_auth() {
  gh auth status >/dev/null 2>&1 || die "GitHub CLI is not authenticated; run: gh auth login"
}

ensure_publish_inputs() {
  local repo_dir
  for repo_dir in \
    "${REPO_ROOT}/dist/${CORE_REPO}/${ARCH}" \
    "${REPO_ROOT}/dist/${EXTRA_REPO}/${ARCH}" \
    "${REPO_ROOT}/site"; do
    [[ -d "${repo_dir}" ]] || die "required publish input is missing: ${repo_dir}"
  done
}

upload_release_assets() {
  local repo="$1"
  local repo_dir="${REPO_ROOT}/dist/${repo}/${ARCH}"
  local tag="${repo}-${ARCH}"
  local -a files=()
  local file

  if gh release view "${tag}" >/dev/null 2>&1; then
    :
  else
    gh release create "${tag}" \
      --title "${tag}" \
      --notes "Automated package assets for ${repo} (${ARCH})."
  fi

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

  gh release upload "${tag}" "${files[@]}" --clobber
}

publish_pages_branch() {
  local pages_dir="${REPO_ROOT}/site"
  local worktree_dir
  mkdir -p "${REPO_ROOT}/work"
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

commit_repo_metadata() {
  git -C "${REPO_ROOT}" add metadata/ pkgbuilds/
  if git -C "${REPO_ROOT}" diff --cached --quiet; then
    echo "Info: no pkgbuild or metadata changes to commit"
    return 0
  fi

  git -C "${REPO_ROOT}" commit -m "chore: update saved PKGBUILDs and metadata" >/dev/null
  if [[ "${NO_PUSH}" -eq 0 ]]; then
    git -C "${REPO_ROOT}" push "${REMOTE_NAME}" HEAD >/dev/null
  else
    echo "Info: metadata commit created locally but not pushed"
  fi
}

ensure_gh_auth
"${REPO_ROOT}/scripts/check-builder.sh"
if [[ "${PREFLIGHT_ONLY}" -eq 1 ]]; then
  exit 0
fi
"${REPO_ROOT}/scripts/sync-removed-from-aur.sh"

if [[ "${PUBLISH_ONLY}" -eq 0 ]]; then
  ensure_multilib_enabled
  "${REPO_ROOT}/scripts/rebuild.sh"
fi

if [[ "${BUILD_ONLY}" -eq 1 ]]; then
  exit 0
fi

ensure_publish_inputs
upload_release_assets "${CORE_REPO}"
upload_release_assets "${EXTRA_REPO}"

if [[ "${SKIP_COMMIT}" -eq 0 ]]; then
  commit_repo_metadata
fi

publish_pages_branch
