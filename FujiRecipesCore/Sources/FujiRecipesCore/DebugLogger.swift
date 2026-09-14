// DebugLogger.swift — Structured logging for FujiRecipes
// Uses Apple's native os.Logger with subsystem categorization.
// All logging is zero-cost in release builds (#if DEBUG guards).

import Foundation
#if canImport(os)
import os
#endif

// MARK: - Log Category

/// Categorized log types for structured logging across the app.
public enum DebugCategory: String, CaseIterable, Sendable {
    case app       = "App"
    case recipes   = "Recipes"
    case loadout   = "Loadout"
    case favorites = "Favorites"
    case camera    = "Camera"
    case ptp       = "PTP"
    case raf       = "RAF"
    case ui        = "UI"
    case storage   = "Storage"
    case debug     = "Debug"
    
    public var emoji: String {
        switch self {
        case .app:       return "📱"
        case .recipes:   return "🍳"
        case .loadout:   return "💾"
        case .favorites: return "⭐"
        case .camera:    return "📷"
        case .ptp:       return "🔌"
        case .raf:       return "🎞️"
        case .ui:        return "🖼️"
        case .storage:   return "💾"
        case .debug:     return "🔍"
        }
    }
}

// MARK: - Log Level

/// Log severity levels matching Apple's unified logging levels.
public enum LogLevel: String, Sendable, CaseIterable {
    case trace   = "TRACE"
    case debug   = "DEBUG"
    case info    = "INFO"
    case warning = "WARN"
    case error   = "ERROR"
    case fault   = "FAULT"
}

// MARK: - DebugLogger

/// Centralized structured logger. All logging in the app goes through this.
/// Usage: `DebugLogger.log(.info, category: .recipes, "Loaded \(count) recipes")`
// Note: Not @MainActor — called from signal handlers and crash contexts.
public final class DebugLogger: @unchecked Sendable {
    
    private static let subsystem = "com.ant.fuji-recipes"
    private static let lock = NSLock()
    private nonisolated(unsafe) static var _enabled: Bool = true
    private nonisolated(unsafe) static var _minLevel: LogLevel = .debug
    private nonisolated(unsafe) static var _categories: Set<DebugCategory> = Set(DebugCategory.allCases)
    private nonisolated(unsafe) static var listeners: [WeakListenerBox] = []  // log subscribers
    
    /// Enable or disable all logging.
    public static func setEnabled(_ enabled: Bool) {
        lock.lock(); defer { lock.unlock() }
        _enabled = enabled
    }
    
    /// Set minimum log level (messages below this level are suppressed).
    public static func setMinimumLevel(_ level: LogLevel) {
        lock.lock(); defer { lock.unlock() }
        _minLevel = level
    }
    
    /// Filter to specific categories (empty = all).
    public static func setCategories(_ categories: Set<DebugCategory>) {
        lock.lock(); defer { lock.unlock() }
        _categories = categories
    }
    
    /// Log a message.
    public static func log(
        _ level: LogLevel,
        category: DebugCategory,
        _ message: @autoclosure () -> String,
        file: String = #file,
        function: String = #function,
        line: Int = #line
    ) {
        #if DEBUG
        lock.lock()
        guard _enabled && _categories.contains(category) && level.rawValue >= _minLevel.rawValue else {
            lock.unlock()
            return
        }
        lock.unlock()

        let shortFile = (file as NSString).lastPathComponent
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let msg = message()
        let formatted = "[\(timestamp)] \(level.rawValue) \(category.emoji)[\(category.rawValue)] \(shortFile):\(line) \(msg)"

        // Send to Apple's unified logging system
        let logger = Logger(subsystem: subsystem, category: category.rawValue)
        switch level {
        case .trace:   logger.trace("\(msg)")
        case .debug:   logger.debug("\(msg)")
        case .info:    logger.info("\(msg)")
        case .warning: logger.warning("\(msg)")
        case .error:   logger.error("\(msg)")
        case .fault:   logger.fault("\(msg)")
        }

        // Notify subscribers without holding the lock, and dispatch to the
        // main actor so listeners can safely mutate @Published SwiftUI state.
        let subscribers: [any LogListenerProtocol] = lock.withLock {
            listeners.compactMap { $0.weakRef }
        }
        if !subscribers.isEmpty {
            Task { @MainActor in
                for listener in subscribers {
                    listener.receive(level: level, category: category, message: msg)
                }
            }
        }

        // Also print to console for immediate feedback during development
        #if DEBUG
        print(formatted)
        #endif
        #endif
    }
    
    // MARK: - Convenience methods
    
    public static func trace(_ message: @autoclosure () -> String, category: DebugCategory = .debug) {
        log(.trace, category: category, message())
    }
    public static func debug(_ message: @autoclosure () -> String, category: DebugCategory = .debug) {
        log(.debug, category: category, message())
    }
    public static func info(_ message: @autoclosure () -> String, category: DebugCategory = .debug) {
        log(.info, category: category, message())
    }
    public static func warning(_ message: @autoclosure () -> String, category: DebugCategory = .debug) {
        log(.warning, category: category, message())
    }
    public static func error(_ message: @autoclosure () -> String, category: DebugCategory = .debug) {
        log(.error, category: category, message())
    }
    public static func fault(_ message: @autoclosure () -> String, category: DebugCategory = .debug) {
        log(.fault, category: category, message())
    }
    
    // MARK: - Structured logging with metadata
    
    public static func logStructured(
        _ level: LogLevel,
        category: DebugCategory,
        message: @autoclosure () -> String,
        metadata: [String: LogMetadataValue]
    ) {
        #if DEBUG
        let metaPairs = metadata.map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
        let fullMessage = metadata.isEmpty ? message() : "\(message()) {\(metaPairs)}"
        log(level, category: category, fullMessage)
        #endif
    }
    
    // MARK: - Log Listener (for in-app debug HUD)
    
    @MainActor
    public static func addListener(_ listener: some LogListenerProtocol) {
        lock.lock()
        listeners.append(WeakListenerBox(listener))
        lock.unlock()
        DebugLogger.log(.debug, category: .debug, "Added log listener (total: \(listeners.count))")
    }

    @MainActor
    public static func removeListener(_ listener: some LogListenerProtocol) {
        lock.lock()
        listeners.removeAll { $0.value === listener as AnyObject }
        lock.unlock()
    }

    public static func clearListeners() {
        lock.lock()
        listeners.removeAll()
        lock.unlock()
    }

    /// Weak reference box for log listeners.  Log listeners are frequently
    /// SwiftUI view-model objects (`DebugLogStore`), so strong references here
    /// would create cycles and prevent deallocation.
    private final class WeakListenerBox {
        weak var value: AnyObject?
        init(_ listener: any LogListenerProtocol) { self.value = listener as AnyObject }
        var weakRef: (any LogListenerProtocol)? { value as? any LogListenerProtocol }
    }
    
    // MARK: - Device & App Info
    
    public static var appInfo: [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        return [
            "appName": info["CFBundleName"] as? String ?? "Unknown",
            "displayName": info["CFBundleDisplayName"] as? String ?? "Unknown",
            "version": info["CFBundleShortVersionString"] as? String ?? "Unknown",
            "build": info["CFBundleVersion"] as? String ?? "Unknown",
            "bundleId": info["CFBundleIdentifier"] as? String ?? "Unknown",
        ]
    }
    
    /// App info as [String: String] for Codable compatibility.
    public static var appInfoStringified: [String: String] {
        let info = Bundle.main.infoDictionary ?? [:]
        return [
            "appName": info["CFBundleName"] as? String ?? "Unknown",
            "displayName": info["CFBundleDisplayName"] as? String ?? "Unknown",
            "version": info["CFBundleShortVersionString"] as? String ?? "Unknown",
            "build": info["CFBundleVersion"] as? String ?? "Unknown",
            "bundleId": info["CFBundleIdentifier"] as? String ?? "Unknown",
        ]
    }
    
    public static var deviceInfo: [String: Any] {
        let process = ProcessInfo.processInfo
        return [
            "operatingSystem": process.operatingSystemVersionString,
            "cpuCount": String(process.processorCount),
            "activeCPUCount": String(process.activeProcessorCount),
            "physicalMemory": String(format: "%.1f GB", Double(process.physicalMemory) / (1024*1024*1024)),
            "hostname": process.hostName,
        ]
    }
    
    /// Device info as [String: String] for Codable compatibility.
    public static var deviceInfoStringified: [String: String] {
        let process = ProcessInfo.processInfo
        return [
            "operatingSystem": process.operatingSystemVersionString,
            "cpuCount": String(process.processorCount),
            "activeCPUCount": String(process.activeProcessorCount),
            "physicalMemory": String(format: "%.1f GB", Double(process.physicalMemory) / (1024*1024*1024)),
            "hostname": process.hostName,
        ]
    }
    
    /// Full diagnostic snapshot for crash reports / bug reports.
    public static func diagnosticSnapshot() -> String {
        let (enabled, minLevel, categories) = lock.withLock {
            (_enabled, _minLevel, _categories)
        }
        var lines: [String] = []
        lines.append("═══ FujiRecipes Diagnostic Snapshot ═══")
        lines.append("App Version: \(DebugLogger.appInfo["version"] ?? "?") (\(DebugLogger.appInfo["build"] ?? "?"))")
        lines.append("Bundle ID: \(DebugLogger.appInfo["bundleId"] ?? "?")")
        lines.append("OS: \(DebugLogger.deviceInfo["operatingSystem"] ?? "?")")
        lines.append("RAM: \(DebugLogger.deviceInfo["physicalMemory"] ?? "?")")
        lines.append("Date: \(ISO8601DateFormatter().string(from: Date()))")
        lines.append("Logger Enabled: \(enabled)")
        lines.append("Min Level: \(minLevel.rawValue)")
        lines.append("Categories: \(categories.map { $0.rawValue }.joined(separator: ", "))")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}

// MARK: - LogMetadataValue

public enum LogMetadataValue: CustomStringConvertible, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([LogMetadataValue])
    case dictionary([String: LogMetadataValue])
    
    public var description: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return "\(i)"
        case .double(let d): return String(format: "%.2f", d)
        case .bool(let b): return b ? "true" : "false"
        case .array(let a): return "[\(a.map { $0.description }.joined(separator: ", "))]"
        case .dictionary(let d): return "{\(d.map { "\($0.key)=\($0.value.description)" }.joined(separator: ", "))}"
        }
    }
}

// MARK: - LogListenerProtocol

/// Protocol for objects that receive log messages (used by DebugHUD).
public protocol LogListenerProtocol: Sendable {
    func receive(level: LogLevel, category: DebugCategory, message: String)
}
