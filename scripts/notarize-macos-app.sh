#!/bin/bash
# Submits a Developer ID-signed Fuji Recipes app for notarization and staples
# the accepted ticket. Credentials remain in an external notarytool keychain
# profile; this script never accepts or logs passwords, private keys, or tokens.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app=""
keychain_profile="${NOTARY_KEYCHAIN_PROFILE:-}"
archive=""

usage() {
  cat <<'EOF'
Usage: scripts/notarize-macos-app.sh --app PATH
       [--keychain-profile PROFILE] [--archive PATH]

Submit a finished Developer ID-signed .app bundle with xcrun notarytool,
wait for acceptance, staple the ticket, and perform local post-staple checks.

Credentials are never passed as command-line arguments. Create a notarytool
keychain profile outside this repository, then provide only its profile name:

  xcrun notarytool store-credentials "fuji-notary" ...
  NOTARY_KEYCHAIN_PROFILE="fuji-notary" \
    scripts/notarize-macos-app.sh --app "Fuji Recipes.app"

Options:
  --app PATH                 Finished .app bundle to notarize (required)
  --keychain-profile NAME    External notarytool keychain profile
  --archive PATH             Destination ZIP (default: temporary file)
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) app="${2:-}"; shift 2 ;;
    --keychain-profile) keychain_profile="${2:-}"; shift 2 ;;
    --archive) archive="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

[[ -n "$app" ]] || { usage >&2; exit 2; }
[[ "$app" == *.app && -d "$app" ]] || {
  printf 'error: --app must name an existing .app bundle\n' >&2
  exit 2
}
[[ -n "$keychain_profile" ]] || {
  printf 'error: provide --keychain-profile or NOTARY_KEYCHAIN_PROFILE\n' >&2
  exit 2
}
command -v xcrun >/dev/null || {
  printf 'error: xcrun/Xcode command-line tools are required\n' >&2
  exit 1
}

# Fail before creating an upload if any nested code is unsigned, lacks the
# hardened runtime, or lacks a timestamp. The package script signs nested code
# first, then seals the outer bundle.
"$root/scripts/verify-macos-app-bundle.sh" \
  --app "$app" \
  --require-developer-id \
  --require-universal

cleanup_archive=false
if [[ -z "$archive" ]]; then
  archive="$(mktemp "${TMPDIR:-/tmp}/FujiRecipes-notarization.XXXXXX.zip")"
  cleanup_archive=true
fi
mkdir -p "$(dirname "$archive")"
rm -f "$archive"
trap 'if "$cleanup_archive"; then rm -f "$archive"; fi' EXIT

echo "▶ Creating notarization archive…"
ditto -c -k --keepParent "$app" "$archive"

echo "▶ Submitting to Apple notary service…"
xcrun notarytool submit "$archive" \
  --keychain-profile "$keychain_profile" \
  --wait

echo "▶ Stapling accepted ticket…"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=4 "$app"

echo "✓ Notarized and stapled $app"
if ! "$cleanup_archive"; then
  echo "  Archive retained at $archive"
fi
