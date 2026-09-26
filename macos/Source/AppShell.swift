import SwiftUI
import FujiRecipesCore
import X100VIHelper

// MARK: - 2026 Sleek Sidebar Navigation Shell
//
// Designed with ultra-thin satin materials, responsive hover micro-interactions,
// hardware link telemetry indicator, and instant filter presets.

public struct SidebarView: View {
    @Binding public var selection: AppTab
    @ObservedObject public var recipeStore: RecipeStore
    @ObservedObject public var cameraManager: CameraManager
    public var onToggleConnection: (() -> Void)? = nil

    public init(
        selection: Binding<AppTab>,
        recipeStore: RecipeStore,
        cameraManager: CameraManager,
        onToggleConnection: (() -> Void)? = nil
    ) {
        self._selection = selection
        self.recipeStore = recipeStore
        self.cameraManager = cameraManager
        self.onToggleConnection = onToggleConnection
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    // Main Navigation: 2 Primary Core Tabs
                    VStack(spacing: 3) {
                        ForEach(AppTab.primaryTabs) { tab in
                            SidebarRow(
                                tab: tab,
                                isSelected: selection == tab || (tab == .camera && selection == .loadouts),
                                badge: tabBadge(for: tab)
                            ) {
                                withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                                    selection = tab
                                }
                            }
                        }
                    }

                    // Film Sim Collections Section
                    VStack(alignment: .leading, spacing: 6) {
                        Text("FILM SIMULATIONS")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 10)

                        VStack(spacing: 2) {
                            simShortcutRow(title: "All Simulations", family: .all, count: recipeStore.recipes.count)
                            simShortcutRow(title: "Classic Chrome", family: .classicChrome)
                            simShortcutRow(title: "Reala Ace", family: .realaAce)
                            simShortcutRow(title: "Classic Negative", family: .classicNeg)
                            simShortcutRow(title: "Velvia", family: .velvia)
                            simShortcutRow(title: "Acros / Monochrome", family: .acros)
                        }
                    }

                    // Dial Staging Quick Rack
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                                selection = .camera
                            }
                        } label: {
                            HStack {
                                Text("DIAL STAGING RACK")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)
                                Spacer()
                                Text("\(recipeStore.loadouts.loadoutCountWithSettings())/7")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(Theme.fujiAmber)
                            }
                            .padding(.horizontal, 10)
                        }
                        .buttonStyle(.plain)
                        .help("Click to open Camera & Staging")

                        // Mini dial slots visualizer (drag and drop target)
                        HStack(spacing: 3) {
                            ForEach(1...7, id: \.self) { slot in
                                let loadout = recipeStore.loadouts.loadout(for: slot)
                                SidebarMiniDialSlot(
                                    slot: slot,
                                    loadout: loadout,
                                    onSelect: {
                                        withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                                            selection = .camera
                                        }
                                    },
                                    onDropRecipe: { recipe in
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                                            recipeStore.loadouts.applyRecipe(recipe, to: slot)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, 8)
                    }

                    // Secondary Utilities
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
    }

    private func tabBadge(for tab: AppTab) -> String? {
        switch tab {
        case .recipes:
            let favs = recipeStore.favorites.favoriteIDs.count
            return favs > 0 ? "\(favs) ★" : nil
        case .camera, .loadouts:
            if cameraManager.status == .connected {
                return "ONLINE"
            }
            let count = recipeStore.loadouts.loadoutCountWithSettings()
            return count > 0 ? "\(count)/7" : nil
        case .darkroom:
            return nil
        }
    }

    private func simShortcutRow(title: String, family: RecipeStore.FilmSimFamily, count: Int? = nil) -> some View {
        let isSelected = selection == .recipes && recipeStore.selectedFilmSimFamily == family && recipeStore.selectedFilterCategory == nil
        let accent = family == .all ? Theme.fujiAmber : Theme.filmSimColor(for: family.rawValue)

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

                if let count {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isSelected ? accent.opacity(0.16) : Color.clear)
            )
        }
        .buttonStyle(.plain)
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
            HStack(spacing: 8) {
                // Live pulsing beacon
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

                VStack(alignment: .leading, spacing: 1) {
                    Text(cameraManager.status.formattedLabel)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)

                    Text(cameraManager.status.detailLabel)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                // 1-Click Connect Button or Chevron
                if let onToggleConnection {
                    Button {
                        onToggleConnection()
                    } label: {
                        HStack(spacing: 3) {
                            if cameraManager.status == .connecting {
                                ProgressView()
                                    .controlSize(.mini)
                            } else {
                                Image(systemName: cameraManager.status == .connected ? "checkmark.circle.fill" : "cable.connector")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            Text(cameraManager.status == .connected ? "Disconnect" : "Connect")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
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
                    .disabled(cameraManager.status == .connecting)
                    .help(cameraManager.status == .connected ? "Disconnect Camera" : "1-Click Connect to Fujifilm X100VI")
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(5)
                        .background(Circle().fill(Color.white.opacity(0.06)))
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
}

// MARK: - Sidebar Row Item

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

// MARK: - Sidebar Mini Dial Slot (Drag & Drop Target)

private struct SidebarMiniDialSlot: View {
    let slot: Int
    let loadout: Loadout?
    let onSelect: () -> Void
    let onDropRecipe: (Recipe) -> Void

    @State private var isDropTargeted = false

    private var hasSetting: Bool { loadout?.hasAnySettings ?? false }
    private var accent: Color { slotAccent(slot) }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: 1) {
                Text("C\(slot)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(isDropTargeted ? Color.black : (hasSetting ? Color.black : Theme.textTertiary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isDropTargeted ? Theme.fujiAmber : (hasSetting ? Theme.fujiAmber : Color.white.opacity(0.05)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        isDropTargeted
                            ? Color.white
                            : (hasSetting ? Theme.fujiAmber.opacity(0.6) : Color.white.opacity(0.08)),
                        lineWidth: isDropTargeted ? 1.5 : 0.8
                    )
            )
            .shadow(color: isDropTargeted ? Theme.fujiAmber.opacity(0.9) : Color.clear, radius: isDropTargeted ? 8 : 0)
            .scaleEffect(isDropTargeted ? 1.18 : 1.0)
        }
        .buttonStyle(.plain)
        .dropDestination(for: Recipe.self) { items, _ in
            guard let recipe = items.first else { return false }
            onDropRecipe(recipe)
            return true
        } isTargeted: { targeted in
            withAnimation(.spring(response: 0.22, dampingFraction: 0.75)) {
                isDropTargeted = targeted
            }
        }
        .animation(.spring(response: 0.22, dampingFraction: 0.75), value: isDropTargeted)
        .help(isDropTargeted ? "Drop recipe to stage into C\(slot)" : (loadout?.recipeName ?? "C\(slot): Empty"))
        .accessibilityLabel("Slot C\(slot), \(hasSetting ? (loadout?.recipeName ?? "configured") : "empty")")
        .accessibilityHint("Click to view C1–C7 matrix, or drop a recipe here to stage it.")
    }
}

// MARK: - App Tabs

public enum AppTab: String, CaseIterable, Identifiable {
    case recipes
    case camera
    case darkroom
    case loadouts

    /// The two primary core workflows of FujiRecipes
    public static var primaryTabs: [AppTab] {
        [.recipes, .camera]
    }

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recipes: return "Recipes"
        case .camera, .loadouts: return "Camera & Staging"
        case .darkroom: return "RAF Darkroom"
        }
    }

    public var icon: String {
        switch self {
        case .recipes: return "photo.stack.fill"
        case .camera: return "camera.fill"
        case .darkroom: return "moon.stars.fill"
        case .loadouts: return "dial.low.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .recipes: return Theme.fujiAmber
        case .camera, .loadouts: return Theme.emeraldGreen
        case .darkroom: return Theme.cyanAccent
        }
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
