import Foundation
import ImageCaptureCore

let icc = ImageCaptureCore()
let devices = icc.availableCaptureDevices

print("Available devices: \(devices.count)")
for device in devices {
    print("  - \(device.displayName) (ID: \(device.deviceIdentifier))")
}

// Try to find X100VI
for device in devices {
    if device.displayName.contains("X100VI") || device.displayName.contains("Fujifilm") {
        print("\nFound X100VI: \(device.displayName)")
        print("Device ID: \(device.deviceIdentifier)")
        
        // Try to get device info
        do {
            let props = try device.properties()
            print("Properties: \(props.count)")
        } catch {
            print("Error getting properties: \(error)")
        }
    }
}
