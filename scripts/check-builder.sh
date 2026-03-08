#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: check-builder.sh

Verify that the local Arch Linux system is ready to run
`scripts/publish-local.sh`.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
elif [[ $# -gt 0 ]]; then
  echo "Error: unknown argument: $1" >&2
  usage >&2
  exit 1
fi

failures=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

check_cmd() {
  local cmd="$1"
  if command -v "${cmd}" >/dev/null 2>&1; then
    pass "command available: ${cmd}"
  else
    fail "missing command: ${cmd}"
  fi
}

for cmd in git curl jq gh makepkg repo-add; do
  check_cmd "${cmd}"
done

if grep -Eq '^[[:space:]]*\[multilib\]' /etc/pacman.conf; then
  pass "multilib enabled in /etc/pacman.conf"
else
  fail "multilib is not enabled in /etc/pacman.conf"
fi

if gh auth status >/dev/null 2>&1; then
  pass "GitHub CLI authentication is active"
else
  fail "GitHub CLI is not authenticated; run: gh auth login"
fi

if [[ "${failures}" -ne 0 ]]; then
  exit 1
fi
