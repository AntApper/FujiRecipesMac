import SwiftUI
import FujiRecipesCore

// MARK: - 2026 C1–C7 Custom Dial Matrix View

public struct LoadoutsView: View {
    @ObservedObject public var loadouts: LoadoutStore
    @ObservedObject public var cameraManager: CameraManager
    @State private var slotPendingLocalClear: Int?
    @State private var slotToEdit: Loadout?
    @State private var selectedDialSlot: Int = 1
    @State private var refreshMessage: String?
    @State private var showOverwriteDrafts = false

    private let columns = [
        GridItem(.adaptive(minimum: 270, maximum: 360), spacing: 14)
    ]

    public init(loadouts: LoadoutStore, cameraManager: CameraManager) {
        self.loadouts = loadouts
        self.cameraManager = cameraManager
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header Panel
                headerPanel

                // Interactive Rotary Dial Strip
                rotaryDialStrip

                // Loadout Grid (C1 to C7)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(1...7, id: \.self) { slot in
                        let loadout = loadouts.loadout(for: slot)
                        LoadoutCard(
                            loadout: loadout,
                            slot: slot,
                            isSelected: selectedDialSlot == slot,
                            isDirty: loadouts.isDirty(slot),
                            isCameraConnected: cameraManager.status == .connected,
                            isCameraSlotEmpty: loadouts.isCameraSlotEmpty(slot),
                            isWriting: cameraManager.operation == .writingSlot(slot),
                            onSelect: { selectedDialSlot = slot },
                            onClear: { slotPendingLocalClear = slot },
                            onEdit: { slotToEdit = loadout },
                            onWriteToCamera: { writeSlot(slot) },
                            onDropRecipe: { recipe in
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                    loadouts.applyRecipe(recipe, to: slot)
                                    selectedDialSlot = slot
                                }
                            }
                        )
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.8), value: loadouts.loadoutCountWithSettings())
            }
            .padding(16)
        }
        .navigationTitle("C1–C7 Preset Dial Matrix")
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
        .sheet(item: $slotToEdit) { loadout in
            SlotEditorSheet(loadout: loadout, store: loadouts, cameraManager: cameraManager, isPresented: Binding(
                get: { slotToEdit != nil },
                set: { if !$0 { slotToEdit = nil } }
            ))
        }
        .confirmationDialog("Replace local drafts with camera data?", isPresented: $showOverwriteDrafts) {
            Button("Replace Local Drafts", role: .destructive) { refreshCameraSlots(overwriteDrafts: true) }
            Button("Keep Local Drafts", role: .cancel) { refreshCameraSlots(overwriteDrafts: false) }
        } message: {
            Text("Refreshing reads C1–C7 again. Keeping drafts skips any slot edited locally until you write it to camera.")
        }
    }

    private var headerPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
        SectionHeader(
            title: "Custom Dial Bank (C1–C7)",
            subtitle: "Map your favorite recipes to physical camera dial positions C1–C7. Sync directly over USB-C.",
            icon: "dial.low.fill",
            trailingValue: "\(loadouts.loadoutCountWithSettings()) / 7",
            trailingLabel: "SLOTS ARMED",
            accentColor: Theme.fujiAmber
        )
        HStack {
            Text("Selected: C\(selectedDialSlot). Local drafts are not camera-synced until a verified write succeeds. Clearing a draft never clears the camera slot.")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Button("Refresh Camera Slots") {
                if loadouts.dirtySlots.isEmpty { refreshCameraSlots(overwriteDrafts: false) }
                else { showOverwriteDrafts = true }
            }
            .disabled(cameraManager.status != .connected || cameraManager.operation == .readingSlots)
            if cameraManager.operation == .readingSlots { ProgressView().controlSize(.small) }
        }
        if let refreshMessage {
            Text(refreshMessage).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        }
    }

    private func refreshCameraSlots(overwriteDrafts: Bool) {
        Task {
            let result = await cameraManager.refreshCameraSlots(into: loadouts, overwriteDirtyDrafts: overwriteDrafts)
            refreshMessage = result.isComplete
                ? "Read all 7 camera slots."
                : "Read \(result.presets.count)/7 slots. Failed: \(result.failures.map { "C\($0.slot)" }.joined(separator: ", "))."
        }
    }

    private func writeSlot(_ slot: Int) {
        guard cameraManager.status == .connected, let loadout = loadouts.loadout(for: slot) else { return }
        Task {
            do {
                let result = try await cameraManager.writeLoadout(loadout, to: slot)
                if let observed = result.observedSnapshot, observed.slot == slot {
                    loadouts.syncFromCameraPresetData([observed], overwriteDirtyDrafts: true)
                    loadouts.markCameraWriteVerified(slot: slot)
                }
                refreshMessage = "✓ Verified C\(slot) on camera."
            } catch {
                refreshMessage = "Write failed for C\(slot): \(error.localizedDescription)"
            }
        }
    }

    private var rotaryDialStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("QUICK DIAL:")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.leading, 4)

                ForEach(1...7, id: \.self) { slot in
                    let loadout = loadouts.loadout(for: slot)
                    RotaryDialStripItem(
                        slot: slot,
                        loadout: loadout,
                        isSelected: selectedDialSlot == slot,
                        onSelect: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                                selectedDialSlot = slot
                            }
                        },
                        onDropRecipe: { recipe in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                loadouts.applyRecipe(recipe, to: slot)
                                selectedDialSlot = slot
                            }
                        }
                    )
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Rotary Dial Strip Item (Drag & Drop Target)

private struct RotaryDialStripItem: View {
    let slot: Int
    let loadout: Loadout?
    let isSelected: Bool
    let onSelect: () -> Void
    let onDropRecipe: (Recipe) -> Void

    @State private var isDropTargeted = false

    private var isFilled: Bool { loadout?.hasAnySettings ?? false }
    private var accent: Color { slotAccent(slot) }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 5) {
                Circle()
                    .fill(isDropTargeted ? Theme.fujiAmber : (isFilled ? accent : Color.white.opacity(0.15)))
                    .frame(width: 7, height: 7)
                    .shadow(color: (isDropTargeted || isFilled) ? (isDropTargeted ? Theme.fujiAmber : accent).opacity(0.8) : Color.clear, radius: 3)
                    .scaleEffect(isSelected || isDropTargeted ? 1.25 : 1.0)

                Text("C\(slot)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle((isSelected || isDropTargeted) ? Color.black : (isFilled ? Color.white : Theme.textTertiary))

                if let name = loadout?.recipeName, !name.isEmpty {
                    Text(name)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle((isSelected || isDropTargeted) ? Color.black.opacity(0.8) : Theme.textSecondary)
                        .lineLimit(1)
                        .frame(maxWidth: 80)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(isDropTargeted ? Theme.fujiAmber : (isSelected ? Theme.fujiAmber : (isFilled ? Color.white.opacity(0.08) : Color.white.opacity(0.03))))
            )
            .overlay(
                Capsule()
                    .stroke(isDropTargeted ? Color.white : (isSelected ? Theme.fujiAmber : (isFilled ? accent.opacity(0.4) : Theme.specularBorder)), lineWidth: isDropTargeted ? 1.8 : 0.8)
            )
            .shadow(color: (isSelected || isDropTargeted) ? Theme.fujiAmber.opacity(0.55) : Color.clear, radius: isDropTargeted ? 10 : 8, y: 2)
            .scaleEffect(isDropTargeted ? 1.08 : (isSelected ? 1.03 : 1.0))
        }
        .buttonStyle(.plain)
        .dropDestination(for: Recipe.self) { items, _ in
            guard let recipe = items.first else { return false }
            onDropRecipe(recipe)
            return true
        } isTargeted: { targeted in
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isDropTargeted = targeted
            }
        }
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isSelected)
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isFilled)
        .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isDropTargeted)
        .help(isDropTargeted ? "Drop recipe to apply to C\(slot)" : (loadout?.recipeName ?? "C\(slot)"))
        .accessibilityLabel("Quick dial C\(slot), \(isFilled ? (loadout?.recipeName ?? "configured") : "empty")")
        .accessibilityHint("Selects slot C\(slot), or drop a recipe here to stage it.")
    }
}

// MARK: - Slot Accent Colors

public func slotAccent(_ slot: Int) -> Color {
    switch slot {
    case 1: return Color(red: 0.28, green: 0.65, blue: 0.98) // Reala/Provia Blue
    case 2: return Color(red: 0.98, green: 0.35, blue: 0.45) // Velvia Red
    case 3: return Color(red: 0.48, green: 0.76, blue: 0.65) // Classic Chrome Sage
    case 4: return Color(red: 0.96, green: 0.70, blue: 0.32) // Nostalgic Gold
    case 5: return Color(red: 0.88, green: 0.54, blue: 0.38) // Classic Neg Terracotta
    case 6: return Color(red: 0.24, green: 0.74, blue: 0.70) // Eterna Teal
    case 7: return Color(red: 0.85, green: 0.87, blue: 0.92) // Acros Platinum
    default: return Theme.fujiAmber
    }
}

// MARK: - Loadout Slot Card

public struct LoadoutCard: View {
    public let loadout: Loadout?
    public let slot: Int
    public var isSelected: Bool = false
    public var isDirty: Bool = false
    public var isCameraConnected: Bool = false
    public var isCameraSlotEmpty: Bool = false
    public var isWriting: Bool = false
    public var onSelect: () -> Void = {}
    public var onClear: () -> Void = {}
    public var onEdit: () -> Void = {}
    public var onWriteToCamera: (() -> Void)? = nil
    public var onDropRecipe: ((Recipe) -> Void)? = nil

    @State private var isHovered = false
    @State private var isDropTargeted = false

    private var accent: Color { slotAccent(slot) }
    private var isConfigured: Bool { loadout?.hasAnySettings ?? false }
    private var isCameraVerified: Bool {
        isCameraConnected && loadout?.provenance == .cameraSynced && !isDirty
    }

    public init(
        loadout: Loadout?,
        slot: Int,
        isSelected: Bool = false,
        isDirty: Bool = false,
        isCameraConnected: Bool = false,
        isCameraSlotEmpty: Bool = false,
        isWriting: Bool = false,
        onSelect: @escaping () -> Void = {},
        onClear: @escaping () -> Void = {},
        onEdit: @escaping () -> Void = {},
        onWriteToCamera: (() -> Void)? = nil,
        onDropRecipe: ((Recipe) -> Void)? = nil
    ) {
        self.loadout = loadout
        self.slot = slot
        self.isSelected = isSelected
        self.isDirty = isDirty
        self.isCameraConnected = isCameraConnected
        self.isCameraSlotEmpty = isCameraSlotEmpty
        self.isWriting = isWriting
        self.onSelect = onSelect
        self.onClear = onClear
        self.onEdit = onEdit
        self.onWriteToCamera = onWriteToCamera
        self.onDropRecipe = onDropRecipe
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Slot Indicator & Status Badge
            slotHeader

            Divider()
                .overlay(Theme.specularBorder)
                .padding(.horizontal, 12)

            // Content Body
            VStack(alignment: .leading, spacing: 8) {
                if isConfigured, let loadout {
                    configuredBody(loadout)
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else {
                    emptyBody
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                }

                // Camera vs Staged Comparison Box
                cameraVsStagedComparison

                // Direct Slot Action Bar
                slotActionBar
            }
            .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 185)
        .glassCard(
            padding: 0,
            radius: 14,
            tint: isDropTargeted ? Theme.fujiAmber.opacity(0.14) : (isConfigured ? accent.opacity(0.06) : Theme.glassPanelBg),
            borderColor: isDropTargeted ? Theme.fujiAmber : (isSelected ? Theme.fujiAmber : (isConfigured ? accent.opacity(0.4) : nil))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isDropTargeted ? Theme.fujiAmber : (isSelected ? Theme.fujiAmber : Color.clear), lineWidth: isDropTargeted ? 2.0 : 1.5)
        )
        .overlay {
            if isDropTargeted {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Theme.deepCharcoal.opacity(0.85))
                        .background(.ultraThinMaterial)

                    VStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Theme.fujiAmber.opacity(0.2))
                                .frame(width: 44, height: 44)

                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(Theme.fujiAmber)
                                .symbolEffect(.bounce, value: isDropTargeted)
                        }

                        VStack(spacing: 2) {
                            Text("STAGE TO C\(slot)")
                                .font(.system(size: 11, weight: .black, design: .monospaced))
                                .foregroundStyle(Theme.fujiAmber)

                            Text("Release to apply recipe")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            LinearGradient(
                                colors: [Theme.fujiAmber, accent],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 2
                        )
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .scaleEffect(isDropTargeted ? 1.025 : (isHovered ? 1.012 : (isSelected ? 1.008 : 1.0)))
        .shadow(
            color: isDropTargeted
                ? Theme.fujiAmber.opacity(0.55)
                : (isHovered ? accent.opacity(0.25) : (isSelected ? Theme.fujiAmber.opacity(0.2) : Color.clear)),
            radius: isDropTargeted ? 20 : 14,
            y: isDropTargeted ? 2 : 5
        )
        .animation(.spring(response: 0.26, dampingFraction: 0.76), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isConfigured)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isDropTargeted)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onSelect)
        .dropDestination(for: Recipe.self) { items, _ in
            guard let recipe = items.first else { return false }
            if let onDropRecipe {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    onDropRecipe(recipe)
                }
            }
            return true
        } isTargeted: { targeted in
            withAnimation(.spring(response: 0.24, dampingFraction: 0.78)) {
                isDropTargeted = targeted
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Custom slot C\(slot), \(isConfigured ? "configured" : "empty"), \(syncStateLabel)")
        .accessibilityHint(isSelected ? "Selected. Use the edit button to change this local draft, or drop a recipe here to stage it." : "Selects this custom slot, or drop a recipe here to stage it.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Select slot C\(slot)") { onSelect() }
    }

    private var slotHeader: some View {
        HStack(spacing: 8) {
            // Tactile Dial Badge
            HStack(spacing: 5) {
                Circle()
                    .fill(accent)
                    .frame(width: 7, height: 7)
                    .shadow(color: isConfigured ? accent.opacity(0.8) : Color.clear, radius: 4)

                Text("DIAL C\(slot)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(isConfigured ? accent : Theme.textTertiary)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isConfigured ? accent.opacity(0.15) : Color.white.opacity(0.04))
            )

            Spacer()

            // Status Badge
            statusBadge
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private var statusBadge: some View {
        Group {
            if !isConfigured {
                HStack(spacing: 3) {
                    Circle()
                        .fill(Theme.textTertiary.opacity(0.4))
                        .frame(width: 5, height: 5)
                    Text("EMPTY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.04), in: Capsule())
            } else if isCameraVerified {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("CAMERA-VERIFIED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Theme.emeraldGreen)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.emeraldGreen.opacity(0.14), in: Capsule())
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 8, weight: .bold))
                    Text("STAGED · READY TO SYNC")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Theme.fujiAmber)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.fujiAmber.opacity(0.14), in: Capsule())
            }
        }
    }

    private var cameraVsStagedComparison: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Local Staged Row
            HStack(spacing: 5) {
                Image(systemName: "square.and.arrow.down.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(isConfigured ? Theme.fujiAmber : Theme.textTertiary)
                Text("STAGED:")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Text(isConfigured ? (loadout?.recipeName ?? loadout?.name ?? "C\(slot)") : "Unassigned")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isConfigured ? Color.white : Theme.textTertiary)
                    .lineLimit(1)
            }

            // Physical Camera Row
            HStack(spacing: 5) {
                Image(systemName: isCameraConnected ? "camera.fill" : "camera")
                    .font(.system(size: 8))
                    .foregroundStyle(isCameraVerified ? Theme.emeraldGreen : Theme.textTertiary)
                Text("CAMERA:")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Text(cameraStateDescription)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(isCameraVerified ? Theme.emeraldGreen : Theme.textSecondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.8)
                )
        )
    }

    private var cameraStateDescription: String {
        guard isCameraConnected else {
            return "Camera offline"
        }
        if isCameraSlotEmpty {
            return "Empty on camera"
        }
        if isCameraVerified {
            return "Verified: \(loadout?.name ?? "C\(slot)")"
        }
        if isDirty {
            return "Unsynced local edits"
        }
        return "Not read"
    }

    private var slotActionBar: some View {
        HStack(spacing: 6) {
            // Write C{x} to Camera button
            if let onWriteToCamera {
                Button {
                    onWriteToCamera()
                } label: {
                    HStack(spacing: 3) {
                        if isWriting {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 8, weight: .bold))
                        }
                        Text("Write C\(slot)")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(canWriteToCamera ? Theme.emeraldGreen.opacity(0.2) : Color.white.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(canWriteToCamera ? Theme.emeraldGreen.opacity(0.55) : Color.white.opacity(0.08), lineWidth: 0.8)
                    )
                    .foregroundStyle(canWriteToCamera ? Theme.emeraldGreen : Theme.textTertiary)
                }
                .buttonStyle(.plain)
                .disabled(!canWriteToCamera || isWriting)
                .help("Write C\(slot) directly to camera")
            }

            // Edit Settings button
            Button(action: onEdit) {
                HStack(spacing: 3) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 8, weight: .semibold))
                    Text("Edit")
                        .font(.system(size: 9, weight: .semibold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.8)
                )
                .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Edit parameters for C\(slot)")

            // Clear button
            if isConfigured {
                Button(action: onClear) {
                    Image(systemName: "trash")
                        .font(.system(size: 9))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.04))
                        )
                }
                .buttonStyle(.plain)
                .help("Clear local draft for C\(slot)")
                .accessibilityIdentifier("clear-local-draft-slot-\(slot)")
            }
        }
        .padding(.top, 2)
    }

    private var canWriteToCamera: Bool {
        isCameraConnected && isConfigured
    }

    private func configuredBody(_ loadout: Loadout) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Recipe Title
            Text(loadout.recipeName ?? loadout.name)
                .font(.system(size: 13, weight: .bold))
                .glassPrimary()
                .lineLimit(1)

            // Film Sim Badge + Dynamic Range + White Balance
            HStack(spacing: 4) {
                if let fs = loadout.filmSim {
                    FilmSimBadge(name: fs.displayName, isCompact: true)
                }

                if let dr = loadout.dr {
                    Text("DR\(dr.rawValue)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.emeraldGreen)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Theme.emeraldGreen.opacity(0.15))
                        .clipShape(Capsule())
                }

                if let wb = loadout.wb {
                    Text(wb == .colorTemperature && loadout.colorTempK != nil ? "\(loadout.colorTempK!)K" : wb.displayName)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.cyanAccent)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Theme.cyanAccent.opacity(0.12))
                        .clipShape(Capsule())
                        .lineLimit(1)
                }
            }

            // Tone Radar
            ToneCurveRadar(
                highlight: loadout.highlight,
                shadow: loadout.shadow,
                color: loadout.color,
                sharpness: loadout.sharpness,
                accentColor: accent
            )
        }
    }

    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "dial.low")
                    .font(.body)
                    .foregroundStyle(Theme.textTertiary)
                Text("Slot Unassigned")
                    .font(.caption.weight(.semibold))
                    .glassSecondary()
            }
            Text("Drag a recipe here or click Edit to stage a formula.")
                .font(.caption2)
                .glassTertiary()
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }

    private var syncStateLabel: String {
        if isDirty { return "LOCAL DRAFT · NOT WRITTEN" }
        if loadout?.provenance == .cameraSynced { return "CAMERA-VERIFIED" }
        return "LOCAL ONLY"
    }
}

// MARK: - In-Place Slot Parameter Editor Sheet

public struct SlotEditorSheet: View {
    @State public var loadout: Loadout
    @ObservedObject public var store: LoadoutStore
    @ObservedObject public var cameraManager: CameraManager
    @Binding public var isPresented: Bool

    @State private var selectedFilmSim: FilmSimulation?
    @State private var selectedDR: DynamicRange?
    @State private var selectedGrain: GrainEffect?
    @State private var selectedWB: WhiteBalanceMode?
    @State private var colorTemperature: Int
    @State private var draftName: String
    @State private var writeMessage: String?
    @State private var highlight: Int32 = 0
    @State private var shadow: Int32 = 0
    @State private var color: Int32 = 0
    @State private var sharpness: Int32 = 0
    @State private var includesHighlight: Bool
    @State private var includesShadow: Bool
    @State private var includesColor: Bool
    @State private var includesSharpness: Bool
    @FocusState private var isNameFocused: Bool

    public init(loadout: Loadout, store: LoadoutStore, cameraManager: CameraManager, isPresented: Binding<Bool>) {
        self._loadout = State(initialValue: loadout)
        self.store = store
        self.cameraManager = cameraManager
        self._isPresented = isPresented
        self._selectedFilmSim = State(initialValue: loadout.filmSim)
        self._selectedDR = State(initialValue: loadout.dr)
        self._selectedGrain = State(initialValue: loadout.grain)
        self._selectedWB = State(initialValue: loadout.wb)
        self._colorTemperature = State(initialValue: Int(loadout.colorTempK ?? 5600))
        self._draftName = State(initialValue: loadout.name)
        self._highlight = State(initialValue: loadout.highlight ?? 0)
        self._shadow = State(initialValue: loadout.shadow ?? 0)
        self._color = State(initialValue: loadout.color ?? 0)
        self._sharpness = State(initialValue: loadout.sharpness ?? 0)
        self._includesHighlight = State(initialValue: loadout.highlight != nil)
        self._includesShadow = State(initialValue: loadout.shadow != nil)
        self._includesColor = State(initialValue: loadout.color != nil)
        self._includesSharpness = State(initialValue: loadout.sharpness != nil)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.obsidianBlack.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(
                            title: "Edit Custom Slot C\(loadout.slot)",
                            subtitle: "Adjust film simulation curve and color shifts for this dial position.",
                            icon: "slider.horizontal.3",
                            accentColor: slotAccent(loadout.slot)
                        )
                        TextField("Slot name", text: $draftName)
                            .textFieldStyle(.roundedBorder)
                            .focused($isNameFocused)

                        // Film Simulation Selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FILM SIMULATION")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)

                            Picker("Film Sim", selection: $selectedFilmSim) {
                                Text("None").tag(Optional<FilmSimulation>.none)
                                ForEach(FilmSimulation.allCases, id: \.self) { sim in
                                    Text(sim.displayName).tag(Optional(sim))
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(6)
                            .glassCard(padding: 4, radius: 10)
                        }

                        pickerSection("DYNAMIC RANGE", selection: $selectedDR, values: [.auto, .dr100, .dr200, .dr400]) { $0.displayName }
                        pickerSection("GRAIN EFFECT", selection: $selectedGrain, values: [.off, .weakSmall, .strongSmall, .weakLarge, .strongLarge]) { $0.displayName }
                        pickerSection("WHITE BALANCE", selection: $selectedWB, values: [.asShot, .auto, .daylight, .cloudy, .tungsten, .fluorescent1, .fluorescent2, .fluorescent3, .shade, .colorTemperature, .ambiencePriority, .underwater]) { $0.displayName }

                        // Kelvin Temperature Slider & Stepper (when White Balance is Color Temperature)
                        if selectedWB == .colorTemperature {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("COLOR TEMPERATURE (KELVIN)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.textTertiary)
                                    Spacer()
                                    Text("\(colorTemperature) K")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.fujiAmber)
                                }

                                Slider(
                                    value: Binding(
                                        get: { Double(colorTemperature) },
                                        set: { colorTemperature = Int((($0 / 100).rounded()) * 100) }
                                    ),
                                    in: 2500...10000,
                                    step: 100
                                )
                                .tint(Theme.fujiAmber)

                                HStack {
                                    Text("2500K (Warm Incandescent)")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Theme.textTertiary)
                                    Spacer()
                                    Stepper("", value: $colorTemperature, in: 2500...10000, step: 100)
                                        .labelsHidden()
                                    Spacer()
                                    Text("10000K (Cool Shade)")
                                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                                        .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            .padding(10)
                            .glassCard(padding: 0, radius: 10)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        // Tone Offset Sliders
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TONE & DETAIL OFFSETS")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)

                            optionalStepperRow(title: "Highlight Tone", included: $includesHighlight, value: $highlight)
                            optionalStepperRow(title: "Shadow Tone", included: $includesShadow, value: $shadow)
                            optionalStepperRow(title: "Color Saturation", included: $includesColor, value: $color)
                            optionalStepperRow(title: "Sharpness", included: $includesSharpness, value: $sharpness)
                        }
                        .glassCard()
                        if let writeMessage {
                            Text(writeMessage).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Button("Write C\(loadout.slot) to Camera") { writeToCamera() }
                            .buttonStyle(GlassProminentButtonStyle(color: Theme.emeraldGreen, height: 34))
                            .disabled(cameraManager.status != .connected || cameraManager.operation == .writingSlot(loadout.slot))
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Slot C\(loadout.slot) Configuration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Local Draft") {
                        saveChanges()
                        isPresented = false
                    }
                    .buttonStyle(GlassProminentButtonStyle(color: Theme.fujiAmber, height: 30))
                }
            }
        }
        .frame(minWidth: 440, minHeight: 400)
        .defaultFocus($isNameFocused, true)
    }

    private func stepperRow(title: String, value: Binding<Int32>) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .glassPrimary()
            Spacer()
            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        if value.wrappedValue > -4 { value.wrappedValue -= 1 }
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decrease \(title)")
                .accessibilityHint("Decreases \(title) by one.")

                Text(value.wrappedValue.formatValue)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(value.wrappedValue == 0 ? Theme.textTertiary : (value.wrappedValue > 0 ? Theme.fujiAmber : Theme.cyanAccent))
                    .frame(width: 36)
                    .contentTransition(.numericText())

                Button {
                    withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                        if value.wrappedValue < 4 { value.wrappedValue += 1 }
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase \(title)")
                .accessibilityHint("Increases \(title) by one.")
            }
        }
    }

    private func optionalStepperRow(title: String, included: Binding<Bool>, value: Binding<Int32>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Include \(title)", isOn: included)
                .font(.caption)
            stepperRow(title: title, value: value)
                .disabled(!included.wrappedValue)
                .opacity(included.wrappedValue ? 1 : 0.45)
        }
    }

    private func saveChanges() {
        loadout.name = draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "C\(loadout.slot)" : draftName
        loadout.filmSim = selectedFilmSim
        loadout.dr = selectedDR
        loadout.grain = selectedGrain
        loadout.wb = selectedWB
        loadout.colorTempK = selectedWB == .colorTemperature ? UInt32(colorTemperature) : nil
        loadout.highlight = includesHighlight ? highlight : nil
        loadout.shadow = includesShadow ? shadow : nil
        loadout.color = includesColor ? color : nil
        loadout.sharpness = includesSharpness ? sharpness : nil
        store.saveLocalDraft(loadout)
    }

    private func writeToCamera() {
        saveChanges()
        Task {
            do {
                let result = try await cameraManager.writeLoadout(loadout, to: loadout.slot)
                guard let observedSnapshot = result.observedSnapshot,
                      observedSnapshot.slot == loadout.slot else {
                    writeMessage = "C\(loadout.slot) was sent to the camera, but the post-write camera readback was unavailable. This local draft remains unverified."
                    return
                }
                store.syncFromCameraPresetData(
                    [observedSnapshot],
                    overwriteDirtyDrafts: true
                )
                store.markCameraWriteVerified(slot: loadout.slot)
                if let observedLoadout = store.loadout(for: loadout.slot) {
                    loadout = observedLoadout
                }
                let action = result.createdFromEmpty ? "Created and verified" : "Updated and verified"
                writeMessage = result.warnings.isEmpty
                    ? "\(action) camera slot C\(loadout.slot)."
                    : "\(action) C\(loadout.slot) with warnings: \(result.warnings.joined(separator: ", "))"
            } catch let recoveryError as PTPPresetSlotWriteRecoveryError {
                writeMessage = cSlotWriteFailureMessage(recoveryError)
            } catch {
                writeMessage = "Camera did not verify the write: \(error.localizedDescription)"
            }
        }
    }

    private func cSlotWriteFailureMessage(_ error: PTPPresetSlotWriteRecoveryError) -> String {
        let failure: String
        switch error.failurePhase {
        case .write:
            failure = "C\(error.slot) write failed before post-write verification"
        case .postWriteVerification:
            failure = "C\(error.slot) write completed, but post-write verification failed"
        }
        let recovery: String
        switch error.rollback {
        case .restored:
            recovery = "Previous camera settings were restored."
        case .notAttemptedEmptySentinel:
            recovery = "The camera slot was previously empty, so there were no settings to restore."
        case .failed(let message):
            recovery = "Recovery could not restore previous camera settings: \(message)"
        case .notNeeded:
            recovery = "No recovery was required."
        }
        return "\(failure): \(error.writeErrorDescription). \(recovery)"
    }

    private func pickerSection<T: Hashable>(
        _ title: String,
        selection: Binding<T?>,
        values: [T],
        label: @escaping (T) -> String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundStyle(Theme.textTertiary)
            Picker(title, selection: selection) {
                Text("None").tag(Optional<T>.none)
                ForEach(values, id: \.self) { value in Text(label(value)).tag(Optional(value)) }
            }
            .pickerStyle(.menu)
        }
    }
}
