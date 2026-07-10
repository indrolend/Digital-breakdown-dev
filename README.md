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

## Source-of-truth rule

`digital-breakdown-apk/main` is authoritative. This repository stores only the control interface and generated outputs tied to explicit commit SHAs.
