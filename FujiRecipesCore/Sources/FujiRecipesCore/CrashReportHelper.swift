// CrashReportHelper.swift — Utilities for capturing crash diagnostics and generating bug reports.
// In debug builds, captures unhandled exceptions and provides diagnostic data.
// In release builds, minimal overhead (only captures fault-level logs).
// Note: Platform-specific UI (NSAlert, NSPasteboard) is handled by the app layer.

import Foundation

// MARK: - CrashReportHelper

/// Handles crash detection and diagnostic capture for bug reports.
/// Note: Not @MainActor — runs in signal handlers and exception contexts.
public final class CrashReportHelper: @unchecked Sendable {
    
    private nonisolated(unsafe) static let fileManager = FileManager.default
    private static var reportDirectory: URL? {
        guard let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = appSupport.appendingPathComponent("FujiRecipes", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    
    /// Set up crash monitoring. Call once at app launch.
    public static func setup() {
        // Install uncaught exception handler for Objective-C exceptions.
        // Note: Swift fatal errors (e.g. force unwraps, precondition failures)
        // terminate via abort(), which is a signal context.  Handling signals
        // from within Swift is fundamentally async-signal-unsafe (allocating,
        // FileManager, JSON encoding, etc. can deadlock on the faulting thread),
        // so we intentionally do NOT install SIGSEGV/SIGABRT handlers here.
        // The OS crash reporter captures those; we only capture NSExceptions.
        NSSetUncaughtExceptionHandler(FujiRecipes_uncaughtExceptionHandler)
    }
    
    /// Capture diagnostic data from an uncaught exception.
    public static func captureException(_ exception: NSException, favorites: Set<String> = [], loadoutSummary: String = "") -> CrashReport {
        let callStack = exception.callStackSymbols ?? []
        return CrashReport(
            type: "exception:\(exception.name.rawValue)",
            message: exception.reason ?? "Unknown exception",
            stackTrace: callStack,
            appInfo: DebugLogger.appInfoStringified,
            deviceInfo: DebugLogger.deviceInfoStringified,
            timestamp: Date(),
            diagnostics: DebugLogger.diagnosticSnapshot(),
            loadoutState: loadoutSummary,
            favoritesCount: favorites.count
        )
    }
    
    /// Capture diagnostic data from a POSIX signal.
    public static func captureSignalReport(_ signal: Int32, favorites: Set<String> = [], loadoutSummary: String = "") -> CrashReport {
        let signalName: String
        switch signal {
        case SIGSEGV: signalName = "SIGSEGV (Segmentation Fault)"
        case SIGABRT: signalName = "SIGABRT (Abort)"
        case SIGILL: signalName = "SIGILL (Illegal Instruction)"
        case SIGBUS: signalName = "SIGBUS (Bus Error)"
        default: signalName = "Signal \(signal)"
        }
        
        return CrashReport(
            type: "signal:\(signalName)",
            message: signalName,
            stackTrace: Thread.callStackSymbols,
            appInfo: DebugLogger.appInfoStringified,
            deviceInfo: DebugLogger.deviceInfoStringified,
            timestamp: Date(),
            diagnostics: DebugLogger.diagnosticSnapshot(),
            loadoutState: loadoutSummary,
            favoritesCount: favorites.count
        )
    }
    
    /// Save crash report to disk.
    public static func saveCrashReport(_ report: CrashReport) {
        guard let dir = reportDirectory else { return }
        let fileName = "crash-\(Int(report.timestamp.timeIntervalSince1970)).json"
        let fileURL = dir.appendingPathComponent(fileName)
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(report)
            try data.write(to: fileURL)
        } catch {
            DebugLogger.error("Failed to save crash report: \(error)", category: .debug)
        }
    }
    
    /// Get list of saved crash reports.
    public static func savedCrashReports() -> [CrashReport] {
        guard let dir = reportDirectory else { return [] }
        
        do {
            let urls = try fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])
                .filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            
            var reports: [CrashReport] = []
            for url in urls {
                if let data = try? Data(contentsOf: url),
                   let report = try? JSONDecoder().decode(CrashReport.self, from: data) {
                    reports.append(report)
                }
            }
            return reports
        } catch {
            return []
        }
    }
    
    /// Clear all saved crash reports.
    public static func clearSavedCrashReports() {
        guard let dir = reportDirectory else { return }
        try? fileManager.removeItem(at: dir)
    }
}

// MARK: - CrashReport

public struct CrashReport: Codable, Sendable {
    public let type: String        // "exception" | "signal" | "fault"
    public let message: String
    public let stackTrace: [String]
    public let appInfo: [String: String]
    public let deviceInfo: [String: String]
    public let timestamp: Date
    public let diagnostics: String
    public let loadoutState: String
    public let favoritesCount: Int
    
    public func toMarkdownString() -> String {
        var lines: [String] = []
        lines.append("```")
        lines.append("═══ FujiRecipes Crash Report ═══")
        lines.append("Type: \(type)")
        lines.append("Time: \(ISO8601DateFormatter().string(from: timestamp))")
        lines.append("")
        lines.append("Message:")
        lines.append(message)
        lines.append("")
        lines.append("Diagnostics:")
        lines.append(diagnostics)
        lines.append("")
        lines.append("Stack Trace:")
        for (i, frame) in stackTrace.enumerated() {
            lines.append("  \(i + 1). \(frame)")
        }
        lines.append("")
        lines.append("App Info:")
        for (key, value) in appInfo.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(key): \(value)")
        }
        lines.append("")
        lines.append("Device Info:")
        for (key, value) in deviceInfo.sorted(by: { $0.key < $1.key }) {
            lines.append("  \(key): \(value)")
        }
        lines.append("")
        lines.append("Loadout State: \(loadoutState)")
        lines.append("Favorites Count: \(favoritesCount)")
        lines.append("```")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Top-level C-compatible signal handlers
// These are global functions (not static methods) so @_cdecl works.

@_cdecl("FujiRecipes_SEGV_handler")
func FujiRecipes_SEGV_handler(_ sig: Int32) -> Int32 {
    let report = CrashReportHelper.captureSignalReport(sig)
    CrashReportHelper.saveCrashReport(report)
    return sig
}

@_cdecl("FujiRecipes_ABORT_handler")
func FujiRecipes_ABORT_handler(_ sig: Int32) -> Int32 {
    let report = CrashReportHelper.captureSignalReport(sig)
    CrashReportHelper.saveCrashReport(report)
    return sig
}

// Void-returning wrappers for signal()
func FujiRecipes_SEGV_handler_void(_ sig: Int32) {
    FujiRecipes_SEGV_handler(sig)
}

func FujiRecipes_ABORT_handler_void(_ sig: Int32) {
    FujiRecipes_ABORT_handler(sig)
}

// Global uncaught exception handler (no context capture for C function pointer)
func FujiRecipes_uncaughtExceptionHandler(_ exception: NSException) {
    let report = CrashReportHelper.captureException(exception)
    CrashReportHelper.saveCrashReport(report)
}
