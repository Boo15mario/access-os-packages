#!/usr/bin/env bash

aur_packaging_die() {
  echo "Error: $*" >&2
  exit 1
}

aur_require_cmd() {
  command -v "$1" >/dev/null 2>&1 || aur_packaging_die "missing required command: $1"
}

aur_read_extra_packages_file() {
  local list_file="$1"
  [[ -f "${list_file}" ]] || return 0

  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "${line}" ]] && continue
    printf '%s\n' "${line}"
  done <"${list_file}"
}

aur_resolve_mirror_dir() {
  printf '%s\n' "${AUR_MIRROR_DIR:-${HOME}/aur-mirror}"
}

aur_local_mirror_pkg_dir() {
  local pkg="$1"
  printf '%s/%s\n' "$(aur_resolve_mirror_dir)" "${pkg}"
}

aur_curated_extra_dir() {
  local pkg="$1"
  printf '%s/extra/%s\n' "${PACKAGES_DIR:-${REPO_ROOT}/packages}" "${pkg}"
}

aur_pkgbuild_snapshot_dir() {
  local pkg="$1"
  printf '%s/%s\n' "${PKGBUILDS_DIR:-${REPO_ROOT}/pkgbuilds}" "${pkg}"
}

aur_curated_extra_has_package() {
  local pkg="$1"
  local pkg_dir
  pkg_dir="$(aur_curated_extra_dir "${pkg}")"
  [[ -d "${pkg_dir}" && -f "${pkg_dir}/PKGBUILD" ]]
}

aur_mirror_has_package() {
  local pkg="$1"
  local pkg_dir
  pkg_dir="$(aur_local_mirror_pkg_dir "${pkg}")"
  [[ -d "${pkg_dir}" && -f "${pkg_dir}/PKGBUILD" ]]
}

aur_mirror_is_usable() {
  local list_file="$1"
  local pkg

  [[ -d "$(aur_resolve_mirror_dir)" ]] || return 1
  while IFS= read -r pkg; do
    if aur_mirror_has_package "${pkg}"; then
      return 0
    fi
  done < <(aur_read_extra_packages_file "${list_file}")
  return 1
}

aur_should_copy_packaging_path() {
  local rel_path="$1"
  local base_name="${rel_path##*/}"

  [[ -n "${rel_path}" ]] || return 1
  [[ "${rel_path}" != .git/* ]] || return 1
  [[ "${rel_path}" != src/* ]] || return 1
  [[ "${rel_path}" != pkg/* ]] || return 1
  [[ "${base_name}" != *.pkg.tar.* ]] || return 1
  [[ "${base_name}" != *.src.tar.* ]] || return 1
  [[ "${base_name}" != *.log ]] || return 1
  [[ "${base_name}" != *.tar ]] || return 1
  [[ "${base_name}" != *.tar.* ]] || return 1
  [[ "${base_name}" != *.zip ]] || return 1
  [[ "${base_name}" != *.7z ]] || return 1
  [[ "${base_name}" != *.iso ]] || return 1
  [[ "${base_name}" != *.img ]] || return 1
  [[ "${base_name}" != *.bin ]] || return 1
  [[ "${base_name}" != *.exe ]] || return 1
  [[ "${base_name}" != *.msi ]] || return 1
  return 0
}

copy_packaging_snapshot() {
  local src_dir="$1"
  local dst_dir="$2"
  local rel_path item

  [[ -d "${src_dir}" ]] || aur_packaging_die "packaging source directory does not exist: ${src_dir}"

  rm -rf -- "${dst_dir}"
  mkdir -p -- "${dst_dir}"

  if [[ -d "${src_dir}/.git" ]]; then
    while IFS= read -r -d '' rel_path; do
      aur_should_copy_packaging_path "${rel_path}" || continue
      mkdir -p -- "${dst_dir}/$(dirname -- "${rel_path}")"
      cp -a -- "${src_dir}/${rel_path}" "${dst_dir}/${rel_path}"
    done < <(git -C "${src_dir}" ls-files -z)
    return 0
  fi

  (
    cd "${src_dir}"
    while IFS= read -r -d '' item; do
      rel_path="${item#./}"
      aur_should_copy_packaging_path "${rel_path}" || continue
      mkdir -p -- "${dst_dir}/$(dirname -- "${rel_path}")"
      cp -a -- "${item}" "${dst_dir}/${rel_path}"
    done < <(find . -type f -print0)
  )
}

aur_resolve_package_source_dir() {
  local pkg="$1"
  local mirror_dir snapshot_dir

  mirror_dir="$(aur_local_mirror_pkg_dir "${pkg}")"
  if [[ -d "${mirror_dir}" && -f "${mirror_dir}/PKGBUILD" ]]; then
    printf '%s\n' "${mirror_dir}"
    return 0
  fi

  snapshot_dir="$(aur_pkgbuild_snapshot_dir "${pkg}")"
  if [[ -d "${snapshot_dir}" && -f "${snapshot_dir}/PKGBUILD" ]]; then
    printf '%s\n' "${snapshot_dir}"
    return 0
  fi

  return 1
}

aur_resolve_extra_package_source_dir() {
  local pkg="$1"
  local curated_dir snapshot_dir

  curated_dir="$(aur_curated_extra_dir "${pkg}")"
  if [[ -d "${curated_dir}" && -f "${curated_dir}/PKGBUILD" ]]; then
    printf '%s\n' "${curated_dir}"
    return 0
  fi

  snapshot_dir="$(aur_pkgbuild_snapshot_dir "${pkg}")"
  if [[ -d "${snapshot_dir}" && -f "${snapshot_dir}/PKGBUILD" ]]; then
    printf '%s\n' "${snapshot_dir}"
    return 0
  fi

  return 1
}
