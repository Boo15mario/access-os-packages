# Adaptive Makepkg Jobs Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add adaptive makepkg job control with `auto` default behavior capped at 15 and explicit operator overrides.

**Architecture:** `scripts/rebuild.sh` computes a repo-local job count once at startup, exports it through `MAKEFLAGS`, and uses that value for all `makepkg` invocations. `README.md` documents the default behavior and manual overrides.

**Tech Stack:** Bash, makepkg, GNU coreutils, procfs

---

### Task 1: Add job calculation helpers

**Files:**
- Modify: `scripts/rebuild.sh`

**Step 1: Add config variables**

Add environment-driven settings near the top of the script:
- `MAKEPKG_JOBS` defaulting to `auto`
- `MAKEPKG_JOBS_MAX` defaulting to `15`

**Step 2: Add auto-calculation helpers**

Implement helper logic to:
- read CPU core count from `nproc`
- read total RAM from `/proc/meminfo`
- compute RAM-based job cap `floor(total_ram_gb / 2)`
- clamp to min `1`
- clamp to max `MAKEPKG_JOBS_MAX`

**Step 3: Resolve effective jobs**

If `MAKEPKG_JOBS` is `auto`, calculate it.
If it is numeric, validate it and use it directly.
If invalid, fail clearly.

### Task 2: Apply jobs to makepkg calls

**Files:**
- Modify: `scripts/rebuild.sh`

**Step 1: Export or inject makeflags**

Pass `MAKEFLAGS="-j${resolved_jobs}"` into every `makepkg` call.

**Step 2: Print selected jobs**

Echo the resolved job count once near the start of a real build.

### Task 3: Document usage

**Files:**
- Modify: `README.md`

**Step 1: Document default behavior**

Explain that local builds auto-tune makepkg jobs from CPU and RAM and cap at 15.

**Step 2: Document override examples**

Add examples for:
- `MAKEPKG_JOBS=5 ./scripts/rebuild.sh`
- `MAKEPKG_JOBS=8 ./scripts/publish-local.sh`

### Task 4: Verify

**Files:**
- Modify as needed from previous tasks only

**Step 1: Run syntax checks**

Run:
```bash
bash -n scripts/rebuild.sh
bash -n scripts/publish-local.sh
bash -n scripts/check-builder.sh
```

**Step 2: Run dry run**

Run:
```bash
scripts/rebuild.sh --dry-run
```

**Step 3: Check diff formatting**

Run:
```bash
git diff --check
```

**Step 4: Commit**

Run:
```bash
git add scripts/rebuild.sh README.md
git commit -m "Add adaptive makepkg job tuning"
```
