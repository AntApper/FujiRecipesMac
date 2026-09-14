# FujiPTPClient

PTP communication abstraction layer for Fuji X100VI. Platform-specific implementations for macOS (libgphoto2) and iOS (ImageCaptureCore).

## Package

- **Swift Tools Version:** 6.0
- **Platforms:** iOS 17+, macOS 14+
- **Dependencies:** FujiRecipesCore

## Structure

```
FujiPTPClient/
├── Package.swift
├── Sources/PTPClient/
│   └── PTPClient.swift           # PTPClientProtocol + data types
├── Sources/PTPClientMacOS/
│   └── MacOS+PTPClient.swift     # libgphoto2 FFI implementation
└── Sources/PTPClientiOS/
    └── iOS+PTPClient.swift       # ImageCaptureCore implementation
```

## Protocol

```swift
public protocol PTPClientProtocol: Sendable {
    func connect() async throws
    func disconnect()
    var isConnected: Bool { get }
    var cameraInfo: CameraInfo { get async }
    func readProperty(_ code: UInt16) async throws -> PropertyResponse
    func writeProperty(_ code: UInt16, value: UInt32) async throws
    func readPresetSlot(_ index: Int) async throws -> PresetData
    func writePresetSlot(_ index: Int, data: PresetData) async throws
    func readNativeProfile() async throws -> Data
}
```

## Platform Implementations

### macOS (MacOSSession)

Uses **libgphoto2** for PTP communication. libgphoto2 provides built-in Fuji X100VI vendor extension support.

**TODO:**
- Build/prebundle `libgphoto2` static library (`arm64` + `x86_64`)
- Wire up `gp_camera_init()`, `gp_camera_set_config()`, `gp_camera_get_config()`
- Map PTP property codes to libgphoto2 config keys

### iOS (IOSSession)

Uses **ImageCaptureCore** (`requestSendPTPCommand`). Untested on actual hardware.

**TODO:**
- Test `requestSendPTPCommand` on iPad/iPhone + X100VI via USB-C
- Parse raw PTP responses (macOS ImageCaptureCore wraps them — iOS may not)
- Implement PTP command builders (GetDevicePropValue, SetDevicePropValue)

## Usage

```swift
import FujiPTPClient

// Choose implementation based on platform
#if os(macOS)
    let session = MacOSSession()
#else
    let session = IOSSession()
#endif

// Connect
try await session.connect()

// Read film sim from camera
let response = try await session.readProperty(PTPProperty.filmSimulation)
if case .uint32(let val) = response {
    print("Film sim: \(val)")
}

// Write a recipe to C1 slot
let preset = PresetData(
    slot: 1,
    name: "My Recipe",
    filmSimulation: 20,  // Reala Ace
    dynamicRange: 200,
    // ...
)
try await session.writePresetSlot(1, data: preset)

// Disconnect
session.disconnect()
```

## Known Issues

- macOS ImageCaptureCore **cannot** send raw PTP to Fuji cameras (Session 4 probe confirmed)
- iOS ImageCaptureCore PTP support **untested** — must be validated on hardware
- libgphoto2 bundling requires static library builds for both arm64 and x86_64
