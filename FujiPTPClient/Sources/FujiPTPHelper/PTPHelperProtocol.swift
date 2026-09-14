// PTPHelperProtocol.swift
// JSON protocol types for communication between main app and FujiPTPHelper.

import Foundation

// MARK: - Request / Response

/// A request sent from the main app to the helper process.
struct PTPHelperRequest: Codable {
    let id: String
    let command: PTPHelperCommand
}

/// A response sent from the helper to the main app.
struct PTPHelperResponse: Codable {
    let id: String
    let success: Bool
    let result: String?
    let error: String?
}

// MARK: - Commands

enum PTPHelperCommand: Codable {
    // Connection
    case connect
    
    // Disconnect
    case disconnect
    
    // Status
    case isConnected
    
    // Camera info
    case cameraInfo
    
    // Property read
    case readProperty(code: UInt16)
    
    // Property write
    case writeProperty(code: UInt16, value: UInt32)
    
    // Preset slot
    case readPresetSlot(index: Int)
    case writePresetSlot(index: Int, data: PTPHelperPresetData)
    
    // Native profile
    case readNativeProfile
    
    // RAF conversion (large binary data)
    case convertRAF(name: String, size: UInt64, base64: String)
    
    // Preview capture
    case capturePreview
    
    // Process management
    case ping
    case exit
}

// MARK: - Preset Data (for preset slots)

struct PTPHelperPresetData: Codable {
    let name: String
    let imageSize: UInt32?
    let imageQuality: UInt32?
    let dynamicRange: UInt32?
    let filmSimulation: UInt32?
    let grainEffect: UInt32?
    let colorChrome: UInt32?
    let colorChromeFxBlue: UInt32?
    let smoothSkin: UInt32?
    let whiteBalance: UInt32?
    let wbShiftRed: Int32?
    let wbShiftBlue: Int32?
    let colorTemp: UInt32?
    let highlight: Int32?
    let shadow: Int32?
    let color: Int32?
    let sharpness: Int32?
    let highIsoNr: UInt32?
    let clarity: Int32?
    let longExpNr: UInt32?
    let colorSpace: UInt32?
}

// MARK: - Camera Info

struct PTPHelperCameraInfo: Codable {
    let model: String
    let vendorExtensionId: UInt32
    let vendorExtensionVersion: UInt32
    let vendorExtensionDescription: String?
}

// MARK: - Result Encoders

extension PTPHelperPresetData {
    /// Encode preset data as a JSON string for response.
    func encodeAsJSON() -> String {
        let wrapper: [String: Any] = [
            "slot": 0,
            "name": name,
            "imageSize": imageSize as Any,
            "imageQuality": imageQuality as Any,
            "dynamicRange": dynamicRange as Any,
            "filmSimulation": filmSimulation as Any,
            "grainEffect": grainEffect as Any,
            "colorChrome": colorChrome as Any,
            "colorChromeFxBlue": colorChromeFxBlue as Any,
            "smoothSkin": smoothSkin as Any,
            "whiteBalance": whiteBalance as Any,
            "wbShiftRed": wbShiftRed as Any,
            "wbShiftBlue": wbShiftBlue as Any,
            "colorTemp": colorTemp as Any,
            "highlight": highlight as Any,
            "shadow": shadow as Any,
            "color": color as Any,
            "sharpness": sharpness as Any,
            "highIsoNr": highIsoNr as Any,
            "clarity": clarity as Any,
            "longExpNr": longExpNr as Any,
            "colorSpace": colorSpace as Any,
        ]
        let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

extension PTPHelperCameraInfo {
    func encodeAsJSON() -> String {
        let wrapper: [String: Any] = [
            "model": model,
            "vendorExtensionId": vendorExtensionId,
            "vendorExtensionVersion": vendorExtensionVersion,
            "vendorExtensionDescription": vendorExtensionDescription as Any,
        ]
        let data = try? JSONSerialization.data(withJSONObject: wrapper, options: [])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
