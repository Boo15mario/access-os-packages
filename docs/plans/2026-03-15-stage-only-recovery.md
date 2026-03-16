# Stage-Only Recovery Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reuse existing built artifacts in `dist/` to regenerate staging metadata and publish without rebuilding, while fixing the lingering rebuild wrapper bug.

**Architecture:** `scripts/rebuild.sh` gains a `--stage-only` mode and unified EXIT cleanup. `scripts/publish-local.sh` learns to regenerate staging automatically during `--publish-only` recovery. `README.md` documents the recovery flow.

**Tech Stack:** Bash, makepkg, repo-add, git, gh

---

### Task 1: Add `--stage-only` mode to `scripts/rebuild.sh`

**Files:**
- Modify: `scripts/rebuild.sh`

**Steps:**
1. Extend usage and argument parsing for `--stage-only`.
2. In stage-only mode, skip `build_core` and `build_extra`.
3. Require existing `dist/<repo>/<arch>/` directories before staging.
4. Still run repo DB creation, manifest generation, and `BUILD_INFO.txt` creation.

### Task 2: Fix rebuild cleanup handling

**Files:**
- Modify: `scripts/rebuild.sh`

**Steps:**
1. Replace competing `trap ... EXIT` calls with one combined cleanup function.
2. Ensure both the sudo keepalive and temp work dir are cleaned up on exit.

### Task 3: Improve publish-only recovery

**Files:**
- Modify: `scripts/publish-local.sh`

**Steps:**
1. Detect when `--publish-only` is used and `site/` is missing or incomplete.
2. Automatically run `scripts/rebuild.sh --stage-only` in that case.
3. Preserve existing build-only and publish-only behavior otherwise.

### Task 4: Update docs

**Files:**
- Modify: `README.md`

**Steps:**
1. Document `--publish-only` recovery behavior.
2. Add a direct recovery example using `scripts/rebuild.sh --stage-only`.

### Task 5: Verify

**Files:**
- Modify as needed from previous tasks only

**Steps:**
1. Run `bash -n scripts/rebuild.sh scripts/publish-local.sh`.
2. Run `scripts/rebuild.sh --dry-run`.
3. Run `bash scripts/publish-local.sh --help`.
4. Run `git diff --check`.
5. Commit only the intended files.
