// DebugHUD.swift — In-app debug overlay for debug builds only.
// Triggered by 5-finger long-press on macOS or 3-finger long-press on iOS.
// Shows: app info, log stream, copy diagnostics, clear logs, PTP status.

import SwiftUI

// MARK: - DebugHUDView

/// Main debug HUD panel — visible in debug builds, hidden in release.
public struct DebugHUDView: View {
    @Binding var isPresented: Bool
    @StateObject private var logStore = DebugLogStore()
    @State private var selectedTab: DebugHUDTab = .logs
    @Environment(\.dismiss) private var dismiss
    
    public init(isPresented: Binding<Bool>) {
        _isPresented = isPresented
    }
    
    public var body: some View {
        #if os(iOS)
        NavigationStack {
            List(DebugHUDTab.allCases, id: \.self) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("Debug")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                }
            }
            switch selectedTab {
            case .logs: LogStreamView(store: logStore)
            case .info: AppInfoView()
            case .performance: PerformanceView()
            case .ptp: PTPStatusView()
            }
        }
        .onAppear { DebugLogger.addListener(logStore) }
        .onDisappear { DebugLogger.removeListener(logStore) }
        #else
        NavigationSplitView {
            List(DebugHUDTab.allCases, id: \.self, selection: $selectedTab) { tab in
                Label(tab.title, systemImage: tab.icon)
                    .tag(tab)
            }
            .navigationTitle("Debug")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Close") { dismiss() }
                        .keyboardShortcut("w", modifiers: .command)
                }
            }
        } detail: {
            switch selectedTab {
            case .logs: LogStreamView(store: logStore)
            case .info: AppInfoView()
            case .performance: PerformanceView()
            case .ptp: PTPStatusView()
            }
        }
        .frame(minWidth: 700, minHeight: 500)
        .onAppear { DebugLogger.addListener(logStore) }
        .onDisappear { DebugLogger.removeListener(logStore) }
        #endif
    }
}

// MARK: - DebugHUDTab

enum DebugHUDTab: String, CaseIterable, Identifiable {
    case logs, info, performance, ptp
    
    var id: String { rawValue }
    var title: String {
        switch self {
        case .logs: return "Log Stream"
        case .info: return "App Info"
        case .performance: return "Performance"
        case .ptp: return "PTP Status"
        }
    }
    var icon: String {
        switch self {
        case .logs: return "terminal"
        case .info: return "info.circle"
        case .performance: return "gauge"
        case .ptp: return "cable.vertical"
        }
    }
}

// MARK: - LogStreamView

struct LogStreamView: View {
    @ObservedObject var store: DebugLogStore
    @State private var filterText = ""
    @State private var selectedLevel: LogLevel?
    
    var filteredLogs: [LogEntry] {
        store.entries.filter { entry in
            let matchesText = filterText.isEmpty || entry.message.lowercased().contains(filterText.lowercased())
            let matchesLevel = selectedLevel == nil || entry.level == selectedLevel
            return matchesText && matchesLevel
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                TextField("Filter logs...", text: $filterText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 300)
                
                Menu("Level") {
                    Button("All") { selectedLevel = nil }
                    Divider()
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        Button(level.rawValue) { selectedLevel = level }
                    }
                }
                
                Spacer()
                
                Button(action: { store.clear() }) {
                    Label("Clear", systemImage: "trash")
                }
                .keyboardShortcut("k", modifiers: .command)
                
                Button(action: {
                    let text = filteredLogs.map { entry in
                        "\([entry.level.rawValue]) (\(entry.category.rawValue)) \(entry.message)"
                    }.joined(separator: "\n")
                    copyToClipboard(text)
                }) {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            
            Divider()
            
            // Log entries
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(filteredLogs.enumerated()), id: \.element.id) { index, entry in
                        LogEntryRow(entry: entry)
                        if index < filteredLogs.count - 1 {
                            Divider()
                        }
                    }
                }
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - LogEntryRow

struct LogEntryRow: View {
    let entry: LogEntry
    
    var levelColor: Color {
        switch entry.level {
        case .trace, .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        case .fault: return .purple
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(entry.timestamp)
                .foregroundStyle(.gray)
                .fixedSize()
            
            Text(entry.category.emoji)
                .fixedSize()
            
            Text(entry.level.rawValue)
                .foregroundStyle(levelColor)
                .fontWeight(.bold)
                .fixedSize()
            
            Text(entry.message)
                .lineLimit(3)
            
            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - AppInfoView

struct AppInfoView: View {
    let appInfo = DebugLogger.appInfoStringified
    let deviceInfo = DebugLogger.deviceInfoStringified
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Section("App") {
                    InfoRow(title: "Name", value: appInfo["displayName"] ?? "?")
                    InfoRow(title: "Version", value: appInfo["version"] ?? "?")
                    InfoRow(title: "Build", value: appInfo["build"] ?? "?")
                    InfoRow(title: "Bundle ID", value: appInfo["bundleId"] ?? "?")
                }
                
                Section("Device") {
                    InfoRow(title: "OS", value: deviceInfo["operatingSystem"] ?? "?")
                    InfoRow(title: "CPU Cores", value: "\(deviceInfo["cpuCount"] ?? "?") (\(deviceInfo["activeCPUCount"] ?? "?") active)")
                    InfoRow(title: "RAM", value: deviceInfo["physicalMemory"] ?? "?")
                }
                
                Section("App State") {
                    InfoRow(title: "Logger Enabled", value: true ? "Yes" : "No")
                    InfoRow(title: "Min Log Level", value: LogLevel.debug.rawValue)
                    InfoRow(title: "Categories", value: DebugCategory.allCases.map { $0.rawValue }.joined(separator: ", "))
                }
                
                Section("Diagnostics") {
                    Button("Copy Diagnostic Report") {
                        let report = DebugLogger.diagnosticSnapshot()
                        copyToClipboard(report)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("App Info")
    }
}

struct InfoRow: View {
    let title: String
    let value: String
    
    init(title: String, value: String) {
        self.title = title
        self.value = value
    }
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospaced()
        }
    }
}

// MARK: - PerformanceView

struct PerformanceView: View {
    @State private var memoryUsage = MemoryInfo()
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                InfoRow(title: "Total Memory", value: String(format: "%.1f GB", memoryUsage.totalGB))
                InfoRow(title: "Used Memory", value: String(format: "%.0f MB", memoryUsage.usedMB))
                InfoRow(title: "Free Memory", value: String(format: "%.1f GB", memoryUsage.freeGB))
                
                Divider()
                
                Text("This screen shows current memory usage. In a future iteration,")
                Text("we may add periodic sampling and charts here.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Performance")
        .onAppear {
            memoryUsage.refresh()
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                if Task.isCancelled { break }
                memoryUsage.refresh()
            }
        }
    }
}

// MARK: - PTPStatusView

struct PTPStatusView: View {
    @EnvironmentObject private var cameraManager: CameraManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Circle()
                        .fill(cameraManager.status == CameraStatus.connected ? .green :
                              cameraManager.status == CameraStatus.connecting ? .yellow : .red)
                        .frame(width: 12, height: 12)
                    Text("PTP Connection Status")
                        .font(.headline)
                }
                
                InfoRow(title: "State", value: cameraManager.status.rawValue)
                InfoRow(title: "Camera", value: cameraManager.cameraInfo?.model ?? "Not connected")
                
                Divider()
                
                Text("Connect your X100VI via USB-C to see live PTP status here.")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("PTP Status")
    }
}

// MARK: - MemoryInfo

struct MemoryInfo {
    var totalGB: Double = 0
    var usedMB: Double = 0
    var freeGB: Double = 0

    mutating func refresh() {
        let processInfo = ProcessInfo.processInfo
        totalGB = Double(processInfo.physicalMemory) / (1024 * 1024 * 1024)

        // Resident (physical) memory used by this process, via mach task info.
        var taskInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &taskInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        if kerr == KERN_SUCCESS {
            usedMB = Double(taskInfo.resident_size) / (1024 * 1024)
        }

        freeGB = totalGB - (usedMB / 1024)
    }
}

// MARK: - DebugHUDModifier (SwiftUI view modifier for triggering debug HUD)

/// Attach to any view to enable the debug HUD with a long-press gesture.
/// Press and hold for ~1.5 s anywhere on the view to open the debug panel.
struct DebugHUDModifier: ViewModifier {
    @State private var showDebug = false

    func body(content: Content) -> some View {
        #if DEBUG
        content
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 1.5)
                    .onEnded { _ in showDebug = true }
            )
            .sheet(isPresented: $showDebug) {
                DebugHUDView(isPresented: $showDebug)
            }
        #else
        content
        #endif
    }
}

extension View {
    /// Add debug HUD trigger (5-finger tap on macOS, 3-finger tap on iOS)
    public func debugHUD() -> some View {
        modifier(DebugHUDModifier())
    }
}

// MARK: - DebugLogStore

final class DebugLogStore: ObservableObject, @unchecked Sendable, LogListenerProtocol {
    @Published private(set) var entries: [LogEntry] = []
    private let maxEntries = 500
    private var idCounter: UInt64 = 0
    
    func clear() {
        entries.removeAll()
    }
    
    func receive(level: LogLevel, category: DebugCategory, message: String) {
        withAnimation(.easeOut(duration: 0.1)) {
            let entry = LogEntry(
                id: idCounter,
                timestamp: ISO8601DateFormatter().string(from: Date()),
                level: level,
                category: category,
                message: message
            )
            idCounter += 1
            entries.append(entry)
            if entries.count > maxEntries {
                entries.removeFirst(entries.count - maxEntries)
            }
        }
    }
}

// MARK: - LogEntry

struct LogEntry: Identifiable, Sendable {
    let id: UInt64
    let timestamp: String
    let level: LogLevel
    let category: DebugCategory
    let message: String
}

// MARK: - Clipboard Helper (cross-platform)

#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// Cross-platform clipboard copy helper.
func copyToClipboard(_ text: String) {
    #if os(macOS)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
    #elseif os(iOS)
    UIPasteboard.general.string = text
    #endif
}
