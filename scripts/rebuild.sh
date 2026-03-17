#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/lib/aur-packaging.sh"

usage() {
  cat <<'EOF'
Usage: rebuild.sh [--dry-run] [--stage-only]

Build packages and stage pacman repositories.

Outputs:
  dist/<repo>/<arch>/   Built package files + repo-add DB tarballs
  site/<repo>/os/<arch>/  Published repo DB/files (no packages)
  site/manifest.json    Desired versions used for update detection

Environment overrides:
  ARCH                (default: x86_64)
  CORE_REPO           (default: access-os-core)
  EXTRA_REPO          (default: access-os-extra)
  EXTRA_LIST_FILE     (default: package-lists/access-os-extra.txt)
  DIST_DIR            (default: dist)
  SITE_DIR            (default: site)
  WORK_ROOT           (default: work)
  REMOTE_NAME         (default: origin)
  CLEAN_BEFORE_BUILD  1=enabled (default), 0=disabled
EOF
}

DRY_RUN=0
STAGE_ONLY=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    --stage-only) STAGE_ONLY=1 ;;
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

if [[ "$(id -u)" -eq 0 ]]; then
  die "do not run as root (makepkg refuses to run as root)"
fi

ARCH="${ARCH:-x86_64}"
CORE_REPO="${CORE_REPO:-access-os-core}"
EXTRA_REPO="${EXTRA_REPO:-access-os-extra}"
EXTRA_LIST_FILE="${EXTRA_LIST_FILE:-${REPO_ROOT}/package-lists/access-os-extra.txt}"
PKGBUILDS_DIR="${PKGBUILDS_DIR:-${REPO_ROOT}/pkgbuilds}"
AUR_MIRROR_DIR="${AUR_MIRROR_DIR:-${HOME}/aur-mirror}"
DIST_DIR="${DIST_DIR:-${REPO_ROOT}/dist}"
SITE_DIR="${SITE_DIR:-${REPO_ROOT}/site}"
WORK_ROOT="${WORK_ROOT:-${REPO_ROOT}/work}"
REMOTE_NAME="${REMOTE_NAME:-origin}"
CLEAN_BEFORE_BUILD="${CLEAN_BEFORE_BUILD:-1}"
DOWNLOAD_HTTP_RETRIES="${DOWNLOAD_HTTP_RETRIES:-5}"
DOWNLOAD_HTTP_RETRY_DELAY="${DOWNLOAD_HTTP_RETRY_DELAY:-3}"
MAKEPKG_JOBS="${MAKEPKG_JOBS:-auto}"
MAKEPKG_JOBS_MAX="${MAKEPKG_JOBS_MAX:-15}"
ACCESS_OS_INCREMENTAL_PUBLISH="${ACCESS_OS_INCREMENTAL_PUBLISH:-0}"
ACCESS_OS_INCREMENTAL_NO_PUSH="${ACCESS_OS_INCREMENTAL_NO_PUSH:-0}"
ACCESS_OS_PUBLISH_HELPER="${ACCESS_OS_PUBLISH_HELPER:-${REPO_ROOT}/scripts/publish-local.sh}"
ACCESS_OS_MANIFEST_CACHE="${ACCESS_OS_MANIFEST_CACHE:-}"

MAKEPKG_DLAGENTS=(
  "https::/usr/bin/curl --http1.1 -qgLC - --retry ${DOWNLOAD_HTTP_RETRIES} --retry-delay ${DOWNLOAD_HTTP_RETRY_DELAY} --retry-all-errors --fail -o %o %u"
  "http::/usr/bin/curl --http1.1 -qgLC - --retry ${DOWNLOAD_HTTP_RETRIES} --retry-delay ${DOWNLOAD_HTTP_RETRY_DELAY} --retry-all-errors --fail -o %o %u"
  "ftp::/usr/bin/curl --http1.1 -qgLC - --retry ${DOWNLOAD_HTTP_RETRIES} --retry-delay ${DOWNLOAD_HTTP_RETRY_DELAY} --retry-all-errors --fail -o %o %u"
)

published_manifest='{}'
desired_manifest='{}'
published_manifest_available=0
desired_manifest_available=0

srcinfo_from_dir() {
  local pkg_dir="$1"

  if [[ -f "${pkg_dir}/.SRCINFO" ]]; then
    cat "${pkg_dir}/.SRCINFO"
    return 0
  fi

  (cd "${pkg_dir}" && makepkg --printsrcinfo)
}

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

load_skip_manifests() {
  local base_url desired_manifest_raw remote_manifest_raw

  if [[ "${STAGE_ONLY}" == "1" ]]; then
    return 0
  fi

  if desired_manifest_raw="$("${REPO_ROOT}/scripts/gen-manifest.sh")"; then
    if desired_manifest="$(jq -S . <<<"${desired_manifest_raw}" 2>/dev/null)"; then
      desired_manifest_available=1
      if [[ -n "${ACCESS_OS_MANIFEST_CACHE}" ]]; then
        printf '%s\n' "${desired_manifest}" >"${ACCESS_OS_MANIFEST_CACHE}"
      fi
    else
      die "desired manifest is invalid"
    fi
  else
    die "failed to generate desired manifest"
  fi

  if ! base_url="$(resolve_pages_base_url)"; then
    echo "Warning: failed to determine GitHub Pages base URL; rebuilding all packages" >&2
    return 0
  fi

  remote_manifest_raw="$(curl -fsSL "${base_url}/manifest.json" 2>/dev/null || true)"
  if [[ -z "${remote_manifest_raw}" ]]; then
    echo "Warning: failed to fetch published manifest from ${base_url}/manifest.json; rebuilding all packages" >&2
    return 0
  fi

  if published_manifest="$(jq -S . <<<"${remote_manifest_raw}" 2>/dev/null)"; then
    published_manifest_available=1
  else
    echo "Warning: published manifest from ${base_url}/manifest.json is invalid; rebuilding all packages" >&2
  fi
}

manifest_version() {
  local manifest_json="$1"
  local repo="$2"
  local pkg="$3"

  jq -r --arg repo "${repo}" --arg pkg "${pkg}" '.repos[$repo].packages[$pkg] // empty' <<<"${manifest_json}"
}

sanitize_version_for_filename() {
  local version="$1"
  printf '%s\n' "${version//:/.}"
}

find_local_package_file_for_version() {
  local repo_dir="$1"
  local pkg="$2"
  local version="$3"
  local version_glob file

  version_glob="$(sanitize_version_for_filename "${version}")"
  shopt -s nullglob
  for file in "${repo_dir}/${pkg}-${version_glob}-"*.pkg.tar.*; do
    [[ "${file}" == *.sig ]] && continue
    printf '%s\n' "${file}"
    shopt -u nullglob
    return 0
  done
  shopt -u nullglob
  return 1
}

ensure_local_package_file_for_version() {
  local repo="$1"
  local repo_dir="$2"
  local pkg="$3"
  local version="$4"
  local tag="${repo}-${ARCH}"
  local version_glob

  if find_local_package_file_for_version "${repo_dir}" "${pkg}" "${version}" >/dev/null; then
    return 0
  fi

  version_glob="$(sanitize_version_for_filename "${version}")"
  if ! gh release download "${tag}" -D "${repo_dir}" -p "${pkg}-${version_glob}-*.pkg.tar.*" >/dev/null 2>&1; then
    return 1
  fi

  find_local_package_file_for_version "${repo_dir}" "${pkg}" "${version}" >/dev/null
}

should_skip_core_pkgbuild() {
  local pkg_dir="$1"
  local repo_dir="$2"
  local srcinfo_text desired_version published_version pkgname
  local -a pkgnames=()

  [[ "${desired_manifest_available}" == "1" && "${published_manifest_available}" == "1" ]] || return 1

  srcinfo_text="$(srcinfo_from_dir "${pkg_dir}")" || return 1
  mapfile -t pkgnames < <(awk -F' = ' '{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2)} $1=="pkgname"{print $2}' <<<"${srcinfo_text}" | sort -u)
  [[ "${#pkgnames[@]}" -gt 0 ]] || return 1

  desired_version="$(manifest_version "${desired_manifest}" "${CORE_REPO}" "${pkgnames[0]}")"
  [[ -n "${desired_version}" ]] || return 1

  for pkgname in "${pkgnames[@]}"; do
    published_version="$(manifest_version "${published_manifest}" "${CORE_REPO}" "${pkgname}")"
    if [[ -z "${published_version}" ]]; then
      echo "    build ${pkgname}: not present in published manifest (desired ${desired_version})"
      return 1
    fi
    if [[ "${published_version}" != "${desired_version}" ]]; then
      echo "    build ${pkgname}: published version ${published_version} differs from desired version ${desired_version}"
      return 1
    fi
    if ! ensure_local_package_file_for_version "${CORE_REPO}" "${repo_dir}" "${pkgname}" "${desired_version}"; then
      echo "    build ${pkgname}: published version matches ${desired_version}, but package artifact could not be reused locally"
      return 1
    fi
  done

  echo "    skip $(IFS=,; echo "${pkgnames[*]}"): published version ${desired_version} matches desired version ${desired_version}"
  return 0
}

should_skip_extra_package() {
  local pkg="$1"
  local repo_dir="$2"
  local desired_version published_version

  [[ "${desired_manifest_available}" == "1" && "${published_manifest_available}" == "1" ]] || return 1

  desired_version="$(manifest_version "${desired_manifest}" "${EXTRA_REPO}" "${pkg}")"
  [[ -n "${desired_version}" ]] || return 1

  published_version="$(manifest_version "${published_manifest}" "${EXTRA_REPO}" "${pkg}")"
  if [[ -z "${published_version}" ]]; then
    echo "    build ${pkg}: not present in published manifest (desired ${desired_version})"
    return 1
  fi
  if [[ "${published_version}" != "${desired_version}" ]]; then
    echo "    build ${pkg}: published version ${published_version} differs from desired version ${desired_version}"
    return 1
  fi
  if ! ensure_local_package_file_for_version "${EXTRA_REPO}" "${repo_dir}" "${pkg}" "${desired_version}"; then
    echo "    build ${pkg}: published version matches ${desired_version}, but package artifact could not be reused locally"
    return 1
  fi

  echo "    skip ${pkg}: published version ${published_version} matches desired version ${desired_version}"
  return 0
}

resolve_makepkg_jobs() {
  local cpu_cores total_mem_kb total_mem_gb ram_jobs jobs

  [[ "${MAKEPKG_JOBS_MAX}" =~ ^[0-9]+$ ]] || die "MAKEPKG_JOBS_MAX must be a positive integer"
  if [[ "${MAKEPKG_JOBS_MAX}" -lt 1 ]]; then
    die "MAKEPKG_JOBS_MAX must be at least 1"
  fi

  if [[ "${MAKEPKG_JOBS}" == "auto" ]]; then
    cpu_cores="$(nproc)"
    [[ -n "${cpu_cores}" && "${cpu_cores}" =~ ^[0-9]+$ ]] || die "failed to determine CPU core count"

    total_mem_kb="$(awk '/^MemTotal:/ {print $2; exit}' /proc/meminfo)"
    [[ -n "${total_mem_kb}" && "${total_mem_kb}" =~ ^[0-9]+$ ]] || die "failed to determine total system memory"

    total_mem_gb="$(( total_mem_kb / 1024 / 1024 ))"
    ram_jobs="$(( total_mem_gb / 2 ))"

    jobs="${cpu_cores}"
    if [[ "${ram_jobs}" -lt "${jobs}" ]]; then
      jobs="${ram_jobs}"
    fi
    if [[ "${MAKEPKG_JOBS_MAX}" -lt "${jobs}" ]]; then
      jobs="${MAKEPKG_JOBS_MAX}"
    fi
    if [[ "${jobs}" -lt 1 ]]; then
      jobs=1
    fi

    printf '%s\n' "${jobs}"
    return 0
  fi

  [[ "${MAKEPKG_JOBS}" =~ ^[0-9]+$ ]] || die "MAKEPKG_JOBS must be a positive integer or 'auto'"
  if [[ "${MAKEPKG_JOBS}" -lt 1 ]]; then
    die "MAKEPKG_JOBS must be at least 1"
  fi

  printf '%s\n' "${MAKEPKG_JOBS}"
}

RESOLVED_MAKEPKG_JOBS="$(resolve_makepkg_jobs)"
MAKEPKG_MAKEFLAGS="-j${RESOLVED_MAKEPKG_JOBS}"

if [[ "${DRY_RUN}" == "1" ]]; then
  echo "Repo root: ${REPO_ROOT}"
  echo "Arch: ${ARCH}"
  echo "Core repo: ${CORE_REPO}"
  echo "Extra repo: ${EXTRA_REPO}"
  echo "Extra list: ${EXTRA_LIST_FILE}"
  echo "Dist dir: ${DIST_DIR}"
  echo "Site dir: ${SITE_DIR}"
  echo "Work root: ${WORK_ROOT}"
  echo "Clean before build: ${CLEAN_BEFORE_BUILD}"
  echo "Makepkg jobs: ${RESOLVED_MAKEPKG_JOBS} (MAKEPKG_JOBS=${MAKEPKG_JOBS}, cap=${MAKEPKG_JOBS_MAX})"
  echo "Stage only: ${STAGE_ONLY}"
  exit 0
fi

sudo_keepalive_pid=""
work_dir=""

stop_sudo_keepalive() {
  if [[ -n "${sudo_keepalive_pid}" ]]; then
    kill "${sudo_keepalive_pid}" >/dev/null 2>&1 || true
    wait "${sudo_keepalive_pid}" 2>/dev/null || true
    sudo_keepalive_pid=""
  fi
}

start_sudo_keepalive() {
  command -v sudo >/dev/null 2>&1 || die "sudo is required for local dependency installs"

  echo "Authenticating sudo for local package installs..."
  sudo -v

  (
    while true; do
      sudo -n true >/dev/null 2>&1 || exit 0
      sleep 30
    done
  ) &
  sudo_keepalive_pid="$!"
}

cleanup() {
  stop_sudo_keepalive
  if [[ -n "${work_dir}" ]]; then
    rm -rf -- "${work_dir}"
    work_dir=""
  fi
}

trap cleanup EXIT

if [[ "${STAGE_ONLY}" != "1" ]]; then
  start_sudo_keepalive
fi

echo "Using makepkg jobs: ${RESOLVED_MAKEPKG_JOBS} (MAKEFLAGS=${MAKEPKG_MAKEFLAGS})"

clean_dir_contents() {
  local dir="$1"
  [[ -n "${dir}" ]] || die "clean_dir_contents: empty path"

  mkdir -p -- "${dir}"

  local resolved_dir resolved_root
  resolved_dir="$(realpath -- "${dir}")"
  resolved_root="$(realpath -- "${REPO_ROOT}")"
  if [[ "${resolved_dir}" == "/" || "${resolved_dir}" == "${resolved_root}" ]]; then
    die "refusing to clean unsafe dir: ${resolved_dir}"
  fi

  find "${resolved_dir}" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
}

resolve_built_package_files() {
  local pkg_dir="$1"
  local out_dir="$2"
  local -a package_list=()
  local built_file

  mapfile -t package_list < <(
    cd "${pkg_dir}" && \
    PKGDEST="${out_dir}" \
    MAKEFLAGS="${MAKEPKG_MAKEFLAGS}" \
    DLAGENTS=("${MAKEPKG_DLAGENTS[@]}") \
    makepkg --packagelist
  )

  for built_file in "${package_list[@]}"; do
    [[ -f "${built_file}" ]] || continue
    printf '%s\n' "${built_file}"
  done
}

publish_incrementally() {
  local repo="$1"
  local pkg_name="$2"
  shift 2
  local -a built_files=("$@")
  local -a cmd=("${ACCESS_OS_PUBLISH_HELPER}")

  [[ "${ACCESS_OS_INCREMENTAL_PUBLISH}" == "1" ]] || return 0

  if [[ "${#built_files[@]}" -eq 0 ]]; then
    die "incremental publish requested for ${pkg_name}, but no built package files were found"
  fi

  if [[ "${ACCESS_OS_INCREMENTAL_NO_PUSH}" == "1" ]]; then
    cmd+=(--no-push)
  fi

  cmd+=(--publish-package "${repo}" --)

  echo "    publishing built package(s) for ${pkg_name} to ${repo}"
  "${cmd[@]}" "${built_files[@]}"
}

if [[ "${CLEAN_BEFORE_BUILD}" == "1" ]]; then
  if [[ "${STAGE_ONLY}" != "1" ]]; then
    clean_dir_contents "${DIST_DIR}"
  fi
  clean_dir_contents "${SITE_DIR}"
fi

mkdir -p "${DIST_DIR}/${CORE_REPO}/${ARCH}" "${DIST_DIR}/${EXTRA_REPO}/${ARCH}"
mkdir -p "${SITE_DIR}/${CORE_REPO}/os/${ARCH}" "${SITE_DIR}/${EXTRA_REPO}/os/${ARCH}"
mkdir -p "${WORK_ROOT}"
touch "${SITE_DIR}/.nojekyll"

# Bootstrap empty repo DBs so that incremental publishes during the build
# always have a valid DB for every repo (including repos with no packages yet).
# The final create_repo_db calls at the end of this script overwrite these with
# the real content.
for _bootstrap_repo in "${CORE_REPO}" "${EXTRA_REPO}"; do
  _bootstrap_dist="${DIST_DIR}/${_bootstrap_repo}/${ARCH}"
  _bootstrap_site="${SITE_DIR}/${_bootstrap_repo}/os/${ARCH}"
  if [[ ! -f "${_bootstrap_dist}/${_bootstrap_repo}.db.tar.gz" ]]; then
    tar -czf "${_bootstrap_dist}/${_bootstrap_repo}.db.tar.gz" --files-from /dev/null
    tar -czf "${_bootstrap_dist}/${_bootstrap_repo}.files.tar.gz" --files-from /dev/null
    cp -f "${_bootstrap_dist}/${_bootstrap_repo}.db.tar.gz" "${_bootstrap_site}/${_bootstrap_repo}.db"
    cp -f "${_bootstrap_dist}/${_bootstrap_repo}.files.tar.gz" "${_bootstrap_site}/${_bootstrap_repo}.files"
  fi
done
unset _bootstrap_repo _bootstrap_dist _bootstrap_site

if [[ "${STAGE_ONLY}" != "1" ]]; then
  work_dir="$(mktemp -d "${WORK_ROOT%/}/rebuild.XXXXXXXX")"
  ACCESS_OS_MANIFEST_CACHE="${work_dir}/desired-manifest.json"
  export ACCESS_OS_MANIFEST_CACHE
fi

load_skip_manifests

build_core() {
  local out_dir="${DIST_DIR}/${CORE_REPO}/${ARCH}"
  local -a pkgbuilds=()
  local pkg_dir pkg_name
  local -a built_files=()

  if [[ -d "${REPO_ROOT}/packages/core" ]]; then
    while IFS= read -r -d '' pkgbuild; do
      pkgbuilds+=("${pkgbuild}")
    done < <(find "${REPO_ROOT}/packages/core" -mindepth 2 -maxdepth 2 -type f -name PKGBUILD -print0 | sort -z)
  fi

  if [[ "${#pkgbuilds[@]}" -eq 0 ]]; then
    echo "Info: no core PKGBUILDs found under packages/core/*/PKGBUILD"
    return 0
  fi

  echo "Building ${#pkgbuilds[@]} core package(s)..."
  for pkgbuild in "${pkgbuilds[@]}"; do
    pkg_dir="$(cd -- "$(dirname -- "${pkgbuild}")" && pwd)"
    pkg_name="$(basename -- "${pkg_dir}")"
    echo "  - ${pkg_dir}"

    if should_skip_core_pkgbuild "${pkg_dir}" "${out_dir}"; then
      continue
    fi

    (
      cd "${pkg_dir}" && \
      PKGDEST="${out_dir}" \
      MAKEFLAGS="${MAKEPKG_MAKEFLAGS}" \
      DLAGENTS=("${MAKEPKG_DLAGENTS[@]}") \
      makepkg --syncdeps --noconfirm --clean --cleanbuild --needed
    )

    mapfile -t built_files < <(resolve_built_package_files "${pkg_dir}" "${out_dir}")
    publish_incrementally "${CORE_REPO}" "${pkg_name}" "${built_files[@]}"
  done
}

read_extra_list() {
  aur_read_extra_packages_file "${EXTRA_LIST_FILE}"
}

build_extra() {
  local out_dir="${DIST_DIR}/${EXTRA_REPO}/${ARCH}"
  local aur_root="${work_dir}/aur"
  mkdir -p "${aur_root}"

  mapfile -t pkgs < <(read_extra_list)
  if [[ "${#pkgs[@]}" -eq 0 ]]; then
    echo "Info: no AUR packages listed in ${EXTRA_LIST_FILE}"
    return 0
  fi

  # Some AUR packages depend on other AUR-only packages. Since makepkg --syncdeps
  # can only install dependencies from pacman repos, we optionally install
  # certain built packages into the build environment to satisfy later builds.
  local -a install_after_build_pkgs=(
    lib32-unixodbc
    openssl-1.0
    python3-memoizedb
    python3-xcgf
    samba-support
    system76-power
  )

  should_install_after_build() {
    local name="$1"
    local p
    for p in "${install_after_build_pkgs[@]}"; do
      [[ "${name}" == "${p}" ]] && return 0
    done
    return 1
  }

  recv_pgp_key() {
    local key="$1"
    gpg --batch --keyserver hkps://keyserver.ubuntu.com --recv-keys "${key}" >/dev/null 2>&1 && return 0
    gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys "${key}" >/dev/null 2>&1 && return 0
    return 1
  }

  import_pgp_keys() {
    local pkg_dir="$1"
    local -a keys=()

    if [[ -f "${pkg_dir}/.SRCINFO" ]]; then
      mapfile -t keys < <(awk -F' = ' '$1 == "validpgpkeys" {print $2}' "${pkg_dir}/.SRCINFO" | sed 's/[[:space:]]//g' | awk 'NF')
    fi

    if [[ "${#keys[@]}" -eq 0 ]]; then
      return 0
    fi

    echo "    importing PGP key(s) from .SRCINFO: ${keys[*]}"
    for key in "${keys[@]}"; do
      if recv_pgp_key "${key}"; then
        echo "    imported PGP key: ${key}"
      else
        echo "Warning: failed to import PGP key ${key}; build may fail" >&2
      fi
    done
  }

makepkg_with_pgp_retry() {
    local pkg_dir="$1"
    local pkg_name="$2"
    shift 2
    local -a makepkg_flags=("$@")
    local max_attempts=2
    local attempt=1

    while true; do
      local log_file rc
      log_file="$(mktemp "${work_dir%/}/makepkg.${pkg_name}.XXXXXX.log")"

      set +e
      (
        cd "${pkg_dir}" && \
        PKGDEST="${out_dir}" \
        MAKEFLAGS="${MAKEPKG_MAKEFLAGS}" \
        DLAGENTS=("${MAKEPKG_DLAGENTS[@]}") \
        makepkg "${makepkg_flags[@]}"
      ) 2>&1 | tee "${log_file}"
      rc="${PIPESTATUS[0]}"
      set -e

      if [[ "${rc}" -eq 0 ]]; then
        rm -f -- "${log_file}"
        return 0
      fi

      local -a missing_keys=()
      mapfile -t missing_keys < <(grep -ioE 'unknown public key [0-9a-f]+' "${log_file}" | awk '{print $4}' | sort -u)
      rm -f -- "${log_file}"

      if [[ "${#missing_keys[@]}" -eq 0 || "${attempt}" -ge "${max_attempts}" ]]; then
        return "${rc}"
      fi

      echo "    makepkg failed due to missing PGP key(s): ${missing_keys[*]}"
      local imported_any=0
      for key in "${missing_keys[@]}"; do
        if recv_pgp_key "${key}"; then
          echo "    imported PGP key: ${key}"
          imported_any=1
        else
          echo "Warning: failed to import PGP key ${key}" >&2
        fi
      done

      if [[ "${imported_any}" -ne 1 ]]; then
        return "${rc}"
      fi

      attempt="$((attempt + 1))"
    done
  }

  echo "Building ${#pkgs[@]} AUR package(s)..."
  local pkgbuilds_save_dir="${PKGBUILDS_DIR}"
  local -a built_files=()
  mkdir -p "${pkgbuilds_save_dir}"
  for pkg in "${pkgs[@]}"; do
    echo "  - ${pkg}"
    local pkg_dir="${aur_root}/${pkg}"
    local pkg_source_dir=""

    if should_skip_extra_package "${pkg}" "${out_dir}"; then
      continue
    fi

    if ! pkg_source_dir="$(aur_resolve_extra_package_source_dir "${pkg}")"; then
      die "${pkg} is missing from both $(aur_curated_extra_dir "${pkg}") and $(aur_pkgbuild_snapshot_dir "${pkg}") (use ./scripts/promote-extra-package.sh or ./scripts/import-aur-snapshots.sh)"
    fi

    echo "    using packaging source: ${pkg_source_dir}"
    copy_packaging_snapshot "${pkg_source_dir}" "${pkg_dir}"

    import_pgp_keys "${pkg_dir}"
    local -a makepkg_flags=(--syncdeps --noconfirm --clean --cleanbuild --needed)
    if [[ "${pkg}" == "mkinitcpio-firmware" ]]; then
      makepkg_flags=(--nodeps --noconfirm --clean --cleanbuild --needed)
    fi
    makepkg_with_pgp_retry "${pkg_dir}" "${pkg}" "${makepkg_flags[@]}"
    mapfile -t built_files < <(resolve_built_package_files "${pkg_dir}" "${out_dir}")

    copy_packaging_snapshot "${pkg_dir}" "${pkgbuilds_save_dir}/${pkg}"
    publish_incrementally "${EXTRA_REPO}" "${pkg}" "${built_files[@]}"

    if should_install_after_build "${pkg}"; then
      echo "    installing built package into build environment: ${pkg}"
      if [[ "${#built_files[@]}" -eq 0 ]]; then
        die "failed to determine built package file(s) for ${pkg}"
      fi
      sudo pacman -U --noconfirm "${built_files[@]}"
    fi
  done
}

create_repo_db() {
  local repo="$1"
  local repo_dir="$2"
  local pages_dir="$3"

  mkdir -p "${pages_dir}"

  (
    cd "${repo_dir}"

    shopt -s nullglob
    for f in *.pkg.tar.*; do
      [[ "${f}" == *.sig ]] && continue
      if [[ "${f}" == *:* ]]; then
        new="${f//:/.}"
        if [[ -e "${new}" ]]; then
          die "cannot rename ${f} -> ${new}: destination already exists"
        fi
        mv -f -- "${f}" "${new}"
      fi
    done
    shopt -u nullglob

    shopt -s nullglob
    local -a pkgs=()
    for f in *.pkg.tar.*; do
      [[ "${f}" == *.sig ]] && continue
      pkgs+=("${f}")
    done
    shopt -u nullglob

    if [[ "${#pkgs[@]}" -gt 0 ]]; then
      repo-add -R "${repo}.db.tar.gz" "${pkgs[@]}"
    else
      echo "Info: ${repo} has no packages yet; creating empty repo DB"
      tar -czf "${repo}.db.tar.gz" --files-from /dev/null
      tar -czf "${repo}.files.tar.gz" --files-from /dev/null
    fi

    # GitHub Pages doesn't preserve symlinks, so publish real files named
    # <repo>.db and <repo>.files (containing the tarball payloads).
    cp -f "${repo}.db.tar.gz" "${pages_dir}/${repo}.db"
    cp -f "${repo}.files.tar.gz" "${pages_dir}/${repo}.files"
  )
}

local_repo_versions_from_db() {
  local repo="$1"
  local repo_dir="$2"
  local db_file="${repo_dir}/${repo}.db.tar.gz"
  local tmpdir json

  [[ -f "${db_file}" ]] || die "missing local repo DB for ${repo}: ${db_file}"

  mkdir -p "${WORK_ROOT}"
  tmpdir="$(mktemp -d "${WORK_ROOT%/}/local-manifest.XXXXXXXX")"
  json='{}'

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

build_manifest_from_local_dbs() {
  local core_json extra_json

  core_json="$(local_repo_versions_from_db "${CORE_REPO}" "${DIST_DIR}/${CORE_REPO}/${ARCH}")"
  extra_json="$(local_repo_versions_from_db "${EXTRA_REPO}" "${DIST_DIR}/${EXTRA_REPO}/${ARCH}")"

  jq -n \
    --argjson core "${core_json}" \
    --argjson extra "${extra_json}" \
    --arg core_repo "${CORE_REPO}" \
    --arg extra_repo "${EXTRA_REPO}" \
    '{
      version: 1,
      repos: {
        ($core_repo): { packages: $core },
        ($extra_repo): { packages: $extra }
      }
    }' | jq -S .
}

if [[ "${STAGE_ONLY}" == "1" ]]; then
  echo "Stage-only mode: skipping package builds and reusing dist/ outputs."
else
  build_core
  build_extra
fi

create_repo_db "${CORE_REPO}" "${DIST_DIR}/${CORE_REPO}/${ARCH}" "${SITE_DIR}/${CORE_REPO}/os/${ARCH}"
create_repo_db "${EXTRA_REPO}" "${DIST_DIR}/${EXTRA_REPO}/${ARCH}" "${SITE_DIR}/${EXTRA_REPO}/os/${ARCH}"

if [[ "${STAGE_ONLY}" == "1" ]]; then
  build_manifest_from_local_dbs >"${SITE_DIR}/manifest.json"
else
  "${REPO_ROOT}/scripts/gen-manifest.sh" >"${SITE_DIR}/manifest.json"
fi

{
  echo "Built at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Commit: $(git -C "${REPO_ROOT}" rev-parse HEAD)"
  fi
} >"${SITE_DIR}/BUILD_INFO.txt"

echo "Done."
echo "  dist/: ${DIST_DIR}"
echo "  site/: ${SITE_DIR}"
