# Upstream PR Suggestions

## For wayclip (destructatron/wayclip)

The PKGBUILD needs to handle the rusqlite linking issue. Here's a fix:

In `PKGBUILD` or ideally in the source `Cargo.toml`, add bundled sqlite feature:

```toml
# In Cargo.toml or workspace Cargo.toml
[dependencies]
rusqlite = { version = "0.32", features = ["bundled"] }
```

Or as a PKGBUILD fix, add to build():
```bash
build() {
  cd "$pkgname-$pkgver"
  # Create .cargo/config to force linker flags
  mkdir -p .cargo
  cat > .cargo/config.toml << 'EOF'
[build]
rustflags = ["-C", "linker=clang", "-C", "link-args=-Wl,-rpath=/usr/lib"]
EOF
  cargo build --release --workspace
}
```

## For waytray (destructatron/waytray)

Similar linking issue with the ring crate. Fix in Cargo.toml:

```toml
[dependencies]
ring = { version = "0.17", features = ["vendored"] }
```

Or ensure proper LDFLAGS during build.

## Testing

These fixes should be tested on the build environment where the failures occurred:
- wayclip: sqlite linking
- waytray: ring crypto library linking