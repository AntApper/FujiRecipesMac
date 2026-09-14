// PTPHelperSession.swift
// Camera session state and operations for the helper process.

import Foundation

// MARK: - PTP Helper Session

final class PTPHelperSession {
    private var camera: UnsafeMutableRawPointer?
    private var context: UnsafeMutableRawPointer?
    private var isConnected = false

    // MARK: - Connect

    func connect() -> String {
        func debug(_ msg: String) { fputs("[HELPER] \(msg)\n", stderr) }
        
        debug("Starting connect...")
        
        // Create context first
        debug("Creating context...")
        guard let ctx = contextNew() else {
            debug("ERROR: could not create context")
            return "error:could_not_create_context"
        }
        context = ctx
        debug("Context created")
        
        // Scan for camera
        debug("Scanning for camera...")
        guard let portPath = scanForFujiCamera() else {
            debug("ERROR: no Fuji camera found")
            return "error:no_fuji_camera_found"
        }
        debug("Found camera: \(portPath)")
        
        // Create camera
        debug("Creating camera object...")
        guard let newCamera = cameraNew() else {
            debug("ERROR: gp_camera_new failed")
            return "error:gp_camera_new_failed"
        }
        camera = newCamera
        debug("Camera object created")

        // Kill PTPCamera before camera_init
        killPTPCameraProcesses()

        // Initialize camera
        debug("Initializing camera...")
        let initResult = cameraInit(camera!, context!)
        if initResult != GP_OK {
            cameraFree(camera)
            camera = nil
            context = nil
            return "error:gp_camera_init failed (\(initResult))"
        }

        isConnected = true
        return "ok"
    }

    // MARK: - Disconnect

    func disconnect() {
        guard isConnected else { return }

        if let camera = camera, let context = context {
            let _ = cameraExit(camera, context)
        }

        if let camera = camera {
            cameraFree(camera)
        }
        camera = nil
        context = nil
        isConnected = false
    }

    // MARK: - IsConnected

    func isConnectedStatus() -> String {
        isConnected ? "true" : "false"
    }

    // MARK: - Camera Info

    func getCameraInfo() -> String? {
        guard let camera = camera else { return nil }
        
        guard let _ = cameraGetAbilities(camera) else {
            return nil
        }

        let info = PTPHelperCameraInfo(
            model: "X100VI",
            vendorExtensionId: 0x0000000E,
            vendorExtensionVersion: 0,
            vendorExtensionDescription: "FujiVendorExtension"
        )
        return info.encodeAsJSON()
    }

    // MARK: - Property Operations

    func readProperty(code: UInt16) -> String {
        return "error:property_read_not_implemented"
    }

    func writeProperty(code: UInt16, value: Int32) -> String {
        return "error:property_write_not_implemented"
    }

    func readPresetSlot(index: Int) -> String {
        guard isConnected, let camera = camera, let context = context else {
            return "error:not_connected"
        }
        
        // Select the preset slot (1-7 maps to C1-C7)
        let slotStr = String(index)
        var result = setConfigValue(camera, context, "/main/settings/preset_slot", slotStr)
        if result != GP_OK {
            return "error:slot_select_failed_\(result)"
        }
        
        // Read slot name
        guard let name = getConfigValue(camera, context, "/main/settings/preset_name") else {
            return "error:slot_name_read_failed"
        }
        
        // Read preset properties from config
        var presetData = PTPHelperPresetData(
            name: name,
            imageSize: getConfigUInt32(camera, context, "/main/settings/imagesize"),
            imageQuality: getConfigUInt32(camera, context, "/main/settings/quality"),
            dynamicRange: getConfigUInt32(camera, context, "/main/settings/wide_dynamic_range"),
            filmSimulation: getConfigUInt32(camera, context, "/main/settings/filmsim"),
            grainEffect: getConfigUInt32(camera, context, "/main/settings/grain"),
            colorChrome: getConfigUInt32(camera, context, "/main/settings/colorchrome"),
            colorChromeFxBlue: getConfigUInt32(camera, context, "/main/settings/colorchrome/blue"),
            smoothSkin: getConfigUInt32(camera, context, "/main/settings/smoothskin"),
            whiteBalance: getConfigUInt32(camera, context, "/main/settings/wb"),
            wbShiftRed: getConfigInt32(camera, context, "/main/settings/wbshift/r"),
            wbShiftBlue: getConfigInt32(camera, context, "/main/settings/wbshift/b"),
            colorTemp: getConfigUInt32(camera, context, "/main/settings/wb/kelvin"),
            highlight: getConfigInt32(camera, context, "/main/settings/highlight"),
            shadow: getConfigInt32(camera, context, "/main/settings/shadow"),
            color: getConfigInt32(camera, context, "/main/settings/color"),
            sharpness: getConfigInt32(camera, context, "/main/settings/sharpness"),
            highIsoNr: getConfigUInt32(camera, context, "/main/settings/noisereduction"),
            clarity: getConfigInt32(camera, context, "/main/settings/clarity"),
            longExpNr: getConfigUInt32(camera, context, "/main/settings/longexpnr"),
            colorSpace: getConfigUInt32(camera, context, "/main/settings/colorspace")
        )
        
        return presetData.encodeAsJSON()
    }

    func writePresetSlot(index: Int, data: PTPHelperPresetData) -> String {
        guard isConnected, let camera = camera, let context = context else {
            return "error:not_connected"
        }
        
        // Select the preset slot (1-7 maps to C1-C7)
        let slotStr = String(index)
        var result = setConfigValue(camera, context, "/main/settings/preset_slot", slotStr)
        if result != GP_OK {
            return "error:slot_select_failed_\(result)"
        }
        
        // Write slot name if provided
        if !data.name.isEmpty {
            result = setConfigValue(camera, context, "/main/settings/preset_name", data.name)
            if result != GP_OK {
                return "warning:slot_name_write_failed"
            }
        }
        
        // Write preset properties
        if let val = data.imageSize { _ = setConfigValue(camera, context, "/main/settings/imagesize", String(val)) }
        if let val = data.imageQuality { _ = setConfigValue(camera, context, "/main/settings/quality", String(val)) }
        if let val = data.dynamicRange { _ = setConfigValue(camera, context, "/main/settings/wide_dynamic_range", String(val)) }
        if let val = data.filmSimulation { _ = setConfigValue(camera, context, "/main/settings/filmsim", String(val)) }
        if let val = data.grainEffect { _ = setConfigValue(camera, context, "/main/settings/grain", String(val)) }
        if let val = data.colorChrome { _ = setConfigValue(camera, context, "/main/settings/colorchrome", String(val)) }
        if let val = data.colorChromeFxBlue { _ = setConfigValue(camera, context, "/main/settings/colorchrome/blue", String(val)) }
        if let val = data.smoothSkin { _ = setConfigValue(camera, context, "/main/settings/smoothskin", String(val)) }
        if let val = data.whiteBalance { _ = setConfigValue(camera, context, "/main/settings/wb", String(val)) }
        if let val = data.wbShiftRed { _ = setConfigValue(camera, context, "/main/settings/wbshift/r", String(val)) }
        if let val = data.wbShiftBlue { _ = setConfigValue(camera, context, "/main/settings/wbshift/b", String(val)) }
        if let val = data.colorTemp { _ = setConfigValue(camera, context, "/main/settings/wb/kelvin", String(val)) }
        if let val = data.highlight { _ = setConfigValue(camera, context, "/main/settings/highlight", String(val)) }
        if let val = data.shadow { _ = setConfigValue(camera, context, "/main/settings/shadow", String(val)) }
        if let val = data.color { _ = setConfigValue(camera, context, "/main/settings/color", String(val)) }
        if let val = data.sharpness { _ = setConfigValue(camera, context, "/main/settings/sharpness", String(val)) }
        if let val = data.highIsoNr { _ = setConfigValue(camera, context, "/main/settings/noisereduction", String(val)) }
        if let val = data.clarity { _ = setConfigValue(camera, context, "/main/settings/clarity", String(val)) }
        if let val = data.longExpNr { _ = setConfigValue(camera, context, "/main/settings/longexpnr", String(val)) }
        if let val = data.colorSpace { _ = setConfigValue(camera, context, "/main/settings/colorspace", String(val)) }
        
        return "ok"
    }

    func readNativeProfile() -> String? {
        return nil
    }

    func convertRAF(name: String, base64: String) -> String? {
        return "error:raf_convert_not_implemented"
    }

    func capturePreview() -> String? {
        return nil
    }

    // MARK: - Private Helpers

    private func scanForFujiCamera() -> String? {
        // Use gphoto2 --auto-detect to find camera (more reliable than system_profiler in subprocess)
        let task = Process()
        // Try both /opt/homebrew and /usr/bin locations
        let gphotoPath = FileManager.default.fileExists(atPath: "/opt/homebrew/bin/gphoto2") 
            ? "/opt/homebrew/bin/gphoto2" 
            : "/usr/bin/gphoto2"
        task.executableURL = URL(fileURLWithPath: gphotoPath)
        task.arguments = ["--auto-detect"]
        
        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()
        
        do {
            try task.run()
            task.waitUntilExit()
            
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let outputStr = String(decoding: data, as: UTF8.self)
            
            // Look for X100VI in output
            if outputStr.lowercased().contains("fuji") && outputStr.lowercased().contains("x100vi") {
                // Extract port from output (format: "Fuji Fujifilm X100VI           usb:005,003")
                for line in outputStr.components(separatedBy: .newlines) {
                    if line.lowercased().contains("x100vi") {
                        let parts = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                        if let usbPort = parts.last, usbPort.contains("usb:") {
                            fputs("[HELPER] Found camera at port: \(usbPort)\n", stderr)
                            return usbPort
                        }
                    }
                }
                // Fallback if we can't parse the port
                return "usb:auto"
            }
        } catch {}
        
        return nil
    }

    private func killPTPCameraProcesses() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        task.arguments = ["-a", "ptpcamera", "PTPCamera", "ptpcamerad"]
        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()
        do {
            try task.run()
            task.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let outputStr = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            for line in outputStr.components(separatedBy: .newlines) where !line.isEmpty {
                let parts = line.split(separator: " ")
                if let pid = Int(parts[0]) {
                    let kill = Process()
                    kill.executableURL = URL(fileURLWithPath: "/bin/kill")
                    kill.arguments = ["-9", String(pid)]
                    try kill.run()
                    kill.waitUntilExit()
                }
            }
        } catch {}
        Thread.sleep(forTimeInterval: 0.2)
    }
    
    private func getConfigUInt32(_ camera: UnsafeMutableRawPointer, _ context: UnsafeMutableRawPointer, _ path: String) -> UInt32? {
        guard let val = getConfigValue(camera, context, path) else { return nil }
        return UInt32(val)
    }
    
    private func getConfigInt32(_ camera: UnsafeMutableRawPointer, _ context: UnsafeMutableRawPointer, _ path: String) -> Int32? {
        guard let val = getConfigValue(camera, context, path) else { return nil }
        return Int32(val)
    }
}
