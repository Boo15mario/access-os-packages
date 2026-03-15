#!/usr/bin/env bash
set -euo pipefail

die() {
  echo "Error: $*" >&2
  exit 1
}

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: rebuild.sh [--dry-run]

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
  CLEAN_BEFORE_BUILD  1=enabled (default), 0=disabled
EOF
}

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
elif [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
elif [[ $# -gt 0 ]]; then
  die "unknown argument: $1"
fi

if [[ "$(id -u)" -eq 0 ]]; then
  die "do not run as root (makepkg refuses to run as root)"
fi

ARCH="${ARCH:-x86_64}"
CORE_REPO="${CORE_REPO:-access-os-core}"
EXTRA_REPO="${EXTRA_REPO:-access-os-extra}"
EXTRA_LIST_FILE="${EXTRA_LIST_FILE:-${REPO_ROOT}/package-lists/access-os-extra.txt}"
DIST_DIR="${DIST_DIR:-${REPO_ROOT}/dist}"
SITE_DIR="${SITE_DIR:-${REPO_ROOT}/site}"
WORK_ROOT="${WORK_ROOT:-${REPO_ROOT}/work}"
CLEAN_BEFORE_BUILD="${CLEAN_BEFORE_BUILD:-1}"
DOWNLOAD_HTTP_RETRIES="${DOWNLOAD_HTTP_RETRIES:-5}"
DOWNLOAD_HTTP_RETRY_DELAY="${DOWNLOAD_HTTP_RETRY_DELAY:-3}"

MAKEPKG_DLAGENTS=(
  "https::/usr/bin/curl --http1.1 -qgLC - --retry ${DOWNLOAD_HTTP_RETRIES} --retry-delay ${DOWNLOAD_HTTP_RETRY_DELAY} --retry-all-errors --fail -o %o %u"
  "http::/usr/bin/curl --http1.1 -qgLC - --retry ${DOWNLOAD_HTTP_RETRIES} --retry-delay ${DOWNLOAD_HTTP_RETRY_DELAY} --retry-all-errors --fail -o %o %u"
  "ftp::/usr/bin/curl --http1.1 -qgLC - --retry ${DOWNLOAD_HTTP_RETRIES} --retry-delay ${DOWNLOAD_HTTP_RETRY_DELAY} --retry-all-errors --fail -o %o %u"
)

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
  exit 0
fi

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

if [[ "${CLEAN_BEFORE_BUILD}" == "1" ]]; then
  clean_dir_contents "${DIST_DIR}"
  clean_dir_contents "${SITE_DIR}"
fi

mkdir -p "${DIST_DIR}/${CORE_REPO}/${ARCH}" "${DIST_DIR}/${EXTRA_REPO}/${ARCH}"
mkdir -p "${SITE_DIR}/${CORE_REPO}/os/${ARCH}" "${SITE_DIR}/${EXTRA_REPO}/os/${ARCH}"
mkdir -p "${WORK_ROOT}"
touch "${SITE_DIR}/.nojekyll"

work_dir="$(mktemp -d "${WORK_ROOT%/}/rebuild.XXXXXXXX")"
cleanup() {
  rm -rf -- "${work_dir}"
}
trap cleanup EXIT

build_core() {
  local out_dir="${DIST_DIR}/${CORE_REPO}/${ARCH}"
  local -a pkgbuilds=()

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
    echo "  - ${pkg_dir}"
    (cd "${pkg_dir}" && PKGDEST="${out_dir}" makepkg --syncdeps --noconfirm --clean --cleanbuild --needed)
  done
}

read_extra_list() {
  [[ -f "${EXTRA_LIST_FILE}" ]] || return 0

  while IFS= read -r line; do
    pkg="${line%%#*}"
    pkg="${pkg#"${pkg%%[![:space:]]*}"}"
    pkg="${pkg%"${pkg##*[![:space:]]}"}"
    [[ -z "${pkg}" ]] && continue
    printf '%s\n' "${pkg}"
  done <"${EXTRA_LIST_FILE}"
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

  aur_package_exists() {
    local pkg="$1"
    local aur_json

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

    [[ -n "${aur_json}" ]] || return 2
    [[ "$(jq -r '.resultcount // 0' <<<"${aur_json}")" != "0" ]]
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

  save_pkgbuild_snapshot() {
    local pkg_dir="$1"
    local save_dir="$2"
    local item

    rm -rf -- "${save_dir}"
    mkdir -p -- "${save_dir}"

    (
      cd "${pkg_dir}"
      shopt -s dotglob nullglob
      for item in * .*; do
        case "${item}" in
          .|..|.git|src|pkg) continue ;;
        esac
        case "${item}" in
          *.pkg.tar.*|*.src.tar.*|*.log) continue ;;
        esac
        cp -a -- "${item}" "${save_dir}/"
      done
    )
  }

  echo "Building ${#pkgs[@]} AUR package(s)..."
  local pkgbuilds_save_dir="${REPO_ROOT}/pkgbuilds"
  mkdir -p "${pkgbuilds_save_dir}"
  for pkg in "${pkgs[@]}"; do
    echo "  - ${pkg}"
    local pkg_dir="${aur_root}/${pkg}"

    # Only use a saved snapshot when the package is actually gone from AUR.
    # Network or transient clone failures should still fail the build.
    if ! git clone --depth 1 "https://aur.archlinux.org/${pkg}.git" "${pkg_dir}"; then
      echo "  Warning: failed to clone ${pkg} from AUR" >&2

      local aur_exists_rc
      set +e
      aur_package_exists "${pkg}"
      aur_exists_rc="$?"
      set -e

      if [[ "${aur_exists_rc}" -eq 0 ]]; then
        die "failed to clone ${pkg} from AUR even though it still exists"
      fi
      if [[ "${aur_exists_rc}" -eq 2 ]]; then
        die "failed to query AUR after clone failure for ${pkg}"
      fi
      if [[ -d "${pkgbuilds_save_dir}/${pkg}" && -f "${pkgbuilds_save_dir}/${pkg}/PKGBUILD" ]]; then
        echo "    Using saved snapshot from pkgbuilds/${pkg}" >&2
        mkdir -p "${pkg_dir}"
        cp -r "${pkgbuilds_save_dir}/${pkg}/." "${pkg_dir}/"
      else
        die "${pkg} is unavailable from AUR and no saved fallback exists"
      fi
    fi

    import_pgp_keys "${pkg_dir}"
    local -a makepkg_flags=(--syncdeps --noconfirm --clean --cleanbuild --needed)
    if [[ "${pkg}" == "mkinitcpio-firmware" ]]; then
      makepkg_flags=(--nodeps --noconfirm --clean --cleanbuild --needed)
    fi
    makepkg_with_pgp_retry "${pkg_dir}" "${pkg}" "${makepkg_flags[@]}"

    save_pkgbuild_snapshot "${pkg_dir}" "${pkgbuilds_save_dir}/${pkg}"

    if should_install_after_build "${pkg}"; then
      echo "    installing built package into build environment: ${pkg}"
      local -a package_list=()
      local -a built_files=()
      local built_file
      mapfile -t package_list < <(
        cd "${pkg_dir}" && \
        PKGDEST="${out_dir}" \
        DLAGENTS=("${MAKEPKG_DLAGENTS[@]}") \
        makepkg --packagelist
      )
      for built_file in "${package_list[@]}"; do
        [[ -f "${built_file}" ]] || continue
        built_files+=("${built_file}")
      done
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

build_core
build_extra

create_repo_db "${CORE_REPO}" "${DIST_DIR}/${CORE_REPO}/${ARCH}" "${SITE_DIR}/${CORE_REPO}/os/${ARCH}"
create_repo_db "${EXTRA_REPO}" "${DIST_DIR}/${EXTRA_REPO}/${ARCH}" "${SITE_DIR}/${EXTRA_REPO}/os/${ARCH}"

"${REPO_ROOT}/scripts/gen-manifest.sh" >"${SITE_DIR}/manifest.json"

{
  echo "Built at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if git -C "${REPO_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Commit: $(git -C "${REPO_ROOT}" rev-parse HEAD)"
  fi
} >"${SITE_DIR}/BUILD_INFO.txt"

echo "Done."
echo "  dist/: ${DIST_DIR}"
echo "  site/: ${SITE_DIR}"
