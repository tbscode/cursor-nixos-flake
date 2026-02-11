#!/usr/bin/env bash

set -euo pipefail

# Script to manually update Cursor version in the flake
# Usage: ./update-cursor.sh [version]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLAKE_FILE="$SCRIPT_DIR/flake.nix"

# Function to extract version from download URL
extract_version_from_url() {
    local url="$1"
    local version
    version=$(echo "$url" | grep -oP 'Cursor-\K[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    if [[ -n "$version" ]]; then
        echo "$version"
        return 0
    fi
    
    echo "Error: Could not extract version from URL: $url" >&2
    return 1
}

# Function to get latest version from the download page and API
get_latest_version() {
    local page_content
    page_content=$(curl -s "https://cursor.com/download")
    
    if [[ -n "$page_content" ]]; then
        local minor_version
        minor_version=$(echo "$page_content" | tr '<' '\n' | grep -E 'type-md.*2\.[0-9]' | grep -o '[0-9]\+\.[0-9]\+' | head -1)
        
        if [[ -n "$minor_version" ]]; then
            local api_url="https://api2.cursor.sh/updates/download/golden/linux-x64/cursor/$minor_version"
            local actual_url
            actual_url=$(curl -s -I "$api_url" | grep -i location | cut -d' ' -f2 | tr -d '\r\n')
            
            if [[ -n "$actual_url" ]]; then
                local full_version
                full_version=$(extract_version_from_url "$actual_url")
                
                if [[ -n "$full_version" ]]; then
                    echo "$full_version"
                    return 0
                fi
            fi
        fi
    fi
    
    echo "Error: Could not get latest version from download page" >&2
    return 1
}

# Function to get current version from flake.nix
get_current_version() {
    grep -o 'version = "[^"]*"' "$FLAKE_FILE" | head -1 | cut -d'"' -f2
}

# Function to normalize version for comparison (extract major.minor)
normalize_version() {
    echo "$1" | grep -oP '^\K[0-9]+\.[0-9]+'
}

# Function to compare versions (returns 0 if equal, 1 if different)
versions_equal() {
    local v1="$1"
    local v2="$2"
    [[ "$v1" == "$v2" ]]
}

# Function to get download info for a specific architecture
get_download_info() {
    local version="$1"
    local arch="$2"
    local api_arch
    
    if [[ "$arch" == "x86_64-linux" ]]; then
        api_arch="linux-x64"
    else
        api_arch="linux-arm64"
    fi
    
    local api_url="https://api2.cursor.sh/updates/download/golden/$api_arch/cursor/$version"
    local actual_url
    actual_url=$(curl -s -I "$api_url" | grep -i location | cut -d' ' -f2 | tr -d '\r\n')
    
    if [[ -z "$actual_url" ]]; then
        echo "Error: Could not get actual download URL for $arch" >&2
        return 1
    fi
    
    echo "$actual_url"
}

# Function to get version from resolved download URL for a specific architecture
get_version_from_url() {
    local version="$1"
    local arch="$2"
    local api_arch
    
    if [[ "$arch" == "x86_64-linux" ]]; then
        api_arch="linux-x64"
    else
        api_arch="linux-arm64"
    fi
    
    local api_url="https://api2.cursor.sh/updates/download/golden/$api_arch/cursor/$version"
    local actual_url
    actual_url=$(curl -s -I "$api_url" | grep -i location | cut -d' ' -f2 | tr -d '\r\n')
    
    if [[ -z "$actual_url" ]]; then
        echo "Error: Could not get actual download URL for $arch" >&2
        return 1
    fi
    
    local resolved_version
    resolved_version=$(extract_version_from_url "$actual_url")
    
    if [[ -z "$resolved_version" ]]; then
        echo "Error: Could not extract version from resolved URL" >&2
        return 1
    fi
    
    echo "$resolved_version"
}

# Function to escape special characters for sed replacement
escape_sed() {
    printf '%s\n' "$1" | sed -e 's/[\/&]/\\&/g'
}

# Function to update flake.nix using sed
update_flake() {
    local version="$1"
    
    echo "Fetching download URLs for version $version..."
    
    local resolved_version_x64
    local resolved_version_arm64
    resolved_version_x64=$(get_version_from_url "$version" "x86_64-linux") || { echo "Failed to get resolved version for x86_64"; exit 1; }
    resolved_version_arm64=$(get_version_from_url "$version" "aarch64-linux") || { echo "Failed to get resolved version for aarch64"; exit 1; }
    
    if [[ "$resolved_version_x64" != "$resolved_version_arm64" ]]; then
        echo "Warning: Version mismatch between architectures: x86_64=$resolved_version_x64, aarch64=$resolved_version_arm64" >&2
        echo "Using x86_64 version: $resolved_version_x64"
        resolved_version_arm64="$resolved_version_x64"
    fi
    
    local actual_version="$resolved_version_x64"
    
    local x64_url
    local arm64_url
    x64_url=$(get_download_info "$version" "x86_64-linux") || { echo "Failed to get x86_64 URL"; exit 1; }
    arm64_url=$(get_download_info "$version" "aarch64-linux") || { echo "Failed to get aarch64 URL"; exit 1; }
    
    echo "Resolved version: $actual_version"
    echo "x86_64 URL: $x64_url"
    echo "aarch64 URL: $arm64_url"
    
    # Get SHA256 hashes for both architectures
    local x64_sha256
    local arm64_sha256
    
    if command -v nix-prefetch-url >/dev/null 2>&1; then
        echo "Fetching SHA256 for x86_64..."
        x64_sha256=$(nix-prefetch-url --type sha256 "$x64_url") || { echo "Failed to fetch x86_64 hash"; exit 1; }
        echo "Fetching SHA256 for aarch64..."
        arm64_sha256=$(nix-prefetch-url --type sha256 "$arm64_url") || { echo "Failed to fetch aarch64 hash"; exit 1; }
    else
        echo "Error: nix-prefetch-url not found" >&2
        exit 1
    fi
    
    echo "x86_64 SHA256: $x64_sha256"
    echo "aarch64 SHA256: $arm64_sha256"
    
    # Create backup
    cp "$FLAKE_FILE" "$FLAKE_FILE.backup"
    
    # Escape URLs for sed
    local x64_url_escaped
    local arm64_url_escaped
    x64_url_escaped=$(escape_sed "$x64_url")
    arm64_url_escaped=$(escape_sed "$arm64_url")
    
    # Update version (first occurrence only, in the let block) using resolved version
    if ! sed -i "s/^\([[:space:]]*version = \)\"[^\"]*\";/\1\"$actual_version\";/" "$FLAKE_FILE"; then
        echo "Error: Failed to update version" >&2
        cp "$FLAKE_FILE.backup" "$FLAKE_FILE"
        exit 1
    fi
    
    # Update x86_64-linux URL (inside x86_64-linux block)
    if ! sed -i "/x86_64-linux = {/,/};/s|url = \"[^\"]*\";|url = \"$x64_url_escaped\";|" "$FLAKE_FILE"; then
        echo "Error: Failed to update x86_64 URL" >&2
        cp "$FLAKE_FILE.backup" "$FLAKE_FILE"
        exit 1
    fi
    
    # Update x86_64-linux SHA256
    if ! sed -i "/x86_64-linux = {/,/};/s/sha256 = \"[^\"]*\";/sha256 = \"$x64_sha256\";/" "$FLAKE_FILE"; then
        echo "Error: Failed to update x86_64 sha256" >&2
        cp "$FLAKE_FILE.backup" "$FLAKE_FILE"
        exit 1
    fi
    
    # Update aarch64-linux URL (inside aarch64-linux block)
    if ! sed -i "/aarch64-linux = {/,/};/s|url = \"[^\"]*\";|url = \"$arm64_url_escaped\";|" "$FLAKE_FILE"; then
        echo "Error: Failed to update aarch64 URL" >&2
        cp "$FLAKE_FILE.backup" "$FLAKE_FILE"
        exit 1
    fi
    
    # Update aarch64-linux SHA256
    if ! sed -i "/aarch64-linux = {/,/};/s/sha256 = \"[^\"]*\";/sha256 = \"$arm64_sha256\";/" "$FLAKE_FILE"; then
        echo "Error: Failed to update aarch64 sha256" >&2
        cp "$FLAKE_FILE.backup" "$FLAKE_FILE"
        exit 1
    fi
    
    # Verify the updates were applied
    if ! grep -q "version = \"$actual_version\"" "$FLAKE_FILE"; then
        echo "Error: Version update verification failed" >&2
        cp "$FLAKE_FILE.backup" "$FLAKE_FILE"
        exit 1
    fi
    
    if ! grep -q "$x64_sha256" "$FLAKE_FILE"; then
        echo "Error: x86_64 sha256 update verification failed" >&2
        cp "$FLAKE_FILE.backup" "$FLAKE_FILE"
        exit 1
    fi
    
    if ! grep -q "$arm64_sha256" "$FLAKE_FILE"; then
        echo "Error: aarch64 sha256 update verification failed" >&2
        cp "$FLAKE_FILE.backup" "$FLAKE_FILE"
        exit 1
    fi
    
    echo "Updated flake.nix with version $actual_version"
}

# Function to test the flake
test_flake() {
    echo "Testing flake..."
    if command -v nix >/dev/null 2>&1; then
        if ! nix flake check; then
            echo "Error: Flake check failed" >&2
            cp "$FLAKE_FILE.backup" "$FLAKE_FILE"
            exit 1
        fi
        echo "Flake check passed!"
    else
        echo "Warning: nix command not found. Skipping flake check."
    fi
}

# Main logic
main() {
    local target_version="${1:-}"
    
    echo "Cursor Flake Updater"
    echo "==================="
    
    # Get current version
    local current_version
    current_version=$(get_current_version)
    echo "Current version: $current_version"
    
    # Determine target version
    local resolved_target_version
    if [[ -n "$target_version" ]]; then
        echo "Target version: $target_version"
        if [[ "$target_version" =~ ^[0-9]+\.[0-9]+$ ]]; then
            echo "Minor version specified, resolving to latest patch version..."
            resolved_target_version=$(get_version_from_url "$target_version" "x86_64-linux") || { echo "Failed to resolve version"; exit 1; }
            echo "Resolved version: $resolved_target_version"
        else
            resolved_target_version="$target_version"
        fi
    else
        echo "Fetching latest version..."
        resolved_target_version=$(get_latest_version) || { echo "Failed to get latest version"; exit 1; }
        echo "Latest version: $resolved_target_version"
    fi
    
    # Check if update is needed
    if versions_equal "$resolved_target_version" "$current_version"; then
        echo "No update needed. Current version is up to date."
        if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
            echo "CURSOR_VERSION_INFO=no_update" >> "$GITHUB_OUTPUT"
        fi
        exit 0
    fi
    
    echo "Update needed: $current_version -> $resolved_target_version"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        echo "CURSOR_VERSION_INFO=updated:$current_version:$resolved_target_version" >> "$GITHUB_OUTPUT"
    fi
    
    # Check if running in CI/GitHub Actions (auto-confirm)
    if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]]; then
        echo "Running in CI mode, auto-confirming update..."
        REPLY="y"
    else
        read -p "Do you want to proceed with the update? (y/N): " -n 1 -r
        echo
    fi
    
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if [[ -n "$target_version" ]]; then
            update_flake "$target_version"
        else
            local minor_version
            minor_version=$(normalize_version "$resolved_target_version")
            update_flake "$minor_version"
        fi
        test_flake
        echo "Update completed successfully!"
        if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
            echo "CURSOR_VERSION_INFO=completed:$current_version:$resolved_target_version" >> "$GITHUB_OUTPUT"
        fi
        echo "You can now commit the changes:"
        echo "  git add flake.nix"
        echo "  git commit -m \"Update Cursor to version $resolved_target_version\""
    else
        echo "Update cancelled."
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v curl >/dev/null 2>&1; then
        missing_deps+=("curl")
    fi
    
    if ! command -v sed >/dev/null 2>&1; then
        missing_deps+=("sed")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
        exit 1
    fi
}

# Run main function
check_dependencies
main "$@"
