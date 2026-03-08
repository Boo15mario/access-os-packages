# Builder Preflight Check Design

**Date:** 2026-03-07

## Goal

Add a local preflight script that validates whether an Arch Linux machine is ready to run `scripts/publish-local.sh`.

## Scope

The script should check only the prerequisites that are likely to cause a local publish to fail immediately:

- required commands are installed
- `multilib` is enabled in `/etc/pacman.conf`
- GitHub CLI authentication is active

It should not:

- modify the system
- install packages
- enable repositories
- change GitHub auth state

## Behavior

Create `scripts/check-builder.sh` with the following behavior:

- print pass/fail lines for each required check
- exit with status 0 when all checks pass
- exit non-zero when any check fails
- support `--help`

## Required commands

- `git`
- `curl`
- `jq`
- `gh`
- `makepkg`
- `repo-add`

## Recommendation

Keep the script small and deterministic. It should serve as a preflight gate before `scripts/publish-local.sh`, not as a repair tool.
