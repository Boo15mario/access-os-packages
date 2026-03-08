# Builder Bootstrap Script Design

**Date:** 2026-03-07

## Goal

Add a minimal helper script that installs the required Arch Linux packages needed to build and publish the Access OS package repositories locally.

## Scope

The script should only install packages. It should not:

- edit `/etc/pacman.conf`
- enable `multilib`
- configure GitHub authentication
- modify Git configuration
- publish packages

Those remain explicit manual setup steps documented in the README.

## Behavior

Create `scripts/bootstrap-builder.sh` with the following behavior:

- install the minimum package set using `sudo pacman -S --needed`
- support `--help`
- support `--dry-run`
- fail clearly on unknown arguments
- print the exact package list before installing

## Minimum package set

- `base-devel`
- `git`
- `curl`
- `jq`
- `pacman-contrib`
- `devtools`
- `github-cli`

## Documentation

Update the README to reference the new script as the primary install path, while still showing the equivalent package list for transparency.

## Recommendation

Keep this script intentionally small. It should be a convenience wrapper around the documented package list, not a full workstation provisioning tool.
