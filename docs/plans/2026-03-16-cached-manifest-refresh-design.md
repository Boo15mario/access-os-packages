# Cached Manifest Refresh Design

**Date:** 2026-03-16

## Goal

Avoid repeated AUR RPC queries during incremental publish by reusing a manifest snapshot that is generated once per build run.

## Problems

1. Incremental publish currently refreshes `site/manifest.json` after each package by calling `scripts/gen-manifest.sh`.
2. `scripts/gen-manifest.sh` queries the AUR for every package in `access-os-extra`.
3. During a long incremental run, this causes repeated full-list AUR RPC traffic and triggers rate limiting (`429`).
4. The package build itself is succeeding; the failure is in repeated metadata refresh.

## Approaches

### 1. Keep full manifest regeneration after each package
- Correct but causes AUR rate limits.
- Not acceptable.

### 2. Generate desired manifest once per run and reuse it
- Best fit.
- Build starts with one manifest snapshot.
- Incremental publish reuses that snapshot instead of requerying AUR.
- Full recovery and publish-only flows can still regenerate when needed.

### 3. Stop updating manifest during incremental publish
- Avoids AUR rate limits.
- Leaves Pages metadata behind until the end of the run.
- Conflicts with the current incremental publish goal.

## Recommendation

Use approach 2.

## Design

### `scripts/rebuild.sh`

At the start of a normal build run:
- generate the desired manifest once
- store it in a run-scoped file under `work/`
- export the path so incremental publish helpers can reuse it

### `scripts/publish-local.sh`

During incremental publish:
- if a cached manifest path is provided and exists, copy it to `site/manifest.json`
- do not call `scripts/gen-manifest.sh` in that path

For `--publish-only` and recovery flows:
- keep the current ability to regenerate `site/manifest.json` from `scripts/gen-manifest.sh`
- this is an occasional operation and does not cause the same repeated-query problem

### Failure behavior

- If the cached manifest is missing during incremental publish, fall back to the current full refresh behavior.
- If the one-time manifest generation at build start fails, fail early before entering the long build loop.

## Expected outcome

A normal long incremental build hits the AUR for manifest generation once, not once per built package, and no longer trips AUR rate limits from metadata refresh alone.
