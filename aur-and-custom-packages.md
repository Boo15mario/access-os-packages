# AUR & Custom Packages

Packages that were in `packages.x86_64` but are **not in the official Arch repos**. These require either a custom repo, AUR helper, or manual building to include in the ISO.

## Custom Package

| Package | Description |
|---------|-------------|
| `access-os-installer` | Custom Access OS installer. Not in AUR or official repos. Must be built and hosted in a custom repo. |

## AUR Packages

| Package | Description |
|---------|-------------|
| `neofetch` | CLI system information tool. Removed from official repos (upstream archived). AUR: `neofetch` |
| `mkinitcpio-firmware` | Optional firmware for the default linux kernel to suppress 'Possibly missing firmware' warnings. AUR: `mkinitcpio-firmware` |
| `reiserfsprogs` | Reiserfs utilities. Removed from official repos. AUR: `reiserfsprogs` |

## Replaced Package

| Package | Replacement | Description |
|---------|-------------|-------------|
| `p7zip` | `7zip` (official `extra` repo) | 7-Zip file archiver. `p7zip` was dropped from official repos; the upstream `7zip` package is now in `extra`. |

