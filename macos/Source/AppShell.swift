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

    public init(
        selection: Binding<AppTab>,
        recipeStore: RecipeStore,
        cameraManager: CameraManager
    ) {
        self._selection = selection
        self.recipeStore = recipeStore
        self.cameraManager = cameraManager
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    // Main Navigation
                    VStack(spacing: 3) {
                        ForEach(AppTab.allCases) { tab in
                            SidebarRow(
                                tab: tab,
                                isSelected: selection == tab,
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

                    // Custom Bank Quick Status
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("CUSTOM DIAL BANK")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)
                            Spacer()
                            Text("\(recipeStore.loadouts.loadoutCountWithSettings())/7")
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.fujiAmber)
                        }
                        .padding(.horizontal, 10)

                        // Mini dial slots visualizer
                        HStack(spacing: 3) {
                            ForEach(1...7, id: \.self) { slot in
                                let loadout = recipeStore.loadouts.loadout(for: slot)
                                let hasSetting = loadout?.hasAnySettings ?? false
                                Button {
                                    withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                                        selection = .loadouts
                                    }
                                } label: {
                                    VStack(spacing: 1) {
                                        Text("C\(slot)")
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .foregroundStyle(hasSetting ? Color.black : Theme.textTertiary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .fill(hasSetting ? Theme.fujiAmber : Color.white.opacity(0.05))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .stroke(hasSetting ? Theme.fujiAmber.opacity(0.6) : Color.white.opacity(0.08), lineWidth: 0.8)
                                    )
                                }
                                .buttonStyle(.plain)
                                .help(loadout?.recipeName ?? "C\(slot): Empty")
                            }
                        }
                        .padding(.horizontal, 8)
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
        case .loadouts:
            let count = recipeStore.loadouts.loadoutCountWithSettings()
            return count > 0 ? "\(count)/7" : nil
        case .camera:
            return cameraManager.status == .connected ? "ONLINE" : nil
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

            Spacer(minLength: 0)

            // Quick Connect / Switcher
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    selection = .camera
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(5)
                    .background(Circle().fill(Color.white.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("Open Camera Settings")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.04))
                .padding(.horizontal, 6)
                .padding(.bottom, 6)
        )
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

// MARK: - App Tabs

public enum AppTab: String, CaseIterable, Identifiable {
    case recipes, loadouts, camera, darkroom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .recipes: return "Recipes"
        case .loadouts: return "C1–C7 Matrix"
        case .camera: return "Camera Hub"
        case .darkroom: return "RAF Darkroom"
        }
    }

    public var icon: String {
        switch self {
        case .recipes: return "photo.stack.fill"
        case .loadouts: return "dial.low.fill"
        case .camera: return "camera.fill"
        case .darkroom: return "moon.stars.fill"
        }
    }

    public var accentColor: Color {
        switch self {
        case .recipes: return Theme.fujiAmber
        case .loadouts: return Theme.warmGold
        case .camera: return Theme.emeraldGreen
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
