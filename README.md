# Digital Breakdown Dev

A dependency-free personal control center for building, downloading, and testing Digital Breakdown from the latest GitHub state.

## Runtime

- Plain HTML
- Plain CSS
- Plain JavaScript
- No package manager
- No local clone required for normal use
- Hosted with GitHub Pages

## GitHub Pages

Repository settings:

1. **Settings → Pages**
2. Set **Source** to **GitHub Actions**
3. Run **Actions → Deploy GitHub Pages** once

Expected URL:

`https://indrolend.github.io/Digital-breakdown-dev/`

Every push to `main` deploys automatically.

## Published outputs

The authoritative game repository is `indrolend/digital-breakdown-apk`.

Its `Publish Dev Portal` workflow builds and publishes:

- `DigitalBreakdown-Android.apk`
- `DigitalBreakdown-Web.zip`
- `DigitalBreakdown-Research.zip`
- checksums for each download
- `build-info.json`
- the live browser build under `/play/`

Release downloads use the rolling tag `latest-dev`, so the public URLs remain stable while the files are replaced with newer builds.

## One-time cross-repository credential

The private game repository needs permission to update this portal repository.

Create a fine-grained GitHub personal access token restricted to `Digital-breakdown-dev` with:

- **Contents: Read and write**

Add it to `digital-breakdown-apk` under:

**Settings → Secrets and variables → Actions → New repository secret**

Name:

`DEV_PORTAL_TOKEN`

Then run:

**digital-breakdown-apk → Actions → Publish Dev Portal → Run workflow**

The workflow records the exact source commit in `build-info.json` and in the rolling release notes.

## Stable Android updates

A new debug signing key is normally generated on each clean GitHub Actions runner. Android will reject a newer APK if it is signed with a different key than the installed APK.

For repeatable in-place updates, configure these Actions secrets in `digital-breakdown-apk`:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

`ANDROID_KEYSTORE_BASE64` must contain the base64-encoded bytes of one persistent Java keystore. Keep that keystore and its passwords backed up. Every future APK must use the same signing key.

When all four secrets are present, `Publish Dev Portal` creates a release-signed APK. Otherwise, it falls back to a debug APK and records that state in `build-info.json`.

## Source-of-truth rule

`digital-breakdown-apk/main` is authoritative. This repository stores only the control interface and generated outputs tied to explicit commit SHAs.
