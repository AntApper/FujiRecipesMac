#!/bin/bash
# Performs credential-free checks appropriate for a macOS release candidate.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

require() {
  [[ -e "$1" ]] || {
    printf 'error: required release input is missing: %s\n' "$1" >&2
    exit 1
  }
}

require "macos/FujiRecipesMac.xcodeproj/project.pbxproj"
require "macos/Source/Info.plist"
require "macos/Resources/recipes-data.json"
require "macos/Resources/x100vi_helper"
require "macos/Resources/libusb-1.0.0.dylib"
require "macos/Resources/x100vi_helper.provenance.json"
require "macos/Resources/ThirdPartyNotices/libusb-COPYING.txt"

xcodebuild -list -project "macos/FujiRecipesMac.xcodeproj"
plutil -lint "macos/Source/Info.plist"
"$root/scripts/verify-helper-resource.sh" --require-universal --minimum-macos 14.0

printf 'macOS release-foundation checks passed\n'
