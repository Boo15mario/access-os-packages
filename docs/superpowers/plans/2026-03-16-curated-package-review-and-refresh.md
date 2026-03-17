# Curated Package Review and Refresh Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add review-first workflows for curated `packages/extra/` packages so one-package refresh, all-package review, and uncurated promotion-candidate reporting are explicit and safe.

**Architecture:** Build on the existing mirror-aware helper layer and curated package structure by adding two focused maintenance scripts: one for single-package review/apply and one for repo-wide review/reporting. Reuse normalized packaging snapshots for all comparisons so operator decisions are based on packaging inputs rather than raw checkout noise.

**Tech Stack:** Bash, git, diff, find, makepkg

---

## File Structure

**Create:**
- `scripts/refresh-extra-package.sh` — review and optionally apply mirror updates for one curated package
- `scripts/review-extra-packages.sh` — summary/diff/report tool for all curated packages and uncurated promotion candidates
- `docs/superpowers/plans/2026-03-16-curated-package-review-and-refresh.md` — this plan

**Modify:**
- `scripts/lib/aur-packaging.sh` — add small helpers for listing curated extra packages and normalized temp comparisons if needed
- `README.md` — document refresh/review workflows
- `packages/extra/README.md` — document refresh vs promote expectations
- `scripts/promote-extra-package.sh` — optionally align messaging with the new refresh flow
- `scripts/diff-extra-package-upstream.sh` — optionally reuse shared comparison helpers if code duplication appears

**Verification commands used throughout:**
- `bash -n scripts/lib/aur-packaging.sh scripts/refresh-extra-package.sh scripts/review-extra-packages.sh scripts/promote-extra-package.sh scripts/diff-extra-package-upstream.sh`
- `./scripts/refresh-extra-package.sh niri-git`
- `./scripts/review-extra-packages.sh`
- `./scripts/review-extra-packages.sh --uncurated`
- `git diff --check`

## Chunk 1: Shared listing/comparison helpers

### Task 1: Extend shared packaging helpers for curated review workflows

**Files:**
- Modify: `scripts/lib/aur-packaging.sh`
- Test: shell syntax and helper-driven smoke checks

- [ ] **Step 1: Add curated package enumeration helpers**

Add helpers such as:
- `aur_list_curated_extra_packages`
- optionally `aur_package_exists_in_transition_list <pkg>`
- optionally a helper to create normalized temp snapshots for diffing two package roots

Keep them small and responsibility-focused.

- [ ] **Step 2: Reuse existing copy rules for all comparisons**

If a shared temp-snapshot comparison helper reduces duplication between scripts, add it here instead of re-implementing temp-dir logic in multiple places.

- [ ] **Step 3: Verify shell syntax**

Run: `bash -n scripts/lib/aur-packaging.sh`
Expected: exits `0`

- [ ] **Step 4: Smoke-test helper output**

Run a simple command using the helper layer to list curated extra packages and confirm it includes current curated packages such as `niri-git`.

- [ ] **Step 5: Commit helper updates**

```bash
git add scripts/lib/aur-packaging.sh
git commit -m "Add curated package review helpers"
```

## Chunk 2: Single-package refresh workflow

### Task 2: Add `scripts/refresh-extra-package.sh`

**Files:**
- Create: `scripts/refresh-extra-package.sh`
- Modify: `scripts/diff-extra-package-upstream.sh` if shared logic should be reused

- [ ] **Step 1: Implement default review mode**

Create `scripts/refresh-extra-package.sh <pkg>` to:
- require a package name
- verify `packages/extra/<pkg>/` exists
- verify `~/aur-mirror/<pkg>/` exists
- compare normalized packaging snapshots
- print one of:
  - `up-to-date`
  - `changed`
  - `missing-from-mirror`
  - `missing-from-curated`
- show a diff summary in changed cases
- make no filesystem changes by default

- [ ] **Step 2: Add `--apply` mode**

Implement:
- `./scripts/refresh-extra-package.sh --apply <pkg>`

Behavior:
- overwrite `packages/extra/<pkg>/` with the normalized packaging snapshot from the mirror
- preserve packaging-only filter rules
- print a clear message about what changed

- [ ] **Step 3: Keep safety explicit**

Ensure there is no implicit apply path. Default must remain read-only.

- [ ] **Step 4: Verify single-package workflow**

Run:
- `bash -n scripts/refresh-extra-package.sh`
- `./scripts/refresh-extra-package.sh niri-git`
Expected: syntax passes and the script reports a valid status for `niri-git`

- [ ] **Step 5: Commit the single-package refresh tool**

```bash
git add scripts/refresh-extra-package.sh scripts/diff-extra-package-upstream.sh scripts/lib/aur-packaging.sh
git commit -m "Add curated package refresh workflow"
```

## Chunk 3: Repo-wide review workflow

### Task 3: Add `scripts/review-extra-packages.sh` summary mode

**Files:**
- Create: `scripts/review-extra-packages.sh`
- Modify: `scripts/lib/aur-packaging.sh` if needed

- [ ] **Step 1: Implement summary mode**

Create `scripts/review-extra-packages.sh` to:
- iterate all curated packages in `packages/extra/`
- compare each one against the corresponding mirror package
- print a concise one-line status per package:
  - `up-to-date`
  - `changed`
  - `missing-from-mirror`

- [ ] **Step 2: Add `--diff` mode**

Implement `--diff` so changed packages print full normalized diffs after the summary.

- [ ] **Step 3: Keep output operator-friendly**

Summary should be scannable enough for regular use without overwhelming noise.

- [ ] **Step 4: Verify repo-wide review mode**

Run:
- `bash -n scripts/review-extra-packages.sh`
- `./scripts/review-extra-packages.sh`
Expected: exits `0` and reports current curated package status lines

- [ ] **Step 5: Commit the repo-wide review tool**

```bash
git add scripts/review-extra-packages.sh scripts/lib/aur-packaging.sh
git commit -m "Add curated package review dashboard"
```

### Task 4: Add `--uncurated` promotion-candidate reporting

**Files:**
- Modify: `scripts/review-extra-packages.sh`
- Modify: `package-lists/access-os-extra.txt` docs if needed

- [ ] **Step 1: Implement `--uncurated` mode**

Behavior:
- read `package-lists/access-os-extra.txt`
- list packages that are not yet in `packages/extra/`
- report whether they exist in:
  - mirror only
  - mirror + `pkgbuilds/`
  - neither

- [ ] **Step 2: Keep this mode read-only**

It should report promotion candidates only, not automatically promote them.

- [ ] **Step 3: Verify uncurated reporting**

Run: `./scripts/review-extra-packages.sh --uncurated`
Expected: exits `0` and prints transition-list packages not yet curated

- [ ] **Step 4: Ensure mode flags behave sensibly**

Define and verify whether `--uncurated --diff` is allowed or rejected; document the behavior clearly.

- [ ] **Step 5: Commit the uncurated review mode**

```bash
git add scripts/review-extra-packages.sh package-lists/access-os-extra.txt
git commit -m "Add uncurated package review mode"
```

## Chunk 4: Documentation and workflow alignment

### Task 5: Document refresh/review workflows

**Files:**
- Modify: `README.md`
- Modify: `packages/extra/README.md`
- Modify: `scripts/promote-extra-package.sh` help text if needed

- [ ] **Step 1: Update top-level workflow docs**

Document:
- single-package refresh review flow
- all-package review flow
- uncurated package review flow
- continued role of `promote-extra-package.sh` for adding packages from the mirror

- [ ] **Step 2: Update `packages/extra/README.md`**

Explain:
- `promote` = add a new curated package
- `refresh` = review/apply upstream changes to an existing curated package
- review-first expectation before `--apply`

- [ ] **Step 3: Align help text and script messaging**

Ensure `promote-extra-package.sh` and `diff-extra-package-upstream.sh` describe their role clearly in the new workflow.

- [ ] **Step 4: Run final verification**

Run:
- `bash -n scripts/lib/aur-packaging.sh scripts/refresh-extra-package.sh scripts/review-extra-packages.sh scripts/promote-extra-package.sh scripts/diff-extra-package-upstream.sh`
- `./scripts/refresh-extra-package.sh niri-git`
- `./scripts/review-extra-packages.sh`
- `./scripts/review-extra-packages.sh --uncurated`
- `git diff --check`
- `git status --short`
Expected:
- syntax checks pass
- review scripts run successfully
- no whitespace errors
- only intended files changed

- [ ] **Step 5: Commit final documentation and cleanup**

```bash
git add README.md packages/extra/README.md scripts
git commit -m "Document curated package review workflows"
```
