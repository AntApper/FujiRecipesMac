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

        let canvasSize = CGSize(
            width: windowWidth + canvasPadding * 2,
            height: windowHeight + canvasPadding * 2
        )

        let shots: [(String, AppTab, AnyView)] = [
            ("recipe-library.png", .recipes, AnyView(
                RecipeListView(store: store, cameraManager: camera)
            )),
            ("camera-hub.png", .camera, AnyView(
                CameraConnectionView(manager: camera, loadouts: store.loadouts)
            )),
            ("darkroom-preview.png", .darkroom, AnyView(
                RAFDarkroomView(manager: camera, store: store)
            )),
            ("recipe-editor.png", .recipes, AnyView(
                ZStack {
                    RecipeListView(store: store, cameraManager: camera)
                    Color.black.opacity(0.60)
                    VStack(spacing: 0) {
                        CustomRecipeEditor(
                            recipe: store.recipes.first { $0.filmSimulation == .classicChrome } ?? topRecipes[0],
                            existingRecipes: store.recipes,
                            onSave: { _ in }
                        )
                    }
                    .frame(width: 720, height: 680)
                    .background(Color(red: 0.10, green: 0.105, blue: 0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.65), radius: 32, y: 16)
                }
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

        return AppSupportDirectory.current.appendingPathComponent("Snapshots", isDirectory: true)
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
                    SidebarView(selection: .constant(tab), recipeStore: store, cameraManager: camera, onToggleConnection: {})
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
