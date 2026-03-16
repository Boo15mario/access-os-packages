#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: bootstrap-builder.sh [--dry-run]

Install the minimum Arch Linux packages required to build and publish
`access-os-packages` locally.

Flags:
  --dry-run   Print the install command without running it
  -h, --help  Show this help
EOF
}

PACKAGES=(
  base-devel
  git
  curl
  jq
  nvchecker
  pacman-contrib
  devtools
  github-cli
)

DRY_RUN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

echo "Installing minimum builder packages:"
printf '  - %s\n' "${PACKAGES[@]}"
echo
echo "Command:"
printf '  %q' sudo pacman -S --needed "${PACKAGES[@]}"
echo

if [[ "${DRY_RUN}" -eq 1 ]]; then
  echo
  echo "Dry run only. No packages were installed."
  exit 0
fi

sudo pacman -S --needed "${PACKAGES[@]}"
