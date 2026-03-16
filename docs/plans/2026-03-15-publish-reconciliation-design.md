# Publish Reconciliation Design

**Date:** 2026-03-15

## Goal

Detect and recover from the common case where GitHub Releases has moved forward but GitHub Pages metadata is still behind after a normal local publish run.

## Problems

1. Normal incremental publish updates Releases before Pages.
2. If the run stops between those steps, pacman metadata can lag behind uploaded assets.
3. There is currently no final reconciliation check to prove that Releases and Pages agree.

## Approaches

### 1. Detection only
- Add an end-of-run verification step.
- Fails loudly on mismatch.
- Better visibility, but still leaves manual recovery work.

### 2. Detection plus one automatic Pages retry
- Verify Releases and Pages alignment at the end.
- If mismatched, retry pushing staged `site/` to `gh-pages` once.
- Recheck and fail if still inconsistent.
- Best fit.

### 3. Reverse publish order
- Publish Pages first, then Releases.
- Avoids Releases being ahead.
- Worse operationally because pacman metadata could point at package files that do not exist yet.

## Recommendation

Use approach 2.

Keep the current order, but add a final reconciliation guard and a single automatic Pages retry.

## Design

### Reconciliation checks

At the end of `scripts/publish-local.sh`, verify for the currently indexed packages:
- `site/manifest.json` contains the package version
- the published GitHub Pages repo DB contains the package
- the matching GitHub Release asset exists

The check can focus on the packages present in the local staged manifest rather than every historical asset.

### Recovery behavior

If the first check fails:
- republish the current staged `site/` to `gh-pages`
- rerun the reconciliation check once
- fail loudly if it still does not match

### Scope

This is a publish-time guard only.

It does not change:
- build ordering
- incremental package upload behavior
- package skip logic
- release asset retention policy

## Expected outcome

A normal `./scripts/publish-local.sh` run ends with explicit proof that Releases and Pages agree, and automatically recovers once from the common “asset uploaded, Pages behind” state.
