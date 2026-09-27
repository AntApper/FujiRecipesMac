import SwiftUI
import FujiRecipesCore
import X100VIHelper
import PTPClientMacOS

private enum MacAppCommand {
    static let refreshRecipes = Notification.Name("com.ant.fuji-recipes.refresh-recipes")
    static let selectTab = Notification.Name("com.ant.fuji-recipes.select-tab")
    static let tabKey = "tab"
}

/// Boundary for supplying a camera transport to macOS views. Tests and
/// previews can inject a deterministic `PTPClientProtocol` without changing
/// `CameraManager` or invoking hardware.
public typealias CameraSessionFactory = @Sendable () -> any PTPClientProtocol

private enum MacAppLaunchConfiguration {
    static var isUITesting: Bool {
        ProcessInfo.processInfo.environment["FUJI_RECIPES_CUSTOM_LIBRARY_PATH"] != nil
    }

    static var usesImageCaptureCoreTransport: Bool {
        ProcessInfo.processInfo.environment["FUJI_RECIPES_TRANSPORT"] != "helper"
    }

    /// UI tests supply a unique path so their custom-library fixture cannot
    /// read or alter a person's persisted recipes.
    @MainActor
    static func recipeStore() -> RecipeStore {
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["FUJI_RECIPES_CUSTOM_LIBRARY_PATH"],
           !path.isEmpty {
            return RecipeStore(
                customRecipes: CustomRecipeLibrary(storageURL: URL(fileURLWithPath: path))
            )
        }
        #endif
        return RecipeStore()
    }
}

@main
struct FujiRecipesMacApp: App {
    init() {
        DebugLogger.setMinimumLevel(.debug)
        DebugLogger.log(.info, category: .app, "🚀 FujiRecipesMac Pro launching")
        DebugLogger.log(.info, category: .app, "Version: \(DebugLogger.appInfo["version"] ?? "2026.1")")

        CrashReportHelper.setup()
        DebugLogger.info("CrashReportHelper.setup() complete", category: .app)
        
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--generate-snapshots") {
            Task { @MainActor in
                SnapshotRenderer.renderSnapshots()
                exit(0)
            }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            FujiRecipesMacRoot(
                recipeStore: MacAppLaunchConfiguration.recipeStore(),
                cameraSessionFactory: {
                    if MacAppLaunchConfiguration.usesImageCaptureCoreTransport {
                        return ImageCaptureCorePTPClient()
                    }
                    return X100VIHelperClient()
                }
            )
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1100, height: 720)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Refresh Recipes") {
                    NotificationCenter.default.post(name: MacAppCommand.refreshRecipes, object: nil)
                }
                .keyboardShortcut("r", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Divider()
                Button("Recipes") {
                    NotificationCenter.default.post(
                        name: MacAppCommand.selectTab,
                        object: nil,
                        userInfo: [MacAppCommand.tabKey: AppTab.recipes.rawValue]
                    )
                }
                .keyboardShortcut("1", modifiers: .command)

                Button("Camera & Staging") {
                    NotificationCenter.default.post(
                        name: MacAppCommand.selectTab,
                        object: nil,
                        userInfo: [MacAppCommand.tabKey: AppTab.camera.rawValue]
                    )
                }
                .keyboardShortcut("2", modifiers: .command)

                Button("RAF Darkroom") {
                    NotificationCenter.default.post(
                        name: MacAppCommand.selectTab,
                        object: nil,
                        userInfo: [MacAppCommand.tabKey: AppTab.darkroom.rawValue]
                    )
                }
                .keyboardShortcut("3", modifiers: .command)
            }
        }
    }
}

public struct FujiRecipesMacRoot: View {
    @StateObject private var recipeStore: RecipeStore
    @StateObject private var cameraManager = CameraManager()
    @State private var selectedTab: AppTab = .recipes
    private let cameraSessionFactory: CameraSessionFactory

    public init(
        recipeStore: RecipeStore = RecipeStore(),
        cameraSessionFactory: @escaping CameraSessionFactory
    ) {
        _recipeStore = StateObject(wrappedValue: recipeStore)
        self.cameraSessionFactory = cameraSessionFactory
    }

    public var body: some View {
        ZStack {
            GlassWindowBackground()

            NavigationSplitView {
                SidebarView(
                    selection: $selectedTab,
                    recipeStore: recipeStore,
                    cameraManager: cameraManager,
                    onToggleConnection: toggleCameraConnection
                )
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 280)
            } detail: {
                ZStack {
                    Color.clear
                    Group {
                        switch selectedTab {
                        case .recipes:
                            RecipeListView(
                                store: recipeStore,
                                cameraManager: cameraManager,
                                onNavigateToCamera: {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                        selectedTab = .camera
                                    }
                                }
                            )
                        case .camera:
                            CameraConnectionView(
                                manager: cameraManager,
                                loadouts: recipeStore.loadouts,
                                cameraSessionFactory: cameraSessionFactory
                            )
                        case .darkroom:
                            RAFDarkroomView(manager: cameraManager)
                        }
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.985)).combined(with: .offset(y: 6)),
                        removal: .opacity.combined(with: .scale(scale: 1.01))
                    ))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedTab)
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 780, minHeight: 520)
            .tint(Theme.fujiAmber)
            .background(.clear)
            .scrollContentBackground(.hidden)
        }
        .preferredColorScheme(.dark)
        .debugHUD(enabled: !MacAppLaunchConfiguration.isUITesting)
        .task {
            DebugLogger.log(.info, category: .app, "App appeared — Tab: \(selectedTab.rawValue)")
            await recipeStore.loadRecipes()
        }
        .onReceive(NotificationCenter.default.publisher(for: MacAppCommand.refreshRecipes)) { _ in
            Task { await recipeStore.loadRecipes() }
        }
        .onReceive(NotificationCenter.default.publisher(for: MacAppCommand.selectTab)) { notification in
            guard
                let rawValue = notification.userInfo?[MacAppCommand.tabKey] as? String,
                let tab = AppTab(rawValue: rawValue)
            else { return }
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                selectedTab = tab
            }
        }
        .accessibilityAction(named: "Show Recipes") { selectedTab = .recipes }
        .accessibilityAction(named: "Show Camera & Staging") { selectedTab = .camera }
        .accessibilityAction(named: "Show RAF Darkroom") { selectedTab = .darkroom }
    }

    private func toggleCameraConnection() {
        Task {
            if cameraManager.status == .connected {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    cameraManager.disconnect()
                }
            } else {
                await cameraManager.connect(using: cameraSessionFactory(), loadouts: recipeStore.loadouts)
            }
        }
    }
}

private extension View {
    @ViewBuilder
    func debugHUD(enabled: Bool) -> some View {
        if enabled {
            debugHUD()
        } else {
            self
        }
    }
}
