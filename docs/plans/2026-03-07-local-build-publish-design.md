# Local Arch Build and Publish Design

**Date:** 2026-03-07

## Goal

Move `access-os-packages` from GitHub-hosted package building to a local Arch Linux build-and-publish workflow, while retaining GitHub Actions as a validation layer that checks repository health, script correctness, and publishing assumptions.

## Summary

The repository should stop relying on GitHub-hosted Arch containers to build AUR and Access OS packages. Package building and publishing should happen on the user's own Arch Linux system. GitHub remains the distribution surface:

- **GitHub Releases** stores built package files (`*.pkg.tar.*`)
- **GitHub Pages** serves repository metadata (`.db`, `.files`, `manifest.json`, `BUILD_INFO.txt`)
- **GitHub Actions** validates the repo and scripts but does not perform the full package build

This change reduces build fragility, makes AUR and custom package handling realistic, and keeps automation where it is useful.

## Why this change

The current GitHub Actions model is a poor fit for this package set:

- AUR packages regularly hit transient source and network failures
- DKMS and firmware-related packages are expensive and environment-sensitive
- long builds provide poor observability in Actions
- local package overrides and custom sources are easier to manage on a real Arch system
- GitHub runners are not the desired long-term trusted build environment

A local Arch builder is the correct primary system for this repo.

## Desired workflow

### Local machine responsibilities

The local Arch system becomes the authoritative build host.

The operator runs one local publish workflow that:

1. builds `access-os-core` and `access-os-extra`
2. generates pacman repository databases and site metadata
3. uploads package files to GitHub Releases
4. publishes the site payload used by GitHub Pages
5. commits updated `pkgbuilds/` snapshots and removed-AUR metadata
6. optionally pushes the repo changes to GitHub

### GitHub responsibilities

GitHub is retained for hosting and validation only.

- **Releases**: package assets
- **Pages**: repo metadata and manifest
- **Actions**: syntax, manifest, update detection, and repository sanity checks

## Minimum local system requirements

The local Arch builder should install, at minimum:

- `base-devel`
- `git`
- `curl`
- `jq`
- `pacman-contrib`
- `devtools`
- `github-cli`

Recommended but not strictly required:

- `ccache`
- `reflector`
- `rsync`

System configuration requirements:

- `multilib` enabled in `/etc/pacman.conf`
- a GitHub login configured via `gh auth login`
- enough disk space for AUR builds, package caches, and temporary work trees

## Script design

### Keep `scripts/rebuild.sh`

`rebuild.sh` already owns the core build logic and output layout. It should remain the build engine.

### Add `scripts/publish-local.sh`

A new script should orchestrate the full local publish flow.

Responsibilities:

- validate required commands are installed
- validate GitHub auth is available
- optionally validate `multilib` is enabled
- call `scripts/rebuild.sh`
- ensure release tags exist for both repos
- upload built package artifacts to the matching moving GitHub release tags
- stage the `site/` content for Pages publication
- commit `pkgbuilds/` and `metadata/` if they changed
- optionally push Git changes

The script should support flags such as:

- `--build-only`
- `--publish-only`
- `--no-push`
- `--skip-commit`

This keeps manual recovery practical when a long build already succeeded.

## GitHub Pages publishing

Pages should continue to serve the generated `site/` content, but publication should no longer depend on a full package-build workflow.

Preferred implementation:

- maintain a dedicated Pages publishing workflow triggered by changes to a staged Pages branch or published artifact path
- or use a local script that pushes generated site content to a Pages branch/worktree

Given the current repo setup, the simplest path is to let the local machine update a tracked publishing location that Actions can deploy to Pages without rebuilding packages.

## GitHub Actions design

The existing build workflow should be converted into validation-only CI.

### What Actions should still do

- run `bash -n` over maintained shell scripts
- run `scripts/check-updates.sh` in a validation-safe mode
- run `scripts/sync-removed-from-aur.sh`
- validate workflow YAML and required repository files
- verify package list formatting and duplicate detection
- optionally run `scripts/rebuild.sh --dry-run`

### What Actions should stop doing

- building packages in Docker
- uploading package files to GitHub Releases
- publishing package metadata produced from GitHub-hosted builds

## Failure model

### Local publish failures

If package build or upload fails locally, the operator can inspect the real Arch environment directly and retry only the required step.

### CI failures

CI failures should mean one of the following:

- a script is syntactically broken
- package metadata is inconsistent
- a listed package is missing without a valid fallback
- publishing assumptions are invalid

That is a better use of CI than acting as the primary builder.

## Documentation changes

The README should be updated to explain:

- the local build-and-publish model
- minimum required packages on the Arch builder
- GitHub auth requirements
- release and Pages publishing flow
- what Actions still validates

## Recommendation

Implement the local builder/publisher now and demote Actions to validation-only CI. This matches the actual package set, reduces operational fragility, and gives the operator direct control over the Arch build environment.
