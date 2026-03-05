# AUR & Custom Packages

Packages that were in `packages.x86_64` but are **not in the official Arch repos**. These require either a custom repo, AUR helper, or manual building to include in the ISO.

## Custom Package

| Package | Description |
|---------|-------------|
| `access-os-installer` | Custom Access OS installer. Not in AUR or official repos. Must be built and hosted in a custom repo. |

## AUR Packages

| Package | Description |
|---------|-------------|
| `aic94xx-firmware` | Firmware for the Adaptec SAS AIC94xx driver. AUR: `aic94xx-firmware` |
| `ast-firmware` | Aspeed VGA firmware (IPMI). AUR: `ast-firmware` |
| `neofetch` | CLI system information tool. Removed from official repos (upstream archived). AUR: `neofetch` |
| `mkinitcpio-firmware` | Optional firmware bundle (via deps) for the default linux kernel to suppress 'Possibly missing firmware' warnings. AUR: `mkinitcpio-firmware` |
| `reiserfsprogs` | Reiserfs utilities. Removed from official repos. AUR: `reiserfsprogs` |
| `upd72020x-fw` | Renesas uPD720201 / uPD720202 USB 3.0 chipset firmware. AUR: `upd72020x-fw` |
| `wd719x-firmware` | Firmware for Western Digital WD719x SCSI cards. AUR: `wd719x-firmware` |

## Replaced Package

| Package | Replacement | Description |
|---------|-------------|-------------|
| `p7zip` | `7zip` (official `extra` repo) | 7-Zip file archiver. `p7zip` was dropped from official repos; the upstream `7zip` package is now in `extra`. |
| `rpi-imager-bin` | `rpi-imager` (official `extra` repo) | Raspberry Pi Imager. `rpi-imager-bin` is not in AUR; use the official `rpi-imager` package. |
| `python-vdf` | `python-vdf` (official `extra` repo) | Valve Data Format Python library. It is in official repos (not AUR), so it should not be in the AUR build list. |
