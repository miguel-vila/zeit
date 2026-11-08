# Build & Installation

## Development

```bash
swift build                           # Build
swift test                            # Run tests
swift run ZeitApp --help              # CLI help
swift run ZeitApp view today          # View today's activities
```

### Toolchain

`.swift-version` records the Swift version this project is built with. Nothing in
SPM or Xcode enforces it — `swift-tools-version` in `Package.swift` is only a
minimum — so `build.sh` warns when the running compiler differs. It matters
because SPM resolves some transitive dependencies differently between versions,
which rewrites `Package.resolved` on every build and compiles a different major
version of a dependency on each machine. The file also serves as the pin for
anyone using swiftly.

## App bundle

Everything that produces an app bundle goes through `build.sh`. Output:
`dist/Zeit.app`.

```bash
# Debug build
./build.sh

# Release build and install to /Applications
./build.sh --release --install
```

### Options

| Flag | Purpose |
|------|---------|
| `--release` | Optimized build |
| `--install` | Install to /Applications |
| `--clean` | Clean build artifacts first |

### Code signing

Every build is signed with the local identity `Zeit Local Signing`, created once
per machine. Without it the build stops and says so, because the alternative —
an ad-hoc signature — makes macOS drop the screen recording and accessibility
grants on every install. The script header says why.

```bash
./scripts/make-signing-cert.sh    # once per machine
```

The certificate is the thing worth keeping: a privacy grant names it, so
recreating it means granting both permissions again. The app is signed for this
machine only and is not distributable; Gatekeeper rejects a self-signed
certificate on any other Mac.

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
| `LOCAL_SIGNING_IDENTITY` | Signing identity (default: `Zeit Local Signing`) |
