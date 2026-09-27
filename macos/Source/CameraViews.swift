import SwiftUI
import FujiRecipesCore
import X100VIHelper
import PTPClientMacOS
import UniformTypeIdentifiers

public extension UTType {
    /// Best-effort type filter for Fuji RAF raw files.
    static let rafDocument = UTType(filenameExtension: "raf") ?? .data
}

// MARK: - 2026 Camera Studio & Hardware Telemetry Hub

public struct CameraConnectionView: View {
    @ObservedObject public var manager: CameraManager
    @ObservedObject public var loadouts: LoadoutStore
    @State private var isConnecting = false
    @State private var showLimitationsAlert = false
    @State private var showTroubleshooting = false
    @State private var slotRefreshMessage: String?
    @State private var confirmOverwriteDrafts = false
    @State private var confirmClearAllStaged = false
    @State private var slotPendingLocalClear: Int?
    @State private var slotToEdit: Loadout?
    @Binding public var selectedDialSlot: Int
    @State private var isWritingAll = false
    @State private var writeAllProgress: String?
    @State private var writeStatusFeedback: String?
    private let cameraSessionFactory: CameraSessionFactory

    private var isConnectionInFlight: Bool {
        isConnecting || manager.status == .connecting
    }

    public init(
        manager: CameraManager,
        loadouts: LoadoutStore,
        selectedDialSlot: Binding<Int> = .constant(1),
        cameraSessionFactory: @escaping CameraSessionFactory = { ImageCaptureCorePTPClient() }
    ) {
        self.manager = manager
        self.loadouts = loadouts
        self._selectedDialSlot = selectedDialSlot
        self.cameraSessionFactory = cameraSessionFactory
    }

    public var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Section Header
                    SectionHeader(
                        title: "Camera & Staging",
                        subtitle: "Unified hardware control & C1–C7 preset dial staging for Fujifilm X100VI. Stage offline, verify live, and write over USB-C.",
                        icon: "camera.fill",
                        trailingValue: manager.status.formattedLabel,
                        trailingLabel: "STATUS",
                        accentColor: manager.status.tint
                    )

                    // Top Hero Hardware & Connection Cards
                    if manager.status != .connected {
                        ViewThatFits(in: .horizontal) {
                            HStack(alignment: .top, spacing: 14) {
                                hardwareStatusCard
                                    .frame(maxWidth: .infinity)
                                connectionGuideCard
                                    .frame(maxWidth: 480)
                            }
                            VStack(spacing: 14) {
                                hardwareStatusCard
                                connectionGuideCard
                            }
                        }
                    } else {
                        hardwareStatusCard
                    }

                    // Error / Warning Diagnostic HUD
                    if let error = manager.lastError {
                        errorHUD(error)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.95)).combined(with: .offset(y: -6)),
                                removal: .opacity.combined(with: .scale(scale: 0.95))
                            ))
                    }

                    // Primary Action Banner (Write All / Refresh / Clear)
                    primaryActionBanner

                    // Dial Rack (Slots C1 through C7)
                    dialRackGrid
                }
                .padding(16)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.status)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.lastError)
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isWritingAll)
            }
            .navigationTitle("Camera & Staging")
            .onChange(of: selectedDialSlot) { _, newSlot in
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    scrollProxy.scrollTo("slot-\(newSlot)", anchor: .center)
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    scrollProxy.scrollTo("slot-\(selectedDialSlot)", anchor: .center)
                }
            }
        }
        .sheet(isPresented: $showLimitationsAlert) {
            LimitationsView(isPresented: $showLimitationsAlert)
        }
        .sheet(isPresented: $showTroubleshooting) {
            TroubleshootingView(isPresented: $showTroubleshooting)
        }
        .sheet(item: $slotToEdit) { loadout in
            SlotEditorSheet(
                loadout: loadout,
                store: loadouts,
                cameraManager: manager,
                isPresented: Binding(
                    get: { slotToEdit != nil },
                    set: { if !$0 { slotToEdit = nil } }
                )
            )
        }
        .confirmationDialog("Replace local drafts with camera data?", isPresented: $confirmOverwriteDrafts) {
            Button("Replace Local Drafts", role: .destructive) { refreshSlots(overwriteDrafts: true) }
            Button("Keep Local Drafts", role: .cancel) { refreshSlots(overwriteDrafts: false) }
        } message: {
            Text("Only successfully read slots are updated. Replacing a local draft discards it in favor of the camera read; clearing a local draft elsewhere never clears the camera slot.")
        }
        .confirmationDialog(
            "Clear All Staged Slots?",
            isPresented: $confirmClearAllStaged,
            titleVisibility: .visible
        ) {
            Button("Clear All 7 Drafts", role: .destructive) {
                clearAllStagedSlots()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears all 7 local recipe drafts in FujiRecipes. It does not modify or clear the camera's physical slots.")
        }
        .confirmationDialog(
            "Clear Local Draft?",
            isPresented: Binding(
                get: { slotPendingLocalClear != nil },
                set: { if !$0 { slotPendingLocalClear = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Clear Local Draft", role: .destructive) {
                if let slot = slotPendingLocalClear {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        loadouts.clearLoadout(for: slot)
                    }
                }
                slotPendingLocalClear = nil
            }
            Button("Cancel", role: .cancel) { slotPendingLocalClear = nil }
        } message: {
            if let slot = slotPendingLocalClear {
                Text("This removes only FujiRecipes’ local draft for C\(slot). It does not clear, reset, or otherwise change the physical camera slot.")
            }
        }
    }

    private var hardwareStatusCard: some View {
        VStack(spacing: 14) {
            ViewThatFits(in: .horizontal) {
                // Horizontal layout
                HStack(alignment: .top, spacing: 16) {
                    cameraGraphic
                    cameraSpecs
                    Spacer(minLength: 0)
                }
                // Compact vertical layout
                VStack(alignment: .leading, spacing: 12) {
                    cameraGraphic
                    cameraSpecs
                }
            }

            Divider()
                .overlay(Theme.specularBorder)

            // Primary Connect / Disconnect Action
            ViewThatFits(in: .horizontal) {
                HStack {
                    connectionStateText
                    Spacer(minLength: 12)
                    connectActionButton
                        .frame(width: 200)
                }
                VStack(alignment: .leading, spacing: 10) {
                    connectionStateText
                    connectActionButton
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .glassPanel(padding: 16, radius: Glass.panelRadius, accentColor: manager.status.tint)
    }

    private var cameraGraphic: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.35))
                .frame(width: 120, height: 95)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(manager.status == .connected ? Theme.emeraldGreen.opacity(0.4) : Theme.specularBorder, lineWidth: 1)
                )

            if manager.status == .connected {
                VStack(spacing: 5) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Theme.emeraldGreen)
                        .shadow(color: Theme.emeraldGreen.opacity(0.8), radius: 6)
                        .symbolEffect(.bounce, value: manager.status == .connected)
                    Text("LINK ACTIVE")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(Theme.emeraldGreen)
                }
            } else if isConnectionInFlight {
                VStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(Theme.fujiAmber)
                    Text("NEGOTIATING")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.fujiAmber)
                }
            } else {
                VStack(spacing: 5) {
                    Image(systemName: "camera.aperture")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(Theme.fujiAmber)
                    Text("X100VI")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: manager.status)
    }

    private var cameraSpecs: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
                Text("FUJIFILM X100VI")
                    .font(.title3.weight(.bold))
                    .glassPrimary()
                    .lineLimit(1)

                Text("X-TRANS V")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.cyanAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Theme.cyanAccent.opacity(0.15))
                    .clipShape(Capsule())
            }

            Text("40.2 MP Back-Illuminated CMOS • High-Speed USB PTP Engine")
                .font(.caption)
                .glassSecondary()
                .lineLimit(2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    telemetryBadge(label: "USB VID", value: "0x04CB")
                    telemetryBadge(label: "USB PID", value: "0x0305")
                    telemetryBadge(label: "MODE", value: "USB RAW CONV")
                }
            }
            .padding(.top, 2)
        }
    }

    private var connectionStateText: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(manager.status == .connected ? "Session Active" : (isConnectionInFlight ? "Connecting…" : (manager.status == .error ? "Retry Available" : "Ready to Connect")))
                .font(.subheadline.weight(.semibold))
                .glassPrimary()
            Text(manager.status == .connected ? "Verified USB session. C1–C7 preset reads and local drafts remain separate." : (isConnectionInFlight ? "Opening a USB PTP session. This can take up to 15 seconds." : "Connect over USB-C to inspect C1–C7 preset slots."))
                .font(.caption2)
                .glassSecondary()
                .lineLimit(2)
        }
    }

    private var connectActionButton: some View {
        Button(action: toggleConnection) {
            HStack(spacing: 6) {
                if isConnectionInFlight {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.black)
                    Text("Establishing Link…")
                        .lineLimit(1)
                } else {
                    Image(systemName: manager.status == .connected ? "xmark.circle.fill" : "bolt.fill")
                    Text(manager.status == .connected ? "Disconnect Camera" : "Connect Camera")
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(GlassProminentButtonStyle(color: manager.status == .connected ? Theme.fujiRed : Theme.emeraldGreen, height: 36))
        .disabled(isConnectionInFlight)
        .accessibilityLabel(manager.status == .connected ? "Disconnect camera" : "Connect camera")
        .accessibilityHint(manager.status == .connected
            ? "Ends the current USB camera session."
            : "Starts a USB camera session.")
    }

    private func telemetryBadge(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private func errorHUD(_ error: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.fujiAmber)
                    .symbolEffect(.pulse)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Connection Diagnostic")
                        .font(.subheadline.weight(.semibold))
                        .glassPrimary()
                    Text(error)
                        .font(.caption)
                        .glassSecondary()
                }

                Spacer(minLength: 8)

                Button("Troubleshooting") {
                    showTroubleshooting = true
                }
                .buttonStyle(GlassBorderedButtonStyle(accentColor: Theme.fujiAmber, height: 30))
                .frame(width: 150)
                .accessibilityHint("Opens USB camera connection troubleshooting steps.")
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.fujiAmber)
                    Text("Connection Diagnostic")
                        .font(.subheadline.weight(.semibold))
                        .glassPrimary()
                }
                Text(error)
                    .font(.caption)
                    .glassSecondary()
                Button("Troubleshooting Guide") {
                    showTroubleshooting = true
                }
                .buttonStyle(GlassBorderedButtonStyle(accentColor: Theme.fujiAmber, height: 30))
                .frame(maxWidth: .infinity)
                .accessibilityHint("Opens USB camera connection troubleshooting steps.")
            }
        }
        .glassCard(padding: 14, tint: Theme.fujiAmber.opacity(0.06), borderColor: Theme.fujiAmber.opacity(0.3))
        .accessibilityLabel("Connection diagnostic: \(error)")
    }

    // MARK: - Primary Action Banner & Controls

    private var primaryActionBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                // Horizontal layout
                HStack(spacing: 12) {
                    writeAllButton
                    Spacer(minLength: 8)
                    refreshButton
                    clearAllButton
                }
                // Compact vertical layout
                VStack(alignment: .leading, spacing: 10) {
                    writeAllButton
                    HStack {
                        refreshButton
                        Spacer()
                        clearAllButton
                    }
                }
            }

            if manager.status == .connected, let writeStatusFeedback {
                HStack(spacing: 6) {
                    Image(systemName: writeStatusFeedback.hasPrefix("✓") ? "checkmark.circle.fill" : "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(writeStatusFeedback.hasPrefix("✓") ? Theme.emeraldGreen : Theme.fujiAmber)
                    Text(writeStatusFeedback)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(writeStatusFeedback.hasPrefix("✓") ? Theme.emeraldGreen : Theme.textSecondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule().fill(Color.white.opacity(0.04))
                )
                .transition(.opacity)
            } else if let slotRefreshMessage {
                Text(slotRefreshMessage)
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .transition(.opacity)
            }
        }
        .padding(14)
        .glassPanel(padding: 0, radius: 14)
    }

    private var writeAllButton: some View {
        let dirtyDraftsCount = loadouts.loadouts.filter { $0.hasAnySettings && ($0.provenance != .cameraSynced || loadouts.isDirty($0.slot)) }.count
        let isConnected = manager.status == .connected
        let canWrite = isConnected && dirtyDraftsCount > 0 && !isWritingAll

        return Button {
            writeAllStagedSlotsToCamera()
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(canWrite ? Color.black.opacity(0.2) : Color.white.opacity(0.06))
                        .frame(width: 32, height: 32)

                    if isWritingAll {
                        ProgressView().controlSize(.small)
                    } else if isConnected && dirtyDraftsCount == 0 {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(Theme.emeraldGreen)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(canWrite ? Color.black : Theme.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(isWritingAll
                        ? (writeAllProgress ?? "Writing to Camera…")
                        : (isConnected && dirtyDraftsCount == 0
                            ? "All 7 Slots Synced with Camera"
                            : "Write \(dirtyDraftsCount) Staged Slot\(dirtyDraftsCount == 1 ? "" : "s") to Camera"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(canWrite ? Color.black : (isConnected && dirtyDraftsCount == 0 ? Theme.emeraldGreen : Theme.textTertiary))

                    Text(!isConnected
                        ? "Connect camera via USB to sync"
                        : (dirtyDraftsCount == 0
                            ? "Camera presets match local library"
                            : "\(dirtyDraftsCount) unsynced draft\(dirtyDraftsCount == 1 ? "" : "s") ready to upload over USB-C"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(canWrite ? Color.black.opacity(0.7) : Theme.textMuted)
                }

                Spacer(minLength: 4)

                if canWrite {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color.black.opacity(0.6))
                        .padding(.trailing, 4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(canWrite ? Theme.emeraldGreen : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(canWrite ? Color.white.opacity(0.3) : (isConnected && dirtyDraftsCount == 0 ? Theme.emeraldGreen.opacity(0.3) : Color.white.opacity(0.08)), lineWidth: 1)
            )
            .shadow(color: canWrite ? Theme.emeraldGreen.opacity(0.4) : Color.clear, radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!canWrite)
        .accessibilityIdentifier("write-all-staged-slots-button")
    }

    private var refreshButton: some View {
        Button {
            refreshSlots(overwriteDrafts: true)
        } label: {
            HStack(spacing: 5) {
                if manager.operation == .readingSlots {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                Text("Refresh from Camera")
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 1))
            .foregroundStyle(Color.white)
        }
        .buttonStyle(.plain)
        .disabled(manager.status != .connected || manager.operation == .readingSlots || isWritingAll)
        .help("Reads physical slots C1–C7 from the connected camera")
    }

    private var clearAllButton: some View {
        Button {
            confirmClearAllStaged = true
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.system(size: 10, weight: .medium))
                Text("Clear All Staged")
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.04)))
            .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 1))
            .foregroundStyle(Theme.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(loadouts.loadoutCountWithSettings() == 0 || isWritingAll)
        .help("Clears all 7 local recipe drafts")
    }

    // MARK: - Rotary Dial Strip

    private var rotaryDialStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(1...7, id: \.self) { slot in
                    let loadout = loadouts.loadout(for: slot)
                    let isSelected = selectedDialSlot == slot
                    let accent = slotAccent(slot)
                    let isConfigured = loadout?.hasAnySettings ?? false

                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            selectedDialSlot = slot
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(isConfigured ? accent : Color.white.opacity(0.2))
                                .frame(width: 7, height: 7)

                            Text("C\(slot)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))

                            if let name = loadout?.name, !name.isEmpty {
                                Text(name)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .frame(maxWidth: 80)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? accent.opacity(0.25) : Color.white.opacity(0.04))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isSelected ? accent : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 0.8)
                        )
                        .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Dial Rack (C1 to C7)

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 420), spacing: 14)
    ]

    private var dialRackGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: "dial.low.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.fujiAmber)
                    Text("DIAL RACK (SLOTS C1–C7)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textSecondary)
                }

                Spacer()

                Text("DRAG & DROP RECIPES TO STAGE")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }

            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(1...7, id: \.self) { slot in
                    let loadout = loadouts.loadout(for: slot)
                    LoadoutCard(
                        loadout: loadout,
                        slot: slot,
                        isSelected: selectedDialSlot == slot,
                        isDirty: loadouts.isDirty(slot),
                        isCameraConnected: manager.status == .connected,
                        isCameraSlotEmpty: loadouts.isCameraSlotEmpty(slot),
                        isWriting: manager.operation == .writingSlot(slot),
                        onSelect: { selectedDialSlot = slot },
                        onClear: { slotPendingLocalClear = slot },
                        onEdit: { slotToEdit = loadout },
                        onWriteToCamera: { writeSingleSlot(slot) },
                        onDropRecipe: { recipe in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                loadouts.applyRecipe(recipe, to: slot)
                                selectedDialSlot = slot
                            }
                        }
                    )
                    .id("slot-\(slot)")
                }
            }
        }
    }

    // MARK: - Slot Sync Actions

    private func writeAllStagedSlotsToCamera() {
        guard manager.status == .connected else { return }
        let armedCount = loadouts.loadoutCountWithSettings()
        guard armedCount > 0 else { return }

        Task {
            isWritingAll = true
            writeStatusFeedback = nil
            writeAllProgress = "Writing staged slots to camera…"

            let results = await manager.writeAllStagedSlots(from: loadouts)

            isWritingAll = false
            writeAllProgress = nil

            let successes = results.filter {
                if case .success = $0.result { return true }
                return false
            }
            let failures = results.filter {
                if case .failure = $0.result { return true }
                return false
            }

            if results.isEmpty {
                writeStatusFeedback = "No staged slots were eligible to write, or camera disconnected."
            } else if failures.isEmpty {
                writeStatusFeedback = "✓ Successfully wrote & verified all \(successes.count) staged slots on camera!"
            } else {
                let failedSlots = failures.map { "C\($0.slot)" }.joined(separator: ", ")
                writeStatusFeedback = "Wrote \(successes.count) slots. Failed: \(failedSlots)."
            }
        }
    }

    private func writeSingleSlot(_ slot: Int) {
        guard manager.status == .connected, let loadout = loadouts.loadout(for: slot) else { return }
        Task {
            do {
                writeStatusFeedback = "Writing C\(slot) to camera…"
                let result = try await manager.writeLoadout(loadout, to: slot)
                if let observed = result.observedSnapshot, observed.slot == slot {
                    loadouts.syncFromCameraPresetData([observed], overwriteDirtyDrafts: true)
                    loadouts.markCameraWriteVerified(slot: slot)
                }
                let action = result.createdFromEmpty ? "Created & verified" : "Updated & verified"
                let warnSuffix = result.warnings.isEmpty ? "" : " (warnings: \(result.warnings.joined(separator: ", ")))"
                writeStatusFeedback = "✓ \(action) camera slot C\(slot)\(warnSuffix)."
            } catch {
                writeStatusFeedback = "Failed to write C\(slot): \(error.localizedDescription)"
            }
        }
    }

    private func clearAllStagedSlots() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            loadouts.clearAllStaged()
            writeStatusFeedback = "Cleared all 7 local staged slots."
        }
    }

    private func refreshSlots(overwriteDrafts: Bool) {
        Task {
            let result = await manager.refreshCameraSlots(into: loadouts, overwriteDirtyDrafts: overwriteDrafts)
            slotRefreshMessage = result.isComplete
                ? "Read all seven camera slots."
                : "Partial read: \(result.presets.count)/7. \(result.failures.map(\.description).joined(separator: "; "))"
        }
    }

    private func toggleConnection() {
        Task {
            if manager.status == .connected {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    manager.disconnect()
                }
            } else {
                isConnecting = true
                defer { isConnecting = false }
                await manager.connect(using: cameraSessionFactory(), loadouts: loadouts)
            }
        }
    }

    private var connectionGuideCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Theme.cyanAccent)
                Text("X100VI USB RAW CONNECTION CHECKLIST")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                guideStep(num: "1", title: "Set USB Mode on Camera", desc: "In camera menu: Connection Setting > Connection Mode > Select \"USB RAW CONV. / BACKUP RESTORE\".")
                guideStep(num: "2", title: "Direct USB-C Cable", desc: "Use a high-speed USB-C data cable connected directly to your Mac.")
                guideStep(num: "3", title: "Close Conflicting Apps", desc: "Ensure macOS Photos or Image Capture are not locking the camera PTP endpoint.")
            }

            ViewThatFits(in: .horizontal) {
                HStack {
                    Button("Known Hardware Limitations") {
                        showLimitationsAlert = true
                    }
                    .buttonStyle(.link)
                    .font(.caption)

                    Spacer()

                    Button("Open Troubleshooting Guide") {
                        showTroubleshooting = true
                    }
                    .buttonStyle(GlassBorderedButtonStyle(accentColor: Theme.cyanAccent, height: 28))
                    .frame(width: 190)
                }
                VStack(alignment: .leading, spacing: 8) {
                    Button("Known Hardware Limitations") {
                        showLimitationsAlert = true
                    }
                    .buttonStyle(.link)
                    .font(.caption)

                    Button("Open Troubleshooting Guide") {
                        showTroubleshooting = true
                    }
                    .buttonStyle(GlassBorderedButtonStyle(accentColor: Theme.cyanAccent, height: 28))
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 2)
        }
        .glassCard(tint: Theme.cyanAccent.opacity(0.04), borderColor: Theme.cyanAccent.opacity(0.2))
    }

    private func guideStep(num: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(num)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.black)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Theme.cyanAccent))

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .glassPrimary()
                Text(desc)
                    .font(.caption2)
                    .glassSecondary()
            }
        }
    }
}

// MARK: - RAF Darkroom View

public struct RAFDarkroomView: View {
    @ObservedObject public var manager: CameraManager
    @State private var converting = false
    @State private var selectedRAFPath: URL?
    @State private var conversionStatus = "Ready"
    @State private var conversionError: String? = nil
    @State private var conversionResult: RAFConversionOutcome?
    @State private var showFileChooser = false

    public init(manager: CameraManager) {
        self.manager = manager
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Section Header
                SectionHeader(
                    title: "RAF In-Camera Darkroom",
                    subtitle: "Upload raw .RAF files to your X100VI and develop them with hardware film simulation recipes.",
                    icon: "moon.stars.fill",
                    trailingValue: manager.status == .connected ? "READY" : "OFFLINE",
                    trailingLabel: "ENGINE",
                    accentColor: Theme.cyanAccent
                )

                if manager.status != .connected {
                    offlineHeroView
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                } else {
                    darkroomStudioWorkspace
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .padding(16)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.status)
        }
        .navigationTitle("RAF In-Camera Darkroom")
        .fileImporter(
            isPresented: $showFileChooser,
            allowedContentTypes: [UTType.rafDocument],
            onCompletion: { result in
                if case .success(let url) = result {
                    if url.pathExtension.lowercased() == "raf" {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                            selectedRAFPath = url
                            conversionResult = nil
                            conversionStatus = "RAF selected. Ready to send to the connected camera."
                        }
                    } else {
                        conversionError = "Please select a Fuji RAF raw file (.raf)."
                    }
                }
            }
        )
        .alert("Conversion Notice", isPresented: Binding(
            get: { conversionError != nil },
            set: { if !$0 { conversionError = nil } }
        )) {
            Button("OK") { conversionError = nil }
                .keyboardShortcut(.defaultAction)
        } message: {
            if let err = conversionError { Text(err) }
        }
    }

    private var offlineHeroView: some View {
        VStack(spacing: 14) {
            DarkroomHeroIllustration()
                .padding(.top, 8)

            Text("Camera Connection Required")
                .font(.title3.weight(.bold))
                .glassPrimary()

            Text("The Darkroom uses the X100VI's dedicated X-Processor 5 hardware chip\nto develop true Fujifilm film simulation recipes from raw files.")
                .font(.callout)
                .glassSecondary()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .glassPanel(accentColor: Theme.cyanAccent)
    }

    private var darkroomStudioWorkspace: some View {
        VStack(spacing: 14) {
            // Stage 1: Select RAF File Dropzone
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("STAGE 1: SOURCE RAW FILE")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }

                if let path = selectedRAFPath {
                    HStack(spacing: 10) {
                        Image(systemName: "doc.badge.gearshape.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.emeraldGreen)
                            .symbolEffect(.pulse)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(path.lastPathComponent)
                                .font(.subheadline.weight(.semibold))
                                .glassPrimary()
                                .lineLimit(1)
                            Text(path.deletingLastPathComponent().path)
                                .font(.caption2)
                                .glassTertiary()
                                .lineLimit(1)
                        }

                        Spacer(minLength: 4)

                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedRAFPath = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove selected RAF file")
                        .accessibilityHint("Clears the current RAW file selection.")
                    }
                    .padding(12)
                    .glassCard(padding: 0, radius: 10, tint: Theme.emeraldGreen.opacity(0.08), borderColor: Theme.emeraldGreen.opacity(0.4))
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                } else {
                    Button {
                        showFileChooser = true
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.down.on.square.fill")
                                .font(.system(size: 24))
                                .foregroundStyle(Theme.fujiAmber)
                            Text("Choose .RAF RAW File")
                                .font(.subheadline.weight(.semibold))
                                .glassPrimary()
                            Text("Choose a RAF created by this X100VI")
                                .font(.caption2)
                                .glassSecondary()
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                        .glassCard(padding: 0, radius: 12, tint: Color.white.opacity(0.02), borderColor: Theme.fujiAmber.opacity(0.3))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Choose RAF raw file")
                    .accessibilityHint("Opens a file picker for a Fujifilm RAF file.")
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .glassCard()
            .animation(.spring(response: 0.3, dampingFraction: 0.78), value: selectedRAFPath)

            // Stage 2: In-Camera Conversion Pipeline
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("STAGE 2: HARDWARE CONVERSION TRIGGER")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                }

                if converting {
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(Theme.cyanAccent)

                        HStack {
                            Text(conversionStatus)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.cyanAccent)
                                .lineLimit(1)
                            Spacer()
                            Text("WORKING")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .glassPrimary()
                        }
                    }
                    .padding(14)
                    .glassCard(padding: 0, radius: 10, tint: Theme.cyanAccent.opacity(0.08))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    Button {
                        convertRAF()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 15, weight: .bold))
                            Text("Develop RAW File On-Camera")
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(GlassProminentButtonStyle(color: Theme.cyanAccent, height: 38))
                    .disabled(selectedRAFPath == nil || manager.status != .connected)
                    .transition(.opacity)
                }
            }
            .glassCard()
            .animation(.spring(response: 0.3, dampingFraction: 0.78), value: converting)

            if let conversionResult, !converting {
                conversionResultCard(conversionResult)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

            // Telemetry & Output Notice
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Theme.fujiAmber)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Output Delivery Note")
                        .font(.caption.weight(.semibold))
                        .glassPrimary()
                    Text("The transport can verify that the conversion trigger was accepted, but this macOS backend cannot verify JPEG delivery. Check the camera manually; keep this source selected to retry.")
                        .font(.caption2)
                        .glassSecondary()
                        .lineLimit(3)
                }
            }
            .padding(12)
            .glassCard(padding: 0, radius: 10, tint: Theme.fujiAmber.opacity(0.04))
        }
    }

    private func convertRAF() {
        guard let rafPath = selectedRAFPath else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            converting = true
            conversionResult = nil
            conversionStatus = "Reading the selected RAF and sending it to the camera…"
        }

        Task {
            do {
                guard rafPath.startAccessingSecurityScopedResource() else {
                    throw CameraError.fileAccessDenied
                }
                defer { rafPath.stopAccessingSecurityScopedResource() }
                let rafData = try Data(contentsOf: rafPath)
                let raf = RAFFile(name: rafPath.lastPathComponent, data: rafData)
                conversionStatus = "Waiting for camera conversion trigger…"
                let outcome = await manager.convertRAF(raf)
                conversionResult = outcome
                switch outcome {
                case .downloadedJPEG:
                    conversionStatus = "JPEG data was returned by the camera."
                case .triggerAcceptedOutputNotRetrievable(let reason):
                    conversionStatus = reason
                case .cancelled:
                    conversionStatus = "Conversion was cancelled. Keep the RAF selected to retry."
                case .failed(let message):
                    conversionStatus = "Conversion could not be completed. Keep the RAF selected and retry after reconnecting the camera."
                    conversionError = "\(message)\n\nKeep the selected RAF and retry after reconnecting the camera or power-cycling it."
                }
                converting = false

            } catch {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    conversionStatus = "Conversion could not be completed. Keep the RAF selected and retry after reconnecting the camera."
                    conversionError = "\(error.localizedDescription)\n\nKeep the selected RAF and retry after reconnecting the camera or power-cycling it."
                    conversionResult = .failed(message: error.localizedDescription)
                    converting = false
                }
            }
        }
    }

    private func conversionResultCard(_ outcome: RAFConversionOutcome) -> some View {
        let isFailure: Bool
        let title: String
        let detail: String

        switch outcome {
        case .downloadedJPEG:
            isFailure = false
            title = "JPEG data returned"
            detail = "The camera returned JPEG data through this connection."
        case .triggerAcceptedOutputNotRetrievable(let reason):
            isFailure = false
            title = "JPEG delivery not verified"
            detail = reason
        case .cancelled:
            isFailure = false
            title = "Conversion cancelled"
            detail = "The RAF remains selected so you can retry."
        case .failed(let message):
            isFailure = true
            title = "Conversion not completed"
            detail = message
        }

        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: isFailure ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .foregroundStyle(isFailure ? Theme.fujiRed : Theme.emeraldGreen)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .glassPrimary()
                Text(detail)
                    .font(.caption2)
                    .glassSecondary()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .glassCard(
            padding: 0,
            radius: 10,
            tint: (isFailure ? Theme.fujiRed : Theme.emeraldGreen).opacity(0.06),
            borderColor: (isFailure ? Theme.fujiRed : Theme.emeraldGreen).opacity(0.3)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Limitations Sheet

public struct LimitationsView: View {
    @Binding public var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.obsidianBlack.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(
                            title: "Hardware Link Technical Notes",
                            subtitle: "Architecture details for the Fujifilm X100VI USB PTP protocol on macOS.",
                            icon: "info.circle.fill",
                            accentColor: Theme.cyanAccent
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            limitationRow(
                                title: "Custom Preset Slots (C1–C7)",
                                desc: "Custom slots can be prepared and organized in FujiRecipes Pro. Direct PTP writes to 0xD18C are subject to camera firmware state machine limits."
                            )
                            limitationRow(
                                title: "RAF Darkroom Result Delivery",
                                desc: "The macOS transport can confirm a conversion trigger, but cannot currently confirm where—or whether—the camera delivers a JPEG."
                            )
                            limitationRow(
                                title: "Recovery / Settle Delays",
                                desc: "High-speed 80MB+ RAW transfers utilize automatic PTP session endpoint recovery for maximum link stability."
                            )
                            limitationRow(
                                title: "Live Active Settings",
                                desc: "USB RAW mode supports C1–C7 preset access, but does not expose the camera’s live active-setting telemetry through this macOS transport."
                            )
                        }
                        .glassCard()
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Technical Limitations")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                        .buttonStyle(GlassProminentButtonStyle(color: Theme.fujiAmber, height: 30))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 380)
    }

    private func limitationRow(title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.cyanAccent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .glassPrimary()
                Text(desc)
                    .font(.caption2)
                    .glassSecondary()
            }
        }
    }
}

// MARK: - Troubleshooting Sheet

public struct TroubleshootingView: View {
    @Binding public var isPresented: Bool

    public init(isPresented: Binding<Bool>) {
        self._isPresented = isPresented
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.obsidianBlack.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(
                            title: "USB Connection Troubleshooting",
                            subtitle: "Step-by-step diagnostic guide for establishing stable PTP connection.",
                            icon: "wrench.and.screwdriver.fill",
                            accentColor: Theme.fujiAmber
                        )

                        VStack(alignment: .leading, spacing: 10) {
                            Text("1. Confirm Camera USB Mode")
                                .font(.headline.weight(.semibold))
                                .glassPrimary()
                            Text("Navigate to SET-UP > CONNECTION SETTING > CONNECTION MODE > Select \"USB RAW CONV. / BACKUP RESTORE\".")
                                .font(.caption)
                                .glassSecondary()

                            Divider().overlay(Theme.specularBorder)

                            Text("2. Avoid Background macOS PTP Capture")
                                .font(.headline.weight(.semibold))
                                .glassPrimary()
                            Text("Close Photos.app or Image Capture if they attempt to automatically import photos when the USB cable is plugged in.")
                                .font(.caption)
                                .glassSecondary()

                            Divider().overlay(Theme.specularBorder)

                            Text("3. Quick Power Cycle")
                                .font(.headline.weight(.semibold))
                                .glassPrimary()
                            Text("If a large 85MB transfer is interrupted, turn the camera off for 5 seconds and turn it back on to reset the USB endpoint.")
                                .font(.caption)
                                .glassSecondary()
                        }
                        .glassCard()
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Connection Troubleshooting")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                        .buttonStyle(GlassProminentButtonStyle(color: Theme.fujiAmber, height: 30))
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 440, minHeight: 400)
    }
}
