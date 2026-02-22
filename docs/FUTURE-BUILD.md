# Building Zeit

This document covers building Zeit for local development and for public distribution.

## Quick Reference

```bash
# Debug build
./build.sh

# Release build and install
./build.sh --release --install

# Signed release with DMG
./build.sh --release --sign --dmg

# Signed + notarized release
./build.sh --release --sign --notarize --dmg
```

## Build Modes

### Debug (default)

```bash
./build.sh
```

Fast build for development. Output: `dist/Zeit.app`

### Release

```bash
./build.sh --release --install
```

Optimized build, optionally installed to `/Applications`.

### Signed + Notarized Release

Properly signed and notarized for public distribution. No warnings, fast first launch.

**Requires:**
- Apple Developer account ($99/year)
- Developer ID Application certificate
- App-specific password for notarization

```bash
./build.sh --release --sign --notarize --dmg
```

---

## Code Signing & Notarization

### Why It Matters

| Build Type | Gatekeeper | First Launch | User Experience |
|------------|------------|--------------|-----------------|
| Unsigned | Blocked | N/A | Must right-click → Open |
| Ad-hoc signed (`--`) | Warning | ~8 seconds | "Unidentified developer" warning |
| Developer ID signed | Warning | ~8 seconds | "Downloaded from internet" warning |
| Signed + Notarized | Allowed | Fast | No warnings |

### Prerequisites

#### 1. Apple Developer Account

1. Enroll at [developer.apple.com](https://developer.apple.com/programs/) ($99/year)
2. Wait for approval (usually 24-48 hours)

#### 2. Developer ID Certificate

1. Open **Keychain Access** → Certificate Assistant → Request a Certificate from a Certificate Authority
2. Enter your email, select "Saved to disk"
3. Go to [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates)
4. Create a new certificate: **Developer ID Application**
5. Upload your certificate request, download the certificate
6. Double-click to install in Keychain

Verify it's installed:
```bash
security find-identity -v -p codesigning
# Should show: "Developer ID Application: Your Name (TEAM_ID)"
```

#### 3. App-Specific Password

For notarization, you need an app-specific password (not your Apple ID password):

1. Go to [appleid.apple.com](https://appleid.apple.com/)
2. Sign in → Security → App-Specific Passwords → Generate
3. Name it "Zeit Notarization"
4. Save the password securely

#### 4. Store Credentials

Store your credentials so build scripts can use them:

```bash
# Store notarization credentials in Keychain
xcrun notarytool store-credentials "zeit-notarize" \
  --apple-id "your@email.com" \
  --team-id "YOUR_TEAM_ID" \
  --password "xxxx-xxxx-xxxx-xxxx"
```

Find your Team ID at [developer.apple.com/account](https://developer.apple.com/account) → Membership.

### Environment Variables

Create a `.env.signing` file (git-ignored):

```bash
# .env.signing
DEVELOPER_ID="Developer ID Application: Your Name (TEAM_ID)"
NOTARIZE_PROFILE="zeit-notarize"
```

---

## Build Process Details

### What Happens During Build

1. **Swift build** (`swift build` via SPM)
2. **Create app bundle** (`dist/Zeit.app`)
3. **Code sign** (ad-hoc or Developer ID)
4. **Notarize** (submit to Apple, wait, staple ticket)
5. **Create DMG** (optional)

### Signing Commands (Manual)

If you need to sign manually:

```bash
# Ad-hoc signing (local dev)
codesign --force --deep --sign - dist/Zeit.app

# Developer ID signing (distribution)
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Your Name (TEAM_ID)" \
  --entitlements ZeitApp.entitlements \
  dist/Zeit.app
```

The `--options runtime` flag enables "hardened runtime" which is required for notarization.

### Notarization Commands (Manual)

```bash
# Create a zip for notarization
ditto -c -k --keepParent dist/Zeit.app Zeit.zip

# Submit for notarization
xcrun notarytool submit Zeit.zip \
  --keychain-profile "zeit-notarize" \
  --wait

# Check status (if not using --wait)
xcrun notarytool info <submission-id> \
  --keychain-profile "zeit-notarize"

# View log if rejected
xcrun notarytool log <submission-id> \
  --keychain-profile "zeit-notarize"

# Staple the ticket to the app
xcrun stapler staple dist/Zeit.app

# Verify
spctl -a -v dist/Zeit.app
# Should say: "accepted" and "source=Notarized Developer ID"
```

---

## Entitlements

The `ZeitApp.entitlements` file declares what permissions the app needs:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <!-- Required for notarization with hardened runtime -->
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>

    <!-- Screen recording (declared, but user must grant in System Preferences) -->
    <key>com.apple.security.screen-capture</key>
    <true/>

    <!-- AppleScript for window detection -->
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
```

---

## Troubleshooting

### "App is damaged and can't be opened"

The app was quarantined and Gatekeeper blocked it:
```bash
xattr -cr /Applications/Zeit.app
```

### Notarization rejected

Check the log:
```bash
xcrun notarytool log <submission-id> --keychain-profile "zeit-notarize"
```

Common issues:
- Missing hardened runtime (`--options runtime`)
- Unsigned nested binaries
- Missing entitlements for certain operations

### "Developer cannot be verified"

The app is signed but not notarized. Users can:
1. Right-click → Open → Open anyway
2. Or: System Preferences → Security & Privacy → "Open Anyway"

### Slow first launch

XProtect is scanning the binary. Either:
- Notarize the app (best)
- Clear quarantine: `xattr -cr /path/to/app`

---

## GitHub Actions Setup

This section covers setting up automated signed + notarized builds in GitHub Actions.

### Prerequisites

You need:
1. Apple Developer account with Developer ID Application certificate
2. App-specific password for notarization
3. GitHub repository with Actions enabled

### Step 1: Export Your Certificate

1. Open **Keychain Access**
2. Find your "Developer ID Application" certificate
3. Right-click → Export → save as `Certificates.p12`
4. Set a strong password (you'll need this as a secret)

### Step 2: Configure GitHub Secrets

Go to your repo → Settings → Secrets and variables → Actions → New repository secret

Add these secrets:

| Secret Name | Value | How to Get It |
|-------------|-------|---------------|
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded .p12 | `base64 -i Certificates.p12 \| pbcopy` |
| `APPLE_CERTIFICATE_PASSWORD` | Password for .p12 | The password you set when exporting |
| `APPLE_ID` | Your Apple ID email | e.g., `you@email.com` |
| `APPLE_TEAM_ID` | Your Team ID | [developer.apple.com/account](https://developer.apple.com/account) → Membership |
| `APPLE_APP_PASSWORD` | App-specific password | [appleid.apple.com](https://appleid.apple.com) → Security → App-Specific Passwords |

### Step 3: Create Workflow

Create `.github/workflows/release.yml`:

```yaml
name: Build and Release

on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:  # Allow manual trigger

jobs:
  build:
    runs-on: macos-latest

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Import Apple certificate
        env:
          APPLE_CERTIFICATE_BASE64: ${{ secrets.APPLE_CERTIFICATE_BASE64 }}
          APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
        run: |
          # Create variables
          CERTIFICATE_PATH=$RUNNER_TEMP/certificate.p12
          KEYCHAIN_PATH=$RUNNER_TEMP/app-signing.keychain-db
          KEYCHAIN_PASSWORD=$(openssl rand -base64 32)

          # Decode certificate
          echo -n "$APPLE_CERTIFICATE_BASE64" | base64 --decode -o $CERTIFICATE_PATH

          # Create temporary keychain
          security create-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security set-keychain-settings -lut 21600 $KEYCHAIN_PATH
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH

          # Import certificate
          security import $CERTIFICATE_PATH -P "$APPLE_CERTIFICATE_PASSWORD" \
            -A -t cert -f pkcs12 -k $KEYCHAIN_PATH
          security set-key-partition-list -S apple-tool:,apple: -k "$KEYCHAIN_PASSWORD" $KEYCHAIN_PATH
          security list-keychain -d user -s $KEYCHAIN_PATH

          # Verify
          security find-identity -v -p codesigning $KEYCHAIN_PATH

      - name: Store notarization credentials
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          APPLE_APP_PASSWORD: ${{ secrets.APPLE_APP_PASSWORD }}
        run: |
          xcrun notarytool store-credentials "zeit-notarize" \
            --apple-id "$APPLE_ID" \
            --team-id "$APPLE_TEAM_ID" \
            --password "$APPLE_APP_PASSWORD"

      - name: Build, sign, and notarize
        env:
          DEVELOPER_ID: "Developer ID Application: Your Name (${{ secrets.APPLE_TEAM_ID }})"
          NOTARIZE_PROFILE: "zeit-notarize"
        run: |
          ./build.sh --release --sign --notarize --dmg

      - name: Upload artifacts
        uses: actions/upload-artifact@v4
        with:
          name: zeit-release
          path: |
            dist/Zeit.app
            dist/*.dmg

      - name: Create GitHub Release
        if: startsWith(github.ref, 'refs/tags/')
        uses: softprops/action-gh-release@v1
        with:
          files: dist/*.dmg
          draft: true
          generate_release_notes: true
```

### Step 4: Update DEVELOPER_ID in Workflow

In the workflow above, replace:
```yaml
DEVELOPER_ID: "Developer ID Application: Your Name (${{ secrets.APPLE_TEAM_ID }})"
```

With your actual certificate name. Find it with:
```bash
security find-identity -v -p codesigning
# Shows: "Developer ID Application: Miguel Vila (ABC123XYZ)"
```

### Step 5: Trigger a Build

Either:
- Push a tag: `git tag v1.0.0 && git push --tags`
- Go to Actions → Build and Release → Run workflow

### Workflow Explanation

1. **Import certificate**: Decodes the base64 certificate, creates a temporary keychain, imports the cert
2. **Store notarization credentials**: Creates a keychain profile for `notarytool`
3. **Build**: Runs `build.sh --release --sign --notarize --dmg`
4. **Upload**: Saves artifacts and creates a draft GitHub release

### Security Notes

- The temporary keychain is deleted when the runner terminates
- Secrets are masked in logs
- Use `workflow_dispatch` to test without creating tags
- Draft releases let you review before publishing

### Troubleshooting CI Builds

**"No identity found"**
- Certificate wasn't imported correctly
- Check that `APPLE_CERTIFICATE_BASE64` is the full base64 string (no newlines)
- Verify password is correct

**"Unable to notarize"**
- Check App-Specific Password is valid
- Verify Team ID matches your account
- View notarization log: the workflow should output the submission ID

**"Hardened runtime not enabled"**
- Ensure `--options runtime` is in codesign commands
- Check entitlements.plist exists

### Local Testing of CI Config

Test the certificate import locally:
```bash
# Export your certificate to test.p12 with password "test"
# Then simulate what CI does:

CERT_BASE64=$(base64 -i test.p12)
echo -n "$CERT_BASE64" | base64 --decode -o /tmp/cert.p12

security create-keychain -p "temp" /tmp/test.keychain
security import /tmp/cert.p12 -P "test" -k /tmp/test.keychain -A
security find-identity -v -p codesigning /tmp/test.keychain

# Cleanup
security delete-keychain /tmp/test.keychain
```
