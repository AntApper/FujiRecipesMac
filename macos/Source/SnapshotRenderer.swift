import SwiftUI
import AppKit
import FujiRecipesCore

@MainActor
public enum SnapshotRenderer {
    private static let windowWidth: CGFloat = 1280
    private static let windowHeight: CGFloat = 820
    private static let sidebarWidth: CGFloat = 248
    private static let canvasPadding: CGFloat = 48
    private static let titleBarHeight: CGFloat = 40

    public static func renderSnapshots() {
        let store = RecipeStore()
        store.loadRecipesSynchronously()
        let camera = CameraManager()

        let outputDir = snapshotOutputDirectory()
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let tag = "v3"
        let canvasSize = CGSize(
            width: windowWidth + canvasPadding * 2,
            height: windowHeight + canvasPadding * 2
        )

        let shots: [(String, AppTab, AnyView)] = [
            ("recipes_studio_\(tag).png", .recipes, AnyView(
                RecipeListView(store: store, cameraManager: camera)
                    .environment(\.snapshotMode, true)
            )),
            ("custom_dial_matrix_\(tag).png", .loadouts, AnyView(
                LoadoutsView(loadouts: store.loadouts, cameraManager: camera)
                    .environment(\.snapshotMode, true)
            )),
            ("camera_hub_\(tag).png", .camera, AnyView(
                CameraConnectionView(manager: camera, loadouts: store.loadouts)
                    .environment(\.snapshotMode, true)
            )),
            ("darkroom_\(tag).png", .darkroom, AnyView(
                RAFDarkroomView(manager: camera)
                    .environment(\.snapshotMode, true)
            )),
        ]

        for (filename, tab, detail) in shots {
            let view = makeFramedWindow(tab: tab, store: store, camera: camera) { detail }
            renderHosting(view, to: outputDir.appendingPathComponent(filename), size: canvasSize)
        }
    }

    private static func snapshotOutputDirectory() -> URL {
        let arguments = ProcessInfo.processInfo.arguments
        if let flagIndex = arguments.firstIndex(of: "--snapshot-output"),
           arguments.indices.contains(flagIndex + 1) {
            return URL(fileURLWithPath: arguments[flagIndex + 1], isDirectory: true)
        }

        return FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
        .appendingPathComponent("FujiRecipes/Snapshots", isDirectory: true)
    }

    private static func makeFramedWindow<Content: View>(
        tab: AppTab,
        store: RecipeStore,
        camera: CameraManager,
        @ViewBuilder detail: () -> Content
    ) -> some View {
        let detailWidth = windowWidth - sidebarWidth
        let bodyHeight = windowHeight - titleBarHeight

        return ZStack {
            Color(red: 0.035, green: 0.037, blue: 0.045)

            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Circle().fill(Color(red: 1.0, green: 0.38, blue: 0.35)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 1.0, green: 0.76, blue: 0.22)).frame(width: 12, height: 12)
                    Circle().fill(Color(red: 0.20, green: 0.80, blue: 0.30)).frame(width: 12, height: 12)
                    Spacer()
                    Text("FujiRecipes Pro")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                    Spacer()
                    Color.clear.frame(width: 52)
                }
                .padding(.horizontal, 16)
                .frame(height: titleBarHeight)
                .background(Color(red: 0.10, green: 0.105, blue: 0.12))

                HStack(alignment: .top, spacing: 0) {
                    SnapshotSidebar(selection: tab, recipeStore: store, cameraManager: camera)
                        .frame(width: sidebarWidth, height: bodyHeight, alignment: .topLeading)

                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                        .frame(width: 1, height: bodyHeight)

                    detail()
                        .frame(width: detailWidth - 1, height: bodyHeight, alignment: .topLeading)
                        .clipped()
                        .background(Color(red: 0.055, green: 0.058, blue: 0.068))
                }
                .frame(width: windowWidth, height: bodyHeight, alignment: .topLeading)
            }
            .frame(width: windowWidth, height: windowHeight, alignment: .topLeading)
            .background(Color(red: 0.07, green: 0.075, blue: 0.085))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.55), radius: 28, y: 14)
            .padding(canvasPadding)
        }
        .preferredColorScheme(.dark)
        .frame(width: windowWidth + canvasPadding * 2, height: windowHeight + canvasPadding * 2)
        .tint(Theme.fujiAmber)
    }

    private static func renderHosting<V: View>(_ view: V, to url: URL, size: CGSize) {
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(origin: .zero, size: size)
        hostingView.wantsLayer = true

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.contentView = hostingView
        window.orderFrontRegardless()
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))

        // Force full layout + a couple of runloop spins so LazyVGrid/ScrollView populate.
        for _ in 0..<6 {
            hostingView.layoutSubtreeIfNeeded()
            window.layoutIfNeeded()
            window.displayIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        }

        let bounds = hostingView.bounds
        guard let rep = hostingView.bitmapImageRepForCachingDisplay(in: bounds) else {
            print("Failed to allocate bitmap for \(url.lastPathComponent)")
            window.close()
            return
        }
        hostingView.cacheDisplay(in: bounds, to: rep)

        // Convert to sRGB PNG for GitHub Camo stability.
        let png: Data?
        if let cg = rep.cgImage {
            let srgb = NSBitmapImageRep(bitmapDataPlanes: nil,
                                        pixelsWide: cg.width,
                                        pixelsHigh: cg.height,
                                        bitsPerSample: 8,
                                        samplesPerPixel: 4,
                                        hasAlpha: true,
                                        isPlanar: false,
                                        colorSpaceName: .deviceRGB,
                                        bytesPerRow: 0,
                                        bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: srgb)
            NSGraphicsContext.current?.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            NSGraphicsContext.restoreGraphicsState()
            png = srgb.representation(using: .png, properties: [:])
        } else {
            png = rep.representation(using: .png, properties: [:])
        }

        if let png {
            try? png.write(to: url)
            print("Hosting wrote \(url.lastPathComponent) (\(png.count) bytes, \(rep.pixelsWide)x\(rep.pixelsHigh))")
        } else {
            print("Failed to encode PNG for \(url.lastPathComponent)")
        }
        window.close()
    }
}

// MARK: - Snapshot environment (disable searchable/toolbar chrome that blanks offscreen)

private struct SnapshotModeKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var snapshotMode: Bool {
        get { self[SnapshotModeKey.self] }
        set { self[SnapshotModeKey.self] = newValue }
    }
}

// MARK: - Deterministic snapshot sidebar

private struct SnapshotSidebar: View {
    let selection: AppTab
    let recipeStore: RecipeStore
    let cameraManager: CameraManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
            navSection
            filmSimSection
            dialBankSection
            Spacer(minLength: 8)
            statusFooter
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(red: 0.09, green: 0.095, blue: 0.11))
    }

    private var brandHeader: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 28, height: 28)
                Image(systemName: "camera.aperture")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.9))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("FUJIRECIPES")
                        .font(.system(size: 11, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("PRO")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundStyle(Theme.fujiAmber)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Theme.fujiAmber.opacity(0.18))
                        .clipShape(Capsule())
                }
                Text("X100VI STUDIO")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.45))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    private var navSection: some View {
        VStack(spacing: 2) {
            ForEach(AppTab.allCases) { tab in
                HStack(spacing: 9) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selection == tab ? tab.accentColor : Color.white.opacity(0.05))
                            .frame(width: 24, height: 24)
                        Image(systemName: tab.icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(selection == tab ? (tab.accentColor == Theme.fujiAmber ? Color.black : Color.white) : Color.white.opacity(0.65))
                    }
                    Text(tab.title)
                        .font(.system(size: 12, weight: selection == tab ? .semibold : .regular))
                        .foregroundStyle(selection == tab ? Color.white : Color.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let badge = badge(for: tab) {
                        Text(badge)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(selection == tab ? Color.black : Theme.fujiAmber)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(selection == tab ? Color.white : Theme.fujiAmber.opacity(0.18)))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selection == tab ? Color.white.opacity(0.10) : Color.clear)
                )
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 14)
    }

    private var filmSimSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("FILM SIMULATIONS")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.horizontal, 14)

            simRow("All Simulations", Theme.fujiAmber, count: recipeStore.recipes.count)
            simRow("Classic Chrome", Theme.filmSimColor(for: "Classic Chrome"))
            simRow("Reala Ace", Theme.filmSimColor(for: "Reala Ace"))
            simRow("Classic Negative", Theme.filmSimColor(for: "Classic Negative"))
            simRow("Velvia", Theme.filmSimColor(for: "Velvia"))
            simRow("Acros / Monochrome", Theme.filmSimColor(for: "Acros"))
        }
        .padding(.bottom, 14)
    }

    private var dialBankSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("CUSTOM DIAL BANK")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
                Spacer()
                Text("\(recipeStore.loadouts.loadoutCountWithSettings())/7")
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.fujiAmber)
            }
            .padding(.horizontal, 14)

            HStack(spacing: 3) {
                ForEach(1...7, id: \.self) { slot in
                    let filled = recipeStore.loadouts.loadout(for: slot)?.hasAnySettings ?? false
                    Text("C\(slot)")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .foregroundStyle(filled ? Color.black : Color.white.opacity(0.4))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(filled ? Theme.fujiAmber : Color.white.opacity(0.05))
                        )
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var statusFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(cameraManager.status.tint)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(cameraManager.status.formattedLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("X100VI USB RAW")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.04))
    }

    private func simRow(_ title: String, _ color: Color, count: Int? = nil) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(Color.white.opacity(0.7))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let count {
                Text("\(count)")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }

    private func badge(for tab: AppTab) -> String? {
        switch tab {
        case .recipes:
            let n = recipeStore.favorites.favoriteIDs.count
            return n > 0 ? "\(n)" : nil
        case .loadouts:
            let n = recipeStore.loadouts.loadoutCountWithSettings()
            return n > 0 ? "\(n)/7" : nil
        case .camera:
            return cameraManager.status == .connected ? "ON" : nil
        case .darkroom:
            return nil
        }
    }
}
