import SwiftUI
import FujiRecipesCore

// MARK: - 2026 C1–C7 Custom Dial Matrix View

public struct LoadoutsView: View {
    @ObservedObject public var loadouts: LoadoutStore
    @ObservedObject public var cameraManager: CameraManager
    @State private var slotPendingClear: Int?
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
                            onSelect: { selectedDialSlot = slot },
                            onClear: { slotPendingClear = slot },
                            onEdit: { slotToEdit = loadout }
                        )
                    }
                }
                .animation(.spring(response: 0.32, dampingFraction: 0.8), value: loadouts.loadoutCountWithSettings())
            }
            .padding(16)
        }
        .navigationTitle("C1–C7 Preset Dial Matrix")
        .confirmationDialog(
            "Clear Custom Slot?",
            isPresented: Binding(
                get: { slotPendingClear != nil },
                set: { if !$0 { slotPendingClear = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Clear Slot", role: .destructive) {
                if let slot = slotPendingClear {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                        loadouts.clearLoadout(for: slot)
                    }
                }
                slotPendingClear = nil
            }
            Button("Cancel", role: .cancel) { slotPendingClear = nil }
        } message: {
            if let slot = slotPendingClear {
                Text("This will remove all custom film recipe parameters from C\(slot).")
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
            Text("Selected: C\(selectedDialSlot). Local drafts are not camera-synced until a verified write succeeds.")
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

    private var rotaryDialStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("QUICK DIAL:")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.leading, 4)

                ForEach(1...7, id: \.self) { slot in
                    let loadout = loadouts.loadout(for: slot)
                    let isFilled = loadout?.hasAnySettings ?? false
                    let isSelected = selectedDialSlot == slot
                    let accent = slotAccent(slot)

                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                            selectedDialSlot = slot
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(isFilled ? accent : Color.white.opacity(0.15))
                                .frame(width: 7, height: 7)
                                .shadow(color: isFilled ? accent.opacity(0.8) : Color.clear, radius: 3)
                                .scaleEffect(isSelected ? 1.25 : 1.0)

                            Text("C\(slot)")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(isSelected ? Color.black : (isFilled ? Color.white : Theme.textTertiary))

                            if let name = loadout?.recipeName, !name.isEmpty {
                                Text(name)
                                    .font(.caption2.weight(.medium))
                                    .foregroundStyle(isSelected ? Color.black.opacity(0.8) : Theme.textSecondary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 80)
                                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            }
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(isSelected ? Theme.fujiAmber : (isFilled ? Color.white.opacity(0.08) : Color.white.opacity(0.03)))
                        )
                        .overlay(
                            Capsule()
                                .stroke(isSelected ? Theme.fujiAmber : (isFilled ? accent.opacity(0.4) : Theme.specularBorder), lineWidth: 0.8)
                        )
                        .shadow(color: isSelected ? Theme.fujiAmber.opacity(0.35) : Color.clear, radius: 8, y: 2)
                        .scaleEffect(isSelected ? 1.03 : 1.0)
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isSelected)
                    .animation(.spring(response: 0.26, dampingFraction: 0.78), value: isFilled)
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 2)
        }
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
    public var onSelect: () -> Void = {}
    public var onClear: () -> Void = {}
    public var onEdit: () -> Void = {}

    @State private var isHovered = false

    private var accent: Color { slotAccent(slot) }
    private var isConfigured: Bool { loadout?.hasAnySettings ?? false }

    public init(
        loadout: Loadout?,
        slot: Int,
        isSelected: Bool = false,
        onSelect: @escaping () -> Void = {},
        onClear: @escaping () -> Void = {},
        onEdit: @escaping () -> Void = {}
    ) {
        self.loadout = loadout
        self.slot = slot
        self.isSelected = isSelected
        self.onSelect = onSelect
        self.onClear = onClear
        self.onEdit = onEdit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header: Slot Indicator & Actions
            slotHeader

            Divider()
                .overlay(Theme.specularBorder)
                .padding(.horizontal, 12)

            // Body
            if isConfigured, let loadout {
                configuredBody(loadout)
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            } else {
                emptyBody
                    .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 160)
        .glassCard(
            padding: 0,
            radius: 14,
            tint: isConfigured ? accent.opacity(0.06) : Theme.glassPanelBg,
            borderColor: isSelected ? Theme.fujiAmber : (isConfigured ? accent.opacity(0.4) : nil)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? Theme.fujiAmber : Color.clear, lineWidth: 1.5)
        )
        .scaleEffect(isHovered ? 1.012 : (isSelected ? 1.008 : 1.0))
        .shadow(color: isHovered ? accent.opacity(0.25) : (isSelected ? Theme.fujiAmber.opacity(0.2) : Color.clear), radius: 14, y: 5)
        .animation(.spring(response: 0.26, dampingFraction: 0.76), value: isHovered)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isSelected)
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: isConfigured)
        .onHover { isHovered = $0 }
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Custom slot C\(slot), \(isConfigured ? "configured" : "empty")")
        .accessibilityHint(isSelected ? "Selected. Use the edit button to change this local draft." : "Selects this custom slot.")
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

            if isConfigured {
                HStack(spacing: 5) {
                    Button(action: onEdit) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(5)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help("Edit parameters for C\(slot)")
                    .accessibilityLabel("Edit slot C\(slot)")
                    .accessibilityHint("Opens the editor for this local slot draft.")

                    Button(action: onClear) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(3)
                    }
                    .buttonStyle(.plain)
                    .help("Clear slot C\(slot)")
                    .accessibilityLabel("Clear slot C\(slot)")
                    .accessibilityHint("Removes the local recipe settings from this slot.")
                }
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            } else {
                Text("EMPTY SLOT")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textMuted)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func configuredBody(_ loadout: Loadout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Recipe Title
            Text(loadout.recipeName ?? loadout.name)
                .font(.system(size: 14, weight: .bold))
                .glassPrimary()
                .lineLimit(1)

            // Film Sim Badge + Dynamic Range
            HStack(spacing: 5) {
                if let fs = loadout.filmSim {
                    FilmSimBadge(name: fs.displayName, isCompact: true)
                }

                if let dr = loadout.dr {
                    Text("DR\(dr.rawValue)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(Theme.emeraldGreen)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.emeraldGreen.opacity(0.15))
                        .clipShape(Capsule())
                }

                if let wb = loadout.wb {
                    Text(wb.displayName)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(Theme.cyanAccent)
                        .padding(.horizontal, 5)
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

            Spacer(minLength: 2)
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var emptyBody: some View {
        VStack(alignment: .leading, spacing: 4) {
            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "dial.low")
                    .font(.body)
                    .foregroundStyle(Theme.textTertiary)
                Text("Slot Unassigned")
                    .font(.caption.weight(.semibold))
                    .glassSecondary()
            }
            Text("Choose any recipe from the Recipes tab and click “Send to Dial”.")
                .font(.caption2)
                .glassTertiary()
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
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
                store.markCameraWriteVerified(slot: loadout.slot)
                writeMessage = result.warnings.isEmpty
                    ? "Verified write to C\(loadout.slot)."
                    : "Verified C\(loadout.slot) with warnings: \(result.warnings.joined(separator: ", "))"
            } catch {
                writeMessage = "Camera did not verify the write: \(error.localizedDescription)"
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
