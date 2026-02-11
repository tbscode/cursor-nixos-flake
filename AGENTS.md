# AGENTS.md

## Project Overview

This is a Nix flake that packages the Cursor IDE AppImage for NixOS. It supports both `x86_64-linux` and `aarch64-linux` architectures.

## File Structure

- `flake.nix` - Main Nix flake definition with Cursor package
- `update-cursor.sh` - Script to update Cursor to a new version (used in CI)

## Key Conventions

- **Never delete comments** in any file
- When editing `flake.nix`, use sed/awk to modify specific lines - never rewrite the entire file
- The update script runs in CI pipelines, so all errors must exit early with non-zero codes

## Flake Structure

The `flake.nix` has these editable fields for version updates:
- `version = "X.Y.Z";` - The Cursor version string
- `sources.x86_64-linux.url` - Download URL for x86_64
- `sources.x86_64-linux.sha256` - Hash for x86_64 AppImage
- `sources.aarch64-linux.url` - Download URL for aarch64
- `sources.aarch64-linux.sha256` - Hash for aarch64 AppImage

## Cursor Download URL Pattern

The Cursor API uses this pattern:
```
https://api2.cursor.sh/updates/download/golden/{arch}/cursor/{version}
```

Where:
- `{arch}` is `linux-x64` or `linux-arm64`
- `{version}` is the version number or `latest`

This redirects to the actual download URL at `downloads.cursor.com`.

## Commands

| Task | Command |
|------|---------|
| Check flake validity | `nix flake check` |
| Build Cursor | `nix build .#cursor` |
| Update to latest version | `./update-cursor.sh` |
| Update to specific version | `./update-cursor.sh 2.3.21` |
| Get SHA256 hash | `nix-prefetch-url --type sha256 <url>` |

## Update Process

1. Get the actual download URL by following the API redirect
2. Fetch SHA256 hashes for both architectures using `nix-prefetch-url`
3. Edit `flake.nix` using sed to update version, URLs, and hashes
4. Run `nix flake check` to verify
5. If any step fails, restore from backup and exit with error

## CI Environment Variables

The update script respects:
- `CI` or `GITHUB_ACTIONS` - Auto-confirms updates when set
- `GITHUB_OUTPUT` - Writes version info for GitHub Actions workflows

