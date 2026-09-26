# Fuji Recipes for macOS

Fuji Recipes for macOS manages Fujifilm recipe data and supports writing
verified custom settings to the **C1–C7** slots of a Fujifilm X100VI over
USB. The release target is macOS 14 or later.

## Supported release workflow

The supported camera operation is an X100VI C1–C7 preset read/write:

1. Set the camera to **USB RAW CONV./BACKUP RESTORE**, connect it with a
   USB-C data cable, and close other camera applications.
2. Connect from the app. The bundled `x100vi_helper` claims the USB PTP
   interface through libusb.
3. Choose a recipe and a C1–C7 target. The app saves the target's existing
   settings, writes the applicable recipe fields, and reads the slot back
   before reporting success.
4. Treat a failed write or incomplete readback as a failure; do not assume a
   local UI state means the camera was changed. Keep a known-good baseline
   before overwriting a slot.

The direct-helper C1–C7 regression passed immediate, alternate-slot,
reconnect, and rollback checks on an X100VI. See
[the hardware evidence record](docs/x100vi-c-slot-hardware-regression-2026-09-12.md)
and the [release guide](docs/RELEASE.md) for the exact scope and test process.

## Release limitations

- **RAF/RAW conversion is not a supported release feature.** The repository
  contains experimental helper and hardware-validation work, but it is outside
  the supported macOS release promise.
- **iOS is a separate workstream.** It does not inherit the macOS libusb
  transport, release status, or C-slot hardware validation.
- **Mac App Store distribution is not supported.** The default app transport
  uses ImageCaptureCore, but the legacy raw-libusb helper remains available
  through `FUJI_RECIPES_TRANSPORT=helper` and has not been validated for the
  App Sandbox.
- A direct macOS build is only a Developer ID candidate after it has been
  signed, timestamped, notarized, and hardware-tested. Credential-free builds
  are ad-hoc signed structural checks, not distributable releases.

## Build and test

Use Xcode/Swift 6 on macOS 14 or later. From the repository root:

```bash
swift test --package-path FujiRecipesCore
swift test --package-path FujiPTPClient
swift build --package-path macos
```

For the credential-free release-package smoke test and the Developer ID /
notarization boundary, follow [docs/RELEASE.md](docs/RELEASE.md).

## Release tooling layout

Release scripts run from this repository root and expect the app at `macos/`;
there is no root Xcode workspace. The checked-in helper and libusb runtime must
remain universal (`arm64` and `x86_64`) for a release candidate. An arm64-only
Homebrew libusb runtime is suitable for neither a release rebuild nor a
Developer ID release: `scripts/build-macos-helper.sh` rejects it unless
`LIBUSB_DYLIB` supplies every requested architecture. See the release guide
for root-level verification and packaging commands.

## Documentation

- [Release guide](docs/RELEASE.md)
- [macOS release boundaries](docs/MACOS_RELEASE_BOUNDARIES.md)
- [Camera connection guide](docs/camera-connection-guide.md)
- [C1–C7 hardware regression record](docs/x100vi-c-slot-hardware-regression-2026-09-12.md)
