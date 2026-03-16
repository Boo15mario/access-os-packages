# Batched AUR Queries Design

**Date:** 2026-03-16

## Goal

Reduce AUR RPC traffic by replacing one-request-per-package behavior with batched `type=info` requests that cover many package names at once.

## Problems

1. `scripts/gen-manifest.sh` currently queries the AUR once per package.
2. `scripts/sync-removed-from-aur.sh` also queries the AUR once per package.
3. On a large package list, this creates enough HTTP requests to trigger AUR rate limiting.
4. The current logic is correct but too chatty.

## Approaches

### 1. Keep per-package requests
- Simple but causes the current failure.
- Not acceptable.

### 2. Batch package names into AUR RPC `arg[]` requests
- Best fit.
- Same API, far fewer requests.
- Minimal behavior change outside the query path.

### 3. Add a persistent local AUR cache
- Stronger optimization.
- More complexity than needed to solve the immediate problem.

## Recommendation

Use approach 2.

## Design

### Shared batch query pattern

For a list of package names:
- group them into batches of reasonable size
- send one AUR RPC `type=info` request per batch with repeated `arg[]=` values
- parse the JSON results into a local package->version/presence map
- process package decisions from that map without further HTTP requests

### `scripts/gen-manifest.sh`

Replace the per-package AUR RPC loop with:
- read all package names
- batch query them
- for each requested package:
  - if present in results, use returned version
  - if absent, apply current fallback/missing logic

### `scripts/sync-removed-from-aur.sh`

Use the same batch lookup approach:
- batch query all listed packages
- treat present packages as normal AUR packages
- treat absent packages as removed and apply current fallback logic

### Failure behavior

- If a batch request fails, fail the overall operation rather than silently treating all packages in that batch as missing.
- Keep existing fallback rules unchanged.

## Expected outcome

Both manifest generation and removed-AUR sync will make a small number of AUR RPC requests per run instead of dozens, greatly reducing the chance of HTTP 429 responses.
