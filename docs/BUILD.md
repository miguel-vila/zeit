# Build & Installation

## Development

```bash
swift build                           # Build
swift test                            # Run tests
swift run ZeitApp --help              # CLI help
swift run ZeitApp view today          # View today's activities
```

## Distribution

All distribution builds go through `build.sh`. Output: `dist/Zeit.app` (macOS app bundle).

```bash
# Debug build
./build.sh

# Release build and install to /Applications
./build.sh --release --install

# Signed release with DMG
./build.sh --release --sign --dmg
```

### Options

| Flag | Purpose |
|------|---------|
| `--release` | Optimized build |
| `--install` | Install to /Applications |
| `--sign` | Code sign (requires `DEVELOPER_ID` env var) |
| `--notarize` | Notarize with Apple (requires `NOTARIZE_PROFILE` env var) |
| `--dmg` | Create DMG installer |
| `--clean` | Clean build artifacts first |

### Code signing

A build with no `--sign` is signed with the local identity `Zeit Local Signing`,
created once per machine by `scripts/make-signing-cert.sh`. Without it the build
falls back to an ad-hoc signature, and macOS then drops the screen recording and
accessibility grants on every install — the script header says why.

```bash
./scripts/make-signing-cert.sh    # once per machine
```

### Debug vs Release

Swift defines the `DEBUG` flag automatically based on build configuration. Several features are gated behind `#if DEBUG` and are only available in debug builds:

- **Menubar debug section** — Force Track, Clear Today's Data, and sampling buttons
- **`--sample` CLI flag** — saves LLM pipeline artifacts (screenshots, prompts, responses) to `~/.local/share/zeit/samples/`

| Build command | `DEBUG` flag | Debug features |
|---------------|-------------|----------------|
| `./build.sh` | Defined | Available |
| `swift build` | Defined | Available |
| `./build.sh --release` | Not defined | Compiled out |
| `swift build -c release` | Not defined | Compiled out |

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `DEVELOPER_ID` | Code signing certificate name |
| `NOTARIZE_PROFILE` | Keychain profile for notarization |
| `LOCAL_SIGNING_IDENTITY` | Identity used when not signing for distribution (default: `Zeit Local Signing`) |
