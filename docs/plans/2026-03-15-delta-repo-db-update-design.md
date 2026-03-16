# Delta Repo DB Update Design

**Date:** 2026-03-15

## Goal

During incremental publish, update the repo database using only the newly built package files instead of reprocessing every package already present in that repo.

## Problems

1. Targeted staging currently restages only the changed repo, but still runs `repo-add` against every package file in that repo directory.
2. That keeps producing repeated `already existed` warnings for old packages.
3. The current behavior is correct, but it is still noisy and slower than necessary.

## Approaches

### 1. Keep repo-level full reindexing
- Correct and simple.
- Does not solve the operator problem.

### 2. Use delta `repo-add` with only newly built package files
- Best fit.
- Keeps the existing repo DB tarball and updates only the changed package entries.
- Much quieter and faster during incremental publish.

### 3. Replace repo DB generation with custom tar manipulation
- More control, but unnecessary complexity.
- Higher risk than using the standard `repo-add` flow.

## Recommendation

Use approach 2.

Incremental publish already knows which package file(s) were just built. Those should be the only files passed to `repo-add` during the per-package publish path.

## Design

### `scripts/publish-local.sh`

Split staging into two modes:
- full repo staging from `dist/` for recovery / `--publish-only`
- delta repo staging from an explicit package-file list for incremental publish

Delta staging should:
- ensure the repo DB tarballs exist, creating empty ones if needed
- normalize any `:` in incoming filenames the same way the full path does
- run `repo-add -R` with only the provided package files
- refresh the published `.db` and `.files`

### Shared metadata

Keep `site/manifest.json` and `site/BUILD_INFO.txt` refresh behavior unchanged.

### Scope

This change only affects incremental publish mode. Full repo restaging remains available and unchanged for recovery or `--publish-only` flows.

## Expected outcome

After a package like `samba-support` builds successfully, incremental publish updates only the `samba-support` entry in the repo DB instead of reprocessing every package already in `access-os-extra`.
