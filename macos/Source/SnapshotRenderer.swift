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
        let loadoutsKey = "com.ant.fuji-recipes.loadouts"
        let previousData = UserDefaults.standard.data(forKey: loadoutsKey)
        defer {
            if let previousData {
                UserDefaults.standard.set(previousData, forKey: loadoutsKey)
            } else {
                UserDefaults.standard.removeObject(forKey: loadoutsKey)
            }
        }

        let store = RecipeStore(recipeLoading: loadBundledRecipes)
        store.loadRecipesSynchronously()
        let camera = CameraManager()

        // Stage 7 diverse recipes across C1–C7 so every slot showcases a distinct formulation
        let topRecipes = Array(store.recipes.prefix(7))
        store.loadouts.stageAll(recipes: topRecipes)

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
            ("camera_hub_\(tag).png", .camera, AnyView(
                CameraConnectionView(manager: camera, loadouts: store.loadouts)
                    .environment(\.snapshotMode, true)
            )),
            ("custom_dial_matrix_\(tag).png", .camera, AnyView(
                LoadoutsView(loadouts: store.loadouts, cameraManager: camera)
                    .environment(\.snapshotMode, true)
            )),
            ("darkroom_\(tag).png", .darkroom, AnyView(
                RAFDarkroomView(manager: camera, store: store)
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
            librarySection
            dialRackSection
            filmSimSection
            utilitiesSection
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
        .padding(.bottom, 12)
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("LIBRARY")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.horizontal, 14)

            libraryRow("All Recipes", "photo.stack.fill", Theme.fujiAmber, selection == .recipes, count: recipeStore.recipes.count)
            libraryRow("Favorites", "star.fill", Theme.fujiAmber, false, count: recipeStore.favorites.favoriteIDs.count)
            libraryRow("My Recipes", "folder.badge.gearshape", Theme.emeraldGreen, false, count: recipeStore.customRecipes.recipes.count)
        }
        .padding(.bottom, 12)
    }

    private var dialRackSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "dial.low.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text("CAMERA DIAL PRESETS")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(selection == .camera ? Color.white : Color.white.opacity(0.4))
                Spacer()
                let armed = recipeStore.loadouts.loadoutCountWithSettings()
                Text("\(armed)/7")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(armed > 0 ? Theme.fujiAmber : Color.white.opacity(0.4))
            }
            .padding(.horizontal, 14)

            VStack(spacing: 2) {
                ForEach(1...7, id: \.self) { slot in
                    let loadout = recipeStore.loadouts.loadout(for: slot)
                    let accent = slotAccent(slot)
                    let hasSettings = loadout?.hasAnySettings ?? false
                    let name: String = {
                        if let recipeName = loadout?.recipeName, !recipeName.isEmpty { return recipeName }
                        if let slotName = loadout?.name, !slotName.isEmpty, slotName != "C\(slot)" { return slotName }
                        return "Empty Slot"
                    }()
                    let isSelected = selection == .camera && slot == 1

                    HStack(spacing: 6) {
                        Text("C\(slot)")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .foregroundStyle(isSelected ? Color.black : accent)
                            .frame(width: 22, height: 16)
                            .background(
                                RoundedRectangle(cornerRadius: 3, style: .continuous)
                                    .fill(isSelected ? accent : accent.opacity(0.16))
                            )

                        VStack(alignment: .leading, spacing: 0) {
                            Text(name)
                                .font(.system(size: 10, weight: isSelected ? .semibold : (hasSettings ? .medium : .regular)))
                                .foregroundStyle(isSelected ? Color.white : (hasSettings ? Color.white.opacity(0.9) : Color.white.opacity(0.4)))
                                .lineLimit(1)

                            if let sim = loadout?.filmSim {
                                Text(sim.displayName)
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundStyle(isSelected ? Color.white.opacity(0.8) : Theme.filmSimColor(for: sim.displayName))
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 2)

                        Circle()
                            .fill(hasSettings ? (loadout?.provenance == .cameraSynced ? Theme.emeraldGreen : Theme.fujiAmber) : Color.white.opacity(0.18))
                            .frame(width: 5, height: 5)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSelected ? accent.opacity(0.15) : Color.white.opacity(0.02))
                    )
                }
            }
            .padding(.horizontal, 10)
        }
        .padding(.bottom, 12)
    }

    private var filmSimSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("FILM SIMULATION BASES")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.horizontal, 14)

            simRow("Classic Chrome", Theme.filmSimColor(for: "Classic Chrome"), count: recipeStore.recipes.filter { RecipeStore.FilmSimFamily.classicChrome.matches($0.filmSimulation) }.count)
            simRow("Reala Ace", Theme.filmSimColor(for: "Reala Ace"), count: recipeStore.recipes.filter { RecipeStore.FilmSimFamily.realaAce.matches($0.filmSimulation) }.count)
            simRow("Classic Neg", Theme.filmSimColor(for: "Classic Negative"), count: recipeStore.recipes.filter { RecipeStore.FilmSimFamily.classicNeg.matches($0.filmSimulation) }.count)
            simRow("Velvia", Theme.filmSimColor(for: "Velvia"), count: recipeStore.recipes.filter { RecipeStore.FilmSimFamily.velvia.matches($0.filmSimulation) }.count)
            simRow("Acros / B&W", Theme.filmSimColor(for: "Acros"), count: recipeStore.recipes.filter { RecipeStore.FilmSimFamily.acros.matches($0.filmSimulation) }.count)
        }
        .padding(.bottom, 12)
    }

    private var utilitiesSection: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("UTILITIES")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(Color.white.opacity(0.4))
                .padding(.horizontal, 14)

            libraryRow("RAF Darkroom", "moon.stars.fill", Theme.cyanAccent, selection == .darkroom, count: nil)
        }
    }

    private var statusFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(cameraManager.status.tint)
                .frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                Text(cameraManager.status == .connected ? "X100VI Online" : "X100VI Disconnected")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text(cameraManager.status == .connected ? "USB PTP • Verified" : "USB RAW Mode")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.white.opacity(0.4))
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            Text("Connect")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.emeraldGreen)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.emeraldGreen.opacity(0.18)))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.white.opacity(0.04))
        )
        .padding(.horizontal, 10)
    }

    private func libraryRow(_ title: String, _ icon: String, _ accent: Color, _ isSelected: Bool, count: Int?) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? accent : Color.white.opacity(0.05))
                    .frame(width: 20, height: 20)
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(isSelected ? (accent == Theme.fujiAmber ? Color.black : Color.white) : Color.white.opacity(0.65))
            }
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.75))
                .lineLimit(1)
            Spacer(minLength: 0)
            if let count {
                Text("\(count)")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.black : Theme.fujiAmber)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(isSelected ? Color.white : Theme.fujiAmber.opacity(0.18)))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.10) : Color.clear)
        )
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
}
