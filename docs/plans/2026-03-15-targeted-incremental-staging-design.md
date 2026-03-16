# Targeted Incremental Staging Design

**Date:** 2026-03-15

## Goal

Reduce incremental publish noise and cost by restaging only the repo metadata affected by the newly built package, instead of rerunning full `--stage-only` staging after every successful build.

## Problems

1. Incremental publish currently calls `scripts/rebuild.sh --stage-only` after each successful package.
2. `--stage-only` recreates both repo databases from the full `dist/` tree.
3. That produces repeated `repo-add` warnings for already indexed packages and slows down incremental publish.
4. The current behavior is correct but unnecessarily expensive.

## Approaches

### 1. Keep full `--stage-only` restaging
- Minimal code.
- Correct but noisy and slow.
- Does not address the operator problem.

### 2. Restage only the affected repo from current `dist/`
- Update only `access-os-core` or `access-os-extra` depending on the package that just finished.
- Regenerate `manifest.json` and `BUILD_INFO.txt`.
- Leave the unaffected repo DB/files untouched.
- Good balance of correctness and simplicity.

### 3. Mutate only the DB entry for the new package
- Smallest amount of work per package.
- More fragile and harder to reason about than rebuilding the one affected repo DB from `dist/`.

## Recommendation

Use approach 2.

That keeps the current single source of truth (`dist/`), avoids special-case DB mutation logic, and cuts the incremental publish cost down to the affected repo only.

## Design

### `scripts/publish-local.sh`

Add a targeted staging helper for incremental publish mode:
- accept repo name as input
- rebuild only that repo's DB/files from `dist/<repo>/<arch>`
- regenerate `site/manifest.json`
- refresh `site/BUILD_INFO.txt`

This helper should share the same repo-add logic as the full staging path where possible.

### `scripts/rebuild.sh`

No behavior change for full builds or `--stage-only` recovery.

It should keep calling the incremental publish hook after successful package builds. The hook implementation in `publish-local.sh` becomes cheaper.

### Recovery behavior

Keep `./scripts/rebuild.sh --stage-only` unchanged for full restaging and recovery.

Targeted staging is only for normal incremental publish mode.

## Expected outcome

After a package builds successfully:
- only the affected repo DB/files are regenerated
- `manifest.json` is refreshed
- Pages publish remains correct
- repeated `repo-add` warnings for unrelated packages go away
