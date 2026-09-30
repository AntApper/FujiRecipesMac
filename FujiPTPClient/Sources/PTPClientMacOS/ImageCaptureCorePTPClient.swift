@preconcurrency import Dispatch
import Foundation
import FujiRecipesCore
import PTPClient

/// macOS camera transport backed by Apple's ImageCaptureCore broker.
///
/// This is deliberately separate from the raw-libusb helper while the
/// X100VI vendor-command codec is being validated. ImageCaptureCore owns the
/// camera session, so this transport does not compete with `ptpcamerad`.
public final class ImageCaptureCorePTPClient: PTPClientProtocol, @unchecked Sendable {
    private let state: NativePTPSession

    public init() {
        state = NativePTPSession(provider: ImageCaptureCoreDeviceProvider.shared)
    }

    /// The injected boundary keeps lifecycle tests independent of USB hardware.
    init(deviceProvider: any NativePTPDeviceProvider, scheduler: any NativePTPDeadlineScheduler = DispatchPTPDeadlineScheduler()) {
        state = NativePTPSession(provider: deviceProvider, scheduler: scheduler)
    }

    deinit { state.disconnect() }

    public var isConnected: Bool {
        state.isConnected
    }

    public var cameraInfo: PTPCameraInfo {
        PTPCameraInfo(
            model: state.cameraName,
            vendorExtensionId: PTPProperty.fujiVendorExtensionId
        )
    }

    public func connect() async throws {
        try await state.connect()
    }

    public func disconnect() {
        let semaphore = DispatchSemaphore(value: 0)
        state.disconnect {
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
    }

    public func setDisconnectHandler(_ handler: (@Sendable () -> Void)?) {
        state.setDisconnectHandler(handler)
    }

    public func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse {
        let result = try await state.send(
            command: PTPPacket.command(operation: 0x1015, parameters: [UInt32(code)]),
            outData: nil
        )
        guard let payload = result.data else {
            throw PTPError.readFailed(code, "Camera returned no property data.")
        }
        if code == 0xD18D {
            return .data(payload)
        }
        switch payload.count {
        case 1:
            return .uint32(UInt32(payload[0]))
        case 2:
            return .uint32(UInt32(payload[0]) | (UInt32(payload[1]) << 8))
        case 4:
            return .uint32(payload.u32LE(at: 0))
        default:
            return .data(payload)
        }
    }

    public func writeProperty(_ code: UInt16, value: Int32) async throws {
        let raw = UInt16(truncatingIfNeeded: value)
        _ = try await state.send(
            command: PTPPacket.command(operation: 0x1016, parameters: [UInt32(code)]),
            outData: Data([UInt8(raw & 0xff), UInt8(raw >> 8)])
        )
    }

    public func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        guard (1...7).contains(index) else {
            throw PTPError.invalidResponse("Preset slot must be 1–7")
        }
        try await writeProperty(0xD18C, value: Int32(index))
        try await Task.sleep(nanoseconds: 120_000_000)

        let values = try await Self.readPresetValues(using: self)
        return Self.presetData(slot: index, values: values)
    }

    /// A never-configured slot reads as an empty name and zero for every
    /// numeric property.
    static func presetData(slot: Int, values: [UInt16: PTPPropertyResponse]) -> PTPClientPresetData {
        let name = stringValue(values[0xD18D])
        let isEmptySlot = name.isEmpty && presetPropertyCodes
            .filter { $0 != 0xD18D }
            .allSatisfy { uintValue(values[$0]) == 0 }
        return PTPClientPresetData(
            slot: slot,
            name: name,
            isEmptySlot: isEmptySlot,
            imageQuality: Self.uintValue(values[0xD18F]),
            imageSize: Self.uintValue(values[0xD18E]),
            dynamicRange: Self.uintValue(values[0xD190]),
            filmSimulation: Self.uintValue(values[0xD192]),
            monoWarmCool: Self.intValue(values[0xD193]),
            monoMagentaGreen: Self.intValue(values[0xD194]),
            grainEffect: Self.uintValue(values[0xD195]),
            colorChrome: Self.uintValue(values[0xD196]),
            colorChromeFxBlue: Self.uintValue(values[0xD197]),
            smoothSkin: Self.uintValue(values[0xD198]),
            whiteBalance: Self.uintValue(values[0xD199]),
            wbShiftRed: Self.intValue(values[0xD19A]),
            wbShiftBlue: Self.intValue(values[0xD19B]),
            colorTemp: Self.uintValue(values[0xD19C]),
            highlight: Self.intValue(values[0xD19D]),
            shadow: Self.intValue(values[0xD19E]),
            color: Self.intValue(values[0xD19F]),
            sharpness: Self.intValue(values[0xD1A0]),
            highIsoNr: Self.uintValue(values[0xD1A1]),
            clarity: Self.intValue(values[0xD1A2]),
            longExpNr: Self.uintValue(values[0xD1A3]),
            colorSpace: Self.uintValue(values[0xD1A4])
        )
    }

    public func writePresetSlot(
        _ index: Int,
        data: PTPClientPresetData
    ) async throws -> PTPPresetSlotWriteResult {
        guard (1...7).contains(index) else {
            throw PTPError.invalidResponse("Preset slot must be 1–7")
        }

        // 1. Select target slot on camera
        try await writeProperty(0xD18C, value: Int32(index))
        let initial = try await readPresetSlot(index)
        let wasEmpty = initial.isEmptySlot

        // 2. Write slot name if provided
        if !data.name.isEmpty {
            try await writeRawProperty(0xD18D, payload: CameraPresetName.ptpPayload(for: data.name, slot: index))
        }

        // 3. Resolve effective modes for conditional field gating
        let effectiveFilmSim = data.filmSimulation ?? initial.filmSimulation
        let effectiveWB = data.whiteBalance ?? initial.whiteBalance
        let isMono = Self.isMonochromeFilmSim(effectiveFilmSim)
        let isColorTempWB = effectiveWB == 0x8007

        var warnings: [String] = []

        // 4. Write film simulation first so camera mode updates before tone/color settings
        if let sim = data.filmSimulation {
            try await writeProperty(0xD192, value: Int32(sim))
        }

        // 5. Write white balance mode next
        if let wb = data.whiteBalance {
            try await writeProperty(0xD199, value: Int32(wb))
        }

        // 6. Write color temperature only when in Color Temperature WB mode (0x8007)
        if isColorTempWB, let colorTemp = data.colorTemp, colorTemp != 0 {
            await writeConditionalProperty(0xD19C, value: Int32(colorTemp), warnings: &warnings)
        }

        // 7. Write white balance shifts
        if let shiftR = data.wbShiftRed {
            try await writeProperty(0xD19A, value: shiftR)
        }
        if let shiftB = data.wbShiftBlue {
            try await writeProperty(0xD19B, value: shiftB)
        }

        // 8. Write tone and saturation settings respecting monochrome eligibility
        if isMono {
            if let warmCool = data.monoWarmCool {
                await writeConditionalProperty(0xD193, value: warmCool, warnings: &warnings)
            }
            if let magentaGreen = data.monoMagentaGreen {
                await writeConditionalProperty(0xD194, value: magentaGreen, warnings: &warnings)
            }
        } else {
            if let color = data.color {
                await writeConditionalProperty(0xD19F, value: color, warnings: &warnings)
            }
        }

        // 9. Write remaining preset properties
        let otherProperties: [(UInt16, Int32?, Bool)] = [
            (0xD18E, data.imageSize.map(Int32.init), false),
            (0xD18F, data.imageQuality.map(Int32.init), false),
            (0xD190, data.dynamicRange.map(Int32.init), false),
            (0xD195, data.grainEffect.map(Int32.init), false),
            (0xD196, data.colorChrome.map(Int32.init), false),
            (0xD197, data.colorChromeFxBlue.map(Int32.init), true),
            (0xD198, data.smoothSkin.map(Int32.init), true),
            (0xD19D, data.highlight, false),
            (0xD19E, data.shadow, false),
            (0xD1A0, data.sharpness, false),
            (0xD1A1, data.highIsoNr.map(Int32.init), false),
            (0xD1A2, data.clarity, false),
            (0xD1A3, data.longExpNr.map(Int32.init), false),
            (0xD1A4, data.colorSpace.map(Int32.init), false)
        ]

        for (code, value, conditional) in otherProperties {
            guard let value else { continue }
            if conditional {
                await writeConditionalProperty(code, value: value, warnings: &warnings)
            } else {
                do {
                    try await writeProperty(code, value: value)
                } catch PTPError.unknown(0x201C) {
                    warnings.append(String(format: "0x%04X: 0x201C", code))
                }
            }
        }

        let observed = try await readPresetSlot(index)
        return PTPPresetSlotWriteResult(
            slot: index,
            createdFromEmpty: wasEmpty,
            warnings: warnings,
            observedSnapshot: observed
        )
    }

    private func writeConditionalProperty(_ code: UInt16, value: Int32, warnings: inout [String]) async {
        do {
            try await writeProperty(code, value: value)
        } catch PTPError.unknown(0x201C) {
            warnings.append(String(format: "0x%04X: 0x201C", code))
        } catch {
            warnings.append(String(format: "0x%04X: %@", code, error.localizedDescription))
        }
    }

    public static func isMonochromeFilmSim(_ raw: UInt32?) -> Bool {
        guard let raw else { return false }
        return (raw >= 6 && raw <= 10) || (raw >= 12 && raw <= 15)
    }

    public func readNativeProfile() async throws -> Data {
        let result = try await readProperty(0xD185)
        guard case .data(let data) = result, !data.isEmpty else {
            throw PTPError.readFailed(0xD185, "Camera returned no native profile data.")
        }
        return data
    }

    public func writePTPSettings(from recipe: Recipe) async throws {
        if let value = recipe.filmSimulation {
            try await writeProperty(0xD192, value: Int32(value.rawValue))
        }
        if let value = recipe.dynamicRange {
            try await writeProperty(0xD190, value: Int32(value.rawValue))
        }
        if let value = recipe.grainEffect {
            try await writeProperty(0xD195, value: Int32(value.rawValue))
        }
        if let value = recipe.colorChrome {
            try await writeProperty(0xD196, value: Int32(value.rawValue))
        }
        if let value = recipe.colorChromeFxBlue {
            try await writeProperty(0xD197, value: Int32(value.rawValue))
        }
        if let value = recipe.smoothSkin {
            try await writeProperty(0xD198, value: Int32(value.rawValue))
        }
        if let value = recipe.whiteBalanceMode {
            try await writeProperty(0xD199, value: Int32(value.rawValue))
        }
        if let value = recipe.colorTempK {
            try await writeProperty(0xD19C, value: Int32(value))
        }
        if let value = recipe.wbShiftRed {
            try await writeProperty(0xD19A, value: value)
        }
        if let value = recipe.wbShiftBlue {
            try await writeProperty(0xD19B, value: value)
        }
        if let value = recipe.highlight {
            try await writeProperty(0xD19D, value: value)
        }
        if let value = recipe.shadow {
            try await writeProperty(0xD19E, value: value)
        }
        if let value = recipe.color {
            try await writeProperty(0xD19F, value: value)
        }
        if let value = recipe.sharpness {
            try await writeProperty(0xD1A0, value: value)
        }
        if let value = recipe.clarity {
            try await writeProperty(0xD1A2, value: value)
        }
        if let value = recipe.highIsoNr {
            try await writeProperty(0xD1A1, value: value)
        }
    }

    public func convertRAF(
        _ raf: RAFFile,
        profileModifier: ((inout Data) -> Void)?
    ) async -> RAFConversionOutcome {
        .failed(message: "RAF conversion is not implemented by ImageCaptureCore transport.")
    }

    public func capturePreview() async throws -> JPEGFile? {
        throw PTPError.platformError("Preview capture is not implemented by ImageCaptureCore transport.")
    }

    private static let presetPropertyCodes: [UInt16] = [
        0xD18D, 0xD18E, 0xD18F, 0xD190, 0xD192, 0xD193, 0xD194,
        0xD195, 0xD196, 0xD197, 0xD198, 0xD199, 0xD19A, 0xD19B,
        0xD19C, 0xD19D, 0xD19E, 0xD19F, 0xD1A0, 0xD1A1, 0xD1A2,
        0xD1A3, 0xD1A4
    ]

    private static func readPresetValues(
        using client: ImageCaptureCorePTPClient
    ) async throws -> [UInt16: PTPPropertyResponse] {
        var values: [UInt16: PTPPropertyResponse] = [:]
        for code in presetPropertyCodes {
            values[code] = try await client.readProperty(code)
        }
        return values
    }

    private static func uintValue(_ response: PTPPropertyResponse?) -> UInt32? {
        switch response {
        case .uint32(let value): return value
        case .int32(let value): return UInt32(bitPattern: value)
        default: return nil
        }
    }

    private static func intValue(_ response: PTPPropertyResponse?) -> Int32? {
        switch response {
        case .uint32(let value):
            // Fuji camera tone/shift properties are signed 16-bit values.
            // If the raw response was a 16-bit payload zero-extended to uint32,
            // sign-extend it so e.g. 0xFFF6 (65526) becomes -10 rather than +65526.
            if value > 0x7FFF && value <= 0xFFFF {
                return Int32(Int16(bitPattern: UInt16(value)))
            }
            return Int32(bitPattern: value)
        case .int32(let value):
            return value
        default:
            return nil
        }
    }

    private static func stringValue(_ response: PTPPropertyResponse?) -> String {
        guard case .data(let data) = response, !data.isEmpty else { return "" }
        let numChars = Int(data[0])
        guard numChars > 1 else { return "" }
        let characterCount = min(numChars - 1, (data.count - 1) / 2)
        var scalars = String.UnicodeScalarView()
        for index in 0..<characterCount {
            let offset = 1 + index * 2
            guard offset + 1 < data.count else { break }
            let scalar = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            if scalar != 0, let unicode = UnicodeScalar(scalar) {
                scalars.append(unicode)
            }
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func writeRawProperty(_ code: UInt16, payload: Data) async throws {
        _ = try await state.send(
            command: PTPPacket.command(operation: 0x1016, parameters: [UInt32(code)]),
            outData: payload
        )
    }
}

enum PTPPacket {
    static func command(operation: UInt16, parameters: [UInt32]) -> Data {
        var bytes = Data(count: 12 + parameters.count * 4)
        bytes.setU32LE(UInt32(bytes.count), at: 0)
        bytes.setU16LE(0x0001, at: 4)
        bytes.setU16LE(operation, at: 6)
        bytes.setU32LE(0, at: 8)
        for (index, parameter) in parameters.enumerated() {
            bytes.setU32LE(parameter, at: 12 + index * 4)
        }
        return bytes
    }
}

extension Data {
    func u16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func u32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    mutating func setU16LE(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(value & 0xff)
        self[offset + 1] = UInt8(value >> 8)
    }

    mutating func setU32LE(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(value & 0xff)
        self[offset + 1] = UInt8((value >> 8) & 0xff)
        self[offset + 2] = UInt8((value >> 16) & 0xff)
        self[offset + 3] = UInt8((value >> 24) & 0xff)
    }
}
