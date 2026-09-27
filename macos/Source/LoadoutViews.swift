import SwiftUI
import FujiRecipesCore

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
    public var isCameraBusy: Bool = false
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
        isCameraBusy: Bool = false,
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
        self.isCameraBusy = isCameraBusy
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

                // Camera Sync Status Indicator
                cameraSyncStatusRow

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
        .accessibilityHint(isSelected ? "Selected. Press ⌥\(slot) or use the edit button to change this local draft, or drop a recipe here to stage it." : "Selects custom slot C\(slot) (⌥\(slot)), or drop a recipe here to stage it.")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Select slot C\(slot)") { onSelect() }
        .help("Custom dial slot C\(slot) (⌥\(slot))")
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
                    Text("CAMERA-SYNCED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Theme.emeraldGreen)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Theme.emeraldGreen.opacity(0.14), in: Capsule())
            } else if loadout?.provenance == .cameraSynced && !isDirty {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.seal")
                        .font(.system(size: 8, weight: .bold))
                    Text("LAST SYNCED")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06), in: Capsule())
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

    private var cameraSyncStatusRow: some View {
        HStack(spacing: 5) {
            Image(systemName: isCameraConnected ? (isCameraVerified ? "checkmark.circle.fill" : "arrow.triangle.2.circlepath") : "cable.connector.slash")
                .font(.system(size: 8))
                .foregroundStyle(isCameraConnected ? (isCameraVerified ? Theme.emeraldGreen : Theme.fujiAmber) : Theme.textTertiary)

            Text(cameraStateDescription)
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundStyle(isCameraVerified ? Theme.emeraldGreen : Theme.textSecondary)
                .lineLimit(1)

            Spacer()

            if isDirty && isCameraConnected {
                Text("UNSAVED DRAFT")
                    .font(.system(size: 7, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.fujiAmber)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.fujiAmber.opacity(0.18))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.black.opacity(0.25))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.white.opacity(0.05), lineWidth: 0.6)
                )
        )
    }

    private var cameraStateDescription: String {
        guard isCameraConnected else {
            if loadout?.provenance == .cameraSynced && !isDirty {
                return "Last synced • Camera offline"
            }
            return isConfigured ? "Draft staged • Connect USB to write" : "Camera offline"
        }
        if isCameraSlotEmpty {
            return "Camera slot is currently empty"
        }
        if isCameraVerified {
            return "Camera Slot: \(loadout?.contentName ?? "C\(slot)")"
        }
        if isDirty {
            return "Staged draft differs from camera"
        }
        return "Camera slot read"
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
        isCameraConnected && isConfigured && !isCameraBusy
    }

    private func configuredBody(_ loadout: Loadout) -> some View {
        let title = loadout.contentName ?? loadout.name
        return VStack(alignment: .leading, spacing: 6) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .glassPrimary()
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 18, alignment: .leading)

                if let recipeName = loadout.recipeName, !recipeName.isEmpty, recipeName != title {
                    Text("from recipe \(recipeName)")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .frame(height: 32, alignment: .topLeading)

            // Film Sim Badge + Dynamic Range + White Balance
            HStack(spacing: 4) {
                if let fs = loadout.filmSim {
                    FilmSimBadge(name: fs.displayName, isCompact: true)
                }

                if let dr = loadout.dr {
                    Text(dr.badgeLabel)
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
            .frame(height: 20, alignment: .leading)

            // Tone Radar
            ToneCurveRadar(tones: loadout.toneTenths, accentColor: accent)
            .frame(height: 36, alignment: .leading)
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
        .frame(height: 100, alignment: .leading)
    }

    private var syncStateLabel: String {
        if isDirty { return "LOCAL DRAFT · NOT WRITTEN" }
        if loadout?.provenance == .cameraSynced { return "CAMERA-VERIFIED" }
        return "LOCAL ONLY"
    }
}

// MARK: - In-Place Slot Parameter Editor Sheet

public struct SlotEditorSheet: View {
    let slot: Int
    @ObservedObject public var store: LoadoutStore
    @ObservedObject public var cameraManager: CameraManager
    @Binding public var isPresented: Bool

    @State private var session: SlotEditorSession
    @State private var pendingAction: (() -> Void)?
    @State private var writeMessage: String?
    @FocusState private var isNameFocused: Bool

    public init(loadout: Loadout, store: LoadoutStore, cameraManager: CameraManager, isPresented: Binding<Bool>) {
        self.slot = loadout.slot
        self.store = store
        self.cameraManager = cameraManager
        self._isPresented = isPresented
        self._session = State(initialValue: SlotEditorSession(loadout))
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Theme.obsidianBlack.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        SectionHeader(
                            title: "Edit Custom Slot C\(slot)",
                            subtitle: "Adjust film simulation curve and color shifts for this dial position.",
                            icon: "slider.horizontal.3",
                            accentColor: slotAccent(slot)
                        )
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Slot name", text: $session.form.name)
                                .textFieldStyle(.roundedBorder)
                                .focused($isNameFocused)
                            cameraLabelPreview
                        }

                        // Film Simulation Selector
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FILM SIMULATION")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)

                            Picker("Film Sim", selection: $session.form.filmSim) {
                                Text("None").tag(Optional<FilmSimulation>.none)
                                ForEach(FilmSimulation.allCases, id: \.self) { sim in
                                    Text(sim.displayName).tag(Optional(sim))
                                }
                            }
                            .pickerStyle(.menu)
                            .padding(6)
                            .glassCard(padding: 4, radius: 10)
                        }

                        pickerSection("DYNAMIC RANGE", selection: $session.form.dynamicRange, values: [.auto, .dr100, .dr200, .dr400]) { $0.displayName }
                        pickerSection("GRAIN EFFECT", selection: $session.form.grain, values: [.off, .weakSmall, .strongSmall, .weakLarge, .strongLarge]) { $0.displayName }
                        pickerSection("WHITE BALANCE", selection: $session.form.whiteBalance, values: WhiteBalanceMode.cameraModes) { $0.displayName }

                        // Kelvin Temperature Slider & Stepper (when White Balance is Color Temperature)
                        if session.form.whiteBalance == .colorTemperature {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("COLOR TEMPERATURE (KELVIN)")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.textTertiary)
                                    Spacer()
                                    Text("\(session.form.colorTemperature) K")
                                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.fujiAmber)
                                }

                                Slider(
                                    value: Binding(
                                        get: { Double(session.form.colorTemperature) },
                                        set: { session.form.colorTemperature = Int((($0 / 100).rounded()) * 100) }
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
                                    Stepper("", value: $session.form.colorTemperature, in: 2500...10000, step: 100)
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

                            optionalStepperRow(title: "Highlight Tone", included: $session.form.includesHighlight, tenths: $session.form.highlight, range: CSlotPresetEncoder.highlightShadowRange, step: 5)
                            optionalStepperRow(title: "Shadow Tone", included: $session.form.includesShadow, tenths: $session.form.shadow, range: CSlotPresetEncoder.highlightShadowRange, step: 5)
                            optionalStepperRow(title: "Color Saturation", included: $session.form.includesColor, tenths: $session.form.color, range: CSlotPresetEncoder.colorSharpnessRange, step: 10)
                            optionalStepperRow(title: "Sharpness", included: $session.form.includesSharpness, tenths: $session.form.sharpness, range: CSlotPresetEncoder.colorSharpnessRange, step: 10)
                        }
                        .glassCard()
                        if let writeMessage {
                            Text(writeMessage).font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Button("Write C\(slot) to Camera") { writeToCamera() }
                            .buttonStyle(GlassProminentButtonStyle(color: Theme.emeraldGreen, height: 34))
                            .disabled(cameraManager.status != .connected || cameraManager.isBusy)
                    }
                    .padding(16)
                }
            }
            .navigationTitle("Slot C\(slot) Configuration")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Local Draft") {
                        commit { isPresented = false }
                    }
                    .buttonStyle(GlassProminentButtonStyle(color: Theme.fujiAmber, height: 30))
                }
            }
        }
        .frame(minWidth: 440, minHeight: 400)
        .defaultFocus($isNameFocused, true)
        .onChange(of: store.loadout(for: slot).map(SlotEditorForm.init)) { _, _ in
            if let current = store.loadout(for: slot) {
                session.follow(current)
            }
        }
        .confirmationDialog(
            "C\(slot) changed while you were editing",
            isPresented: Binding(get: { pendingAction != nil }, set: { if !$0 { pendingAction = nil } }),
            titleVisibility: .visible,
            presenting: pendingAction
        ) { action in
            Button("Keep My Edits") {
                store.save(&session)
                action()
                pendingAction = nil
            }
            Button("Discard My Edits", role: .destructive) {
                if let current = store.loadout(for: slot) {
                    session.reload(from: current)
                }
                pendingAction = nil
            }
            Button("Cancel", role: .cancel) { pendingAction = nil }
        } message: { _ in
            Text("A camera write or another edit changed C\(slot) after you opened this editor. Keep My Edits stages the values shown here over the new ones. Discard My Edits shows the new values.")
        }
    }

    private var cameraLabelPreview: some View {
        let label = CameraPresetName.label(for: session.form.name, slot: slot)
        let limit = CameraPresetName.maximumCharacterCount
        let showsTypedName = label == session.form.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return HStack {
            Text("Camera will show: \(label)")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer()
            Text("\(label.count)/\(limit)")
                .monospacedDigit()
                .foregroundStyle(showsTypedName ? Theme.textTertiary : Theme.fujiAmber)
        }
        .font(.caption)
        .foregroundStyle(Theme.textTertiary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Camera will show \(label), \(label.count) of \(limit) characters")
    }

    /// `range` is in whole UI steps; `tenths` and `step` are C-slot tenths.
    private func stepperRow(title: String, tenths value: Binding<Int32>, range: ClosedRange<Int32>, step: Int32) -> some View {
        let decrease = {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                if value.wrappedValue - step >= range.lowerBound * 10 { value.wrappedValue -= step }
            }
        }
        let increase = {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) {
                if value.wrappedValue + step <= range.upperBound * 10 { value.wrappedValue += step }
            }
        }
        return HStack {
            Text(title)
                .font(.subheadline)
                .glassPrimary()
            Spacer()
            HStack(spacing: 8) {
                Button(action: decrease) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)

                Text(ToneTenths.text(value.wrappedValue))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(value.wrappedValue == 0 ? Theme.textTertiary : (value.wrappedValue > 0 ? Theme.fujiAmber : Theme.cyanAccent))
                    .frame(width: 36)
                    .contentTransition(.numericText())

                Button(action: increase) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .accessibilityRepresentation {
            Stepper(title, onIncrement: increase, onDecrement: decrease)
                .accessibilityValue(ToneTenths.text(value.wrappedValue))
                .accessibilityHint("Adjusts in steps of \(ToneTenths.text(step).dropFirst()).")
        }
    }

    private func optionalStepperRow(title: String, included: Binding<Bool>, tenths: Binding<Int32>, range: ClosedRange<Int32>, step: Int32) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Include \(title)", isOn: included)
                .font(.caption)
            stepperRow(title: title, tenths: tenths, range: range, step: step)
                .disabled(!included.wrappedValue)
                .opacity(included.wrappedValue ? 1 : 0.45)
        }
    }

    private func commit(then action: @escaping () -> Void) {
        if let current = store.loadout(for: slot), session.conflicts(with: current) {
            pendingAction = action
            return
        }
        store.save(&session)
        action()
    }

    private func writeToCamera() {
        commit {
            writeMessage = "Writing C\(slot)…"
            Task {
                do {
                    let result = try await cameraManager.writeSlot(slot, from: store)
                    guard result.observedSnapshot?.slot == slot else {
                        writeMessage = "C\(slot) was sent to the camera, but the post-write camera readback was unavailable. This local draft remains unverified."
                        return
                    }
                    writeMessage = result.summary
                } catch let recoveryError as PTPPresetSlotWriteRecoveryError {
                    writeMessage = recoveryError.localizedDescription
                } catch {
                    writeMessage = "Camera did not verify the write: \(error.localizedDescription)"
                }
            }
        }
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
