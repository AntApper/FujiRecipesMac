// GPhoto2PTPClient.swift
// PTPClientProtocol implementation using gphoto2 CLI.

import Foundation
import FujiRecipesCore

/// PTPClientProtocol implementation that shells out to the gphoto2 CLI.
public final class GPhoto2PTPClient: PTPClientProtocol, @unchecked Sendable {
    public init() {}
    
    private let cli = GPhoto2CLI()
    private let queue = DispatchQueue(label: "com.fujirecipes.gphoto2cli", qos: .userInitiated)
    private var _isConnected = false
    public var isConnected: Bool { _isConnected }
    
    private var _cameraInfo: PTPCameraInfo = PTPCameraInfo(model: "Not connected")
    public var cameraInfo: PTPCameraInfo { _cameraInfo }
    
    // Property code mapping
    private static let propertyMap: [UInt16: String] = [
        0xD001: "/main/settings/filmsim",
        0xD002: "/main/settings/color",
        0xD007: "/main/settings/dr",
        0x5005: "/main/settings/wb",
        0xD00B: "/main/settings/wbshift/r",
        0xD00C: "/main/settings/wbshift/b",
        0xD017: "/main/settings/wb/kelvin",
        0xD018: "/main/settings/quality",
        0xD01C: "/main/settings/noisereduction",
        0xD023: "/main/settings/grain",
        0xD029: "/main/settings/shadowing",
        0xD02E: "/main/settings/wide_dynamic_range",
        0xD104: "/main/settings/black_point_tone",
        0xD185: "/main/settings/native_profile",
    ]
    

    
    public var cameraInfoValue: PTPCameraInfo {
        queue.sync { cameraInfo }
    }
    
    // MARK: - Connect
    
    public func connect() async throws {
        try queue.sync {
            // Kill PTPCamera daemon
            let killTask = Process()
            killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            killTask.arguments = ["-9", "ptpcamerad"]
            try? killTask.run()
            killTask.waitUntilExit()
            sleep(1)
            
            // Test connection
            let summary = try cli.run(["--summary"])
            
            // Parse camera info
            let info = parseCameraInfo(summary)
            _cameraInfo = info
            _isConnected = true
        }
    }
    
    // MARK: - Disconnect
    
    public func disconnect() {
        queue.sync {
            _isConnected = false
        }
    }
    
    // MARK: - Read Property
    
    public func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse {
        try queue.sync {
            // Check if this is a preset slot property
            if code == 0xD18C {
                // Preset slot select - return current slot
                let output = try cli.run(["--get-config", "/main/settings/preset_slot", "--format=raw"])
                if let value = parseConfigValue(output) {
                    if let slot = UInt32(value) {
                        return .uint32(slot)
                    }
                }
                return .uint32(1) // Default to C1
            }
            
            // Check if this is a preset slot name property
            if code == 0xD18D {
                // Preset slot name
                let output = try cli.run(["--get-config", "/main/settings/preset_name", "--format=raw"])
                if let value = parseConfigValue(output) {
                    return .string(value)
                }
                return .string("")
            }
            
            guard let configPath = Self.propertyMap[code] else {
                return .unsupported
            }
            
            do {
                let output = try cli.run(["--get-config", configPath])
                
                // Parse the value from output
                if let value = parseConfigValue(output) {
                    // Try to convert to appropriate type
                    if let intValue = UInt32(value) {
                        return .uint32(intValue)
                    } else if let intValue = Int32(value) {
                        return .int32(intValue)
                    }
                    return .string(value)
                }
                return .unsupported
            } catch {
                return .error(.readFailed(code, error.localizedDescription))
            }
        }
    }
    
    // MARK: - Write Property
    
    public func writeProperty(_ code: UInt16, value: Int32) async throws {
        try queue.sync {
            guard let configPath = Self.propertyMap[code] else {
                throw PTPError.writeFailed(code, "Unsupported property")
            }

            do {
                // Convert signed value to string for gphoto2.
                let valueStr = String(value)
                let _ = try cli.run(["--set-config", "\(configPath)=\(valueStr)"])
            } catch {
                throw PTPError.writeFailed(code, error.localizedDescription)
            }
        }
    }
    
    // MARK: - Preset Slots
    
    public func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        try queue.sync {
            // Select the slot first
            let _ = try cli.run(["--set-config", "/main/settings/preset_slot=\(index)"])
            usleep(500_000) // 0.5 seconds
            
            // Read preset slot name
            let nameOutput = try cli.run(["--get-config", "/main/settings/preset_name"])
            let name = parseConfigValue(nameOutput) ?? ""
            
            // Read all properties for this slot
            let filmSimOutput = try cli.run(["--get-config", "/main/settings/filmsim"])
            let filmSim = parseConfigValue(filmSimOutput)
            
            let drOutput = try cli.run(["--get-config", "/main/settings/dr"])
            let dr = parseConfigValue(drOutput)
            
            return PTPClientPresetData(
                slot: index,
                name: name,
                dynamicRange: dr.flatMap { UInt32($0) },
                filmSimulation: filmSim.flatMap { UInt32($0) }
            )
        }
    }
    
    public func writePresetSlot(_ index: Int, data: PTPClientPresetData) async throws -> PTPPresetSlotWriteResult {
        try queue.sync {
            // Select the slot
            let _ = try cli.run(["--set-config", "/main/settings/preset_slot=\(index)"])
            usleep(500_000) // 0.5 seconds
            
            // Write preset name
            if !data.name.isEmpty {
                let _ = try cli.run(["--set-config", "/main/settings/preset_name=\(data.name)"])
            }
            
            // Write film simulation
            if let filmSim = data.filmSimulation {
                let _ = try cli.run(["--set-config", "/main/settings/filmsim=\(filmSim)"])
            }
            
            // Write dynamic range
            if let dr = data.dynamicRange {
                let _ = try cli.run(["--set-config", "/main/settings/dr=\(dr)"])
            }
            // libgphoto2 does not expose the raw-zero C-slot sentinel, so it
            // cannot distinguish creation from update.
            return PTPPresetSlotWriteResult(slot: index)
        }
    }
    
    // MARK: - Native Profile
    
    public func readNativeProfile() async throws -> Data {
        try queue.sync {
            do {
                let output = try cli.run(["--get-config", "/main/settings/native_profile", "--format=raw"])
                // Parse binary data from output
                if let data = parseBinaryConfigValue(output) {
                    return data
                }
                return Data()
            } catch {
                throw PTPError.readFailed(0xD185, error.localizedDescription)
            }
        }
    }
    
    // MARK: - Write PTP Settings
    
    public func writePTPSettings(from recipe: Recipe) async throws {
        // Map recipe settings to PTP property codes and write them
        for (code, value) in recipe.toPTPPropertyValues() {
            try await writeProperty(code, value: value)
        }
    }
    
    // MARK: - Convert RAF
    
    public func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)?) async -> RAFConversionOutcome {
        // gphoto2 does not expose a RAW-file upload API, and the X100VI preset
        // range is not visible through its config tree.  RAF conversion is
        // intentionally unsupported via this backend; use the X100VI libusb
        // helper (`X100VIHelperClient`) instead.
        .failed(message: "RAF conversion is not supported through the gphoto2 CLI backend")
    }
    
    // MARK: - Capture Preview
    
    public func capturePreview() async throws -> JPEGFile? {
        return try queue.sync {
            let tempDir = FileManager.default.temporaryDirectory
            let jpegURL = tempDir.appendingPathComponent("preview.jpg")
            
            do {
                let _ = try cli.run(["--capture-preview", "--filename", jpegURL.path])
                
                if let jpegData = try? Data(contentsOf: jpegURL) {
                    let jpeg = JPEGFile(
                        name: "preview.jpg",
                        data: jpegData,
                        size: UInt32(jpegData.count),
                        storageID: 0xFFFFFFFF,
                        objectHandle: 0
                    )
                    return jpeg
                }
            } catch {
                throw PTPError.commandFailed(0x1006, error.localizedDescription)
            }
            
            return nil
        }
    }
    
    // MARK: - Private Helpers
    
    private func parseCameraInfo(_ summary: String) -> PTPCameraInfo {
        var model = "Not connected"
        var firmwareVersion: String?
        var vendorExtID: UInt32 = 0x0000000E
        let vendorExtVersion: UInt32 = 0
        var vendorExtDesc: String?
        
        let lines = summary.components(separatedBy: .newlines)
        for line in lines {
            if line.hasPrefix("Model:") {
                model = line.replacingOccurrences(of: "Model:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Version:") {
                firmwareVersion = line.replacingOccurrences(of: "Version:", with: "").trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("Vendor Extension ID:") {
                // Parse "0xe (1.0)"
                let parts = line.components(separatedBy: " ")
                if let hexStr = parts.first?.replacingOccurrences(of: "0x", with: "", options: .caseInsensitive),
                   let id = UInt32(hexStr, radix: 16) {
                    vendorExtID = id
                }
            } else if line.hasPrefix("Vendor Extension Description:") {
                vendorExtDesc = line.replacingOccurrences(of: "Vendor Extension Description:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        
        return PTPCameraInfo(
            model: model,
            firmwareVersion: firmwareVersion,
            vendorExtensionId: vendorExtID,
            vendorExtensionVersion: vendorExtVersion,
            vendorExtensionDescription: vendorExtDesc
        )
    }
    
    private func parseConfigValue(_ output: String) -> String? {
        // Parse gphoto2 config output for the value
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains("=") {
                let parts = line.split(separator: "=", maxSplits: 1)
                if parts.count == 2 {
                    return String(parts[1]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return nil
    }
    
    private func parseBinaryConfigValue(_ output: String) -> Data? {
        // Parse base64-encoded binary data from config output
        guard let data = Data(base64Encoded: output) else {
            return nil
        }
        return data
    }
    
    private func readPresetData(index: Int) throws -> PTPClientPresetData {
        // Read preset slot name via device property 0xD18C
        let output = try cli.run(["--get-config", "/main/settings/preset_slot", "--format=raw"])
        let name = parseConfigValue(output) ?? ""
        
        return PTPClientPresetData(
            slot: index,
            name: name
        )
    }
    
    private func writePresetData(index: Int, data: PTPClientPresetData) throws {
        // Write preset slot via device properties
        let _ = try cli.run(["--set-config", "/main/settings/preset_slot=\(index)"])
        if !data.name.isEmpty {
            let _ = try cli.run(["--set-config", "/main/settings/preset_name=\(data.name)"])
        }
    }
}

// Extension to convert Recipe to PTP property values
extension Recipe {
    func toPTPPropertyValues() -> [UInt16: Int32] {
        var values: [UInt16: Int32] = [:]
        
        if let filmSim = filmSimulation { values[0xD001] = Int32(filmSim.rawValue) }
        if let dr = dynamicRange { values[0xD007] = Int32(dr.rawValue) }
        if let wb = whiteBalanceMode { values[0x5005] = Int32(wb.actualPTPValue) }
        if let sharpness = sharpness { values[0x5015] = sharpness }
        
        return values
    }
}
