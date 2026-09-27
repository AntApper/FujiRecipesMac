import SwiftUI
import FujiRecipesCore
import X100VIHelper

// MARK: - 2026 Sleek Sidebar Navigation Shell
//
// Refined macOS sidebar featuring a distinct Library collection, an interactive
// C1–C7 Custom Dial Rack with real-time camera sync provenance, responsive
// hardware telemetry with ViewThatFits adaptive width handling, and film simulation shortcuts.

public struct SidebarView: View {
    @Binding public var selection: AppTab
    @Binding public var selectedDialSlot: Int
    @ObservedObject public var recipeStore: RecipeStore
    @ObservedObject public var cameraManager: CameraManager
    public var onToggleConnection: (() -> Void)? = nil

    @State private var slotToEdit: Loadout? = nil

    public init(
        selection: Binding<AppTab>,
        selectedDialSlot: Binding<Int> = .constant(1),
        recipeStore: RecipeStore,
        cameraManager: CameraManager,
        onToggleConnection: (() -> Void)? = nil
    ) {
        self._selection = selection
        self._selectedDialSlot = selectedDialSlot
        self.recipeStore = recipeStore
        self.cameraManager = cameraManager
        self.onToggleConnection = onToggleConnection
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // 1. LIBRARY Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("LIBRARY")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 10)

                        VStack(spacing: 2) {
                            SidebarLibraryRow(
                                title: "All Recipes",
                                icon: "photo.stack.fill",
                                accentColor: Theme.fujiAmber,
                                isSelected: selection == .recipes && recipeStore.selectedFilterCategory == nil && recipeStore.selectedFilmSimFamily == .all,
                                count: recipeStore.recipes.count
                            ) {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                                    selection = .recipes
                                    recipeStore.selectedFilterCategory = nil
                                    recipeStore.selectedFilmSimFamily = .all
                                }
                            }

                            SidebarLibraryRow(
                                title: "Favorites",
                                icon: "star.fill",
                                accentColor: Theme.fujiAmber,
                                isSelected: selection == .recipes && recipeStore.selectedFilterCategory == .favorites,
                                count: recipeStore.favorites.favoriteIDs.count,
                                onDropRecipe: { recipe in
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        recipeStore.favorites.addFavorite(recipe.id)
                                    }
                                }
                            ) {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                                    selection = .recipes
                                    recipeStore.selectedFilterCategory = .favorites
                                    recipeStore.selectedFilmSimFamily = .all
                                }
                            }

                            SidebarLibraryRow(
                                title: "My Recipes",
                                icon: "folder.badge.gearshape",
                                accentColor: Theme.emeraldGreen,
                                isSelected: selection == .recipes && recipeStore.selectedFilterCategory == .myRecipes,
                                count: recipeStore.customRecipes.recipes.count,
                                onDropRecipe: { recipe in
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                        try? recipeStore.customRecipes.save(recipe.duplicated())
                                    }
                                }
                            ) {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                                    selection = .recipes
                                    recipeStore.selectedFilterCategory = .myRecipes
                                    recipeStore.selectedFilmSimFamily = .all
                                }
                            }
                        }
                    }

                    // 2. CAMERA DIAL PRESETS (C1–C7) Section
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Button {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                                    selection = .camera
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "dial.low.fill")
                                        .font(.system(size: 9, weight: .bold))
                                    Text("CAMERA DIAL PRESETS")
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                }
                                .foregroundStyle(selection == .camera ? Color.white : Theme.textTertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Open Camera & Staging overview")

                            Spacer()

                            let armedCount = recipeStore.loadouts.loadoutCountWithSettings()
                            Text("\(armedCount)/7")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(armedCount > 0 ? Theme.fujiAmber : Theme.textTertiary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(
                                    Capsule()
                                        .fill(armedCount > 0 ? Theme.fujiAmber.opacity(0.18) : Color.white.opacity(0.06))
                                )
                        }
                        .padding(.horizontal, 10)

                        // Interactive C1–C7 Rack
                        VStack(spacing: 3) {
                            ForEach(1...7, id: \.self) { slot in
                                let loadout = recipeStore.loadouts.loadout(for: slot)
                                let isSelected = selection == .camera && selectedDialSlot == slot
                                SidebarDialRackRow(
                                    slot: slot,
                                    loadout: loadout,
                                    isSelected: isSelected,
                                    isDirty: recipeStore.loadouts.isDirty(slot),
                                    isCameraSlotEmpty: recipeStore.loadouts.isCameraSlotEmpty(slot),
                                    isCameraConnected: cameraManager.status == .connected,
                                    onSelect: {
                                        withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                                            selection = .camera
                                            selectedDialSlot = slot
                                        }
                                    },
                                    onDropRecipe: { recipe in
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            recipeStore.loadouts.applyRecipe(recipe, to: slot)
                                            selectedDialSlot = slot
                                        }
                                    },
                                    onInspect: {
                                        withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                                            selection = .camera
                                            selectedDialSlot = slot
                                        }
                                    },
                                    onEdit: {
                                        selectedDialSlot = slot
                                        slotToEdit = loadout ?? Loadout(slot: slot, name: "C\(slot)", filmSim: nil, dr: nil)
                                    },
                                    onClear: {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                            recipeStore.loadouts.clearLoadout(for: slot)
                                        }
                                    }
                                )
                                .accessibilityIdentifier("sidebar-slot-\(slot)")
                            }
                        }
                    }

                    // 3. FILM SIMULATION BASES Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FILM SIMULATION BASES")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 10)

                        VStack(spacing: 2) {
                            simShortcutRow(title: "Classic Chrome", family: .classicChrome)
                            simShortcutRow(title: "Reala Ace", family: .realaAce)
                            simShortcutRow(title: "Classic Neg", family: .classicNeg)
                            simShortcutRow(title: "Velvia", family: .velvia)
                            simShortcutRow(title: "Acros / B&W", family: .acros)
                        }
                    }

                    // 4. UTILITIES Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("UTILITIES")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 10)

                        SidebarRow(
                            tab: .darkroom,
                            isSelected: selection == .darkroom,
                            badge: nil
                        ) {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                                selection = .darkroom
                            }
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }

            Spacer(minLength: 0)

            statusFooter
        }
        .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)
        .background(
            ZStack {
                Theme.deepCharcoal.opacity(0.85)
                Rectangle().fill(.ultraThinMaterial)
            }
        )
        .overlay(
            Rectangle()
                .fill(Theme.specularBorder)
                .frame(width: 0.8)
                .blendMode(.plusLighter),
            alignment: .trailing
        )
        .sheet(item: $slotToEdit) { loadout in
            SlotEditorSheet(
                loadout: loadout,
                store: recipeStore.loadouts,
                cameraManager: cameraManager,
                isPresented: Binding(
                    get: { slotToEdit != nil },
                    set: { if !$0 { slotToEdit = nil } }
                )
            )
        }
    }

    private func simShortcutRow(title: String, family: RecipeStore.FilmSimFamily) -> some View {
        let isSelected = selection == .recipes && recipeStore.selectedFilmSimFamily == family && recipeStore.selectedFilterCategory == nil
        let accent = family == .all ? Theme.fujiAmber : Theme.filmSimColor(for: family.rawValue)
        let count = recipeStore.recipes.filter { family.matches($0.filmSimulation) }.count

        return Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selection = .recipes
                recipeStore.selectedFilterCategory = nil
                recipeStore.selectedFilmSimFamily = family
            }
        } label: {
            HStack(spacing: 8) {
                Circle()
                    .fill(accent)
                    .frame(width: 6, height: 6)
                    .shadow(color: isSelected ? accent.opacity(0.8) : Color.clear, radius: 3)

                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
                    .lineLimit(1)

                Spacer()

                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Theme.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.18) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? accent.opacity(0.4) : Color.clear, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count == 1 ? "1 recipe" : "\(count) recipes")")
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            // Machined camera aperture badge
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.22), Color(white: 0.10)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 30, height: 30)
                    .overlay(Circle().stroke(Theme.specularBorder, lineWidth: 1))

                Circle()
                    .stroke(Theme.fujiRed, lineWidth: 1.5)
                    .frame(width: 12, height: 12)

                Image(systemName: "camera.aperture")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.titaniumMist)
            }
            .shadow(color: Color.black.opacity(0.4), radius: 6, y: 3)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text("FUJIRECIPES")
                        .font(.system(size: 12, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .tracking(0.4)
                        .lineLimit(1)

                    Text("PRO")
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.fujiAmber)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.fujiAmber.opacity(0.18))
                        .clipShape(Capsule())
                }

                Text("X100VI STUDIO")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    private var statusFooter: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                selection = .camera
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                // Wide layout: full horizontal bar
                HStack(spacing: 8) {
                    statusBeacon
                    statusLabels
                    Spacer(minLength: 4)
                    quickConnectButton(fullWidth: false)
                }

                // Compact layout: 2 stacked rows to eliminate any text truncation
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        statusBeacon

                        Text(statusLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)

                        Spacer(minLength: 2)

                        Text(statusCapsuleText)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(cameraManager.status.tint)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(cameraManager.status.tint.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    quickConnectButton(fullWidth: true)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(cameraManager.status.tint.opacity(cameraManager.status == .connected ? 0.35 : 0.08), lineWidth: 0.8)
                    )
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 8)
        .padding(.bottom, 8)
    }

    private var statusBeacon: some View {
        ZStack {
            Circle()
                .fill(cameraManager.status.tint)
                .frame(width: 7, height: 7)

            if cameraManager.status == .connected || cameraManager.status == .connecting {
                Circle()
                    .stroke(cameraManager.status.tint.opacity(0.6), lineWidth: 1.2)
                    .frame(width: 14, height: 14)
                    .scaleEffect(cameraManager.status == .connecting ? 1.4 : 1.1)
                    .opacity(cameraManager.status == .connecting ? 0.4 : 0.8)
                    .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: cameraManager.status)
            }
        }
        .shadow(color: cameraManager.status.tint.opacity(0.8), radius: 3)
    }

    private var statusLabels: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(statusLabel)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            Text(statusSubtitle)
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
    }

    private var statusLabel: String {
        switch cameraManager.status {
        case .connected: return "X100VI Online"
        case .connecting: return "Connecting…"
        case .disconnected: return "X100VI Disconnected"
        case .error: return "Link Offline"
        }
    }

    private var statusSubtitle: String {
        switch cameraManager.status {
        case .connected: return "USB PTP • Verified"
        case .connecting: return cameraManager.operation == .readingSlots ? "Reading C1–C7" : "USB PTP • Linking"
        case .disconnected: return "USB RAW mode"
        case .error: return "Check USB-C cable"
        }
    }

    private var statusCapsuleText: String {
        switch cameraManager.status {
        case .connected: return "ONLINE"
        case .connecting: return "PTP"
        case .disconnected: return "OFFLINE"
        case .error: return "ERR"
        }
    }

    @ViewBuilder
    private func quickConnectButton(fullWidth: Bool) -> some View {
        if let onToggleConnection {
            Button {
                onToggleConnection()
            } label: {
                HStack(spacing: 4) {
                    if cameraManager.status == .connecting {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: cameraManager.status == .connected ? "checkmark.circle.fill" : "cable.connector")
                            .font(.system(size: 8, weight: .bold))
                    }
                    Text(connectButtonLabel)
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(1)
                }
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(
                    Capsule()
                        .fill(cameraManager.status == .connected ? Color.white.opacity(0.08) : Theme.emeraldGreen.opacity(0.18))
                )
                .overlay(
                    Capsule()
                        .stroke(cameraManager.status == .connected ? Color.white.opacity(0.16) : Theme.emeraldGreen.opacity(0.5), lineWidth: 0.8)
                )
                .foregroundStyle(cameraManager.status == .connected ? Theme.textSecondary : Theme.emeraldGreen)
            }
            .buttonStyle(.plain)
            .disabled(cameraManager.status == .connecting || cameraManager.isBusy)
            .help(cameraManager.status == .connected ? "Disconnect Camera" : "1-Click Connect to Fujifilm X100VI")
        }
    }

    private var connectButtonLabel: String {
        switch cameraManager.status {
        case .connecting: return "Connecting"
        case .connected: return "Disconnect"
        case .disconnected: return "Connect"
        case .error: return "Reconnect"
        }
    }
}

// MARK: - Sidebar Library Row

private struct SidebarLibraryRow: View {
    let title: String
    let icon: String
    let accentColor: Color
    let isSelected: Bool
    let count: Int
    var onDropRecipe: ((Recipe) -> Void)? = nil
    let action: () -> Void

    @State private var isHovered = false
    @State private var isDropTargeted = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isDropTargeted ? accentColor : (isSelected ? accentColor : (isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.04))))
                        .frame(width: 24, height: 24)

                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle((isSelected || isDropTargeted) ? (accentColor == Theme.fujiAmber ? Color.black : Color.white) : (isHovered ? Color.white : Theme.textSecondary))
                }

                Text(title)
                    .font(.system(size: 12, weight: (isSelected || isDropTargeted) ? .semibold : .regular))
                    .foregroundStyle((isSelected || isDropTargeted) ? Color.white : Theme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle((isSelected || isDropTargeted) ? Color.black : Theme.fujiAmber)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill((isSelected || isDropTargeted) ? Color.white : Theme.fujiAmber.opacity(0.18))
                    )
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isDropTargeted ? accentColor.opacity(0.2) : (isSelected ? Color.white.opacity(0.12) : (isHovered ? Color.white.opacity(0.05) : Color.clear)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isDropTargeted ? accentColor : (isSelected ? Theme.specularGlowBorder : Color.clear), lineWidth: isDropTargeted ? 1.5 : 0.8)
                    .blendMode(isDropTargeted ? .normal : .plusLighter)
            )
            .scaleEffect(isDropTargeted ? 1.02 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isSelected || isHovered || isDropTargeted)
            .onHover { isHovered = $0 }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count == 1 ? "1 recipe" : "\(count) recipes")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .dropDestination(for: Recipe.self) { items, _ in
            guard let onDropRecipe, let recipe = items.first else { return false }
            onDropRecipe(recipe)
            return true
        } isTargeted: { targeted in
            if onDropRecipe != nil {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isDropTargeted = targeted
                }
            }
        }
    }
}

// MARK: - Sidebar Interactive Dial Rack Row (C1–C7)

public struct SidebarDialRackRow: View {
    public let slot: Int
    public let loadout: Loadout?
    public let isSelected: Bool
    public let isDirty: Bool
    public let isCameraSlotEmpty: Bool
    public let isCameraConnected: Bool
    public let onSelect: () -> Void
    public let onDropRecipe: (Recipe) -> Void
    public let onInspect: () -> Void
    public let onEdit: () -> Void
    public let onClear: () -> Void

    @State private var isHovered = false
    @State private var isDropTargeted = false
    @State private var justDropped = false

    private var accent: Color { slotAccent(slot) }
    private var hasSettings: Bool { loadout?.hasAnySettings ?? false }

    private var isCameraSynced: Bool {
        loadout?.provenance == .cameraSynced && !isDirty
    }

    private var isStagedDraft: Bool {
        hasSettings && !isCameraSynced
    }

    private var assignedRecipeName: String {
        if hasSettings {
            if let recipeName = loadout?.recipeName, !recipeName.isEmpty {
                return recipeName
            }
            if let name = loadout?.name, !name.isEmpty, name != "C\(slot)" {
                return name
            }
            return "Custom Preset"
        }
        return "Empty Slot"
    }

    private var filmSimDisplayName: String? {
        loadout?.filmSim?.displayName
    }

    private var filmSimTint: Color {
        if let sim = loadout?.filmSim {
            return Theme.filmSimColor(for: sim.displayName)
        }
        return Theme.textTertiary
    }

    public var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 8) {
                dialBadge
                recipeDetails
                Spacer(minLength: 4)
                statusIndicator
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(rowBorderColor, lineWidth: isDropTargeted ? 1.5 : (isSelected ? 1.0 : 0.8))
            )
            .shadow(color: isDropTargeted ? Theme.fujiAmber.opacity(0.6) : (isSelected ? accent.opacity(0.2) : Color.clear), radius: isDropTargeted ? 8 : (isSelected ? 4 : 0))
            .scaleEffect(isDropTargeted ? 1.03 : (justDropped ? 1.04 : 1.0))
            .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isHovered || isSelected || isDropTargeted || justDropped)
            .onHover { isHovered = $0 }
        }
        .buttonStyle(.plain)
        .dropDestination(for: Recipe.self) { items, _ in
            guard let recipe = items.first else { return false }
            withAnimation(.spring(response: 0.22, dampingFraction: 0.72)) {
                justDropped = true
            }
            onDropRecipe(recipe)
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                withAnimation(.easeOut(duration: 0.35)) {
                    justDropped = false
                }
            }
            return true
        } isTargeted: { targeted in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                isDropTargeted = targeted
            }
        }
        .contextMenu {
            Button {
                onInspect()
            } label: {
                Label("Inspect in Dial Rack", systemImage: "dial.low.fill")
            }

            Button {
                onEdit()
            } label: {
                Label("Edit Slot C\(slot)…", systemImage: "slider.horizontal.3")
            }

            Divider()

            Button(role: .destructive) {
                onClear()
            } label: {
                Label("Clear Slot C\(slot)", systemImage: "trash")
            }
            .disabled(!hasSettings)
        }
        .help(isDropTargeted ? "Drop to stage recipe into slot C\(slot)" : "\(assignedRecipeName) (C\(slot) · ⌥\(slot))")
        .accessibilityLabel("Dial Slot C\(slot): \(assignedRecipeName)")
        .accessibilityValue(isCameraSynced ? "Camera-Synced" : (isStagedDraft ? "Staged Draft" : "Empty Slot"))
        .accessibilityHint("Click or press ⌥\(slot) to inspect C\(slot) in camera staging, or drop a recipe here to stage it.")
    }

    private var dialBadge: some View {
        let tagForeground: Color = isDropTargeted ? .black : (isSelected ? .black : accent)
        let tagBg: Color = isDropTargeted ? Theme.fujiAmber : (isSelected ? accent : accent.opacity(0.16))
        let tagStroke: Color = isDropTargeted ? .white : (isSelected ? Color.white.opacity(0.4) : accent.opacity(0.35))
        let strokeWidth: CGFloat = isDropTargeted ? 1.5 : 0.8

        return Text("C\(slot)")
            .font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundStyle(tagForeground)
            .frame(width: 25, height: 18)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tagBg))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous).stroke(tagStroke, lineWidth: strokeWidth))
    }

    private var recipeDetails: some View {
        let titleColor: Color = isSelected ? .white : (hasSettings ? Theme.textPrimary : Theme.textTertiary)
        let titleWeight: Font.Weight = isSelected ? .semibold : (hasSettings ? .medium : .regular)

        return VStack(alignment: .leading, spacing: 1) {
            Text(assignedRecipeName)
                .font(.system(size: 11, weight: titleWeight))
                .foregroundStyle(titleColor)
                .lineLimit(1)

            if let filmSimDisplayName {
                HStack(spacing: 3) {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.8) : filmSimTint)
                        .frame(width: 4, height: 4)

                    Text(filmSimDisplayName)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Theme.textSecondary)
                        .lineLimit(1)
                }
            } else if !hasSettings {
                Text("Ready to stage")
                    .font(.system(size: 8, weight: .regular))
                    .foregroundStyle(Theme.textTertiary.opacity(0.6))
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if justDropped {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Theme.emeraldGreen)
                .transition(.scale.combined(with: .opacity))
                .help("Recipe Staged!")
        } else if isCameraSynced {
            Circle()
                .fill(Theme.emeraldGreen)
                .frame(width: 6, height: 6)
                .shadow(color: Theme.emeraldGreen.opacity(0.8), radius: 3)
                .help("Camera-Synced")
        } else if isStagedDraft {
            Circle()
                .fill(Theme.fujiAmber)
                .frame(width: 6, height: 6)
                .shadow(color: Theme.fujiAmber.opacity(0.6), radius: 2)
                .help("Staged Draft (unsynced)")
        } else {
            Circle()
                .fill(Color.white.opacity(0.18))
                .frame(width: 5, height: 5)
                .help("Empty Slot")
        }
    }

    private var rowBackground: Color {
        if justDropped { return Theme.emeraldGreen.opacity(0.2) }
        if isDropTargeted { return Theme.fujiAmber.opacity(0.2) }
        if isSelected { return accent.opacity(0.14) }
        if isHovered { return Color.white.opacity(0.06) }
        return Color.white.opacity(0.02)
    }

    private var rowBorderColor: Color {
        if justDropped { return Theme.emeraldGreen }
        if isDropTargeted { return Theme.fujiAmber }
        if isSelected { return accent.opacity(0.55) }
        if isHovered { return Color.white.opacity(0.12) }
        return Color.white.opacity(0.04)
    }
}

// MARK: - Sidebar Row Item (for Utilities & Tabs)

private struct SidebarRow: View {
    let tab: AppTab
    let isSelected: Bool
    let badge: String?
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(isSelected ? tab.accentColor : (isHovered ? Color.white.opacity(0.1) : Color.white.opacity(0.04)))
                        .frame(width: 26, height: 26)

                    Image(systemName: tab.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSelected ? (tab.accentColor == Theme.fujiAmber ? Color.black : Color.white) : (isHovered ? Color.white : Theme.textSecondary))
                }

                Text(tab.title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : Theme.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if let badge {
                    Text(badge)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(isSelected ? Color.black : Theme.fujiAmber)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(isSelected ? Color.white : Theme.fujiAmber.opacity(0.18))
                        )
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(rowBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(isSelected ? Theme.specularGlowBorder : Color.clear, lineWidth: 0.8)
                    .blendMode(.plusLighter)
            )
            .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isSelected || isHovered)
            .onHover { isHovered = $0 }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint("Opens the \(tab.title) workspace.")
    }

    private var rowBackground: Color {
        if isSelected { return Color.white.opacity(0.12) }
        if isHovered { return Color.white.opacity(0.05) }
        return Color.clear
    }
}

// MARK: - App Tabs

public enum AppTab: String, CaseIterable, Identifiable {
    case recipes
    case camera
    case darkroom

    /// Backward compatibility alias for the unified Camera & Staging tab
    public static var loadouts: AppTab { .camera }

    public init?(rawValue: String) {
        switch rawValue {
        case "recipes": self = .recipes
        case "camera", "loadouts": self = .camera
        case "darkroom": self = .darkroom
        default: return nil
        }
    }

    /// The two primary core workflows of FujiRecipes
    public static var primaryTabs: [AppTab] {
        [.recipes, .camera]
    }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recipes: return "Recipes"
        case .camera: return "Camera & Staging"
        case .darkroom: return "RAF Darkroom"
        }
    }

    public var icon: String {
        switch self {
        case .recipes: return "photo.stack.fill"
        case .camera: return "camera.fill"
        case .darkroom: return "moon.stars.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .recipes: return Theme.fujiAmber
        case .camera: return Theme.emeraldGreen
        case .darkroom: return Theme.cyanAccent
        }
    }
}

extension DynamicRange {
    var badgeLabel: String {
        self == .auto ? "DR Auto" : displayName
    }
}

// MARK: - CameraStatus Formatting

public extension CameraStatus {
    var tint: Color {
        switch self {
        case .disconnected: return Color.white.opacity(0.3)
        case .connecting: return Theme.fujiAmber
        case .connected: return Theme.emeraldGreen
        case .error: return Theme.fujiRed
        }
    }

    var formattedLabel: String {
        switch self {
        case .disconnected: return "Camera Disconnected"
        case .connecting: return "PTP Connecting…"
        case .connected: return "Camera Online"
        case .error: return "Link Offline"
        }
    }

    var detailLabel: String {
        switch self {
        case .disconnected: return "X100VI USB RAW • Not connected"
        case .connecting: return "USB PTP • Connecting"
        case .connected: return "USB PTP • Verified session"
        case .error: return "USB PTP • Connection needs attention"
        }
    }

    var iconName: String {
        switch self {
        case .disconnected: return "cable.connector.slash"
        case .connecting: return "arrow.triangle.2.circlepath.camera"
        case .connected: return "checkmark.shield.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }

    var displayTint: Color {
        switch self {
        case .disconnected: return Theme.textTertiary
        case .connecting: return Theme.fujiAmber
        case .connected: return Theme.emeraldGreen
        case .error: return Theme.fujiRed
        }
    }
}
