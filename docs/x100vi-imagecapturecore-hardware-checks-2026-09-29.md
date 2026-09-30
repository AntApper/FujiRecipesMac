# X100VI ImageCaptureCore hardware checks — 2026-09-29

## Tested scope and identity

This bounded run used a physical Fujifilm X100VI (`04CB:0305`) with the native
ImageCaptureCore transport on macOS 27.0.1, arm64, Xcode 27.0 (`27A266a`), and
Apple Swift 6.4. The working tree was `codex/refinement-fixes`, based on
`271db24a4b13461d55a418c576cdd6b3400974fe`, with **uncommitted refinements**.
The base commit records ancestry; the source hashes below identify the tested
implementation. The date is local to America/Chicago.

## Bounded observations

| Check | Observed result |
| --- | --- |
| Baseline and repeated reads | All seven slots supplied 25 captured fields each. Twenty connect/read/compare/disconnect cycles passed with every captured value and the original C1 selector preserved. Five further immediate cycles passed without an artificial pause. |
| Repository probe | Three C4 reads verified selector restoration. A guarded C4 sharpness change from raw `-10` to `20` and back to `-10` verified both value restoration and the original C1 selector. A subsequent comparison matched all seven slots exactly. |
| Real manager write | A diagnostic using the actual `CameraManager` verified a configured C4 write, readback, and synchronized adoption. Its cleanup restored the complete baseline. This was a manager diagnostic, not a GUI camera-write check. |
| Injected acknowledgement failure | After a confirmed real C4 sharpness write, the diagnostic deliberately injected an acknowledgement failure. One real manager rollback verified restoration; the requested draft remained staged in an isolated defaults suite. All seven captured slot contents matched the baseline and C1 was preserved. No natural hardware write failure was observed. |
| Packaged app unplug and recovery | The running app detected physical unplug while no write was in progress. An absent-camera retry timed out cleanly after 15 seconds. The first cable replug had no OS USB enumeration. Following a requested camera off/on, `04CB:0305` enumerated and the same app reconnected with all seven slots synced, without relaunch. The final app reconnect after diagnostics also passed. |
| Native brokers | `ptpcamerad` and `icdd` were observed running; neither was terminated for these checks. |

The power-switch action was not independently observed. The recovered reads
establish preservation after USB re-enumeration, not independently verified
power-cycle persistence.

The local evidence includes `immediate-reconnect.log`, `repo-probe-read.log`,
`repo-probe-write.log`, `after-repo-probe-compare.log`, `workflow.log`, broker
status, and build identities. Raw camera baselines and logs remain outside the
repository; this document records only bounded outcomes and source identity.

## Source identity

SHA-256 values are relative to the repository root. Native transport and Core
sources were unchanged from the passing soak. The repository probe sources
matched the later diagnostic build identity used for the checks above.

| Source | SHA-256 |
| --- | --- |
| `FujiPTPClient/Sources/PTPClientMacOS/ImageCaptureCorePTPClient.swift` | `0ca460ce2082b651164f286ddb2381a9384cccbaa68449b8d25db26e7a393bd2` |
| `FujiPTPClient/Sources/PTPClientMacOS/ImageCaptureCoreSessionDevice.swift` | `9b5edfe8cf362cbcd791ca90e3255727869b1cb00c42182e1cb6178b219f10aa` |
| `FujiPTPClient/Sources/PTPClientMacOS/NativePTPSession.swift` | `a5c1bb3827f26588b3fb1e3ded98227629a5b0e1d23fb42b452ff978670efcad` |
| `FujiRecipesCore/Sources/FujiRecipesCore/Models/CameraManager.swift` | `698cfcfcabea7c45088a366121dd86861bb55fdb3002f2f39b2d475716f7cbf7` |
| `FujiRecipesCore/Sources/FujiRecipesCore/Models/PTPClientProtocol.swift` | `d0f78f8968927340d564faa62345154b460799bbc351c7c3fb4d360fb825f97a` |
| `FujiRecipesCore/Sources/FujiRecipesCore/Mapping/CSlotPresetEncoder.swift` | `5b72bb0c7a065a1216071818c36614d1ae410e926aebf3c3f751ed7ed9a6e8f8` |
| `FujiRecipesCore/Sources/FujiRecipesCore/Models/LoadoutStore.swift` | `39345614c0e565d57f7f3f30fc840da854fb1928344a6db29cdb69a714b36506` |
| `FujiPTPClient/Sources/PTPClientMacOS/ImageCaptureCoreWriteProbe.swift` | `bee0d63e1f9e3dd680eea1e9c9c70ae052263c658eed42f65f248a8ecc4a12cc` |
| `FujiPTPClient/Tools/ImageCaptureCoreProbe/main.swift` | `3d05c54f31d5699d45f65c15251f3582cf5c8e076e929bfbab31bc49172a46dc` |

## Separate software checks and remaining limits

Reported software checks passed: Core 233, PTP 76, Python 15. All eight GUI
behaviors passed across a 7/8 run and a passing corrected retry. Those GUI
checks used fixtures and do not establish a native GUI camera write.

Untested in this run: native writes to slots other than configured C4,
all-seven-slot writes, native empty-slot creation, native GUI camera writes,
unplug during a write, unattended extended operation, Intel hardware,
firmware identity, and independently verified power-cycle persistence.

The [September 12 helper evidence](x100vi-c-slot-evidence-manifest-2026-09-12.json)
remains a separate historical record. RAF conversion remains unsupported;
Developer ID signing, notarization, and distribution requirements remain in
the [release boundaries](MACOS_RELEASE_BOUNDARIES.md).
