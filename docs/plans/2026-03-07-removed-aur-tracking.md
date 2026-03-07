# Removed AUR Package Tracking Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Automatically track packages that disappear from AUR but continue building from saved `pkgbuilds/` fallbacks, using a canonical JSON registry and a generated text list.

**Architecture:** Add a small metadata layer under `metadata/` and a helper script that reconciles AUR presence against `package-lists/access-os-extra.txt` and available `pkgbuilds/` fallbacks. Reuse the existing “fail on transient errors, fallback only on confirmed absence” policy, and commit the metadata updates during the same workflow that already commits saved `pkgbuilds/`.

**Tech Stack:** Bash, `jq`, existing AUR RPC calls, GitHub Actions, existing `pkgbuilds/` fallback flow.

---

### Task 1: Add metadata files and baseline documentation

**Files:**
- Create: `metadata/removed-from-aur.json`
- Create: `metadata/removed-from-aur.txt`
- Modify: `README.md`
- Modify: `pkgbuilds/README.md`

**Step 1: Create empty metadata files**

Create:
- `metadata/removed-from-aur.json` with `[]`
- `metadata/removed-from-aur.txt` as an empty file

**Step 2: Update docs**

Document:
- what counts as a removed AUR package
- that JSON is canonical
- that TXT is generated
- that packages are removed from the registry if they return to AUR

**Step 3: Verify formatting**

Run:
- `jq . metadata/removed-from-aur.json`

Expected: `[]`

**Step 4: Commit**

Run:
- `git add metadata/removed-from-aur.json metadata/removed-from-aur.txt README.md pkgbuilds/README.md`
- `git commit -m "docs: add removed AUR tracking metadata"`

---

### Task 2: Add a metadata sync helper

**Files:**
- Create: `scripts/sync-removed-from-aur.sh`

**Step 1: Implement reconciliation logic**

The script should:
- read packages from `package-lists/access-os-extra.txt`
- query AUR RPC for each package
- determine:
  - package present in AUR
  - package missing from AUR with fallback in `pkgbuilds/<pkg>/`
  - package missing from AUR without fallback
- update `metadata/removed-from-aur.json`
  - add or refresh entries for confirmed removed packages with fallback
  - remove entries for packages that are back on AUR
- regenerate `metadata/removed-from-aur.txt` from JSON

Fields per JSON entry:
```json
{
  "package": "example-pkg",
  "detected_at": "2026-03-07T00:00:00Z",
  "fallback_path": "pkgbuilds/example-pkg",
  "last_known_version": "1.2.3-1"
}
```

**Step 2: Preserve failure semantics**

The helper must exit non-zero if:
- AUR query fails unexpectedly
- a package is confirmed missing from AUR and no fallback exists

**Step 3: Verify syntax**

Run:
- `bash -n scripts/sync-removed-from-aur.sh`

Expected: no output

**Step 4: Commit**

Run:
- `git add scripts/sync-removed-from-aur.sh`
- `git commit -m "feat: track packages removed from AUR"`

---

### Task 3: Wire metadata sync into manifest/update flow

**Files:**
- Modify: `scripts/gen-manifest.sh`
- Modify: `scripts/check-updates.sh`

**Step 1: Decide invocation point**

Recommended:
- call `scripts/sync-removed-from-aur.sh` from `scripts/check-updates.sh` before manifest comparison

Reason:
- metadata stays fresh on every CI check
- manifest generation remains focused on manifest output

**Step 2: Keep manifest behavior consistent**

Ensure `scripts/gen-manifest.sh` still:
- uses fallback only for confirmed missing AUR packages with saved snapshots
- fails if missing packages have no fallback

**Step 3: Verify**

Run:
- `bash -n scripts/gen-manifest.sh`
- `bash -n scripts/check-updates.sh`

**Step 4: Commit**

Run:
- `git add scripts/gen-manifest.sh scripts/check-updates.sh`
- `git commit -m "feat: sync removed AUR metadata during update checks"`

---

### Task 4: Commit metadata changes from CI

**Files:**
- Modify: `.github/workflows/build-repos.yml`

**Step 1: Extend the existing commit step**

Update the workflow so the step that commits `pkgbuilds/` also stages:
- `metadata/removed-from-aur.json`
- `metadata/removed-from-aur.txt`

**Step 2: Keep commit conditions narrow**

Only commit if there are actual tracked-file changes.

**Step 3: Verify YAML**

Run:
- `python - <<'PY'\nimport yaml\nprint('ok' if yaml.safe_load(open('.github/workflows/build-repos.yml')) is not None else 'bad')\nPY`

Expected: `ok`

**Step 4: Commit**

Run:
- `git add .github/workflows/build-repos.yml`
- `git commit -m "ci: persist removed AUR package metadata"`

---

### Task 5: Add an end-to-end dry verification path

**Files:**
- Modify: `scripts/sync-removed-from-aur.sh` (if needed)

**Step 1: Add testability hooks**

Support environment overrides for:
- AUR RPC base URL (optional)
- metadata output paths (optional)
- package list path (optional)

This allows local dry verification without editing tracked files.

**Step 2: Run focused checks**

Run:
- `bash -n scripts/sync-removed-from-aur.sh`
- `bash -n scripts/gen-manifest.sh`
- `bash -n scripts/check-updates.sh`
- `git diff --check`

**Step 3: Commit**

Run:
- `git add scripts/sync-removed-from-aur.sh scripts/gen-manifest.sh scripts/check-updates.sh`
- `git commit -m "test: make removed AUR sync script easier to verify"`

