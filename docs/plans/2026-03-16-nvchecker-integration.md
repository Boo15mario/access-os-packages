# NVChecker Integration Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `nvchecker`-style update tracking for both local/custom packages and the AUR package list, while keeping the existing build/publish system unchanged.

**Architecture:** Introduce centralized `nvchecker` configuration under `metadata/nvchecker/`, a new update-check script that produces JSON/Markdown reports, and a dedicated scheduled GitHub Actions workflow for update tracking. Existing build and publish scripts remain the source of truth for package production.

**Tech Stack:** Bash, nvchecker, jq, GitHub Actions, .SRCINFO/PKGBUILD parsing

---

## Chunk 1: Add update-tracking configuration

### Task 1: Define config layout

**Files:**
- Create: `metadata/nvchecker/local.toml`
- Create: `metadata/nvchecker/aur.toml`
- Modify/Create: helper metadata files as needed

- [ ] Define centralized config for local/custom package upstream tracking.
- [ ] Define centralized config or generated mapping for AUR package tracking.
- [ ] Keep config readable and reviewable.

## Chunk 2: Add update-check script

### Task 2: Implement update reporting

**Files:**
- Create: `scripts/check-upstream-updates.sh`
- Modify: supporting scripts/files as needed

- [ ] Run `nvchecker` against the centralized config.
- [ ] Resolve current local package versions.
- [ ] Resolve AUR package current/local versions as needed.
- [ ] Generate `metadata/upstream-updates.json`.
- [ ] Generate `metadata/upstream-updates.md`.

## Chunk 3: Add CI workflow

### Task 3: Add scheduled update-report workflow

**Files:**
- Create or modify: `.github/workflows/*`

- [ ] Add a scheduled workflow for update tracking.
- [ ] Install `nvchecker` and required tools.
- [ ] Run the update-check script.
- [ ] Store or publish the generated report.

## Chunk 4: Documentation and verification

### Task 4: Update docs

**Files:**
- Modify: `README.md`

- [ ] Document the purpose of `nvchecker` integration.
- [ ] Document where update-tracking config and reports live.

### Task 5: Verification

**Files:**
- Modify only files from prior tasks

- [ ] Run `bash -n` on the new/changed shell scripts.
- [ ] Validate workflow YAML.
- [ ] Run `git diff --check`.
- [ ] Commit only the intended files.
