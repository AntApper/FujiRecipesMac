# macOS release guide

## Supported scope

The supported macOS camera workflow is a direct USB PTP write to the Fujifilm
X100VI's C1–C7 custom slots. It is not a general Fujifilm-camera compatibility
claim.

Before overwriting a slot:

1. Put the X100VI in **USB RAW CONV./BACKUP RESTORE** mode and use a USB-C data
   cable.
2. Close Photos, Image Capture, Preview, and other camera clients. macOS's
   `ptpcamerad` can claim the interface; reconnect the camera and retry if the
   app cannot open a PTP session.
3. Read and retain a complete baseline of the target slot. Empty raw-zero
   sentinel values are not a usable rollback fixture; use a documented,
   camera-accepted replacement baseline for an empty slot.
4. Write only through the app's C1–C7 flow. Success requires the helper's
   per-property responses and a complete post-write readback, not a local
   recipe selection.
5. Confirm persistence by switching to another slot, returning to the target,
   disconnecting/reconnecting the helper, and reading the target again.

The X100VI direct-helper regression completed those checks for C1–C7. C1 and
C2 were restored to their original fixtures; C3–C7 use explicitly recorded
replacement baselines because their original empty values cannot be written
back. The detailed evidence is in
[x100vi-c-slot-hardware-regression-2026-09-12.md](x100vi-c-slot-hardware-regression-2026-09-12.md).
This evidence applies only to the tested X100VI/helper combination.

## Explicit exclusions

- **RAF/RAW conversion is unsupported for a release.** Conversion-related code
  and hardware notes are experimental validation material. Do not advertise,
  package, or support conversion as a released macOS capability.
- **iOS is separate.** Its transport and device validation are independent of
  this macOS raw-libusb helper and do not receive C1–C7 support from this
  release evidence.
- **Mac App Store distribution is unsupported.** The app bundles and launches
  a raw-libusb helper, while `ptpcamerad` can contend for the same PTP
  interface. That model has not been demonstrated to work under App Sandbox
  restrictions.

## Reproducible local checks

Prerequisites: macOS 14+, Xcode/Swift 6, and a checkout at the repository
root. The standalone repository keeps the app at `macos/`; it does not
contain a root `FujiRecipes.xcworkspace`. These checks do not need a camera or
Apple credentials:

```bash
set -euo pipefail
bash -n scripts/*.sh macos/package_app.sh
swift test --package-path FujiRecipesCore
swift test --package-path FujiPTPClient
swift build --package-path macos

scripts/verify-macos-release-foundation.sh
(
  cd macos
  ./package_app.sh debug --version 0.0.0 --build-number 1
)
```

The release-foundation check verifies the standalone Xcode project, metadata,
helper provenance, macOS 14 deployment target, and both `arm64` and `x86_64`
helper/runtime slices. Debug packaging is an ad-hoc-signed structural smoke
test, not a distributable build.

## Universal helper-runtime requirement

The checked-in helper resources are currently universal. The default libusb
runtime from an Apple-silicon Homebrew installation is commonly arm64-only
(including the current `/opt/homebrew/opt/libusb` runtime), so it cannot
rebuild those release resources. This is an intentional release blocker:
`scripts/build-macos-helper.sh` refuses a requested architecture that is
missing from `LIBUSB_DYLIB`; do not bypass that check or treat an arm64-only
helper as releasable.

To regenerate release resources, provide matching universal libusb runtime,
headers, and license inputs, then rerun the strict verifier:

```bash
set -euo pipefail
LIBUSB_DYLIB=/path/to/universal/libusb-1.0.0.dylib \
LIBUSB_INCLUDE_DIR=/path/to/libusb/include \
LIBUSB_LICENSE=/path/to/libusb/COPYING \
  scripts/build-macos-helper.sh

scripts/verify-helper-resource.sh --require-universal --minimum-macos 14.0
```

With universal resources already verified, the CI-equivalent credential-free
release package runs directly from this checkout:

```bash
(
  cd macos
  ./package_app.sh release --version 0.0.0 --build-number 1
)
```

This produces an ad-hoc-signed `.app` and runs strict universal bundle checks.
It does not contact Apple, notarize, staple, or create a distributable build.

## Developer ID release boundary

Direct distribution requires a Developer ID Application identity supplied
outside the repository, hardened-runtime signing, secure timestamps,
notarization, stapling, clean-machine Gatekeeper assessment, and hardware
validation on Apple Silicon and Intel Macs. CI deliberately has no Apple
certificate, private key, notarization credential, or camera attached.

For a provisioned signing environment, set an externally managed identity:

```bash
cd macos
SIGNING_IDENTITY="Developer ID Application: Your Organization (TEAMID)" \
  ./package_app.sh release --version 1.0.0 --build-number 1

../scripts/verify-macos-app-bundle.sh \
  --app "build/Fuji Recipes.app" \
  --require-universal \
  --require-developer-id \
  --expected-version 1.0.0 \
  --expected-build 1
```

Then use `scripts/notarize-macos-app.sh` with an external keychain profile.
Never add Developer ID certificates, private keys, App Store Connect keys,
passwords, or keychain profiles to the repository or CI configuration. See
[MACOS_RELEASE_BOUNDARIES.md](MACOS_RELEASE_BOUNDARIES.md) for the full
notarization and raw-USB boundary.
