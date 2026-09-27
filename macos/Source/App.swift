import SwiftUI
import FujiRecipesCore
import X100VIHelper
import PTPClientMacOS

enum MacAppCommand {
    static let refreshRecipes = Notification.Name("com.ant.fuji-recipes.refresh-recipes")
    static let selectTab = Notification.Name("com.ant.fuji-recipes.select-tab")
    static let selectDialSlot = Notification.Name("com.ant.fuji-recipes.select-dial-slot")
    static let focusSearch = Notification.Name("com.ant.fuji-recipes.focus-search")
    static let toggleDebugHUD = Notification.Name("com.ant.fuji-recipes.toggle-debug-hud")
    static let showToast = Notification.Name("com.ant.fuji-recipes.show-toast")
    static let tabKey = "tab"
    static let slotKey = "slot"
    static let toastTitleKey = "title"
    static let toastMessageKey = "message"
    static let toastIsErrorKey = "isError"
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

    /// UI tests supply a unique library path and defaults suite so their
    /// fixtures cannot read or alter a person's recipes, favorites, or drafts.
    @MainActor
    static func recipeStore() -> RecipeStore {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let defaults = environment["FUJI_RECIPES_DEFAULTS_SUITE"]
            .flatMap { $0.isEmpty ? nil : UserDefaults(suiteName: $0) } ?? .standard
        let library = environment["FUJI_RECIPES_CUSTOM_LIBRARY_PATH"]
            .flatMap { $0.isEmpty ? nil : CustomRecipeLibrary(storageURL: URL(fileURLWithPath: $0)) }
            ?? CustomRecipeLibrary()
        return RecipeStore(recipeLoading: loadBundledRecipes, defaults: defaults, customRecipes: library)
        #else
        return RecipeStore(recipeLoading: loadBundledRecipes)
        #endif
    }
}

/// Packaged apps and the Xcode project copy `recipes-data.json` into the main
/// bundle. A bare SwiftPM build only has it in this target's resource bundle,
/// nested under the `Resources` folder name from `Package.swift`, and
/// `Bundle.module` only exists (and traps if missing) under SwiftPM.
@MainActor
func loadBundledRecipes() throws -> [Recipe] {
    #if SWIFT_PACKAGE
    if Bundle.main.url(forResource: "recipes-data", withExtension: "json") == nil {
        return try RecipeLoader.loadRecipes(from: .module, subdirectory: "Resources")
    }
    #endif
    return try RecipeLoader.loadRecipes(from: .main)
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
            CommandGroup(after: .pasteboard) {
                Button("Find Recipes…") {
                    NotificationCenter.default.post(
                        name: MacAppCommand.selectTab,
                        object: nil,
                        userInfo: [MacAppCommand.tabKey: AppTab.recipes.rawValue]
                    )
                    NotificationCenter.default.post(name: MacAppCommand.focusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
            CommandMenu("Dial Presets") {
                ForEach(1...7, id: \.self) { slot in
                    Button("Select C\(slot)") {
                        NotificationCenter.default.post(
                            name: MacAppCommand.selectDialSlot,
                            object: nil,
                            userInfo: [MacAppCommand.slotKey: slot]
                        )
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(slot)")), modifiers: .option)
                }
            }
            #if DEBUG
            CommandGroup(after: .help) {
                Divider()
                Button("Diagnostics & Debug HUD") {
                    NotificationCenter.default.post(name: MacAppCommand.toggleDebugHUD, object: nil)
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
            }
            #endif
        }
    }
}

public struct FujiRecipesMacRoot: View {
    @StateObject private var recipeStore: RecipeStore
    @StateObject private var cameraManager = CameraManager()
    @State private var selectedTab: AppTab = .recipes
    @State private var selectedDialSlot: Int = 1
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
                    selectedDialSlot: $selectedDialSlot,
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
                                selectedDialSlot: $selectedDialSlot,
                                cameraSessionFactory: cameraSessionFactory
                            )
                        case .darkroom:
                            RAFDarkroomView(
                                manager: cameraManager,
                                store: recipeStore,
                                cameraSessionFactory: cameraSessionFactory
                            )
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
        .environmentObject(recipeStore)
        .environmentObject(cameraManager)
        .environment(\.cameraManager, cameraManager)
        .dataRecoveryAlerts(library: recipeStore.customRecipes, loadouts: recipeStore.loadouts)
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
        .onReceive(NotificationCenter.default.publisher(for: MacAppCommand.selectDialSlot)) { notification in
            guard let slot = notification.userInfo?[MacAppCommand.slotKey] as? Int,
                  (1...7).contains(slot) else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                selectedTab = .camera
                selectedDialSlot = slot
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: MacAppCommand.focusSearch)) { _ in
            if selectedTab != .recipes {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.78)) {
                    selectedTab = .recipes
                }
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
