import Foundation
import FujiRecipesCore
import PTPClient
#if canImport(ImageCaptureCore)
import ImageCaptureCore
#endif

/// iOS implementation of PTPClientProtocol using ImageCaptureCore.
///
/// This implementation uses Apple's native ImageCaptureCore framework to
/// communicate with the camera via PTP. iOS handles USB connection natively
/// and may return raw PTP responses (unlike macOS ImageCaptureCore).
///
/// NOTE: This must be tested on actual iOS hardware (iPad/iPhone + USB-C).
public final class IOSSession: PTPClientProtocol, @unchecked Sendable {
    private var isConnectedFlag = false
    // TODO: Store ICDevice, ICDeviceBrowser, session references

    // MARK: - PTPClientProtocol

    public init() {}

    public var isConnected: Bool {
        isConnectedFlag
    }

    public var cameraInfo: PTPCameraInfo {
        // TODO: Extract from ICDevice properties
        PTPCameraInfo(
            model: "Fuji X100VI (iOS/ImageCaptureCore)",
            vendorExtensionId: PTPProperty.fujiVendorExtensionId
        )
    }

    public func connect() async throws {
        // TODO:
        // 1. ICDeviceBrowser — scan for connected cameras
        // 2. Match by USB VID/PID: 0x04CB:0x0305 (standard) or 0x4CB0:0x3050 (byte-swapped)
        // 3. requestOpenSession() — open PTP session
        // 4. Verify ICDeviceCanAcceptPTPCommands capability

        isConnectedFlag = true
    }

    public func disconnect() {
        // TODO: requestCloseSession()
        isConnectedFlag = false
    }

    public func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse {
        guard isConnectedFlag else { throw PTPError.notConnected }

        // TODO: requestSendPTPCommand with PTP GetDevicePropValue (0x1015)
        // PTP command structure:
        //   TransactionID (4 bytes) + OpCode (2 bytes) + Param1 (4 bytes) + ...
        //   0x1015 = GetDevicePropValue
        //   Param1 = property code (e.g., 0xD001 for film sim)
        //
        // Response handling (if ImageCaptureCore returns raw PTP):
        //   TransactionID (4 bytes) + OpCode (2 bytes) + Data...

        // Placeholder for now
        return .unsupported
    }

    public func writeProperty(_ code: UInt16, value: Int32) async throws {
        guard isConnectedFlag else { throw PTPError.notConnected }

        // TODO: requestSendPTPCommand with PTP SetDevicePropValue (0x1016)
        //   0x1016 = SetDevicePropValue
        //   Param1 = property code
        //   Param2 = value (signed 32-bit)

        // Properties are committed per-write (no separate commit needed).
    }

    public func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        guard isConnectedFlag else { throw PTPError.notConnected }
        guard (1...7).contains(index) else {
            throw PTPError.invalidResponse("Preset slot must be 1–7")
        }

        // TODO:
        // 1. SetDevicePropValue(0xD18C, index) — select slot
        // 2. GetDevicePropValue(0xD18D) → name
        // 3. GetDevicePropValue(0xD190) → DR
        // 4. GetDevicePropValue(0xD192) → film sim
        // ... etc

        return PTPClientPresetData(slot: index)
    }

    public func writePresetSlot(_ index: Int, data: PTPClientPresetData) async throws -> PTPPresetSlotWriteResult {
        guard isConnectedFlag else { throw PTPError.notConnected }
        guard (1...7).contains(index) else {
            throw PTPError.invalidResponse("Preset slot must be 1–7")
        }

        // TODO: Preset write sequence:
        // 1. SetDevicePropValue(0xD18C, index)
        // 2. SetDevicePropValue(0xD18D, name)
        // 3. SetDevicePropValue(0xD190, dr)
        // 4. SetDevicePropValue(0xD192, filmSim)
        // ... etc
        return PTPPresetSlotWriteResult(slot: index)
    }

    public func readNativeProfile() async throws -> Data {
        guard isConnectedFlag else { throw PTPError.notConnected }

        // TODO: GetDevicePropValue(0xD185) — 625 bytes
        return Data(count: 625)
    }

    public func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)?) async -> RAFConversionOutcome {
        guard isConnectedFlag else {
            return .failed(message: PTPError.notConnected.localizedDescription)
        }

        // TODO: Full RAF upload → conversion → download sequence
        return .failed(message: "RAF conversion not yet implemented for iOS")
    }

    public func capturePreview() async throws -> JPEGFile? {
        guard isConnectedFlag else { throw PTPError.notConnected }

        // TODO: CapturePreview (0x1006) → download JPEG
        throw PTPError.platformError("Preview capture not yet implemented for iOS")
    }

    public func writePTPSettings(from recipe: Recipe) async throws {
        guard isConnectedFlag else { throw PTPError.notConnected }

        // TODO: Write each property via ImageCaptureCore PTP
        // This needs the full PTP write sequence per property
        throw PTPError.platformError("PTP settings write not yet implemented for iOS")
    }
}
