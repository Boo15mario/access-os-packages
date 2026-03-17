#!/usr/bin/env bash
set -euo pipefail

die() { echo "Error: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
MIRROR_DIR="${REPO_ROOT}/aur-mirror"
LIST_FILE="${REPO_ROOT}/packages/extra.list"

[[ -f "${LIST_FILE}" ]] || die "package list not found: ${LIST_FILE}"

read_list() {
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "${line}" ]] && printf '%s\n' "${line}"
  done <"${LIST_FILE}"
}

mkdir -p "${MIRROR_DIR}"

mapfile -t packages < <(read_list)
[[ "${#packages[@]}" -gt 0 ]] || die "no packages in ${LIST_FILE}"

for pkg in "${packages[@]}"; do
  pkg_dir="${MIRROR_DIR}/${pkg}"
  remote_url="https://aur.archlinux.org/${pkg}.git"

  if [[ ! -d "${pkg_dir}/.git" ]]; then
    echo "Cloning ${pkg}"
    git clone --quiet "${remote_url}" "${pkg_dir}"
    continue
  fi

  echo "Updating ${pkg}"
  git -C "${pkg_dir}" remote set-url origin "${remote_url}"
  git -C "${pkg_dir}" fetch --quiet --prune origin
  branch="$(git -C "${pkg_dir}" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  if [[ -z "${branch}" ]]; then
    branch="$(git -C "${pkg_dir}" remote show origin 2>/dev/null | awk '/HEAD branch/ {print $NF; exit}')"
    [[ -n "${branch}" ]] || branch="master"
    git -C "${pkg_dir}" checkout -B "${branch}" "origin/${branch}"
  fi
  git -C "${pkg_dir}" reset --hard "origin/${branch}"
  git -C "${pkg_dir}" clean -fdx
done

echo "Done. Mirror synced at ${MIRROR_DIR}"
