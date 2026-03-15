# Adaptive Makepkg Jobs Design

**Date:** 2026-03-15

## Goal

Add repo-local makepkg job control so builds default to an adaptive job count based on available CPU and RAM, while still allowing an explicit override.

## Behavior

`scripts/rebuild.sh` should support `MAKEPKG_JOBS` with these modes:

- explicit integer value: use that exact `-j` count
- `auto`: calculate a job count automatically
- unset: behave as `auto`

## Auto mode

Auto mode should calculate jobs conservatively as:

- detect CPU cores with `nproc`
- detect total RAM from `/proc/meminfo`
- compute a RAM cap as `floor(total_ram_gb / 2)`
- choose the smaller of:
  - CPU core count
  - RAM cap
  - hard cap `15`
- minimum job count is `1`

This keeps large package builds from overcommitting memory while still using available CPU.

## Scope

- implement calculation in `scripts/rebuild.sh`
- pass the chosen value to all makepkg invocations via `MAKEFLAGS=-jN`
- document the default behavior and override examples in `README.md`

## Recommendation

Keep this logic repo-local and transparent. Print the chosen job count at build start so the operator can see what the script decided.
