#!/bin/bash
# Validates the helper, bundled libusb runtime, and their provenance manifest.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
helper="$root/FujiRecipesMac/macos/Resources/x100vi_helper"
source_file="$root/poc-x100vi-reader/x100vi_helper.c"
runtime="$root/FujiRecipesMac/macos/Resources/libusb-1.0.0.dylib"
provenance="$root/FujiRecipesMac/macos/Resources/x100vi_helper.provenance.json"
notice="$root/FujiRecipesMac/macos/Resources/ThirdPartyNotices/libusb-COPYING.txt"
require_universal=false
minimum_macos=""

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: scripts/verify-helper-resource.sh [--require-universal] [--minimum-macos VERSION]

Verifies that the app resource helper was rebuilt from the checked-in C source,
uses only its bundled libusb runtime through @rpath, and has matching
architectures. --require-universal additionally requires arm64 and x86_64
slices. --minimum-macos rejects a helper or runtime built for a newer macOS.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-universal)
      require_universal=true
      shift
      ;;
    --minimum-macos)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      minimum_macos="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 2
      ;;
  esac
done

json_value() {
  awk -F'"' -v key="$1" '$2 == key { print $4; exit }' "$provenance"
}

assert_hash() {
  local label="$1"
  local path="$2"
  local expected="$3"
  local actual
  actual="$(shasum -a 256 "$path" | awk '{print $1}')"
  [[ "$actual" == "$expected" ]] || fail "$label hash differs from provenance; rerun scripts/build-macos-helper.sh"
}

assert_maximum_macos() {
  local path="$1"
  vtool -show-build "$path" 2>/dev/null |
    awk -v maximum="$minimum_macos" '
      /minos/ { found = 1; if ($2 > maximum) { bad = $2 } }
      END { exit (!found || bad != "") }
    ' ||
    fail "$path has a slice requiring macOS newer than the declared deployment target $minimum_macos"
}

[[ -f "$source_file" ]] || fail "helper source is missing: $source_file"
[[ -f "$helper" ]] || fail "bundled helper resource is missing: $helper"
[[ -x "$helper" ]] || fail "bundled helper is not executable: $helper"
[[ -f "$runtime" ]] || fail "bundled libusb runtime is missing: $runtime"
[[ -f "$provenance" ]] || fail "helper provenance manifest is missing: $provenance"
[[ -f "$notice" ]] || fail "libusb license notice is missing: $notice"
codesign --verify --strict "$helper" >/dev/null 2>&1 ||
  fail "bundled helper has an invalid Mach-O signature; rerun scripts/build-macos-helper.sh"
codesign --verify --strict "$runtime" >/dev/null 2>&1 ||
  fail "bundled libusb runtime has an invalid Mach-O signature; rerun scripts/build-macos-helper.sh"

file_output="$(file "$helper")"
printf '%s\n' "$file_output"
[[ "$file_output" == *"Mach-O"* ]] || fail "bundled helper is not a macOS Mach-O executable"
runtime_file_output="$(file "$runtime")"
printf '%s\n' "$runtime_file_output"
[[ "$runtime_file_output" == *"Mach-O"* ]] || fail "bundled libusb runtime is not a macOS Mach-O dylib"

source_hash="$(json_value helper_source_sha256)"
helper_hash="$(json_value helper_sha256)"
runtime_hash="$(json_value runtime_sha256)"
[[ -n "$source_hash" && -n "$helper_hash" && -n "$runtime_hash" ]] ||
  fail "helper provenance manifest is incomplete"
assert_hash "helper source" "$source_file" "$source_hash"
assert_hash "bundled helper" "$helper" "$helper_hash"
assert_hash "bundled libusb runtime" "$runtime" "$runtime_hash"

helper_architectures="$(lipo -archs "$helper")"
runtime_architectures="$(lipo -archs "$runtime")"
[[ "$helper_architectures" == "$runtime_architectures" ]] ||
  fail "helper architectures ($helper_architectures) do not match libusb architectures ($runtime_architectures)"
manifest_architectures="$(json_value architectures)"
[[ "$manifest_architectures" == "$runtime_architectures" ]] ||
  fail "provenance architectures ($manifest_architectures) do not match runtime ($runtime_architectures)"
for arch in $helper_architectures; do
  dependencies="$(otool -arch "$arch" -L "$helper")"
  printf '%s\n' "$dependencies"
  if printf '%s\n' "$dependencies" | grep -E '/(opt/homebrew|usr/local)/.*libusb' >/dev/null; then
    fail "bundled $arch helper links libusb from a developer path"
  fi
  printf '%s\n' "$dependencies" | grep -Eq '^[[:space:]]*@rpath/libusb-1\.0\.0\.dylib ' ||
    fail "bundled $arch helper must load its bundled libusb runtime through @rpath"
  otool -arch "$arch" -l "$helper" | grep -A2 'LC_RPATH' | grep -Fq '@loader_path' ||
    fail "bundled $arch helper is missing the @loader_path rpath for its packaged runtime"
  runtime_id="$(otool -arch "$arch" -D "$runtime" | awk 'NR == 2 { print; exit }')"
  [[ "$runtime_id" == "@rpath/libusb-1.0.0.dylib" ]] ||
    fail "bundled $arch libusb install name is not @rpath/libusb-1.0.0.dylib"
  if otool -arch "$arch" -L "$runtime" | grep -E '/(opt/homebrew|usr/local)/' >/dev/null; then
    fail "bundled $arch libusb has a developer-machine dependency"
  fi
done
if "$require_universal"; then
  for arch in arm64 x86_64; do
    printf '%s\n' "$helper_architectures" | tr ' ' '\n' | grep -Fxq "$arch" ||
      fail "helper is missing required $arch slice; provide a universal LIBUSB_DYLIB and rerun scripts/build-macos-helper.sh"
  done
fi

if [[ -n "$minimum_macos" ]]; then
  assert_maximum_macos "$helper"
  assert_maximum_macos "$runtime"
fi

printf 'helper resource and runtime provenance checks passed\n'
