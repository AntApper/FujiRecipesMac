# Architecture Decision: macOS PTP Transport

**Original decision:** 2026-07-03
**Status:** Accepted; supersedes the original macOS libgphoto2 conclusion
**Current implementation:** `ImageCaptureCorePTPClient` is the default macOS transport. `X100VIHelperClient` remains an explicit legacy fallback.

## Context

The app needs to read and write Fujifilm X100VI C1–C7 preset properties over
USB PTP. The original July probe misread ImageCaptureCore's completion
parameters: `responseData` contains the payload, while `ptpResponseData`
contains the PTP response container. That probe did not establish that native
ImageCaptureCore could not perform the operations.

## Decision

Use Apple's ImageCaptureCore session and PTP passthrough APIs by default on
macOS. This lets macOS and `ptpcamerad` own the camera session and avoids the
legacy helper's direct libusb interface claim during the normal app workflow.
The `FUJI_RECIPES_TRANSPORT=helper` setting explicitly selects the bundled
raw-libusb helper as a diagnostic/fallback path.

The macOS app constructs this transport in both its root app scene and the
standalone camera view factory. Keep those factories consistent when changing
the default. The shared `PTPClientProtocol` keeps camera operations behind a
transport boundary; FujiRecipesCore owns recipe mapping, C-slot encoding,
readback comparison, and recovery decisions.

## Evidence and limits

The [2026-09-29 native hardware checks](x100vi-imagecapturecore-hardware-checks-2026-09-29.md)
passed a bounded X100VI run on macOS 27.0.1 arm64. They cover all-seven-slot
reads and comparisons, configured C4 writes through the real manager
diagnostic, restoration after an injected acknowledgement failure, and
packaged-app unplug detection and reconnect after USB re-enumeration.
`ptpcamerad` and `icdd` remained running. The record identifies the uncommitted
`codex/refinement-fixes` working tree by its base commit and source hashes.
Native GUI writes, other-slot and empty-slot writes, Intel hardware, and the
other listed limits remain untested.

The repository hardware record documents X100VI C1–C7 persistence and rollback
through the legacy helper, plus a production macOS UI C4 operation, on
2026-09-12. See the [evidence manifest](x100vi-c-slot-evidence-manifest-2026-09-12.json)
and [detailed chronology](x100vi-c-slot-hardware-regression-2026-09-12.md).
Those results identify the helper path and camera, but the retained record
does not identify the tested repository revision or macOS version, and the
camera firmware was unavailable. Keep this helper record separate from the
later native transport checks. Builds and software tests provide their own
evidence; broader physical-device acceptance requires the remaining hardware
checks recorded in the native summary.

The X100VI is the only camera in the repository's C1–C7 hardware record. iOS
transport and other Fujifilm bodies remain outside that evidence.

## Consequences

- The default macOS path uses ImageCaptureCore and does not directly claim the
  USB interface through libusb.
- The helper, its libusb runtime, and provenance remain packaged for the
  explicit fallback and are still subject to release validation.
- The helper path can conflict with `ptpcamerad`; do not force-terminate the
  system PTP service as a connection workaround.
- RAF/RAW conversion code is experimental and is not a supported release
  capability.
- Mac App Store distribution remains unsupported until a sandbox-compatible
  design is demonstrated.

## Reproducible references

- [macOS release guide](RELEASE.md)
- [Release boundaries](MACOS_RELEASE_BOUNDARIES.md)
- [Camera connection guide](camera-connection-guide.md)
