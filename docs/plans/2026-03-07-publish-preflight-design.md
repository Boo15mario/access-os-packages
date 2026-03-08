# Publish Preflight Integration Design

**Date:** 2026-03-07

## Goal

Integrate builder readiness checks into `scripts/publish-local.sh` and extend the readiness checks to verify that the required builder packages are installed.

## Scope

### `scripts/check-builder.sh`

Add installed-package validation for the minimum builder package set:

- `base-devel`
- `git`
- `curl`
- `jq`
- `pacman-contrib`
- `devtools`
- `github-cli`

The script should continue checking:

- required commands
- `multilib`
- GitHub CLI authentication

### `scripts/publish-local.sh`

Add a `--preflight` flag with this behavior:

- run `scripts/check-builder.sh`
- exit immediately with its result
- do not build or publish anything

Also run the same preflight check automatically at the start of a normal publish flow.

## Recommendation

Keep `scripts/check-builder.sh` as the single source of truth for builder readiness. `scripts/publish-local.sh` should delegate to it rather than duplicating checks.
