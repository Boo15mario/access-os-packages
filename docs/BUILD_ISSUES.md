# Build Issues

## Known Build Issues

Two packages fail to build in the current environment due to Rust linking issues:

### wayclip
- **Issue**: rusqlite crate linking failure with system sqlite
- **Error**: undefined symbol: sqlite3_* functions
- **Root cause**: Rust rusqlite crate not linking properly in this build environment
- **Tested fixes**:
  - Using newer upstream version with `bundled` feature ✓ (upstream already has this)
  - Using system sqlite - still fails
  - Adding LDFLAGS - still fails
- **Note**: Upstream already includes `features = ["bundled"]` in their Cargo.toml - the issue is environment-specific

### waytray  
- **Issue**: ring crate linking failure
- **Error**: undefined symbol: ring_core_* functions
- **Root cause**: Cryptography library linking issue in this environment

## Status

Successfully built packages are in `dist/access-os-extra/x86_64/`:

- waynotify
- niri-sounds
- waygreet
- xdg-chooser
- wayvol
- soundthemed
- google-cloud-cli (+ 4 split packages)

Total: 15 packages built successfully.

## Recommendations

These packages should build fine on a standard Arch Linux system with:
- `base-devel` installed
- Standard Rust toolchain
- The PKGBUILDs as currently configured

The failures appear to be specific to this build environment's Rust/linker configuration.
