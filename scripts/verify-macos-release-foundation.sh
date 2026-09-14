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

require "FujiRecipes.xcworkspace/contents.xcworkspacedata"
require "FujiRecipesMac/macos/FujiRecipesMac.xcodeproj/project.pbxproj"
require "FujiRecipesMac/macos/Source/Info.plist"
require "FujiRecipesMac/macos/Resources/recipes-data.json"
require "FujiRecipesMac/macos/Resources/x100vi_helper"
require "FujiRecipesMac/macos/Resources/libusb-1.0.0.dylib"
require "FujiRecipesMac/macos/Resources/x100vi_helper.provenance.json"
require "FujiRecipesMac/macos/Resources/ThirdPartyNotices/libusb-COPYING.txt"

xcodebuild -list -workspace "FujiRecipes.xcworkspace"
plutil -lint "FujiRecipesMac/macos/Source/Info.plist"
"$root/scripts/verify-helper-resource.sh" --require-universal --minimum-macos 14.0

printf 'macOS release-foundation checks passed\n'
