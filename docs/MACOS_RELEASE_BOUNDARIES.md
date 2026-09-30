# macOS Release Boundaries

This repository can build a Developer ID signing candidate and validate its
local bundle evidence. It cannot prove notarization, distribute a release, or
make camera behavior reliable without the external Apple account, certificate,
and hardware steps described below.

## Current development boundary

- The macOS app now defaults to `ImageCaptureCorePTPClient`, which lets
  ImageCaptureCore/`ptpcamerad` own the USB PTP session. The bundled
  `x100vi_helper` and libusb runtime remain an explicit fallback selected with
  `FUJI_RECIPES_TRANSPORT=helper`; that path retains the interface-ownership
  caveat described below. The [2026-09-29 native hardware checks](x100vi-imagecapturecore-hardware-checks-2026-09-29.md)
  passed bounded all-seven-slot reads, configured C4 manager diagnostic
  writes/restoration, and packaged-app connection/read and unplug recovery
  after USB re-enumeration. The tested working tree was uncommitted; source
  hashes and remaining hardware limits are recorded in that summary.
- The helper now loads a bundled `libusb-1.0.0.dylib` through
  `@rpath/libusb-1.0.0.dylib` with an `@loader_path` rpath. Its source,
  helper, and runtime SHA-256 values are recorded in the app resource
  provenance manifest, and the bundled license text is checked.
- A release still requires a verified universal helper and libusb runtime.
  `scripts/verify-macos-release-foundation.sh` rejects missing `arm64` or
  `x86_64` slices and any Mach-O whose minimum macOS version is later than
  14.0. A locally installed Homebrew libusb can be arm64-only and built for a
  newer macOS; that input is intentionally rejected by the release gate.

## What the credential-free checks prove

`scripts/verify-macos-app-bundle.sh` validates a completed `.app` bundle:

- concrete bundle identifier, marketing version, and numeric build number;
- the expected helper, libusb runtime, provenance manifest, and license notice;
- bundled provenance hashes, `arm64`/`x86_64` coverage when requested, and a
  macOS 14.0-or-earlier deployment target;
- no Homebrew or `/Users/...` load commands/rpaths in the executable, helper,
  or libusb runtime; and
- strict app and nested-code signature/resource-seal verification.

It can additionally require Developer ID Application authorities and hardened
runtime flags, but it never calls Apple's notarization service. An ad-hoc
signature can pass the structural check and is explicitly **not** a
distributable signature.

For a local candidate bundle:

```bash
cd FujiRecipesMac/macos
./package_app.sh release --version 1.0.0 --build-number 1
```

For an externally provisioned Developer ID candidate:

```bash
SIGNING_IDENTITY="Developer ID Application: Your Organization (TEAMID)" \
  ./package_app.sh release --version 1.0.0 --build-number 1
scripts/verify-macos-app-bundle.sh \
  --app "build/Fuji Recipes.app" \
  --require-universal --require-developer-id \
  --expected-version 1.0.0 --expected-build 1
```

`FujiRecipesMac/macos/package_app.sh` is the authoritative direct-distribution
app build path. It builds both architectures with SwiftPM, assembles the
finished `.app`, signs nested runtime/helper code before the outer bundle, and
runs the bundle validator. The GitHub release-foundation workflow uses this
same credential-free path. It produces an `.app`; the notarization script
creates the ZIP submitted to Apple.

## Distribution status

- **Local development:** The app defaults to ImageCaptureCore. The explicit
  helper fallback requires its bundled libusb runtime and can encounter USB
  interface ownership conflicts.
- **Developer ID:** The repository can prepare and locally validate a signing
  candidate. Actual distribution remains blocked on an Apple-issued Developer
  ID Application certificate, hardened-runtime signing, timestamping,
  notarization, staple verification, and hardware testing.
- **Mac App Store:** Not supported. The raw libusb/helper process and
  `ptpcamerad` conflict have not been shown to work within the App Sandbox or
  its entitlement model.
- **iOS:** A separate workstream. Its transport, signing, privacy disclosures,
  and device testing are independent of this macOS helper path.

## Notarization

Notarization is intentionally outside repository CI. It requires an enrolled
Apple Developer Program team, a Developer ID Application certificate and
private key in the signing keychain, a timestamp-capable signing environment,
and either an App Store Connect API key or app-specific password. The final
signed archive must be submitted with `notarytool`, accepted by Apple, stapled,
then assessed on a clean macOS installation. Do not add those credentials,
private keys, API keys, or passwords to this repository or its workflows.

For a signed candidate from the authoritative package path, use
`scripts/notarize-macos-app.sh`. It accepts only an external notarytool
keychain-profile name (`--keychain-profile` or
`NOTARY_KEYCHAIN_PROFILE`), verifies Developer ID, hardened-runtime, and
timestamp evidence before upload, then archives, submits, staples, validates,
and Gatekeeper-assesses the app. It does not accept or log Apple passwords,
private keys, or API tokens.

Enabling `ENABLE_HARDENED_RUNTIME` in the Release target only configures the
build requirement. It does not sign the application, grant USB access, or
establish notarization acceptance.

## Raw libusb / PTP fallback caveat

The explicit legacy helper claims the USB PTP interface directly through
libusb. On macOS, `ptpcamerad` can automatically claim that same interface.
The default ImageCaptureCore path delegates the session to macOS and avoids
the helper's direct interface claim. The bounded native run passed with
`ptpcamerad` and `icdd` running. Keep the older helper results scoped to that
transport. Neither camera path has been validated under App Sandbox
restrictions; sandboxed fixture UI tests do not establish camera access.

## Required evidence before a public macOS release

1. Supply a redistributable universal libusb dylib built for macOS 14.0 or
   earlier, then rebuild the helper with `scripts/build-macos-helper.sh`.
2. Run `FujiRecipesMac/macos/package_app.sh release` with a Developer ID
   identity; it signs nested code first with hardened runtime and timestamp,
   then run the finished-bundle check with `--require-developer-id`.
3. Run `scripts/notarize-macos-app.sh` with an external keychain profile,
   wait for accepted notarization, staple the resulting ticket, and
   independently assess the stapled artifact.
4. Verify the helper's architecture coverage and extend native camera evidence
   beyond the bounded arm64 run. Intel hardware, native GUI writes,
   other-slot/empty-slot writes, and the other limits in the native summary
   remain untested. Keep the helper record scoped to the helper.
5. Define and test a signed, sandbox-compatible distribution design, or
   explicitly limit distribution to a non-App-Store channel.
6. Extend broker-coexistence evidence to the intended unattended usage. The
   bounded native checks passed without terminating `ptpcamerad` or `icdd`;
   extended unattended operation and unplug during a write remain untested.
