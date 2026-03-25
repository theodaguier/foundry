# Desktop Releases

This repository ships signed desktop installers and Tauri updater artifacts through GitHub Releases.

## Release flow

1. Push to `main`.
2. `.github/workflows/release.yml` runs `release-please`, updates versions, merges the release PR, and publishes a GitHub Release.
3. `.github/workflows/desktop-release.yml` triggers on the published release.
4. Native jobs build:
   - `macos-14` for `aarch64-apple-darwin`
   - `macos-13` for `x86_64-apple-darwin`
   - `windows-latest` for `x86_64-pc-windows-msvc`
5. The workflow signs/notarizes the binaries, generates updater artifacts and signatures, writes `latest.json`, then uploads everything to the GitHub Release.

The first version containing the updater must still be installed manually. Auto-update starts working from the next release onward.

## Release assets

Every desktop release is expected to contain:

- `Foundry_<version>_darwin_aarch64.dmg`
- `Foundry_<version>_darwin_aarch64.app.tar.gz`
- `Foundry_<version>_darwin_aarch64.app.tar.gz.sig`
- `Foundry_<version>_darwin_x86_64.dmg`
- `Foundry_<version>_darwin_x86_64.app.tar.gz`
- `Foundry_<version>_darwin_x86_64.app.tar.gz.sig`
- `Foundry_<version>_windows_x86_64-setup.exe`
- `Foundry_<version>_windows_x86_64-setup.exe.sig`
- `Foundry_<version>_windows_x86_64.msi`
- `Foundry_<version>_windows_x86_64.msi.sig`
- `latest.json`

`latest.json` is the static Tauri updater manifest served from:

- `https://github.com/theodaguier/foundry/releases/latest/download/latest.json`

## Required GitHub secrets

### Tauri updater signing

- `TAURI_SIGNING_PRIVATE_KEY`
- `TAURI_SIGNING_PRIVATE_KEY_PASSWORD` (optional if the key has no password)

Generate the keypair once:

```bash
npm run tauri signer generate -- --ci -w ~/.tauri/foundry.key
```

Commit the public key into `src-tauri/tauri.conf.json`. Store the private key content in `TAURI_SIGNING_PRIVATE_KEY`.

### macOS signing and notarization

- `APPLE_CERTIFICATE`
- `APPLE_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_API_ISSUER`
- `APPLE_API_KEY`
- `APPLE_API_PRIVATE_KEY`

Expected formats:

- `APPLE_CERTIFICATE`: base64-encoded `.p12`
- `APPLE_API_PRIVATE_KEY`: raw `.p8` file content

### Windows signing

- `WINDOWS_CERTIFICATE`
- `WINDOWS_CERTIFICATE_PASSWORD`

Expected format:

- `WINDOWS_CERTIFICATE`: base64-encoded `.pfx`

## Certificate rotation

### Windows certificate

1. Export the new `.pfx` certificate.
2. Base64-encode it.
3. Update `WINDOWS_CERTIFICATE`.
4. Update `WINDOWS_CERTIFICATE_PASSWORD`.
5. Replace `REPLACE_WITH_WINDOWS_CERTIFICATE_THUMBPRINT` in `src-tauri/tauri.windows.conf.json` with the new thumbprint if you want the repo config to match the imported certificate.

The desktop release workflow also derives the runtime thumbprint from the imported certificate before building signed installers.

### Apple certificate

1. Export a new Developer ID Application certificate as `.p12`.
2. Base64-encode it.
3. Update `APPLE_CERTIFICATE`.
4. Update `APPLE_CERTIFICATE_PASSWORD`.
5. If the notarization API key changes, update `APPLE_API_ISSUER`, `APPLE_API_KEY`, and `APPLE_API_PRIVATE_KEY`.

## Smoke checklist

After each release:

1. Confirm the GitHub Release contains all expected assets and `latest.json`.
2. Download the macOS `.dmg` on Apple Silicon and Intel hardware.
3. Download the Windows NSIS `.exe`.
4. Install the updater-enabled build manually on each platform.
5. Publish the next patch release.
6. Open the installed app and confirm `Settings > General > App updates` shows the new version.
7. Install the update from inside the app and confirm the relaunch succeeds.
