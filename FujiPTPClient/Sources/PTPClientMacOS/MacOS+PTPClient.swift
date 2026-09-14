import Foundation
import FujiRecipesCore
import PTPClient

// MARK: - Configuration Path Mapping

fileprivate enum ConfigPath {
    static let filmSim = "/main/settings/filmsim"
    static let color = "/main/settings/color"
    static let dynamicRange = "/main/settings/dr"
    static let whiteBalance = "/main/settings/wb"
    static let wbRed = "/main/settings/wbshift/r"
    static let wbBlue = "/main/settings/wbshift/b"
    static let colorTemp = "/main/settings/wb/kelvin"
    static let highlight = "/main/settings/highlight"
    static let shadow = "/main/settings/shadow"
    static let sharpness = "/main/settings/sharpness"
    static let highIsoNr = "/main/settings/noisereduction"
    static let grain = "/main/settings/grain"
    static let colorChrome = "/main/settings/colorchrome"
    static let iso = "/main/settings/iso"
    static let exposureComp = "/main/settings/ev"
    static let clarity = "/main/settings/clarity"
}

// MARK: - PTP Property to Config Path Mapping

fileprivate enum PTPConfigMapping {
    struct Mapping: Sendable {
        let path: String
        let readConverter: @Sendable (String) -> Int32?
        let writeConverter: @Sendable (Int32) -> String?
    }
    
    static let properties: [UInt16: Mapping] = [
        PTPProperty.filmSimulation: Mapping(
            path: ConfigPath.filmSim,
            readConverter: { Int32($0) },
            writeConverter: { String($0) }
        ),
        PTPProperty.color: Mapping(
            path: ConfigPath.color,
            readConverter: { Int32($0) },
            writeConverter: { String($0) }
        ),
        PTPProperty.dynamicRange: Mapping(
            path: ConfigPath.dynamicRange,
            readConverter: { Int32($0) ?? -1 },
            writeConverter: { String($0) }
        ),
        PTPProperty.whiteBalance: Mapping(
            path: ConfigPath.whiteBalance,
            readConverter: { Int32($0) },
            writeConverter: { String($0) }
        ),
        PTPProperty.wbShiftRed: Mapping(
            path: ConfigPath.wbRed,
            readConverter: { Int32($0) },
            writeConverter: { String($0) }
        ),
        PTPProperty.wbShiftBlue: Mapping(
            path: ConfigPath.wbBlue,
            readConverter: { Int32($0) },
            writeConverter: { String($0) }
        ),
        PTPProperty.colorTemp: Mapping(
            path: ConfigPath.colorTemp,
            readConverter: { Int32($0) },
            writeConverter: { String($0) }
        ),
        PTPProperty.highlight: Mapping(
            path: ConfigPath.highlight,
            readConverter: { Int32($0) },
            writeConverter: { String($0) }
        ),
        PTPProperty.shadow: Mapping(
            path: ConfigPath.shadow,
            readConverter: { Int32($0) },
            writeConverter: { String($0) }
        ),
        PTPProperty.sharpness: Mapping(
            path: ConfigPath.sharpness,
            readConverter: { Int32($0) },
            writeConverter: { String($0) }
        ),
        PTPProperty.highIsoNr: Mapping(
            path: ConfigPath.highIsoNr,
            readConverter: { Int32($0) },
            writeConverter: { String($0) }
        ),
        PTPProperty.grainEffect: Mapping(
            path: ConfigPath.grain,
            readConverter: { Int32($0) },
            writeConverter: { String($0) }
        ),
        PTPProperty.iso: Mapping(
            path: ConfigPath.iso,
            readConverter: { Int32($0) },
            writeConverter: { String($0) }
        ),
        PTPProperty.exposureCompensation: Mapping(
            path: ConfigPath.exposureComp,
            readConverter: { Int32($0) },
            writeConverter: { String($0) }
        ),
    ]
}

// MARK: - MacOSSession

public final class MacOSSession: PTPClientProtocol, @unchecked Sendable {
    private let bridge = PTPHelperBridge()
    private var connected = false
    private var _ptpTransactionID: UInt32 = 1
    private var cameraInfoCache: PTPCameraInfo?

    public init() {}
    
    public var isConnected: Bool { connected }
    
    public var cameraInfo: PTPCameraInfo {
        guard let info = cameraInfoCache else {
            return PTPCameraInfo(
                model: "Not connected",
                vendorExtensionId: PTPProperty.fujiVendorExtensionId
            )
        }
        return info
    }
    
    // MARK: - Connect

    public func connect() async throws {
        debugLog("🔌 Starting camera connection via FujiPTPHelper...")

        // Send connect command to helper (handles libgphoto2 init, PTPCamera kill, camera init)
        let result = try await bridge.sendCommand("connect", timeout: 30.0)
        
        if result != "ok" {
            throw PTPError.connectionFailed("Helper reported: \(result)")
        }

        connected = true

        // Get camera info
        let infoJSON = try await bridge.sendCommand("cameraInfo", timeout: 10.0)
        cameraInfoCache = Self.parseCameraInfo(from: infoJSON)

        debugLog("✅ Connected to Fuji X100VI via FujiPTPHelper")
    }
    
    // MARK: - Disconnect

    public func disconnect() {
        guard connected else { return }
        
        connected = false
        cameraInfoCache = nil
        
        // Fire-and-forget disconnect command (don't block)
        Task { @MainActor in
            _ = try? await bridge.sendCommand("disconnect", timeout: 3.0)
        }
        
        debugLog("✅ Disconnected from camera")
    }
    
    // MARK: - Read Property

    public func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse {
        guard connected else { throw PTPError.notConnected }
        
        guard let mapping = PTPConfigMapping.properties[code] else {
            return .unsupported
        }
        
        // Send readProperty command to helper
        let result = try await bridge.sendCommand(
            "readProperty",
            parameters: ["code": code],
            timeout: 10.0
        )
        
        if result.hasPrefix("ERROR:") {
            return .error(PTPError.readFailed(code, String(result.dropFirst(6))))
        }
        
        // Result is a string value from the config tree; convert via the mapping.
        if let intValue = mapping.readConverter(result) {
            if intValue >= 0 {
                return .uint32(UInt32(intValue))
            } else {
                return .int32(intValue)
            }
        }
        return .string(result)
    }
    
    // MARK: - Write Property

    public func writeProperty(_ code: UInt16, value: Int32) async throws {
        guard connected else { throw PTPError.notConnected }
        
        guard let mapping = PTPConfigMapping.properties[code] else {
            throw PTPError.writeFailed(code, "No config path mapping for property 0x\(String(code, radix: 16))")
        }
        
        guard let stringValue = mapping.writeConverter(value) else {
            throw PTPError.writeFailed(code, "Failed to convert value \(value)")
        }
        
        let result = try await bridge.sendCommand(
            "writeProperty",
            parameters: ["code": code, "value": stringValue],
            timeout: 10.0
        )
        
        if result.hasPrefix("ERROR:") {
            throw PTPError.writeFailed(code, String(result.dropFirst(6)))
        }
    }
    
    // MARK: - Preset Slot

    public func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        guard connected else { throw PTPError.notConnected }
        guard (1...7).contains(index) else {
            throw PTPError.invalidResponse("Preset slot must be 1–7")
        }
        
        let result = try await bridge.sendCommand(
            "readPresetSlot",
            parameters: ["index": index],
            timeout: 10.0
        )
        
        if result.hasPrefix("ERROR:") {
            throw PTPError.readFailed(0xD18C, String(result.dropFirst(6)))
        }
        
        // Result is Base64-encoded JSON preset data
        guard let data = Self.parsePresetData(from: result) else {
            throw PTPError.readFailed(0xD18C, "Failed to parse preset data")
        }
        return data
    }
    
    public func writePresetSlot(_ index: Int, data: PTPClientPresetData) async throws -> PTPPresetSlotWriteResult {
        guard connected else { throw PTPError.notConnected }
        guard (1...7).contains(index) else {
            throw PTPError.invalidResponse("Preset slot must be 1–7")
        }
        
        let params = Self.encodePresetData(data)
        let result = try await bridge.sendCommand(
            "writePresetSlot",
            parameters: ["index": index, "data": params],
            timeout: 10.0
        )
        
        if result.hasPrefix("ERROR:") {
            throw PTPError.writeFailed(0xD18C, String(result.dropFirst(6)))
        }
        return PTPPresetSlotWriteResult(slot: index)
    }
    
    // MARK: - Native Profile

    public func readNativeProfile() async throws -> Data {
        guard connected else { throw PTPError.notConnected }
        
        let result = try await bridge.sendCommand(
            "readNativeProfile",
            timeout: 10.0
        )
        
        if result.hasPrefix("ERROR:") {
            throw PTPError.readFailed(0xD185, String(result.dropFirst(6)))
        }
        
        // Result is Base64-encoded data
        guard let data = Data(base64Encoded: result) else {
            throw PTPError.readFailed(0xD185, "Failed to decode profile data")
        }
        return data
    }
    
    // MARK: - RAF Conversion

    public func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)? = nil) async -> RAFConversionOutcome {
        // Note: profileModifier is not supported via the helper bridge (protocol limitation).
        guard connected else {
            return .failed(message: PTPError.notConnected.localizedDescription)
        }
        
        // Encode RAF as Base64
        let base64 = raf.data.base64EncodedString()
        
        let result: String
        do {
            result = try await bridge.sendCommand(
                "convertRAF",
                parameters: [
                    "name": raf.name,
                    "base64": base64,
                ],
                timeout: 60.0  // RAF conversion takes longer
            )
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(message: error.localizedDescription)
        }
        
        if result.hasPrefix("ERROR:") {
            return .failed(message: PTPError.commandFailed(0xD183, String(result.dropFirst(6))).localizedDescription)
        }
        
        // Result is Base64-encoded JPEG
        guard let jpegData = Data(base64Encoded: result) else {
            return .failed(message: PTPError.commandFailed(0x900D, "Failed to decode JPEG data").localizedDescription)
        }
        
        return .downloadedJPEG(JPEGFile(
            name: "converted.jpg",
            data: jpegData,
            size: UInt32(jpegData.count),
            storageID: 0xFFFFFFFF,
            objectHandle: 0
        ))
    }
    
    // MARK: - Capture Preview

    public func capturePreview() async throws -> JPEGFile? {
        guard connected else { throw PTPError.notConnected }
        
        let result = try await bridge.sendCommand(
            "capturePreview",
            timeout: 15.0
        )
        
        if result.hasPrefix("ERROR:") {
            throw PTPError.commandFailed(0x1006, String(result.dropFirst(6)))
        }
        
        // Result is Base64-encoded JPEG
        guard let jpegData = Data(base64Encoded: result) else {
            throw PTPError.commandFailed(0x1006, "Failed to decode preview data")
        }
        
        return JPEGFile(
            name: "preview.jpg",
            data: jpegData,
            size: UInt32(jpegData.count),
            storageID: 0xFFFFFFFF,
            objectHandle: 0
        )
    }
    
    // MARK: - Write Recipe

    public func writePTPSettings(from recipe: Recipe) async throws {
        guard connected else { throw PTPError.notConnected }
        
        if let fs = recipe.filmSimulation {
            try await writeProperty(PTPProperty.filmSimulation, value: Int32(fs.rawValue))
        }
        if let dr = recipe.dynamicRange {
            try await writeProperty(PTPProperty.dynamicRange, value: Int32(dr.rawValue))
        }
        if let grain = recipe.grainEffect {
            try await writeProperty(PTPProperty.grainEffect, value: Int32(grain.rawValue))
        }
        if let wb = recipe.whiteBalanceMode {
            try await writeProperty(PTPProperty.whiteBalance, value: Int32(wb.actualPTPValue))
        }
        if let color = recipe.color {
            try await writeProperty(PTPProperty.color, value: color)
        }
        if let highlight = recipe.highlight {
            try await writeProperty(PTPProperty.highlight, value: highlight)
        }
        if let shadow = recipe.shadow {
            try await writeProperty(PTPProperty.shadow, value: shadow)
        }
        if let sharpness = recipe.sharpness {
            try await writeProperty(PTPProperty.sharpness, value: sharpness)
        }
        if let isoNr = recipe.highIsoNr {
            try await writeProperty(PTPProperty.highIsoNr, value: isoNr)
        }
        if let wbRed = recipe.wbShiftRed {
            try await writeProperty(PTPProperty.wbShiftRed, value: wbRed)
        }
        if let wbBlue = recipe.wbShiftBlue {
            try await writeProperty(PTPProperty.wbShiftBlue, value: wbBlue)
        }
        // Clarity is only available in preset properties (0xD1A2), not as an
        // active shooting property on the X100VI in USB RAW mode.
    }
    
    // MARK: - Helpers

    private static func parseCameraInfo(from json: String) -> PTPCameraInfo? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = dict["model"] as? String else {
            return nil
        }
        return PTPCameraInfo(
            model: model,
            vendorExtensionId: (dict["vendorExtensionId"] as? UInt32) ?? 0x0000000E
        )
    }

    private static func parsePresetData(from base64: String) -> PTPClientPresetData? {
        guard let data = Data(base64Encoded: base64),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return PTPClientPresetData(
            slot: dict["slot"] as? Int ?? 0,
            name: dict["name"] as? String ?? "",
            imageQuality: dict["imageQuality"] as? UInt32,
            imageSize: dict["imageSize"] as? UInt32,
            dynamicRange: dict["dynamicRange"] as? UInt32,
            filmSimulation: dict["filmSimulation"] as? UInt32,
            grainEffect: dict["grainEffect"] as? UInt32,
            colorChrome: dict["colorChrome"] as? UInt32,
            colorChromeFxBlue: dict["colorChromeFxBlue"] as? UInt32,
            smoothSkin: dict["smoothSkin"] as? UInt32,
            whiteBalance: dict["whiteBalance"] as? UInt32,
            wbShiftRed: dict["wbShiftRed"] as? Int32,
            wbShiftBlue: dict["wbShiftBlue"] as? Int32,
            colorTemp: dict["colorTemp"] as? UInt32,
            highlight: dict["highlight"] as? Int32,
            shadow: dict["shadow"] as? Int32,
            color: dict["color"] as? Int32,
            sharpness: dict["sharpness"] as? Int32,
            highIsoNr: dict["highIsoNr"] as? UInt32,
            clarity: dict["clarity"] as? Int32,
            longExpNr: dict["longExpNr"] as? UInt32,
            colorSpace: dict["colorSpace"] as? UInt32
        )
    }

    private static func encodePresetData(_ data: PTPClientPresetData) -> [String: Any] {
        [
            "name": data.name,
            "imageSize": data.imageSize ?? 0,
            "imageQuality": data.imageQuality ?? 0,
            "dynamicRange": data.dynamicRange ?? 0,
            "filmSimulation": data.filmSimulation ?? 0,
            "grainEffect": data.grainEffect ?? 0,
            "colorChrome": data.colorChrome ?? 0,
            "colorChromeFxBlue": data.colorChromeFxBlue ?? 0,
            "smoothSkin": data.smoothSkin ?? 0,
            "whiteBalance": data.whiteBalance ?? 0,
            "wbShiftRed": data.wbShiftRed ?? 0,
            "wbShiftBlue": data.wbShiftBlue ?? 0,
            "colorTemp": data.colorTemp ?? 0,
            "highlight": data.highlight ?? 0,
            "shadow": data.shadow ?? 0,
            "color": data.color ?? 0,
            "sharpness": data.sharpness ?? 0,
            "highIsoNr": data.highIsoNr ?? 0,
            "clarity": data.clarity ?? 0,
            "longExpNr": data.longExpNr ?? 0,
            "colorSpace": data.colorSpace ?? 0,
        ]
    }
}
