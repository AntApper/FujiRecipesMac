// FFI+MACCamera.swift
// macOS-specific camera utilities: PTPCamera process management, camera status.
//
// macOS has a built-in PTPCamera/ptpcamerad daemon that claims USB cameras
// and prevents libgphoto2 from accessing them. We need to kill this process
// before connecting, and handle it gracefully in case it respawns.
//
// References:
// - https://github.com/gphoto/libgphoto2/issues/971
// - https://github.com/gphoto/gphoto2/issues/112

import Foundation
import FujiRecipesCore

// MARK: - File Logging (macOS GUI apps cannot use print() to terminal)

internal let debugLogPath = "/tmp/fuji-connection.log"

internal func debugLog(_ message: String) {
    let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    let line = "[\(timestamp)] \(message)\n"
    let data = line.data(using: .utf8) ?? Data()
    DispatchQueue.global(qos: .utility).async {
        let url = URL(fileURLWithPath: debugLogPath)
        if FileManager.default.fileExists(atPath: debugLogPath) {
            do {
                let fh = try FileHandle(forWritingTo: url)
                fh.seekToEndOfFile()
                try fh.write(contentsOf: data)
                try fh.close()
            } catch { _ = error }
        } else {
            do {
                try data.write(to: url)
            } catch { _ = error }
        }
    }
}
// MARK: - PTPCamera Process Management

enum MACameraUtils {
    /// Kill macOS PTPCamera/ptpcamerad processes that may be blocking USB camera access.
    /// Returns true if any process was found and killed, false otherwise.
    @MainActor
    static func killPTPCameraProcesses() async -> Bool {
        let processes = await PTPCameraProcesses.allRunning()
        guard !processes.isEmpty else {
            debugLog("ℹ️  No PTPCamera daemon found")
            return false
        }

        debugLog("🔴 Found \(processes.count) PTPCamera process(es) blocking camera access:")
        for proc in processes {
            debugLog("   PID \(proc.pid): \(proc.name)")
        }

        // Try graceful termination first, then force kill
        var killedCount = 0
        for proc in processes {
            let (killed, reason) = await PTPCameraProcesses.killProcess(proc.pid)
            if killed {
                debugLog("   ✅ Killed PID \(proc.pid)")
                killedCount += 1
            } else {
                debugLog("   ⚠️ Could not kill PID \(proc.pid): \(reason)")
                debugLog("      Tip: Try running 'sudo kill -9 \(proc.pid)' in Terminal")
            }
        }

        // Wait a moment for processes to die and USB to become available
        debugLog("⏳ Waiting 2 seconds for USB to become available...")
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        // Verify processes are gone
        let remaining = await PTPCameraProcesses.allRunning()
        if !remaining.isEmpty {
            debugLog("⚠️ \(remaining.count) PTPCamera process(es) survived. They may respawn.")
            debugLog("   Tip: Try 'sudo killall -9 ptpcamera' in Terminal")
        }

        return killedCount > 0
    }

    /// Check if any PTPCamera process is currently running.
    static func isPTPCameraRunning() async -> Bool {
        !(await PTPCameraProcesses.allRunning().isEmpty)
    }
}

// MARK: - PTPCamera Process Info

struct PTPCameraProcess {
    let pid: Int
    let name: String
}

// MARK: - PTPCamera Process Discovery

enum PTPCameraProcesses {
    /// Find all running PTPCamera/ptpcamerad processes.
    /// Deduplicates by PID so the same process isn't listed multiple times
    /// (lsof returns one line per open file descriptor).
    internal static func allRunning() async -> [PTPCameraProcess] {
        // Use lsof to find PTPCamera processes (more reliable than ps)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        task.arguments = ["-c", "PTPCamera", "-c", "ptpcamerad"]

        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let outputStr = String(decoding: data, as: UTF8.self)

            // Use a Set to deduplicate by PID
            var seenPids: Set<Int> = []
            var processes: [PTPCameraProcess] = []
            for line in outputStr.components(separatedBy: .newlines) {
                // lsof output format: COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
                let parts = line.split(separator: " ")
                if parts.count >= 2 {
                    if let pid = Int(parts[1]) {
                        // Deduplicate: skip if we've already seen this PID
                        if seenPids.contains(pid) { continue }
                        seenPids.insert(pid)
                        let name = parts[0].map(String.init).joined()
                        processes.append(PTPCameraProcess(pid: pid, name: name))
                    }
                }
            }

            // Also check with ps as fallback (in case lsof doesn't show it)
            if processes.isEmpty {
                processes = await PTPCameraProcesses.fromPs()
            }

            return processes
        } catch {
            // Fall back to ps
            return await PTPCameraProcesses.fromPs()
        }
    }

    internal static func fromPs() async -> [PTPCameraProcess] {
        var processes: [PTPCameraProcess] = []

        // Check for both "ptpcamera" (lowercase) and "PTPCamera" (mixed case)
        for pattern in ["ptpcamera", "ptpcamerad", "PTPCamera"] {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            task.arguments = ["-a", pattern]

            let output = Pipe()
            task.standardOutput = output
            task.standardError = Pipe()

            do {
                try task.run()
                task.waitUntilExit()

                let data = output.fileHandleForReading.readDataToEndOfFile()
                let outputStr = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

                var seenPids: Set<Int> = []
                for line in outputStr.components(separatedBy: .newlines) where !line.isEmpty {
                    let parts = line.split(separator: " ")
                    if parts.count >= 2 {
                        if let pid = Int(parts[0]) {
                            // Deduplicate across patterns
                            if !seenPids.contains(pid) {
                                seenPids.insert(pid)
                                processes.append(PTPCameraProcess(pid: pid, name: pattern))
                            }
                        }
                    }
                }
            } catch {
                // pgrep failed for this pattern, try the next one
            }
        }

        return processes
    }

    /// Kill a specific process by PID. Returns (success, reason).
    internal static func killProcess(_ pid: Int) async -> (Bool, String) {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/kill")
        task.arguments = ["-9", String(pid)]

        let errorPipe = Pipe()
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()

            if task.terminationStatus == 0 {
                return (true, "")
            }

            // Capture stderr for debugging
            let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errMsg = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)

            // Check if it's a "No such process" error (process already dead)
            if errMsg.contains("No such process") || errMsg.contains("no such process") {
                return (true, "process already gone")
            }

            // Check if it's a permission error
            if errMsg.contains("Operation not permitted") || errMsg.contains("Permission denied") {
                return (false, "permission denied — try 'sudo kill -9 \(pid)'")
            }

            return (false, errMsg.isEmpty ? "exit code \(task.terminationStatus)" : errMsg)
        } catch {
            return (false, "\(error.localizedDescription)")
        }
    }
}

// MARK: - Camera USB Status

extension MACameraUtils {
    /// Check if a Fuji X100VI (or compatible) is connected via USB.
    static func isFujiCameraConnected() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPUSBDataType", "-json"]

        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = output.fileHandleForReading.readDataToEndOfFile()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["SPUSBDataType"] as? [[String: Any]] {
                for item in items {
                    if let name = item["_name"] as? String,
                       name.lowercased().contains("fuji") || name.lowercased().contains("fujifilm") || name.lowercased().contains("ptp") {
                        if let vendorID = item["_vendorID"] as? String,
                           vendorID.uppercased().contains("04CB") {
                            return true
                        }
                    }
                }
            }
            return false
        } catch {
            // Fallback: check ioreg
            return isFujiCameraConnectedViaIOReg()
        }
    }

    private static func isFujiCameraConnectedViaIOReg() -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        task.arguments = ["-p", "IOUSB", "-l"]

        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = output.fileHandleForReading.readDataToEndOfFile()
            let outputStr = String(decoding: data, as: UTF8.self)

            // Check for Fuji VID (04CB) and PTP Camera
            return outputStr.contains("04cb") && outputStr.contains("PTP")
        } catch {
            return false
        }
    }

    /// Get the vendor:product ID of connected Fuji cameras.
    static func getFujiCameraIDs() -> [(vendorID: String, productID: String, name: String)] {
        var ids: [(String, String, String)] = []

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        task.arguments = ["SPUSBDataType", "-json"]

        let output = Pipe()
        task.standardOutput = output
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()

            let data = output.fileHandleForReading.readDataToEndOfFile()
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = json["SPUSBDataType"] as? [[String: Any]] {
                for item in items {
                    if let vendorID = item["_vendorID"] as? String,
                       vendorID.uppercased().contains("04CB"),
                       let productID = item["_productID"] as? String,
                       let name = item["_name"] as? String {
                        ids.append((vendorID, productID, name))
                    }
                }
            }
        } catch {}

        return ids
    }
}

// MARK: - Camera Connection Helper

extension MacOSSession {
    /// Prepare the system for camera connection by killing blocking processes.
    /// Call this before connect() to avoid PTPCamera interference.
    func prepareForCameraConnection() async {
        // Kill PTPCamera processes
        _ = await MACameraUtils.killPTPCameraProcesses()

        // Check if camera is connected
        let cameraIDs = MACameraUtils.getFujiCameraIDs()
        if cameraIDs.isEmpty {
            debugLog("⚠️ No Fuji camera detected. Connect via USB-C and try again.")
            debugLog("   Connected USB devices:")
            let camList = MACameraUtils.getFujiCameraIDs().map { "\($0.name) (\($0.vendorID):\($0.productID))" }
            debugLog("   - \(camList.isEmpty ? "None" : camList.joined(separator: "\n   - "))")
        } else {
            debugLog("📷 Found Fuji camera(s):")
            for id in cameraIDs {
                debugLog("   \(id.name) (\(id.vendorID):\(id.productID))")
            }
        }
    }

    /// Check if the camera is properly connected and accessible.
    /// Note: This is synchronous and does NOT check PTPCamera (which requires async).
    /// Use prepareForCameraConnection() which does the async PTPCamera check.
    func checkCameraAccessibility() -> String? {
        // Check camera connection
        if !MACameraUtils.isFujiCameraConnected() {
            return "Fuji X100VI not detected via USB. Try:\n" +
                   "  1. Ensure camera is powered on\n" +
                   "  2. Use a USB-C data cable (not charge-only)\n" +
                   "  3. On camera: Settings → USB Connection → PTP\n" +
                   "  4. Disconnect and reconnect the USB cable\n" +
                   "  5. On Mac: Quit Photos and Image Capture\n" +
                   "  6. Run: killall PTPCamera"
        }

        return nil
    }

    /// Async version that also checks PTPCamera status.
    func checkCameraAccessibilityAsync() async -> String? {
        // Check if PTPCamera is running
        if await MACameraUtils.isPTPCameraRunning() {
            return "macOS PTPCamera service is running. Please quit Photos, Image Capture, and any other camera apps, then try again. Or run: killall PTPCamera"
        }

        // Check camera connection
        if !MACameraUtils.isFujiCameraConnected() {
            return "Fuji X100VI not detected via USB. Try:\n" +
                   "  1. Ensure camera is powered on\n" +
                   "  2. Use a USB-C data cable (not charge-only)\n" +
                   "  3. On camera: Settings → USB Connection → PTP\n" +
                   "  4. Disconnect and reconnect the USB cable\n" +
                   "  5. On Mac: Quit Photos and Image Capture\n" +
                   "  6. Run: killall PTPCamera"
        }

        return nil
    }
}
