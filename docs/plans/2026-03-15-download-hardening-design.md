# Build Download Hardening Design

**Date:** 2026-03-15

## Goal

Make local package builds more resilient to intermittent upstream TLS and transfer failures without requiring the operator to change system-wide `makepkg.conf`.

## Problem

Some upstream hosts used by AUR packages, such as `xyne.dev`, intermittently fail during `curl`-based source downloads with errors such as:

- `TLS connect error`
- `unexpected eof while reading`

These failures are often transient and may succeed on retry or with HTTP/1.1.

## Scope

Patch `scripts/rebuild.sh` so that all `makepkg` source downloads use a controlled `DLAGENTS` override that:

- forces `curl` to HTTP/1.1
- follows redirects
- retries failed downloads
- resumes partial downloads when possible
- remains local to this repository's build flow

Update the README to document that local builds use hardened download settings to reduce flaky source-download failures.

## Recommendation

Use a `DLAGENTS` array override passed to `makepkg` invocations inside `scripts/rebuild.sh`, rather than editing `/etc/makepkg.conf`.
