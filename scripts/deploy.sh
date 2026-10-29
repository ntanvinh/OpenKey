#!/bin/bash
# Build and publish VOpenKey AI with release notes to GitHub Releases, which feeds the LSSoft download link.
set -euo pipefail

cd "$(dirname "$0")/.."

say() {
    printf '==> %s\n' "$*"
}

die() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    local command_name="$1"
    local install_hint="$2"
    if ! command -v "$command_name" >/dev/null 2>&1; then
        printf "Missing required CLI '%s'. %s\n" "$command_name" "$install_hint" >&2
        exit 1
    fi
}

[[ "${OSTYPE:-}" == darwin* ]] || die "Run this release on macOS with Xcode 15 or later."

say "Checking GitHub and Xcode release tools"
require_command gh "Install GitHub CLI with Homebrew: brew install gh."
require_command git "Install Xcode Command Line Tools: xcode-select --install."
require_command xcodebuild "Install Xcode 15 or later from the Mac App Store or developer.apple.com."
require_command xcrun "Install Xcode 15 or later from the Mac App Store or developer.apple.com."

say "Releasing the version already set by dev.sh: build, notarize, publish with notes, attach Windows build, and announce without bumping"
exec /bin/bash scripts/release.sh current --yes
