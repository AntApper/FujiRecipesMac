import SwiftUI
import FujiRecipesCore
import X100VIHelper
import PTPClientMacOS
import UniformTypeIdentifiers
import QuickLookThumbnailing
import ImageIO

public extension UTType {
    /// Best-effort type filter for Fuji RAF raw files.
    static let rafDocument = UTType(filenameExtension: "raf") ?? .data
}

// MARK: - 2026 Camera Studio & Hardware Telemetry Hub

private struct ActionFeedback: Equatable {
    let text: String
    let succeeded: Bool
}

public struct CameraConnectionView: View {
    @ObservedObject public var manager: CameraManager
    @ObservedObject public var loadouts: LoadoutStore
    @State private var isConnecting = false
    @State private var showLimitationsAlert = false
    @State private var showTroubleshooting = false
    @State private var confirmOverwriteDrafts = false
    @State private var confirmWriteAll = false
    @State private var confirmClearAllStaged = false
    @State private var slotPendingLocalClear: Int?
    @State private var slotToEdit: Loadout?
    @Binding public var selectedDialSlot: Int
    @State private var isWritingAll = false
    /// Captured when Write All starts, because `stagedSlots` shrinks as each
    /// slot verifies and the "2 of 5" progress needs the original list.
    @State private var writeAllPlan: [Int] = []
    @State private var feedback: ActionFeedback?
    @State private var rackWidth: Double = 0
    @FocusState private var isRackFocused: Bool
    private let cameraSessionFactory: CameraSessionFactory

    private var isConnectionInFlight: Bool {
        isConnecting || manager.status == .connecting
    }

    private var isReadingSlotsDuringConnect: Bool {
        manager.status == .connecting && manager.operation == .readingSlots
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
                    if let failure = manager.lastError {
                        errorHUD(failure)
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
        .onChange(of: manager.status) { _, status in
            if status == .connecting {
                feedback = nil
            }
        }
        .onChange(of: feedback) { _, feedback in
            if let feedback {
                AccessibilityNotification.Announcement(feedback.text).post()
            }
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
            "Write \(stagedSlotList) to the camera?",
            isPresented: $confirmWriteAll,
            titleVisibility: .visible
        ) {
            Button("Write \(loadouts.stagedSlots.count == 1 ? "1 Slot" : "\(loadouts.stagedSlots.count) Slots")") {
                writeAllStagedSlotsToCamera()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces the camera presets in \(stagedSlotList). Other camera slots are not touched.")
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
        .clearLocalDraftConfirmation(slot: $slotPendingLocalClear, loadouts: loadouts)
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
            Text(manager.status == .connected ? "Verified USB session. C1–C7 preset reads and local drafts remain separate." : (isReadingSlotsDuringConnect ? "Session open. Reading preset slots C1–C7 from the camera." : (isConnectionInFlight ? "Opening a USB PTP session. This can take up to 15 seconds." : "Connect over USB-C to inspect C1–C7 preset slots.")))
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
                    Text(isReadingSlotsDuringConnect ? "Reading C1–C7…" : "Establishing Link…")
                        .lineLimit(1)
                } else {
                    Image(systemName: manager.status == .connected ? "xmark.circle.fill" : "bolt.fill")
                    Text(manager.status == .connected ? "Disconnect Camera" : "Connect Camera")
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(GlassProminentButtonStyle(color: manager.status == .connected ? Theme.fujiRed : Theme.emeraldGreen, height: 36))
        .disabled(isConnectionInFlight || manager.isBusy)
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

    private func errorHUD(_ failure: CameraFailure) -> some View {
        let title: String
        let offersTroubleshooting: Bool
        switch failure.kind {
        case .connection:
            (title, offersTroubleshooting) = ("Connection Failed", true)
        case .slotRead:
            (title, offersTroubleshooting) = ("Some Slots Couldn’t Be Read", true)
        case .slotWrite(let slot):
            (title, offersTroubleshooting) = ("C\(slot) Write Failed", false)
        case .rawConversion:
            (title, offersTroubleshooting) = ("RAW Conversion Failed", false)
        }
        let actions = HStack(spacing: 8) {
            if offersTroubleshooting {
                Button("Troubleshooting") {
                    showTroubleshooting = true
                }
                .buttonStyle(GlassBorderedButtonStyle(accentColor: Theme.fujiAmber, height: 30))
                .frame(width: 150)
                .accessibilityHint("Opens USB camera connection troubleshooting steps.")
            }
            Button("Dismiss") {
                manager.lastError = nil
            }
            .buttonStyle(GlassBorderedButtonStyle(accentColor: Theme.textSecondary, height: 30))
            .frame(width: 90)
        }

        return ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.fujiAmber)
                    .symbolEffect(.pulse)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .glassPrimary()
                    Text(failure.message)
                        .font(.caption)
                        .glassSecondary()
                }

                Spacer(minLength: 8)

                actions
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.fujiAmber)
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .glassPrimary()
                }
                Text(failure.message)
                    .font(.caption)
                    .glassSecondary()
                actions
            }
        }
        .glassCard(padding: 14, tint: Theme.fujiAmber.opacity(0.06), borderColor: Theme.fujiAmber.opacity(0.3))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): \(failure.message)")
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

            if let feedback {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: feedback.succeeded ? "checkmark.circle.fill" : "info.circle.fill")
                        .font(.caption)
                        .foregroundStyle(feedback.succeeded ? Theme.emeraldGreen : Theme.fujiAmber)
                    Text(feedback.text)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(feedback.succeeded ? Theme.emeraldGreen : Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04))
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("camera-action-feedback")
                .transition(.opacity)
            }
        }
        .padding(14)
        .glassPanel(padding: 0, radius: 14)
    }

    private var stagedSlotList: String {
        loadouts.stagedSlots.map { "C\($0)" }.formatted(.list(type: .and))
    }

    private var writeAllProgress: String {
        guard case .writingSlot(let slot) = manager.operation,
              let index = writeAllPlan.firstIndex(of: slot) else {
            return "Writing to Camera…"
        }
        return "Writing C\(slot) (\(index + 1) of \(writeAllPlan.count))"
    }

    private var writeAllButton: some View {
        let stagedCount = loadouts.stagedSlots.count
        let isConnected = manager.status == .connected
        let canWrite = isConnected && stagedCount > 0 && !manager.isBusy
        let isSynced = isConnected && stagedCount == 0 && loadouts.dirtySlots.isEmpty
        let clearedSlots = loadouts.dirtySlots.subtracting(loadouts.stagedSlots).sorted().map { "C\($0)" }

        return Button {
            confirmWriteAll = true
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(canWrite ? Color.black.opacity(0.2) : Color.white.opacity(0.06))
                        .frame(width: 32, height: 32)

                    if isWritingAll {
                        ProgressView().controlSize(.small)
                    } else if isSynced {
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
                        ? writeAllProgress
                        : (stagedCount == 0
                            ? (isSynced ? "All 7 Slots Synced with Camera" : "No Staged Changes")
                            : "Write \(stagedCount) Staged Slot\(stagedCount == 1 ? "" : "s") to Camera"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(canWrite ? Color.black : (isSynced ? Theme.emeraldGreen : Theme.textTertiary))

                    Text(!isConnected
                        ? "Connect camera via USB to sync"
                        : (stagedCount > 0
                            ? "\(stagedCount) unsynced draft\(stagedCount == 1 ? "" : "s") ready to upload over USB-C"
                            : (isSynced
                                ? "Camera presets match local library"
                                : "Cleared locally, still on the camera: \(clearedSlots.formatted(.list(type: .and))). Refresh to reload.")))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(canWrite ? Color.black.opacity(0.7) : Theme.textTertiary)
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
                    .stroke(canWrite ? Color.white.opacity(0.3) : (isSynced ? Theme.emeraldGreen.opacity(0.3) : Color.white.opacity(0.08)), lineWidth: 1)
            )
            .shadow(color: canWrite ? Theme.emeraldGreen.opacity(0.4) : Color.clear, radius: 10, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(!canWrite)
        .accessibilityIdentifier("write-all-staged-slots-button")
    }

    private var refreshButton: some View {
        Button {
            if loadouts.dirtySlots.isEmpty {
                refreshSlots(overwriteDrafts: false)
            } else {
                confirmOverwriteDrafts = true
            }
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
        .disabled(manager.status != .connected || manager.isBusy)
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
        .disabled(loadouts.loadoutCountWithSettings() == 0 || manager.isBusy)
        .help("Clears all 7 local recipe drafts")
    }

    // MARK: - Dial Rack (C1 to C7)

    private var rackColumnCount: Int {
        GridNavigation.columnCount(width: rackWidth, minimum: 280, spacing: 14)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(maximum: 420), spacing: 14), count: rackColumnCount)
    }

    private func selectSlot(_ slot: Int) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            selectedDialSlot = slot
        }
        isRackFocused = true
    }

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
                        isCameraBusy: manager.isBusy,
                        onSelect: { selectSlot(slot) },
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
                    .accessibilityIdentifier("slot-\(slot)")
                }
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: Double.self) { $0.size.width } action: { rackWidth = $0 }
            .focusable()
            .focusEffectDisabled()
            .focused($isRackFocused)
            .onKeyPress { keyPress in
                if let char = keyPress.characters.first, let num = Int(String(char)), (1...7).contains(num) {
                    selectSlot(num)
                    return .handled
                }
                guard let move = GridNavigation.Move(key: keyPress.key) else { return .ignored }
                let index = GridNavigation.index(from: selectedDialSlot - 1, move: move, count: 7, columns: rackColumnCount)
                selectSlot(index + 1)
                return .handled
            }
            .onAppear {
                isRackFocused = true
            }
        }
    }

    // MARK: - Slot Sync Actions

    private func writeAllStagedSlotsToCamera() {
        guard manager.status == .connected, !loadouts.stagedSlots.isEmpty else { return }

        Task {
            writeAllPlan = loadouts.stagedSlots
            isWritingAll = true
            feedback = nil

            let outcomes = await manager.writeAllStagedSlots(from: loadouts)

            isWritingAll = false
            writeAllPlan = []
            let verified = !outcomes.isEmpty && outcomes.allSatisfy { (try? $0.result.get())?.isVerified == true }
            feedback = ActionFeedback(text: WriteAllSummary.text(for: outcomes), succeeded: verified)
        }
    }

    private func writeSingleSlot(_ slot: Int) {
        guard manager.status == .connected else { return }
        Task {
            do {
                feedback = ActionFeedback(text: "Writing C\(slot) to camera…", succeeded: false)
                let result = try await manager.writeSlot(slot, from: loadouts)
                feedback = ActionFeedback(text: result.summary, succeeded: result.isVerified)
            } catch {
                feedback = ActionFeedback(text: "C\(slot): \(error.localizedDescription)", succeeded: false)
            }
        }
    }

    private func clearAllStagedSlots() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            loadouts.clearAllStaged()
            feedback = ActionFeedback(text: "Cleared all 7 local drafts. The camera slots are unchanged.", succeeded: false)
        }
    }

    private func refreshSlots(overwriteDrafts: Bool) {
        Task {
            feedback = nil
            let result = await manager.refreshCameraSlots(into: loadouts, overwriteDirtyDrafts: overwriteDrafts)
            feedback = ActionFeedback(text: result.summary, succeeded: result.isComplete)
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
    @ObservedObject public var store: RecipeStore
    private let cameraSessionFactory: CameraSessionFactory

    // RAF Source State
    @State private var selectedRAFURL: URL?
    @State private var rafFileSizeString: String?
    @State private var rafTimestampString: String?
    @State private var rafThumbnail: NSImage?
    @State private var isTargetedForDrop = false
    @State private var showFileChooser = false

    // Recipe Target Selection State
    @State private var selectedTargetKey: String = "slot-1"

    // Conversion Execution & HUD State
    @State private var converting = false
    @State private var conversionProgressStep = "Ready"
    @State private var conversionOutcome: RAFConversionOutcome?
    @State private var conversionError: String? = nil
    @State private var isConnectingCamera = false
    @State private var developedJPEGImage: NSImage?
    @State private var saveFeedback: String? = nil

    public init(
        manager: CameraManager,
        store: RecipeStore? = nil,
        cameraSessionFactory: @escaping CameraSessionFactory = { ImageCaptureCorePTPClient() }
    ) {
        self.manager = manager
        self.store = store ?? RecipeStore()
        self.cameraSessionFactory = cameraSessionFactory
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                // Section Header
                SectionHeader(
                    title: "RAF In-Camera Darkroom",
                    subtitle: "Upload raw .RAF files to your X100VI and develop them with hardware film simulation recipes.",
                    icon: "moon.stars.fill",
                    trailingValue: manager.status == .connected ? "READY" : "OFFLINE",
                    trailingLabel: "ENGINE",
                    accentColor: Theme.cyanAccent
                )

                // STAGE 1: Interactive RAF Import Zone
                rafImportZone

                // STAGE 2: Recipe Development Selector & Parameter Card
                recipeDevelopmentSelector

                // STAGE 3: Conversion Execution & Hardware Status HUD
                conversionExecutionHUD

                // Telemetry & Output Notice
                telemetryNoticeCard
            }
            .padding(16)
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: manager.status)
        }
        .navigationTitle("RAF In-Camera Darkroom")
        .alert("Darkroom Notice", isPresented: Binding(
            get: { conversionError != nil },
            set: { if !$0 { conversionError = nil } }
        )) {
            Button("OK") { conversionError = nil }
                .keyboardShortcut(.defaultAction)
        } message: {
            if let err = conversionError { Text(err) }
        }
    }

    // MARK: - Stage 1: Interactive RAF Import Zone

    private var rafImportZone: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("STAGE 1: SOURCE RAW FILE", systemImage: "arrow.down.doc")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                if selectedRAFURL != nil {
                    Text("FILE LOADED")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.emeraldGreen)
                }
            }

            if let path = selectedRAFURL {
                // Selected RAF File Card
                HStack(spacing: 14) {
                    // Metadata Thumbnail or Fallback Badge
                    Group {
                        if let thumb = rafThumbnail {
                            Image(nsImage: thumb)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 76, height: 76)
                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                                )
                                .shadow(color: Color.black.opacity(0.4), radius: 4)
                        } else {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color.black.opacity(0.45))
                                    .frame(width: 76, height: 76)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(Theme.cyanAccent.opacity(0.3), lineWidth: 0.8)
                                    )
                                VStack(spacing: 3) {
                                    Image(systemName: "camera.macro")
                                        .font(.title2)
                                        .foregroundStyle(Theme.cyanAccent)
                                    Text("RAF")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(path.lastPathComponent)
                            .font(.headline.weight(.semibold))
                            .glassPrimary()
                            .lineLimit(1)

                        HStack(spacing: 10) {
                            if let size = rafFileSizeString {
                                Label(size, systemImage: "internaldrive")
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            if let time = rafTimestampString {
                                Label(time, systemImage: "clock")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }

                        Text(path.deletingLastPathComponent().path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 8) {
                        Button("Change…") {
                            browseForRAF()
                        }
                        .buttonStyle(GlassBorderedButtonStyle())
                        .accessibilityLabel("Change selected RAF file")

                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                selectedRAFURL = nil
                                rafThumbnail = nil
                                rafFileSizeString = nil
                                rafTimestampString = nil
                                developedJPEGImage = nil
                                conversionOutcome = nil
                                conversionError = nil
                                saveFeedback = nil
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove selected RAF file")
                    }
                }
                .padding(14)
                .glassCard(
                    padding: 0,
                    radius: 12,
                    tint: isTargetedForDrop ? Theme.emeraldGreen.opacity(0.12) : Theme.cyanAccent.opacity(0.06),
                    borderColor: isTargetedForDrop ? Theme.emeraldGreen.opacity(0.6) : Theme.cyanAccent.opacity(0.35)
                )
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    return handleDroppedURL(url)
                } isTargeted: { targeted in
                    withAnimation(.easeInOut(duration: 0.15)) { isTargetedForDrop = targeted }
                }
            } else {
                // Interactive Empty Dropzone
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(isTargetedForDrop ? Theme.emeraldGreen.opacity(0.18) : Theme.cyanAccent.opacity(0.08))
                            .frame(width: 54, height: 54)
                        Image(systemName: isTargetedForDrop ? "arrow.down.circle.fill" : "square.and.arrow.down.on.square.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(isTargetedForDrop ? Theme.emeraldGreen : Theme.cyanAccent)
                    }

                    VStack(spacing: 4) {
                        Text(isTargetedForDrop ? "Release to Drop .RAF File" : "Drag & Drop Fujifilm .RAF File Here")
                            .font(.subheadline.weight(.semibold))
                            .glassPrimary()
                        Text("Accepts native uncompressed and lossless compressed .RAF raw files from X100VI")
                            .font(.caption2)
                            .glassSecondary()
                    }

                    Button {
                        browseForRAF()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                                .font(.caption.weight(.semibold))
                            Text("Browse Files…")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(GlassBorderedButtonStyle())
                    .frame(width: 160)
                    .accessibilityIdentifier("browse-raf-button")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .glassCard(
                    padding: 0,
                    radius: 12,
                    tint: isTargetedForDrop ? Theme.emeraldGreen.opacity(0.08) : Color.white.opacity(0.015),
                    borderColor: isTargetedForDrop ? Theme.emeraldGreen.opacity(0.6) : Color.white.opacity(0.10)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: isTargetedForDrop ? 2 : 1, dash: [6, 4])
                        )
                        .foregroundStyle(isTargetedForDrop ? Theme.emeraldGreen : Color.white.opacity(0.18))
                )
                .dropDestination(for: URL.self) { urls, _ in
                    guard let url = urls.first else { return false }
                    return handleDroppedURL(url)
                } isTargeted: { targeted in
                    withAnimation(.easeInOut(duration: 0.15)) { isTargetedForDrop = targeted }
                }
            }
        }
        .glassCard()
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: selectedRAFURL)
    }

    // MARK: - Stage 2: Recipe Development Selector

    private var activeRecipe: Recipe {
        if selectedTargetKey.hasPrefix("slot-") {
            let slotNumStr = selectedTargetKey.replacingOccurrences(of: "slot-", with: "")
            if let slotNum = Int(slotNumStr), let loadout = store.loadouts.loadout(for: slotNum) {
                return makeRecipe(from: loadout)
            }
        } else if selectedTargetKey.hasPrefix("custom-") {
            let id = selectedTargetKey.replacingOccurrences(of: "custom-", with: "")
            if let custom = store.customRecipes.recipes.first(where: { $0.id == id }) {
                return custom
            }
        } else {
            let id = selectedTargetKey.replacingOccurrences(of: "catalog-", with: "")
            if let catalog = store.recipes.first(where: { $0.id == id }) {
                return catalog
            }
        }

        if let first = store.recipes.first {
            return first
        }

        return Recipe(
            id: "default-provia",
            name: "Standard Provia",
            source: "Fujifilm Default",
            sourceUrl: nil,
            filmSimulation: .provia,
            dynamicRange: .dr100,
            grainEffect: .off,
            whiteBalanceMode: .auto
        )
    }

    private func makeRecipe(from loadout: Loadout) -> Recipe {
        Recipe(
            id: "slot-\(loadout.slot)",
            name: loadout.name.isEmpty ? "C\(loadout.slot)" : loadout.name,
            source: "Custom Slot C\(loadout.slot)",
            sourceUrl: nil,
            filmSimulation: loadout.filmSim ?? .provia,
            dynamicRange: loadout.dr ?? .dr100,
            grainEffect: loadout.grain ?? .off,
            whiteBalanceMode: loadout.wb ?? .auto,
            wbShiftRed: loadout.wbShiftRed ?? 0,
            wbShiftBlue: loadout.wbShiftBlue ?? 0,
            colorTempK: loadout.colorTempK,
            highlight: loadout.highlight ?? 0,
            shadow: loadout.shadow ?? 0,
            color: loadout.color ?? 0,
            sharpness: loadout.sharpness ?? 0,
            highIsoNr: loadout.highIsoNr ?? 0,
            clarity: loadout.clarity ?? 0
        )
    }

    private var recipeDevelopmentSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("STAGE 2: RECIPE DEVELOPMENT PROFILE", systemImage: "slider.horizontal.2.square.on.square")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("RECIPE READY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.fujiAmber)
            }

            // Recipe Target Dropdown Menu
            Menu {
                Section("Staged Presets (C1–C7)") {
                    ForEach(store.loadouts.loadouts.sorted(by: { $0.slot < $1.slot })) { slot in
                        Button {
                            selectedTargetKey = "slot-\(slot.slot)"
                        } label: {
                            HStack {
                                Text("C\(slot.slot): \(slot.name.isEmpty ? "Standard" : slot.name)")
                                if selectedTargetKey == "slot-\(slot.slot)" {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }

                if !store.customRecipes.recipes.isEmpty {
                    Section("My Custom Recipes") {
                        ForEach(store.customRecipes.recipes) { r in
                            Button {
                                selectedTargetKey = "custom-\(r.id)"
                            } label: {
                                HStack {
                                    Text(r.name)
                                    if selectedTargetKey == "custom-\(r.id)" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Recipe Catalog") {
                    ForEach(store.recipes.prefix(20)) { r in
                        Button {
                            selectedTargetKey = "catalog-\(r.id)"
                        } label: {
                            HStack {
                                Text(r.name)
                                if selectedTargetKey == "catalog-\(r.id)" {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "camera.filters")
                        .foregroundStyle(Theme.filmSimColor(for: activeRecipe.filmSimulation?.displayName ?? "Provia"))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(activeRecipe.name)
                            .font(.subheadline.weight(.semibold))
                            .glassPrimary()
                        Text(activeRecipe.source)
                            .font(.caption2)
                            .glassSecondary()
                    }

                    Spacer()

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.white.opacity(0.04)))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Theme.specularBorder, lineWidth: 0.8))
            }
            .menuStyle(.borderlessButton)
            .accessibilityLabel("Select recipe to apply for RAW development")

            // Compact Recipe Parameter Card
            compactRecipeParameterCard(activeRecipe)
        }
        .glassCard()
    }

    private func compactRecipeParameterCard(_ recipe: Recipe) -> some View {
        let simName = recipe.filmSimulation?.displayName ?? "Provia"
        let simColor = Theme.filmSimColor(for: simName)

        return VStack(alignment: .leading, spacing: 10) {
            // Header Row: Film Sim Badge & Dynamic Range
            HStack(spacing: 8) {
                FilmSimBadge(name: simName, isCompact: true)

                // Dynamic Range Pill
                HStack(spacing: 3) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 8))
                    Text(recipe.dynamicRange?.displayName ?? "DR100")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.white.opacity(0.06)))
                .overlay(Capsule().stroke(Color.white.opacity(0.12), lineWidth: 0.7))
                .foregroundStyle(Theme.textPrimary)

                Spacer()

                // White Balance Kelvin Chip
                KelvinChip(
                    kelvin: recipe.colorTempK,
                    modeName: recipe.whiteBalanceMode?.displayName
                )
            }

            Divider().overlay(Color.white.opacity(0.08))

            // Parameter Grid: Tone Curve Radar & Secondary Attributes
            HStack(alignment: .center, spacing: 12) {
                // Tone Curve Radar
                VStack(alignment: .leading, spacing: 3) {
                    Text("TONE CURVE (H / S / C / Sh)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)

                    ToneCurveRadar(tones: recipe.toneTenths, accentColor: simColor)
                }

                Spacer()

                // Grain & Clarity Chips
                HStack(spacing: 6) {
                    if let grain = recipe.grainEffect, grain != .off {
                        attributePill(label: "Grain", value: grain.displayName)
                    }
                    if let clarity = recipe.clarity, clarity != 0 {
                        attributePill(label: "Clarity", value: clarity > 0 ? "+\(clarity)" : "\(clarity)")
                    }
                    if let nr = recipe.highIsoNr, nr != 0 {
                        attributePill(label: "NR", value: nr > 0 ? "+\(nr)" : "\(nr)")
                    }
                }
            }
        }
        .padding(12)
        .glassCard(
            padding: 0,
            radius: 10,
            tint: simColor.opacity(0.05),
            borderColor: simColor.opacity(0.3)
        )
    }

    private func attributePill(label: String, value: String) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Text(value)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.white.opacity(0.04)))
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.6))
    }

    // MARK: - Stage 3: Conversion Execution & Hardware Status HUD

    private var conversionExecutionHUD: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("STAGE 3: HARDWARE CONVERSION TRIGGER", systemImage: "cpu.fill")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                HStack(spacing: 5) {
                    Circle()
                        .fill(manager.status.tint)
                        .frame(width: 7, height: 7)
                    Text(manager.status.formattedLabel)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(manager.status.tint)
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.3)))
                .overlay(Capsule().stroke(manager.status.tint.opacity(0.3), lineWidth: 0.7))
            }

            if manager.status != .connected {
                // Offline Hardware Link Explanation Card
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "cpu")
                            .font(.title2)
                            .foregroundStyle(Theme.fujiAmber)

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Dedicated X-Processor 5 Hardware Required")
                                .font(.subheadline.weight(.bold))
                                .glassPrimary()
                            Text("The RAF In-Camera Darkroom processes RAW files directly on your X100VI's dedicated X-Processor 5 hardware via USB. This yields authentic Fujifilm demosaicing, sensor color science, and dynamic range preservation with zero emulation degradation.")
                                .font(.caption)
                                .glassSecondary()
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Divider().overlay(Theme.specularBorder)

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ready to connect via high-speed USB-C")
                                .font(.caption.weight(.medium))
                                .glassPrimary()
                            Text("Set camera mode: Connection Setting > Connection Mode > 'USB RAW CONV. / BACKUP RESTORE'.")
                                .font(.caption2)
                                .glassTertiary()
                        }

                        Spacer()

                        Button {
                            connectCamera()
                        } label: {
                            HStack(spacing: 6) {
                                if isConnectingCamera || manager.status == .connecting {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 14, height: 14)
                                    Text("Connecting…")
                                } else {
                                    Image(systemName: "bolt.fill")
                                    Text("Connect Camera")
                                }
                            }
                        }
                        .buttonStyle(GlassProminentButtonStyle(color: Theme.cyanAccent, height: 34))
                        .disabled(isConnectingCamera || manager.status == .connecting || manager.isBusy)
                        .accessibilityIdentifier("darkroom-connect-camera-button")
                    }
                }
                .padding(14)
                .glassCard(padding: 0, radius: 10, tint: Theme.fujiAmber.opacity(0.06), borderColor: Theme.fujiAmber.opacity(0.3))
            } else {
                // Connected Execution Controls
                if converting {
                    VStack(spacing: 12) {
                        ProgressView()
                            .tint(Theme.cyanAccent)
                            .scaleEffect(1.1)

                        VStack(spacing: 4) {
                            Text(conversionProgressStep)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.cyanAccent)
                            Text("X-Processor 5 hardware pipeline active on camera")
                                .font(.caption2)
                                .glassSecondary()
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .glassCard(padding: 0, radius: 10, tint: Theme.cyanAccent.opacity(0.08), borderColor: Theme.cyanAccent.opacity(0.35))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
                } else {
                    HStack(spacing: 12) {
                        Button {
                            convertRAF()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 14, weight: .bold))
                                Text("Develop with X-Processor 5")
                                    .font(.subheadline.weight(.bold))
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(GlassProminentButtonStyle(color: Theme.cyanAccent, height: 40))
                        .disabled(selectedRAFURL == nil || manager.isBusy)
                        .accessibilityIdentifier("develop-raf-button")

                        if selectedRAFURL == nil {
                            Text("Select or drop a .RAF file above to begin development")
                                .font(.caption2)
                                .glassTertiary()
                        }
                    }
                }

                // Developed JPEG Preview and Action Card
                if let jpegImage = developedJPEGImage, let outcome = conversionOutcome, let jpeg = outcome.jpeg {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Theme.emeraldGreen)
                            Text("X-Processor 5 Development Succeeded")
                                .font(.caption.weight(.bold))
                                .glassPrimary()
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: Int64(jpeg.data.count), countStyle: .file))
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.emeraldGreen)
                        }

                        Image(nsImage: jpegImage)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: 280)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Theme.emeraldGreen.opacity(0.35), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.5), radius: 8)

                        HStack(spacing: 10) {
                            Button {
                                saveDevelopedJPEG(jpeg)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.down.fill")
                                    Text("Save Developed JPEG…")
                                }
                            }
                            .buttonStyle(GlassProminentButtonStyle(color: Theme.emeraldGreen, height: 32))
                            .accessibilityIdentifier("save-developed-jpeg-button")

                            Button {
                                openInPreview(jpeg)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "eye.fill")
                                    Text("Open in Preview")
                                }
                            }
                            .buttonStyle(GlassBorderedButtonStyle())
                            .accessibilityIdentifier("open-in-preview-button")

                            if let feedback = saveFeedback {
                                Text(feedback)
                                    .font(.caption2)
                                    .foregroundStyle(Theme.emeraldGreen)
                                    .lineLimit(1)
                            }
                        }
                    }
                    .padding(14)
                    .glassCard(padding: 0, radius: 12, tint: Theme.emeraldGreen.opacity(0.06), borderColor: Theme.emeraldGreen.opacity(0.35))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else if let outcome = conversionOutcome, !converting {
                    conversionResultCard(outcome)
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .glassCard()
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: converting)
        .animation(.spring(response: 0.3, dampingFraction: 0.78), value: developedJPEGImage != nil)
    }

    private var telemetryNoticeCard: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.fujiAmber)
            VStack(alignment: .leading, spacing: 1) {
                Text("Output Delivery Architecture")
                    .font(.caption.weight(.semibold))
                    .glassPrimary()
                Text("X-Processor 5 performs full hardware RAW demosaicing. When JPEG retrieval is supported by the USB session, the output appears above for instant saving and Preview inspection.")
                    .font(.caption2)
                    .glassSecondary()
                    .lineLimit(3)
            }
        }
        .padding(12)
        .glassCard(padding: 0, radius: 10, tint: Theme.fujiAmber.opacity(0.04))
    }

    // MARK: - Actions & Operations

    private func handleDroppedURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ext == "raf" || ext == "raw" || ext == "dng" else {
            conversionError = "Please select a Fujifilm RAW file (.raf)."
            return false
        }
        loadRAFMetadata(url: url)
        return true
    }

    private func browseForRAF() {
        let panel = NSOpenPanel()
        panel.title = "Select Fujifilm RAW (.RAF) File"
        panel.prompt = "Choose RAF"
        panel.allowedContentTypes = [
            UTType.rafDocument,
            UTType(filenameExtension: "raf") ?? .data,
            UTType.rawImage
        ]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            loadRAFMetadata(url: url)
        }
    }

    private func loadRAFMetadata(url: URL) {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
            selectedRAFURL = url
            conversionOutcome = nil
            developedJPEGImage = nil
            conversionError = nil
            saveFeedback = nil
        }

        // Extract file attributes
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
            if let size = attrs[.size] as? Int64 {
                rafFileSizeString = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
            }
            if let modDate = attrs[.modificationDate] as? Date {
                let formatter = DateFormatter()
                formatter.dateStyle = .medium
                formatter.timeStyle = .short
                rafTimestampString = formatter.string(from: modDate)
            }
        }

        // Asynchronous thumbnail extraction
        Task.detached(priority: .userInitiated) {
            var thumbImage: NSImage?

            // 1. Try CGImageSource embedded thumbnail
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
                let options: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 320
                ]
                if let cgThumb = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                    thumbImage = NSImage(cgImage: cgThumb, size: NSSize(width: cgThumb.width, height: cgThumb.height))
                }
            }

            // 2. Fallback to QuickLook thumbnail generator
            if thumbImage == nil {
                let request = QLThumbnailGenerator.Request(
                    fileAt: url,
                    size: CGSize(width: 256, height: 256),
                    scale: 2.0,
                    representationTypes: .thumbnail
                )
                if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
                    thumbImage = rep.nsImage
                }
            }

            let finalThumb = thumbImage
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.2)) {
                    self.rafThumbnail = finalThumb
                }
            }
        }
    }

    private func connectCamera() {
        Task {
            isConnectingCamera = true
            await manager.connect(using: cameraSessionFactory(), loadouts: store.loadouts)
            isConnectingCamera = false
        }
    }

    private func convertRAF() {
        guard let rafURL = selectedRAFURL else { return }

        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            converting = true
            conversionOutcome = nil
            developedJPEGImage = nil
            conversionProgressStep = "Reading RAF raw file payload…"
        }

        Task {
            do {
                let isAccessing = rafURL.startAccessingSecurityScopedResource()
                defer {
                    if isAccessing { rafURL.stopAccessingSecurityScopedResource() }
                }
                let rafData = try Data(contentsOf: rafURL)
                let raf = RAFFile(name: rafURL.lastPathComponent, data: rafData)

                await MainActor.run {
                    conversionProgressStep = "Uploading RAW payload to X-Processor 5…"
                }

                let outcome = await manager.convertRAF(raf)

                await MainActor.run {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        conversionOutcome = outcome
                        converting = false

                        switch outcome {
                        case .downloadedJPEG(let jpeg):
                            conversionProgressStep = "Development complete! 40.2MP JPEG ready."
                            developedJPEGImage = NSImage(data: jpeg.data)
                        case .triggerAcceptedOutputNotRetrievable(let reason):
                            conversionProgressStep = reason
                        case .cancelled:
                            conversionProgressStep = "Conversion cancelled."
                        case .failed(let message):
                            conversionProgressStep = "Conversion failed."
                            conversionError = message
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        converting = false
                        conversionProgressStep = "Conversion error: \(error.localizedDescription)"
                        conversionError = error.localizedDescription
                        conversionOutcome = .failed(message: error.localizedDescription)
                    }
                }
            }
        }
    }

    private func saveDevelopedJPEG(_ jpeg: JPEGFile) {
        let panel = NSSavePanel()
        panel.title = "Save Developed JPEG"
        panel.prompt = "Save JPEG"
        panel.allowedContentTypes = [.jpeg]
        let baseName = selectedRAFURL?.deletingPathExtension().lastPathComponent ?? "DSCF_developed"
        panel.nameFieldStringValue = "\(baseName).jpg"

        if panel.runModal() == .OK, let targetURL = panel.url {
            do {
                try jpeg.data.write(to: targetURL)
                saveFeedback = "Saved to \(targetURL.lastPathComponent)"
            } catch {
                conversionError = "Failed to save developed JPEG: \(error.localizedDescription)"
            }
        }
    }

    private func openInPreview(_ jpeg: JPEGFile) {
        let baseName = selectedRAFURL?.deletingPathExtension().lastPathComponent ?? "DSCF_developed"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName)_\(UUID().uuidString.prefix(6)).jpg")
        do {
            try jpeg.data.write(to: tempURL)
            NSWorkspace.shared.open(tempURL)
        } catch {
            conversionError = "Failed to open preview: \(error.localizedDescription)"
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
            title = "JPEG written to camera SD card"
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
