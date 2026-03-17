#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

show_menu() {
  cat <<'EOF'

  access-os-packages — repo management

  1) Full publish          Build all packages and publish to GitHub
  2) Build only            Build packages without publishing
  3) Publish only          Publish existing build outputs
  4) Dry run               Show what would be built (no changes)
  5) Sync AUR mirror       Clone/fetch upstream AUR repos
  6) Check updates         Run nvchecker upstream update report
  7) Preflight check       Verify builder system is ready
  8) Bootstrap builder     Install required build packages
  9) Stage only            Regenerate repo DBs from existing dist/
  10) Update core packages  Check GitHub for new versions of core packages
  q) Quit

EOF
}

run() {
  echo ""
  echo ">>> $*"
  echo ""
  "$@"
}

while true; do
  show_menu
  read -rp "  Choose [1-10, q]: " choice
  case "${choice}" in
    1) run "${SCRIPT_DIR}/publish.sh" ;;
    2) run "${SCRIPT_DIR}/publish.sh" --build-only ;;
    3) run "${SCRIPT_DIR}/publish.sh" --publish-only ;;
    4) run "${SCRIPT_DIR}/build.sh" --dry-run ;;
    5) run "${SCRIPT_DIR}/sync-aur-mirror.sh" ;;
    6) run "${SCRIPT_DIR}/check-upstream-updates.sh" ;;
    7) run "${SCRIPT_DIR}/check-builder.sh" ;;
    8) run "${SCRIPT_DIR}/bootstrap-builder.sh" ;;
    9) run "${SCRIPT_DIR}/build.sh" --stage-only ;;
    10) run "${SCRIPT_DIR}/update-core-packages.sh" ;;
    q|Q) exit 0 ;;
    *) echo "  Invalid choice." ;;
  esac
done
