# Sudo Keepalive Design

**Date:** 2026-03-15

## Goal

Allow long local package builds to prompt for the sudo password at most once, instead of failing or re-prompting in the middle of a build when `sudo pacman -U` is needed.

## Scope

Implement sudo timestamp initialization and keepalive inside `scripts/rebuild.sh` so it applies to both:

- direct `scripts/rebuild.sh` usage
- `scripts/publish-local.sh`, which delegates to `rebuild.sh`

## Behavior

At the start of a real build:

- validate sudo credentials once with `sudo -v`
- start a background keepalive loop using `sudo -n true`
- stop the keepalive loop automatically on exit

Do not do this in `--dry-run` mode.

## Recommendation

Keep the logic in `scripts/rebuild.sh` and leave `publish-local.sh` as an orchestrator. That avoids duplicated sudo/session handling.
