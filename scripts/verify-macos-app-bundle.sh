#!/bin/bash
# Validates a finished macOS app bundle without submitting it to Apple.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

app=""
require_universal=false
require_developer_id=false
allow_developer_rpaths=false
minimum_macos="14.0"
expected_version=""
expected_build=""
expected_bundle_id="com.ant.fuji-recipes-mac"

usage() {
  cat <<'EOF'
Usage: scripts/verify-macos-app-bundle.sh --app PATH [options]

Checks a final .app bundle's version metadata, required resources, architecture
coverage, nested signatures, sealed resources, deployment target, and Mach-O
load commands. It does not notarize or contact Apple.

Options:
  --app PATH                 App bundle to validate (required)
  --require-universal        Require arm64 and x86_64 in executable code
  --require-developer-id     Require Developer ID Application signatures and
                             hardened runtime (external release signing only)
  --allow-developer-rpaths   Allow developer-machine runtime search paths (debug only)
  --minimum-macos VERSION    Reject code built for a newer macOS (default 14.0)
  --expected-version VALUE   Require CFBundleShortVersionString to match
  --expected-build VALUE     Require CFBundleVersion to match
  --expected-bundle-id VALUE Require CFBundleIdentifier to match
                             (default com.ant.fuji-recipes-mac)
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) app="${2:-}"; shift 2 ;;
    --require-universal) require_universal=true; shift ;;
    --require-developer-id) require_developer_id=true; shift ;;
    --allow-developer-rpaths) allow_developer_rpaths=true; shift ;;
    --minimum-macos) minimum_macos="${2:-}"; shift 2 ;;
    --expected-version) expected_version="${2:-}"; shift 2 ;;
    --expected-build) expected_build="${2:-}"; shift 2 ;;
    --expected-bundle-id) expected_bundle_id="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[[ -n "$app" ]] || { usage >&2; exit 2; }
[[ "$app" == *.app ]] || fail "--app must name a .app bundle"
[[ -d "$app" ]] || fail "app bundle is missing: $app"

contents="$app/Contents"
plist="$contents/Info.plist"
main_executable="$contents/MacOS/FujiRecipesMac"
resources="$contents/Resources"
helper="$resources/x100vi_helper"
runtime="$resources/libusb-1.0.0.dylib"
provenance="$resources/x100vi_helper.provenance.json"
notice="$resources/ThirdPartyNotices/libusb-COPYING.txt"

recipes="$resources/recipes-data.json"

for required in "$plist" "$main_executable" "$helper" "$runtime" "$provenance" "$notice" "$recipes"; do
  [[ -e "$required" ]] || fail "required bundle content is missing: $required"
done
[[ -x "$main_executable" ]] || fail "main executable is not executable"
[[ -x "$helper" ]] || fail "bundled helper is not executable"
plutil -lint "$plist" >/dev/null

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist")"
bundle_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
bundle_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")"
[[ "$bundle_identifier" == "$expected_bundle_id" ]] ||
  fail "unexpected bundle identifier: $bundle_identifier"
[[ "$bundle_version" != *'$('* && "$bundle_version" != "" ]] ||
  fail "CFBundleShortVersionString must be a concrete release version"
[[ "$bundle_build" =~ ^[0-9]+$ ]] ||
  fail "CFBundleVersion must be a numeric build number"
[[ -z "$expected_version" || "$bundle_version" == "$expected_version" ]] ||
  fail "bundle version $bundle_version does not match expected $expected_version"
[[ -z "$expected_build" || "$bundle_build" == "$expected_build" ]] ||
  fail "bundle build $bundle_build does not match expected $expected_build"

python3 "$root/scripts/packaged-provenance.py" verify --resources "$resources"

for code in "$main_executable" "$helper" "$runtime"; do
  file_output="$(file "$code")"
  [[ "$file_output" == *"Mach-O"* ]] || fail "not a Mach-O file: $code"
  architectures="$(lipo -archs "$code")"
  if "$require_universal"; then
    for arch in arm64 x86_64; do
      printf '%s\n' "$architectures" | tr ' ' '\n' | grep -Fxq "$arch" ||
        fail "$(basename "$code") is missing required $arch slice"
    done
  fi
  vtool -show-build "$code" 2>/dev/null |
    awk -v maximum="$minimum_macos" '
      /minos/ { found = 1; if ($2 > maximum) { bad = 1 } }
      END { exit (!found || bad) }
    ' || fail "$(basename "$code") requires macOS newer than $minimum_macos"

  if otool -L "$code" | grep -E '(/Users/|/opt/homebrew/|/usr/local/)' >/dev/null; then
    fail "$(basename "$code") contains a developer-machine library dependency"
  fi
  if ! "$allow_developer_rpaths"; then
    if otool -l "$code" | grep -A2 'LC_RPATH' | grep -E '(/Users/|/opt/homebrew/|/usr/local/)' >/dev/null; then
      fail "$(basename "$code") contains a developer-machine runtime search path"
    fi
  fi
done

helper_dependencies="$(otool -L "$helper")"
printf '%s\n' "$helper_dependencies" | grep -Eq '^[[:space:]]*@rpath/libusb-1\.0\.0\.dylib ' ||
  fail "helper does not load bundled libusb through @rpath"
otool -l "$helper" | grep -A2 'LC_RPATH' | grep -Fq '@loader_path' ||
  fail "helper is missing its @loader_path runtime search path"
[[ "$(otool -D "$runtime" | awk 'NR == 2 { print; exit }')" == "@rpath/libusb-1.0.0.dylib" ]] ||
  fail "bundled libusb install name is not @rpath/libusb-1.0.0.dylib"

# --strict verifies the app's sealed resources. Verify nested executable code
# explicitly as well so a broken helper cannot be hidden by a shallow seal.
codesign --verify --deep --strict --verbose=2 "$app"
codesign --verify --strict --verbose=2 "$helper"
codesign --verify --strict --verbose=2 "$runtime"

if "$require_developer_id"; then
  for code in "$app" "$helper" "$runtime"; do
    signing_info="$(codesign -dvv "$code" 2>&1)"
    printf '%s\n' "$signing_info" | grep -Fq 'Authority=Developer ID Application:' ||
      fail "$(basename "$code") is not signed with a Developer ID Application certificate"
    printf '%s\n' "$signing_info" | grep -Eq 'flags=.*runtime' ||
      fail "$(basename "$code") does not have the hardened runtime enabled"
    printf '%s\n' "$signing_info" | grep -Eq '^Timestamp=' ||
      fail "$(basename "$code") is missing a secure signing timestamp"
  done
fi

printf 'macOS app bundle checks passed: %s (%s build %s)\n' \
  "$bundle_identifier" "$bundle_version" "$bundle_build"
