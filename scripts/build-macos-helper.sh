#!/bin/bash
# Rebuilds the X100VI helper and its libusb runtime for the macOS app bundle.
#
# This script is the only supported way to refresh:
#   FujiRecipesMac/macos/Resources/x100vi_helper
#   FujiRecipesMac/macos/Resources/libusb-1.0.0.dylib
#   FujiRecipesMac/macos/Resources/x100vi_helper.provenance.json
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source_file="$root/poc-x100vi-reader/x100vi_helper.c"
resources="$root/FujiRecipesMac/macos/Resources"
helper="$resources/x100vi_helper"
runtime="$resources/libusb-1.0.0.dylib"
provenance="$resources/x100vi_helper.provenance.json"
notice_dir="$resources/ThirdPartyNotices"
architectures="arm64 x86_64"

usage() {
  cat <<'EOF'
Usage: scripts/build-macos-helper.sh [--architectures "arm64 x86_64"]

Builds a helper slice and a matching libusb slice for every requested
architecture, combines them into universal Mach-O files when more than one
architecture is requested, then writes resource hashes to the provenance
manifest. Set LIBUSB_DYLIB to a universal (or requested-architecture) libusb
dylib to avoid Homebrew discovery. When using a prebuilt runtime, set
LIBUSB_INCLUDE_DIR and LIBUSB_LICENSE to the matching header and COPYING paths.

Examples:
  scripts/build-macos-helper.sh
  scripts/build-macos-helper.sh --architectures arm64
  LIBUSB_DYLIB=/path/to/universal/libusb-1.0.0.dylib \
    scripts/build-macos-helper.sh
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --architectures)
      [[ $# -ge 2 ]] || { usage >&2; exit 2; }
      architectures="$2"
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

[[ -f "$source_file" ]] || { echo "error: missing helper source: $source_file" >&2; exit 1; }
mkdir -p "$resources" "$notice_dir"

if [[ -n "${LIBUSB_DYLIB:-}" ]]; then
  libusb_source="$LIBUSB_DYLIB"
else
  command -v brew >/dev/null || {
    echo "error: Homebrew is unavailable; set LIBUSB_DYLIB to a compatible libusb dylib" >&2
    exit 1
  }
  libusb_source="$(brew --prefix libusb)/lib/libusb-1.0.0.dylib"
fi
[[ -f "$libusb_source" ]] || { echo "error: missing libusb dylib: $libusb_source" >&2; exit 1; }
if [[ -n "${LIBUSB_INCLUDE_DIR:-}" ]]; then
  libusb_include_dir="$LIBUSB_INCLUDE_DIR"
else
  libusb_include_dir="$(dirname "$(dirname "$libusb_source")")/include"
fi
[[ -f "$libusb_include_dir/libusb-1.0/libusb.h" ]] || {
  echo "error: missing libusb headers: $libusb_include_dir/libusb-1.0/libusb.h" >&2
  exit 1
}

sdk="$(xcrun --sdk macosx --show-sdk-path)"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/fuji-helper.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
stage="$tmp/resources"
mkdir -p "$stage/ThirdPartyNotices"

helper_slices=()
runtime_slices=()
libusb_architectures="$(lipo -archs "$libusb_source")"
for arch in $architectures; do
  if ! printf '%s\n' "$libusb_architectures" | tr ' ' '\n' | grep -Fx "$arch" >/dev/null; then
    echo "error: libusb runtime lacks required $arch slice: $libusb_source" >&2
    echo "error: provide LIBUSB_DYLIB containing $architectures" >&2
    exit 1
  fi

  helper_slice="$tmp/x100vi_helper.$arch"
  runtime_slice="$tmp/libusb-1.0.0.dylib.$arch"
  if [[ "$libusb_architectures" == "$arch" ]]; then
    cp "$libusb_source" "$runtime_slice"
  else
    lipo -extract "$arch" "$libusb_source" -output "$runtime_slice"
  fi
  # Normalize each input slice before linking. A universal dylib can have
  # different source install names per architecture; changing it only after
  # lipo would leave one helper slice pointing to a build-directory path.
  install_name_tool -id "@rpath/libusb-1.0.0.dylib" "$runtime_slice"
  clang -O2 -arch "$arch" -isysroot "$sdk" -mmacosx-version-min=14.0 \
    "$source_file" -I"$libusb_include_dir" \
    "$runtime_slice" \
    -Wl,-rpath,@loader_path -o "$helper_slice"
  helper_slices+=("$helper_slice")
  runtime_slices+=("$runtime_slice")
done

if [[ ${#helper_slices[@]} -eq 1 ]]; then
  cp "${helper_slices[0]}" "$stage/x100vi_helper"
  cp "${runtime_slices[0]}" "$stage/libusb-1.0.0.dylib"
else
  lipo -create "${helper_slices[@]}" -output "$stage/x100vi_helper"
  lipo -create "${runtime_slices[@]}" -output "$stage/libusb-1.0.0.dylib"
fi
staged_helper="$stage/x100vi_helper"
staged_runtime="$stage/libusb-1.0.0.dylib"

# Make the dependency self-contained. The helper locates the runtime beside
# itself in Contents/Resources, never through a Homebrew loader path.
chmod 755 "$staged_helper"

# install_name_tool invalidates Mach-O signatures. Ad-hoc signatures make the
# local artifact executable and are replaced by the distributor's signature.
codesign --force --sign - "$staged_runtime"
codesign --force --sign - "$staged_helper"

license="${LIBUSB_LICENSE:-$(dirname "$(dirname "$libusb_source")")/COPYING}"
[[ -f "$license" ]] || {
  echo "error: missing libusb COPYING file: $license" >&2
  exit 1
}
cp "$license" "$stage/ThirdPartyNotices/libusb-COPYING.txt"

for arch in $architectures; do
  printf '%s\n' "$(lipo -archs "$staged_runtime")" | tr ' ' '\n' | grep -Fxq "$arch" ||
    { echo "error: staged libusb runtime lacks required $arch slice" >&2; exit 1; }
  printf '%s\n' "$(lipo -archs "$staged_helper")" | tr ' ' '\n' | grep -Fxq "$arch" ||
    { echo "error: staged helper lacks required $arch slice" >&2; exit 1; }
  otool -arch "$arch" -L "$staged_helper" | grep -Eq '^[[:space:]]*@rpath/libusb-1\.0\.0\.dylib ' ||
    { echo "error: staged $arch helper does not load libusb through @rpath" >&2; exit 1; }
  otool -arch "$arch" -l "$staged_helper" | grep -A2 'LC_RPATH' | grep -Fq '@loader_path' ||
    { echo "error: staged $arch helper lacks @loader_path rpath" >&2; exit 1; }
  [[ "$(otool -arch "$arch" -D "$staged_runtime" | awk 'NR == 2 { print; exit }')" == "@rpath/libusb-1.0.0.dylib" ]] ||
    { echo "error: staged $arch libusb install name is not @rpath/libusb-1.0.0.dylib" >&2; exit 1; }
done
for candidate in "$staged_helper" "$staged_runtime"; do
  if ! vtool -show-build "$candidate" | awk '/minos/ { if ($2 > 14.0) exit 1; found = 1 } END { exit !found }'; then
    echo "error: staged $(basename "$candidate") requires macOS newer than 14.0" >&2
    exit 1
  fi
done
if otool -L "$staged_runtime" | grep -E '/(opt/homebrew|usr/local)/' >/dev/null; then
  echo "error: staged libusb has a developer-machine dependency" >&2
  exit 1
fi

source_hash="$(shasum -a 256 "$source_file" | awk '{print $1}')"
helper_hash="$(shasum -a 256 "$staged_helper" | awk '{print $1}')"
runtime_hash="$(shasum -a 256 "$staged_runtime" | awk '{print $1}')"
runtime_architectures="$(lipo -archs "$staged_runtime")"
cat > "$stage/x100vi_helper.provenance.json" <<EOF
{
  "schema_version": 1,
  "helper_source": "poc-x100vi-reader/x100vi_helper.c",
  "helper_source_sha256": "$source_hash",
  "helper_sha256": "$helper_hash",
  "runtime": "libusb-1.0.0.dylib",
  "runtime_sha256": "$runtime_hash",
  "architectures": "$runtime_architectures",
  "runtime_install_name": "@rpath/libusb-1.0.0.dylib",
  "helper_rpath": "@loader_path"
}
EOF

# All commands that can fail ran against staged files. Only publish the
# coherent resource set after validation succeeds, preserving prior artifacts
# on a build, link, signing, or validation failure.
mv "$staged_helper" "$helper"
mv "$staged_runtime" "$runtime"
mv "$stage/x100vi_helper.provenance.json" "$provenance"
mv "$stage/ThirdPartyNotices/libusb-COPYING.txt" "$notice_dir/libusb-COPYING.txt"

echo "built helper architectures: $(lipo -archs "$helper")"
echo "bundled libusb architectures: $runtime_architectures"
echo "wrote provenance: $provenance"
