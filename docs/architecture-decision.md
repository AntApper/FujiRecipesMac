# Architecture Decision: Cross-Platform PTP Communication

**Date:** 2026-07-03  
**Status:** Accepted  
**Context:** Session 4 hardware probe results

## Problem

We need a Fujifilm recipe manager that:
- Runs on **iOS** (primary target, iPad/iPhone with USB-C)
- Runs on **macOS** (secondary target, development/debugging)
- Communicates with the **X100VI** via USB to push recipe presets to C1–C7 slots
- Has all dependencies **bundled** — no user-facing setup required
- Uses a **single codebase** shared across platforms

The core technical challenge: **how to send raw PTP commands to Fuji cameras on both macOS and iOS.**

## Decision

**Use ImageCaptureCore on iOS + libgphoto2 (bundled) on macOS, unified under a `PTPClient` protocol.**

```
┌─────────────────────────────────────────────────┐
│                 FujiRecipesCore                  │
│  (shared Swift: recipes, models, PTP mapping)   │
└────────────────┬────────────────────────────────┘
                 │
     ┌───────────┴───────────┐
     │                       │
┌────▼─────┐          ┌──────▼──────┐
│FujiRecipes│         │FujiRecipesMac│
│  (iOS)    │         │  (macOS)     │
│           │         │              │
│ ImageCap- │         │ libgphoto2   │
│ tureCore  │         │ (bundled)    │
└───────────┘         └─────────────┘
```

## Why Not Pure ImageCaptureCore?

Our Session 4 probe proved that **macOS ImageCaptureCore transforms raw PTP responses** for non-Apple cameras:

| What We Sent | What We Got |
|-------------|-------------|
| PTP GetDeviceInfo (0x1001), 18 bytes | Response: 12 bytes, code `0x2000` |
| Expected: standard PTP response (18+ bytes, code 0x2001) | Not parseable as PTP |

This means ImageCaptureCore on macOS:
- Cannot parse GetDeviceInfo into readable fields
- Cannot read/write device properties via raw PTP
- Cannot push recipes to camera preset slots

**Conclusion:** ImageCaptureCore alone won't work for the macOS target.

## Why Not Pure libgphoto2?

libgphoto2 is available on both platforms but:
- Requires significant build complexity for iOS (cross-compilation, bitcode, etc.)
- The iOS ImageCaptureCore path is simpler if it works
- libgphoto2 is ~8MB — fine for macOS, heavy for iOS if not needed

## Why This Hybrid?

| Factor | iOS (ImageCaptureCore) | macOS (libgphoto2) |
|--------|----------------------|-------------------|
| PTP support | ✅ May work (untested) | ✅ Proven for X100VI |
| Dependencies | None (native) | ~8MB bundled |
| Complexity | Low | Medium (FFI) |
| App Store | ✅ Clean | ✅ With proper stripping |

**iOS path:** Test first. If ImageCaptureCore returns raw PTP responses on iOS, we're done — zero dependencies. If it also transforms responses, iOS needs libgphoto2 too.

**macOS path:** libgphoto2 is the reliable option. We bundle a prebuilt binary.

## Package Structure

```
FujiPTPClient/                     ← Swift Package Manager package
├── Package.swift
├── Sources/
│   └── FujiPTPClient/
│       ├── PTPClient.swift        ← Public protocol (shared across platforms)
│       ├── CameraInfo.swift       ← Parsed camera info types
│       ├── PropertyResponse.swift ← Typed property values
│       ├── PTP+macOS.swift        ← libgphoto2 FFI implementation
│       └── PTP+iOS.swift          ← ImageCaptureCore implementation
└── Resources/
    └── libgphoto2/
        ├── arm64-apple-macosx/
        │   ├── libgphoto2.a
        │   └── headers/
        ├── x86_64-apple-macosx/
        │   ├── libgphoto2.a
        │   └── headers/
        └── arm64-apple-ios/
            ├── libgphoto2.a
            └── headers/
```

## The PTPClient Protocol

```swift
public protocol PTPClient {
    func connect() async throws
    func disconnect()
    var isConnected: Bool { get }
    var cameraInfo: CameraInfo { get async }
    func readProperty(_ code: UInt16) async throws -> PropertyResponse
    func writeProperty(_ code: UInt16, value: UInt32) async throws
    func readPresetSlot(_ index: Int) async throws -> PresetData
    func writePresetSlot(_ index: Int, data: PresetData) async throws
}

public struct CameraInfo {
    public let manufacturer: String
    public let model: String
    public let firmwareVersion: String
    public let vendorExtension: VendorExtension?
    public let supportedProperties: [UInt16]
}

public enum PropertyResponse {
    case uint8(UInt8)
    case int8(Int8)
    case uint16(UInt16)
    case int16(Int16)
    case uint32(UInt32)
    case int32(Int32)
    case uint64(UInt64)
    case string(String)
    case data(Data)
}

public struct PresetData {
    public let filmSimulation: UInt16
    public let filmSimulationTune: Int16
    public let dynamicRange: UInt16
    public let colorMode: UInt16
    public let whiteBalance: UInt16
    public let whiteBalanceTune1: Int16
    public let whiteBalanceTune2: Int16
    public let colorTemperature: UInt16
    public let quality: UInt16
    public let noiseReduction: UInt16
    public let grainEffect: UInt16
    public let shadowing: UInt16
    public let wideDynamicRange: UInt16
    public let highlightTone: UInt16
    public let shadowTone: UInt16
    public let colorChrome: UInt16
    public let clarity: UInt16
    public let sharpness: Int16
    public let exposureCompensation: Int32
    public let lightTune: UInt16
    public let priorityMode: UInt16
}
```

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| iOS ImageCaptureCore may also mangle PTP | libgphoto2 iOS bundle in contingency plan |
| libgphoto2 binary size (~8MB) | Acceptable for macOS; iOS gets it only if needed |
| FFI overhead for libgphoto2 | Minimal — calls are infrequent (recipe writes) |
| App Store review for bundled C lib | Documented, stripped, notarized builds |
| libgphoto2 updates break ABI | Pin to specific version; test on every update |

## Open Questions

1. **iOS hardware testing:** Do we have an iPhone/iPad with USB-C to test iOS PTP?
2. **libgphoto2 iOS build:** Do we need a prebuilt iOS binary, or can we cross-compile at build time?
3. **App Store entitlements:** Does the macOS app need any special entitlements for USB access?
4. **libgphoto2 licensing:** libgphoto2 is LGPL — does our app comply (dynamic linking, user modifications)?

## References

- `ios-app/PTP-probe-results.md` — Session 4 probe results with byte-level analysis
- `docs/setting-to-ptp-map.md` — Fuji setting-to-PTP property mapping
- `docs/ptp-command-map.md` — PTP command reference (from previous research)
- libgphoto2 X100VI driver source (public GitHub)
