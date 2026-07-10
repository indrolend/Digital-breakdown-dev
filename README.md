# Digital Breakdown Dev

A dependency-free personal control center for quickly accessing, building, downloading, and testing Digital Breakdown from the latest GitHub state.

## Runtime

- Plain HTML
- Plain CSS
- Plain JavaScript
- No package manager
- No build step
- Intended for Cloudflare Pages

## Cloudflare Pages

Connect this repository through **Workers & Pages → Create application → Pages → Import an existing Git repository**.

Use:

- Production branch: `main`
- Framework preset: `None`
- Build command: `exit 0`
- Build output directory: `/`

Every push to `main` will deploy automatically.

## Current scope

The first version is a thin personal control surface. It links directly to the authoritative game repository, GitHub Actions workflows, artifacts, and browser demo. It does not clone, build, or store a second copy of the game source.
