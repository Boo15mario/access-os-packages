# Stage-Only Recovery Design

**Date:** 2026-03-15

## Goal

Allow already-built package artifacts in `dist/` to be reused for metadata staging and publishing without forcing a full rebuild, and fix the rebuild wrapper hang caused by conflicting EXIT traps.

## Problems

1. A long local build can finish producing package files in `dist/` while failing or hanging before `site/` metadata is staged.
2. `scripts/rebuild.sh` currently installs two EXIT traps separately, which means the later trap overwrites the earlier one.
3. `scripts/publish-local.sh --publish-only` expects `site/` to already exist, which makes recovery awkward when only `dist/` is complete.

## Design

### `scripts/rebuild.sh`

Add `--stage-only` mode:
- skip package builds
- reuse existing `dist/` outputs
- regenerate repo databases in `site/`
- regenerate `manifest.json` and `BUILD_INFO.txt`

Fix EXIT handling by using one combined cleanup trap that stops the sudo keepalive and removes the temp work dir.

### `scripts/publish-local.sh`

Improve `--publish-only` behavior:
- if package artifacts exist but `site/` is missing or incomplete, regenerate staging automatically via `scripts/rebuild.sh --stage-only`
- then continue with release uploads and Pages publication

## Recommendation

This is the right recovery path because it preserves finished package builds, avoids redoing expensive work like `wine-stable`, and makes local publishing tolerant of staging interruptions.
