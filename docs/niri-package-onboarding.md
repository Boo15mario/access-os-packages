# Niri Package Onboarding

This document tracks the package work needed to support the Access OS Niri desktop profile.

## Decisions Already Made

- GNOME uses `gdm`
- Niri uses `greetd` + `waygreet`
- the Niri compositor package is `niri-git`
- `access-launcher` is the default launcher for the Niri profile
- the Niri-specific helper packages should be added to `access-os-extra` first

## Packages To Add

Create package directories under `packages/extra/` for:

- `waynotify`
- `niri-sounds`
- `waygreet`
- `xdg-chooser`
- `wayclip`
- `wayvol`
- `waytray`
- `soundthemed`

## Why These Belong In `access-os-extra`

These are curated upstream third-party packages rather than Access OS-owned packages. They are best added to `access-os-extra` first and can be reconsidered later if one becomes foundational enough for `access-os-core`.

## Per-Package Packaging Checklist

For each package:

- [ ] create `packages/extra/<pkgname>/PKGBUILD`
- [ ] create `.SRCINFO`
- [ ] verify `depends`, `makedepends`, `optdepends`, `provides`, and `conflicts`
- [ ] confirm installed binary names and paths
- [ ] confirm whether a package should install one binary or multiple binaries
- [ ] test `makepkg -si` or equivalent clean build locally
- [ ] verify package installs on a clean Access OS test environment

## Package-Specific Notes

### `waynotify`
Expected role:
- notification daemon for the Niri desktop

Expected runtime needs from upstream docs:
- Python
- GTK 3
- gtk-layer-shell
- at-spi2-core
- D-Bus session support
- Python bindings including GObject and dasbus

Integration note:
- should likely autostart in the Niri session
- only one notification daemon should own the freedesktop notifications name

### `niri-sounds`
Expected role:
- event sounds for Niri session events

Expected runtime needs from upstream docs:
- Python
- `sox`

Integration note:
- likely started from Niri config via `spawn-at-startup`

### `waygreet`
Expected role:
- accessibility-first greeter for `greetd`

Expected runtime needs from upstream docs:
- `greetd`
- GTK4
- libadwaita
- gtk4-layer-shell
- `cage`
- Orca
- PipeWire

Integration note:
- package alone is not enough; Access OS also needs `greetd` config and likely a default `waygreet` config

### `xdg-chooser`
Expected role:
- accessible default application chooser

Expected runtime needs from upstream docs:
- GTK4

Integration note:
- likely user-invoked app, not an autostart daemon

### `wayclip`
Expected role:
- clipboard history manager for Wayland with daemon + client

Expected runtime needs from upstream docs:
- GTK4
- SQLite
- `wl-clipboard`

Integration note:
- daemon should likely autostart in the Niri session
- client should be bound to a keybinding

### `wayvol`
Expected role:
- accessible volume mixer

Expected runtime needs from upstream docs:
- GTK4
- libadwaita
- WirePlumber
- PipeWire
- `wpctl`
- `pw-dump`
- a `pactl` provider / pulse compatibility layer

Integration note:
- likely user-invoked from a keybinding or launcher

### `waytray`
Expected role:
- accessible tray window with daemon + client architecture

Expected runtime needs from upstream docs:
- GTK4
- GStreamer
- D-Bus session support
- `pactl` provider for some modules

Integration note:
- daemon should likely autostart in the Niri session
- client should be launched from a keybinding or launcher

### `soundthemed`
Expected role:
- freedesktop sound theme daemon for desktop/system events

Expected runtime needs from upstream docs:
- PipeWire (`pw-play`)
- udev
- installed sound theme assets
- possibly `gsettings-desktop-schemas` depending on runtime assumptions

Integration note:
- likely autostart in the Niri session or via a user service

## Repo Update Checklist

After adding the package directories:

- [ ] add all new package names to `packages/extra.list`
- [ ] run `./scripts/check-builder.sh`
- [ ] run `./scripts/publish.sh --preflight`
- [ ] run `./scripts/publish.sh` when ready
- [ ] verify packages appear in repo metadata and GitHub Releases

## Installer Coordination Checklist

These package changes should be coordinated with installer work:

- [ ] update `access-os-installer/profiles/niri.txt`
- [ ] ensure the profile uses `niri-git`
- [ ] ensure the profile uses `greetd` + `waygreet`, not `gdm`
- [ ] include `access-launcher`
- [ ] add finalized helper package names after packaging is complete

## Additional Package Notes

### `google-cloud-cli`
Added as an additional `access-os-extra` package using the maintained AUR multi-package PKGBUILD. This package base also defines related split packages such as:

- `google-cloud-cli-bq`
- `google-cloud-cli-gsutil`
- `google-cloud-cli-bundled-python3-unix`
- `google-cloud-cli-component-gke-gcloud-auth-plugin`

For now, `packages/extra.list` includes the base package name `google-cloud-cli`.

## Nice Follow-Up Docs

Once the packages exist, add a short integration document that answers:

- which Niri helper daemons autostart
- which apps get keybindings by default
- which components are required for the first supported Niri release
- which packages are optional later polish
