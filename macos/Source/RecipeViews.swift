import SwiftUI
import FujiRecipesCore
import AppKit
import UniformTypeIdentifiers

// MARK: - 2026 Sleek Recipe Gallery & Cards View

private struct HUDToast: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
    let isError: Bool
}

private struct PendingStageTop {
    let recipes: [Recipe]
    let replacedSlots: [Int]

    var replacedSlotList: String {
        ListFormatter.localizedString(byJoining: replacedSlots.map { "C\($0)" })
    }
}

public struct RecipeListView: View {
    @ObservedObject public var store: RecipeStore
    @ObservedObject public var cameraManager: CameraManager
    @State private var expandedRecipeIDs: Set<Recipe.ID> = []
    @State private var recipeToLoad: Recipe?
    @State private var selectedPhotoUrl: String? = nil
    @State private var activeHUDToast: HUDToast?
    @State private var pendingStageTop: PendingStageTop?
    @State private var recipeToEdit: Recipe?
    @State private var recipeToDelete: Recipe?
    @State private var customRecipeMessage: String?
    @State private var selectedRecipeID: Recipe.ID? = nil
    @State private var quickLookRecipe: Recipe? = nil
    @State private var gridWidth: Double = 0
    @FocusState private var isSearchFocused: Bool
    @FocusState private var isGridFocused: Bool

    private var columnCount: Int {
        GridNavigation.columnCount(width: gridWidth, minimum: 330, spacing: 14)
    }

    // Expanded cards can be substantially taller than the compact cards.
    // Top-align each grid cell so adjacent cards do not float in the
    // middle of the selected recipe's detail area.
    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(maximum: 560), spacing: 14, alignment: .top),
            count: columnCount
        )
    }

    public var onNavigateToCamera: (() -> Void)? = nil
    /// Set by Find Recipes… before this view may exist.
    @Binding private var isSearchFocusPending: Bool

    public init(
        store: RecipeStore,
        cameraManager: CameraManager,
        isSearchFocusPending: Binding<Bool> = .constant(false),
        onNavigateToCamera: (() -> Void)? = nil
    ) {
        self.store = store
        self.cameraManager = cameraManager
        self._isSearchFocusPending = isSearchFocusPending
        self.onNavigateToCamera = onNavigateToCamera
    }

    public var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerControlBar

                    filterAndSortBar

                    quickDialBar

                    if store.loadingState == .loading {
                        recipeLoadingState
                    } else if store.loadingState == .failed {
                        emptyState
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }

                    // Stays mounted while recipes load so it keeps keyboard focus.
                    LazyVGrid(columns: columns, spacing: 14) {
                        ForEach(store.filteredRecipes) { recipe in
                            RecipeCard(
                                recipe: recipe,
                                isExpanded: expandedRecipeIDs.contains(recipe.id),
                                isSelected: selectedRecipeID == recipe.id,
                                favorites: store.favorites,
                                loadouts: store.loadouts,
                                isCustomRecipe: store.isCustomRecipe(recipe),
                                onSelect: {
                                    select(recipe)
                                },
                                onQuickLook: {
                                    select(recipe)
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                                        quickLookRecipe = recipe
                                    }
                                },
                                onToggleExpand: {
                                    select(recipe)
                                    withAnimation(.spring(response: 0.34, dampingFraction: 0.8)) {
                                        if expandedRecipeIDs.contains(recipe.id) {
                                            expandedRecipeIDs.remove(recipe.id)
                                        } else {
                                            expandedRecipeIDs.insert(recipe.id)
                                        }
                                    }
                                },
                                onQuickLoadToSlot: { slot in
                                    Task {
                                        await load(recipe, into: slot)
                                    }
                                },
                                onLoadToSlot: {
                                    recipeToLoad = recipe
                                },
                                onSelectPhoto: { url in
                                    selectedPhotoUrl = url
                                },
                                onEdit: {
                                    recipeToEdit = recipe
                                },
                                onDelete: {
                                    recipeToDelete = recipe
                                },
                                onDuplicate: {
                                    select(recipe)
                                    recipeToEdit = store.customRecipes.uniquelyNamedCopy(of: recipe)
                                }
                            )
                            .id(recipe.id)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .scale(scale: 0.94)).combined(with: .offset(y: 10)),
                                removal: .opacity.combined(with: .scale(scale: 0.96))
                            ))
                        }
                    }
                    .animation(.spring(response: 0.32, dampingFraction: 0.8), value: store.filteredRecipes.map(\.id))
                    .frame(maxWidth: .infinity)
                    .onGeometryChange(for: Double.self) { $0.size.width } action: { gridWidth = $0 }
                    .focusable()
                    .focusEffectDisabled()
                    .focused($isGridFocused)
                    .onKeyPress { press in
                        guard let move = GridNavigation.Move(key: press.key) else { return .ignored }
                        return moveSelection(move, scrollProxy: scrollProxy)
                    }
                    .onKeyPress(.space) {
                        toggleQuickLook()
                        return .handled
                    }
                    .onKeyPress(.escape) {
                        guard quickLookRecipe != nil else { return .ignored }
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            quickLookRecipe = nil
                        }
                        return .handled
                    }

                    if store.filteredRecipes.isEmpty && store.loadingState != .failed && store.loadingState != .loading {
                        emptyState
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .padding(16)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.filteredRecipes.isEmpty)
            }
        }
        .navigationTitle("Fuji Recipes Studio")
        .searchable(text: $store.searchQuery, placement: .toolbar, prompt: "Search recipes, film sims, Kelvin, tags…")
        .modifier(SearchFocusModifier(isSearchFocused: $isSearchFocused))
        .onAppear {
            if !focusSearchIfRequested() {
                isGridFocused = true
            }
        }
        .onChange(of: isSearchFocusPending) {
            focusSearchIfRequested()
        }
        .onChange(of: activeHUDToast) { _, toast in
            if let toast {
                AccessibilityNotification.Announcement("\(toast.title). \(toast.message)").post()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: MacAppCommand.showToast)) { notification in
            guard
                let title = notification.userInfo?[MacAppCommand.toastTitleKey] as? String,
                let message = notification.userInfo?[MacAppCommand.toastMessageKey] as? String
            else { return }
            let isError = notification.userInfo?[MacAppCommand.toastIsErrorKey] as? Bool ?? false
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                activeHUDToast = HUDToast(title: title, message: message, isError: isError)
            }
            if !isError {
                dismissToast(activeHUDToast, after: .seconds(3))
            }
        }
        .sheet(item: $recipeToLoad) { recipe in
            CSlotPickerSheet(
                recipe: recipe,
                loadouts: store.loadouts,
                isCameraConnected: cameraManager.status == .connected
            ) { slot in
                recipeToLoad = nil
                Task {
                    await load(recipe, into: slot)
                }
            }
        }
        .alert("Custom Recipe Library", isPresented: Binding(
            get: { customRecipeMessage != nil },
            set: { if !$0 { customRecipeMessage = nil } }
        )) {
            Button("OK") { customRecipeMessage = nil }
        } message: {
            Text(customRecipeMessage ?? "")
        }
        .confirmationDialog(
            "Delete Custom Recipe?",
            isPresented: Binding(
                get: { recipeToDelete != nil },
                set: { if !$0 { recipeToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Recipe", role: .destructive) {
                if let recipe = recipeToDelete {
                    let visible = store.filteredRecipes
                    do {
                        try store.customRecipes.delete(id: recipe.id)
                        store.favorites.removeFavorite(recipe.id)
                        if selectedRecipeID == recipe.id {
                            let remaining = visible.filter { $0.id != recipe.id }
                            if let index = visible.firstIndex(where: { $0.id == recipe.id }), !remaining.isEmpty {
                                selectedRecipeID = remaining[min(index, remaining.count - 1)].id
                            } else {
                                selectedRecipeID = nil
                            }
                        }
                    } catch {
                        customRecipeMessage = error.localizedDescription
                    }
                }
                recipeToDelete = nil
            }
            Button("Cancel", role: .cancel) { recipeToDelete = nil }
        } message: {
            Text(recipeToDelete.map { "“\($0.name)” will be removed from My Recipes." } ?? "")
        }
        .confirmationDialog(
            pendingStageTop.map { "Replace Local Draft\($0.replacedSlots.count == 1 ? "" : "s") in \($0.replacedSlotList)?" } ?? "",
            isPresented: Binding(
                get: { pendingStageTop != nil },
                set: { if !$0 { pendingStageTop = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingStageTop
        ) { pending in
            Button("Replace Draft\(pending.replacedSlots.count == 1 ? "" : "s")", role: .destructive) {
                stageToDial(pending.recipes)
            }
            Button("Cancel", role: .cancel) {}
        } message: { pending in
            Text("Stage Top \(pending.recipes.count) replaces your unsynced draft\(pending.replacedSlots.count == 1 ? "" : "s") in \(pending.replacedSlotList) with the top filtered recipe\(pending.recipes.count == 1 ? "" : "s"). The camera isn’t changed.")
        }
        .sheet(item: $recipeToEdit) { recipe in
            CustomRecipeEditor(
                recipe: recipe,
                existingRecipes: store.customRecipes.recipes
            ) { edited in
                do {
                    try store.customRecipes.save(edited)
                    recipeToEdit = nil
                } catch {
                    customRecipeMessage = error.localizedDescription
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { selectedPhotoUrl != nil },
            set: { if !$0 { selectedPhotoUrl = nil } }
        )) {
            if let urlStr = selectedPhotoUrl, let url = URL(string: urlStr) {
                PhotoLightboxView(imageUrl: url, isPresented: Binding(
                    get: { selectedPhotoUrl != nil },
                    set: { if !$0 { selectedPhotoUrl = nil } }
                ))
            }
        }
        .overlay {
            if let recipe = quickLookRecipe {
                RecipeQuickLookView(
                    recipe: recipe,
                    isFavorite: store.favorites.isFavorite(recipe.id),
                    loadouts: store.loadouts,
                    isCameraConnected: cameraManager.status == .connected,
                    onToggleFavorite: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            store.favorites.toggleFavorite(for: recipe.id)
                        }
                    },
                    onDismiss: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            quickLookRecipe = nil
                        }
                    },
                    onStageToSlot: { slot in
                        Task {
                            await load(recipe, into: slot)
                        }
                    },
                    onSelectPhoto: { url in
                        selectedPhotoUrl = url
                    },
                    onDuplicate: {
                        let duplicated = store.customRecipes.uniquelyNamedCopy(of: recipe)
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            quickLookRecipe = nil
                        }
                        recipeToEdit = duplicated
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .animation(.spring(response: 0.28, dampingFraction: 0.8), value: quickLookRecipe?.id)
            }
        }
        .overlay(alignment: .bottom) {
            if let toast = activeHUDToast {
                HStack(spacing: 12) {
                    Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(toast.isError ? Theme.fujiAmber : Theme.emeraldGreen)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(toast.title)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white)
                        Text(toast.message)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(2)
                    }

                    Spacer(minLength: 12)

                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            activeHUDToast = nil
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(6)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Dismiss message")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor).opacity(0.95))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(toast.isError ? Theme.fujiAmber.opacity(0.5) : Theme.emeraldGreen.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.45), radius: 18, y: 6)
                )
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .opacity.combined(with: .scale(scale: 0.95))
                ))
            }
        }
    }

    private func toggleQuickLook() {
        if quickLookRecipe != nil {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                quickLookRecipe = nil
            }
        } else {
            let target = store.filteredRecipes.first(where: { $0.id == selectedRecipeID })
                ?? store.filteredRecipes.first
            if let target {
                selectedRecipeID = target.id
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    quickLookRecipe = target
                }
            }
        }
    }

    private func select(_ recipe: Recipe) {
        selectedRecipeID = recipe.id
        isGridFocused = true
    }

    private func moveSelection(_ move: GridNavigation.Move, scrollProxy: ScrollViewProxy) -> KeyPress.Result {
        let recipes = store.filteredRecipes
        guard !recipes.isEmpty else { return .ignored }
        let target = recipes.firstIndex(where: { $0.id == selectedRecipeID })
            .map { recipes[GridNavigation.index(from: $0, move: move, count: recipes.count, columns: columnCount)] }
            ?? recipes[0]
        selectedRecipeID = target.id
        if quickLookRecipe != nil {
            quickLookRecipe = target
        }
        withAnimation(.easeOut(duration: 0.2)) {
            scrollProxy.scrollTo(target.id)
        }
        return .handled
    }

    @discardableResult
    private func focusSearchIfRequested() -> Bool {
        guard isSearchFocusPending else { return false }
        isSearchFocusPending = false
        focusSearchField()
        return true
    }

    private func focusSearchField() {
        if #available(macOS 15.0, *) {
            isSearchFocused = true
        } else {
            DispatchQueue.main.async {
                if let window = NSApp.keyWindow ?? NSApp.mainWindow,
                   let searchField = window.findSearchField() {
                    window.makeFirstResponder(searchField)
                }
            }
        }
    }

    @MainActor
    private func load(_ recipe: Recipe, into slot: Int) async {
        if cameraManager.status == .connected {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                activeHUDToast = HUDToast(
                    title: "Syncing to C\(slot)…",
                    message: "Writing \"\(recipe.name)\" to camera…",
                    isError: false
                )
            }
            do {
                let result = try await cameraManager.importRecipeToCState(recipe, slot: slot, updating: store.loadouts)
                guard result.observedSnapshot?.slot == slot else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        activeHUDToast = HUDToast(
                            title: "C\(slot) Sync Incomplete",
                            message: "\"\(recipe.name)\" was sent, but post-write readback was unavailable.",
                            isError: true
                        )
                    }
                    return
                }
                let verified = result.isVerified
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    activeHUDToast = HUDToast(
                        title: verified ? "✓ Synced to C\(slot)" : "C\(slot) Differs from \"\(recipe.name)\"",
                        message: result.summary,
                        isError: !verified
                    )
                }
                if verified {
                    dismissToast(activeHUDToast, after: .seconds(4))
                }
            } catch let recoveryError as PTPPresetSlotWriteRecoveryError {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    activeHUDToast = HUDToast(
                        title: "C\(slot) Write Error",
                        message: cSlotWriteFailureMessage(recoveryError),
                        isError: true
                    )
                }
            } catch {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                    activeHUDToast = HUDToast(
                        title: "C\(slot) Error",
                        message: error.localizedDescription,
                        isError: true
                    )
                }
            }
        } else {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                store.loadouts.applyRecipe(recipe, to: slot)
                activeHUDToast = HUDToast(
                    title: "Saved to Local C\(slot)",
                    message: "\"\(recipe.name)\" saved as local draft. Connect camera to sync.",
                    isError: false
                )
            }
            dismissToast(activeHUDToast, after: .seconds(3))
        }
    }

    private func dismissToast(_ toast: HUDToast?, after delay: Duration) {
        guard let id = toast?.id else { return }
        Task {
            try? await Task.sleep(for: delay)
            guard activeHUDToast?.id == id else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                activeHUDToast = nil
            }
        }
    }

    private func stageTop7ToDial() {
        let recipes = Array(store.filteredRecipes.prefix(7))
        guard !recipes.isEmpty else { return }
        let replaced = store.loadouts.stagedSlots.filter { $0 <= recipes.count }
        if replaced.isEmpty {
            stageToDial(recipes)
        } else {
            pendingStageTop = PendingStageTop(recipes: recipes, replacedSlots: replaced)
        }
    }

    private func stageToDial(_ recipes: [Recipe]) {
        store.loadouts.stageAll(recipes: recipes)
        let count = recipes.count
        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
            activeHUDToast = HUDToast(
                title: count == 1 ? "✓ Staged 1 Recipe to Dial" : "✓ Staged Top \(count) to Dial",
                message: count == 1
                    ? "Assigned it to slot C1. Ready to write in Camera & Staging."
                    : "Assigned recipes to slots C1–C\(count). Ready to write in Camera & Staging.",
                isError: false
            )
        }
        dismissToast(activeHUDToast, after: .seconds(3))
    }

    private func cSlotWriteFailureMessage(_ error: PTPPresetSlotWriteRecoveryError) -> String {
        let failure: String
        switch error.failurePhase {
        case .write:
            failure = "Camera slot C\(error.slot) write failed before post-write verification"
        case .postWriteVerification:
            failure = "Camera slot C\(error.slot) write completed, but post-write verification failed"
        }
        let recovery: String
        switch error.rollback {
        case .restored:
            recovery = "The previous camera settings were restored."
        case .notAttemptedEmptySentinel:
            recovery = "The camera slot was previously empty, so there were no settings to restore."
        case .failed(let message):
            recovery = "Recovery could not restore the previous camera settings: \(message)"
        case .notNeeded:
            recovery = "No recovery was required."
        }
        return "\(failure): \(error.writeErrorDescription). \(recovery)"
    }

    private var headerControlBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    headerTextCluster
                    Spacer(minLength: 12)
                    topActionButtons
                }
                VStack(alignment: .leading, spacing: 8) {
                    headerTextCluster
                    topActionButtons
                }
            }

            HStack {
                customRecipeLibraryMenu
                Spacer()
                headerFilterToggle
            }
        }
        .glassPanel(padding: 14, radius: Glass.panelRadius, accentColor: Theme.fujiAmber)
    }

    private var topActionButtons: some View {
        HStack(spacing: 8) {
            // Batch button: Stage Top 7 to Dial
            Button {
                stageTop7ToDial()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "dial.low.fill")
                        .font(.system(size: 11, weight: .bold))
                    Text("Stage Top 7 to Dial")
                        .font(.system(size: 11, weight: .bold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Theme.fujiAmber.opacity(0.18))
                )
                .overlay(
                    Capsule()
                        .stroke(Theme.fujiAmber.opacity(0.55), lineWidth: 1)
                )
                .foregroundStyle(Theme.fujiAmber)
            }
            .buttonStyle(.plain)
            .disabled(store.filteredRecipes.isEmpty)
            .help("Auto-fills dial slots C1–C7 with the top filtered recipes in 1 click")
            .accessibilityIdentifier("stage-top-7-button")

            // View Camera & Staging button
            if let onNavigateToCamera {
                Button {
                    onNavigateToCamera()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("View Camera & Staging")
                            .font(.system(size: 11, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )
                    .foregroundStyle(Color.white)
                }
                .buttonStyle(.plain)
                .help("Jump directly to Camera & Staging")
                .accessibilityIdentifier("view-camera-staging-button")
            }
        }
    }

    private var customRecipeLibraryMenu: some View {
        Menu {
            Button("New Recipe") {
                recipeToEdit = CustomRecipeEditor.newRecipe()
            }
            .accessibilityIdentifier("custom-recipe-new")
            Divider()
            Button("Import Library…") {
                importCustomRecipes()
            }
            .accessibilityIdentifier("custom-recipe-import")
            Button("Export Library…") {
                exportCustomRecipes()
            }
            .accessibilityIdentifier("custom-recipe-export")
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 11, weight: .semibold))
                Text("My Recipes (\(store.customRecipes.recipes.count))")
                    .font(.caption.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Capsule().fill(Color.white.opacity(0.05)))
            .overlay(Capsule().stroke(Theme.specularBorder, lineWidth: 0.8))
        }
        .menuStyle(.borderlessButton)
        .accessibilityIdentifier("custom-recipe-library-menu")
    }

    private func importCustomRecipes() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let count = try store.customRecipes.import(Data(contentsOf: url))
            customRecipeMessage = "Imported \(count) recipe\(count == 1 ? "" : "s") into My Recipes."
        } catch {
            customRecipeMessage = error.localizedDescription
        }
    }

    private func exportCustomRecipes() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "fuji-custom-recipes-v1.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.customRecipes.exportData().write(to: url, options: .atomic)
            customRecipeMessage = "Exported \(store.customRecipes.recipes.count) recipe\(store.customRecipes.recipes.count == 1 ? "" : "s")."
        } catch {
            customRecipeMessage = "Couldn’t export My Recipes: \(error.localizedDescription)"
        }
    }

    private var headerTextCluster: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Text("Recipes Studio")
                    .font(.title2.weight(.bold))
                    .glassPrimary()
                    .lineLimit(1)

                Text("\(store.filteredRecipes.count) RECIPE\(store.filteredRecipes.count == 1 ? "" : "S")")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.fujiAmber)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Theme.fujiAmber.opacity(0.16))
                    .clipShape(Capsule())
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: store.filteredRecipes.count)
            }

            Text("Curated Fujifilm X100VI film simulation formulations & custom dial presets.")
                .font(.caption)
                .glassSecondary()
                .lineLimit(2)
        }
    }

    private var headerFilterToggle: some View {
        GlassPillToggle(
            options: [
                (value: Optional<RecipeStore.FilterCategory>.none, label: "All (\(store.recipes.count))"),
                (value: Optional<RecipeStore.FilterCategory>.some(.favorites), label: "★ Favorites (\(store.favorites.favoriteIDs.count))"),
                (value: Optional<RecipeStore.FilterCategory>.some(.myRecipes), label: "My Recipes (\(store.customRecipes.recipes.count))")
            ],
            selection: $store.selectedFilterCategory,
            accentColor: Theme.fujiAmber
        )
    }

    private var filterAndSortBar: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // Film Sim Family Quick Filters
                    ForEach(RecipeStore.FilmSimFamily.allCases) { family in
                        let isSelected = store.selectedFilmSimFamily == family
                        let accent = family == .all ? Theme.fujiAmber : Theme.filmSimColor(for: family.rawValue)
                        filterPill(
                            title: family.rawValue,
                            icon: family.icon,
                            isSelected: isSelected,
                            accent: accent
                        ) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                store.selectedFilmSimFamily = family
                            }
                        }
                    }

                    Divider()
                        .frame(height: 16)
                        .overlay(Theme.specularBorder)

                    // DR Filter
                    ForEach(RecipeStore.DRFilter.allCases) { dr in
                        let isSelected = store.selectedDRFilter == dr
                        filterPill(
                            title: dr.rawValue,
                            isSelected: isSelected,
                            accent: Theme.emeraldGreen
                        ) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                store.selectedDRFilter = dr
                            }
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .trailingScrollFade()

            HStack(spacing: 8) {
                metadataFilterMenus

                // Sort Order Menu
                Menu {
                    ForEach(RecipeStore.SortOrder.allCases) { order in
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.78)) {
                                store.sortOrder = order
                            }
                        } label: {
                            HStack {
                                Text(order.rawValue)
                                if store.sortOrder == order {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: store.sortOrder.icon)
                            .font(.system(size: 11, weight: .semibold))
                        Text(store.sortOrder.rawValue)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8))
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule().fill(Color.white.opacity(0.07))
                    )
                    .overlay(
                        Capsule().stroke(Theme.specularBorder, lineWidth: 0.8)
                    )
                }
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
        }
    }

    private var metadataFilterMenus: some View {
        Group {
            Menu {
                Button("Any White Balance") { store.selectedWhiteBalance = nil }
                Divider()
                ForEach(store.availableWhiteBalances, id: \.rawValue) { whiteBalance in
                    Button {
                        store.selectedWhiteBalance = whiteBalance
                    } label: {
                        if store.selectedWhiteBalance == whiteBalance {
                            Label(whiteBalance.displayName, systemImage: "checkmark")
                        } else {
                            Text(whiteBalance.displayName)
                        }
                    }
                }
            } label: {
                filterMenuLabel(
                    title: store.selectedWhiteBalance?.displayName ?? "White Balance",
                    icon: "thermometer.medium",
                    isActive: store.selectedWhiteBalance != nil
                )
            }

            if !store.availableKeywords.isEmpty {
                Menu {
                    Button("Any Source Keyword") { store.selectedKeyword = nil }
                    Divider()
                    ForEach(store.availableKeywords) { keyword in
                        Button {
                            store.selectedKeyword = keyword.name
                        } label: {
                            HStack {
                                Text(keyword.name)
                                Text("\(keyword.count)")
                            }
                        }
                    }
                } label: {
                    filterMenuLabel(
                        title: store.selectedKeyword ?? "Keywords",
                        icon: "tag",
                        isActive: store.selectedKeyword != nil
                    )
                }
            }
        }
    }

    private func filterPill(
        title: String,
        icon: String? = nil,
        isSelected: Bool,
        accent: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.black : Theme.textSecondary)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Capsule().fill(isSelected ? accent : Color.white.opacity(0.05)))
            .overlay(Capsule().stroke(isSelected ? accent : Theme.specularBorder, lineWidth: 0.8))
            .shadow(color: isSelected ? accent.opacity(0.35) : Color.clear, radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: isSelected)
    }

    private func filterMenuLabel(title: String, icon: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .font(.caption.weight(isActive ? .semibold : .medium))
                .lineLimit(1)
                .frame(maxWidth: 120)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .bold))
        }
        .foregroundStyle(isActive ? Color.black : Theme.textSecondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(isActive ? Theme.fujiAmber : Color.white.opacity(0.04)))
        .overlay(Capsule().stroke(isActive ? Theme.fujiAmber : Theme.specularBorder, lineWidth: 0.8))
    }

    private var quickDialBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "dial.low.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.fujiAmber)
                Text("CAMERA DIAL")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.leading, 2)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(1...7, id: \.self) { slot in
                        let loadout = store.loadouts.loadout(for: slot)
                        GallerySlotPill(
                            slot: slot,
                            loadout: loadout,
                            isCameraConnected: cameraManager.status == .connected,
                            onDropRecipe: { recipe in
                                Task {
                                    await load(recipe, into: slot)
                                }
                            }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .trailingScrollFade()

            if let onNavigateToCamera {
                Button {
                    onNavigateToCamera()
                } label: {
                    HStack(spacing: 3) {
                        Text("Manage")
                            .font(.system(size: 9, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .foregroundStyle(Theme.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Manage camera staging and sync")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 1)
                )
        )
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 64, height: 64)
                Image(systemName: emptyIcon)
                    .font(.system(size: 28))
                    .foregroundStyle(Theme.fujiAmber.opacity(0.8))
                    .symbolEffect(.bounce, value: store.filteredRecipes.count)
            }

            VStack(spacing: 4) {
                Text(emptyTitle)
                    .font(.headline.weight(.semibold))
                    .glassPrimary()
                Text(emptyMessage)
                    .font(.caption)
                    .glassSecondary()
            }

            if store.loadingState == .failed {
                Button("Try Loading Recipes Again") {
                    Task { await store.loadRecipes() }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(GlassBorderedButtonStyle(accentColor: Theme.fujiAmber, height: 32))
                .frame(width: 220)
                .padding(.top, 6)
            } else if hasActiveFilters {
                Button("Reset Filters") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        store.searchQuery = ""
                        store.selectedFilmSimFamily = .all
                        store.selectedDRFilter = .all
                        store.selectedWhiteBalance = nil
                        store.selectedKeyword = nil
                    }
                }
                .buttonStyle(GlassBorderedButtonStyle(accentColor: Theme.fujiAmber, height: 32))
                .frame(width: 140)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
        .glassCard(tint: Color.white.opacity(0.02))
    }

    private var hasSearchText: Bool {
        !store.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var hasActiveFilters: Bool {
        hasSearchText
            || store.selectedFilmSimFamily != .all
            || store.selectedDRFilter != .all
            || store.selectedWhiteBalance != nil
            || store.selectedKeyword != nil
    }

    private var emptyIcon: String {
        if store.loadingState == .failed {
            return "film.stack"
        }
        if hasActiveFilters {
            return "magnifyingglass"
        }
        switch store.selectedFilterCategory {
        case .favorites: return "star.slash"
        case .myRecipes: return "folder.badge.minus"
        case nil: return "film.stack"
        }
    }

    private var emptyTitle: String {
        if store.loadingState == .failed {
            return "Couldn’t Load Recipes"
        }
        if hasActiveFilters {
            return "No matching recipes"
        }
        switch store.selectedFilterCategory {
        case .favorites: return "No favorites starred"
        case .myRecipes: return "No custom recipes yet"
        case nil: return "No recipes found"
        }
    }

    private var emptyMessage: String {
        if store.loadingState == .failed {
            return "The bundled recipe library could not be loaded. Try again or reinstall the app if this persists."
        }
        if hasSearchText {
            return "Try searching for a different film sim, Kelvin value, or tag."
        }
        if hasActiveFilters {
            return "No recipe matches every selected filter. Remove one or reset them all."
        }
        switch store.selectedFilterCategory {
        case .favorites:
            return "Click the star icon on any recipe to add it to your favorites."
        case .myRecipes:
            return "Create custom recipes or import a recipe collection from the My Recipes menu."
        case nil:
            return "The recipe library is empty."
        }
    }

    private var recipeLoadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.large)
                .tint(Theme.fujiAmber)
            Text("Loading recipe library…")
                .font(.headline.weight(.semibold))
                .glassPrimary()
            Text("Preparing your local Fujifilm recipe collection.")
                .font(.caption)
                .glassSecondary()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 70)
        .glassCard(tint: Color.white.opacity(0.02))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Loading recipe library")
    }
}

// MARK: - Keyboard and Scroll Row Helpers

extension GridNavigation.Move {
    init?(key: KeyEquivalent) {
        switch key {
        case .leftArrow: self = .left
        case .rightArrow: self = .right
        case .upArrow: self = .up
        case .downArrow: self = .down
        default: return nil
        }
    }
}

private extension ScrollView {
    func trailingScrollFade() -> some View {
        let width: CGFloat = 24
        return contentMargins(.trailing, width, for: .scrollContent)
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: width)
                }
            }
    }
}

// MARK: - Search Focus Helpers

private struct SearchFocusModifier: ViewModifier {
    @FocusState.Binding var isSearchFocused: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.searchFocused($isSearchFocused)
        } else {
            content
        }
    }
}

private extension NSWindow {
    /// The toolbar search field lives beside `contentView`, under the
    /// window's frame view, so the search starts one level up.
    func findSearchField() -> NSSearchField? {
        (contentView?.superview ?? contentView)?.findSearchField()
    }
}

private extension NSView {
    func findSearchField() -> NSSearchField? {
        if let searchField = self as? NSSearchField {
            return searchField
        }
        for subview in subviews {
            if let found = subview.findSearchField() {
                return found
            }
        }
        return nil
    }
}

private struct CSlotPickerSheet: View {
    let recipe: Recipe
    @ObservedObject var loadouts: LoadoutStore
    let isCameraConnected: Bool
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @FocusState private var focusedSlot: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "dial.low.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.fujiAmber)
                    .frame(width: 38, height: 38)
                    .background(Theme.fujiAmber.opacity(0.14), in: Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text("Send to Dial")
                        .font(.title2.weight(.bold))
                    Text(recipe.name)
                        .font(.headline)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
            }

            Text(isCameraConnected
                ? "Choose a physical C1–C7 slot. The recipe is written and verified on the connected camera before this app confirms success."
                : "Choose a local C1–C7 draft. It will not change the camera until you connect and write it.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(
                    isCameraConnected
                        ? "c-slot-picker-camera-write-notice"
                        : "c-slot-picker-local-draft-notice"
                )

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(1...7, id: \.self) { slot in
                    slotButton(slot)
                }
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(24)
        .frame(minWidth: 520, idealWidth: 520, maxWidth: 520, minHeight: 570, idealHeight: 570)
        .defaultFocus($focusedSlot, 1)
    }

    private func slotButton(_ slot: Int) -> some View {
        let loadout = loadouts.loadout(for: slot)
        let destination: String
        if isCameraConnected {
            destination = loadouts.isCameraSlotEmpty(slot)
                ? "Camera last read as empty"
                : "Write and verify on camera"
        } else if let name = loadout?.contentName {
            destination = "Local draft: \(name)"
        } else {
            destination = "No local draft"
        }

        return Button {
            onSelect(slot)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("C\(slot)")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Image(systemName: isCameraConnected ? "camera.fill" : "internaldrive")
                        .font(.caption.weight(.semibold))
                }
                Text(destination)
                    .font(.caption)
                    .lineLimit(1)
                Text(isCameraConnected ? "Write & verify" : "Save locally")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isCameraConnected ? Theme.emeraldGreen : Theme.fujiAmber)
            }
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .padding(10)
        }
        .buttonStyle(GlassBorderedButtonStyle(
            accentColor: isCameraConnected ? Theme.emeraldGreen : Theme.fujiAmber,
            height: 96
        ))
        .accessibilityLabel("Select C\(slot), \(destination)")
        .accessibilityHint(isCameraConnected
            ? "Writes and verifies \(recipe.name) on C\(slot)."
            : "Saves \(recipe.name) as a local C\(slot) draft.")
        .help(isCameraConnected
            ? "Write \(recipe.name) to physical slot C\(slot) and verify it"
            : "Save \(recipe.name) locally to C\(slot)")
        .accessibilityIdentifier("send-to-dial-slot-\(slot)")
        .focused($focusedSlot, equals: slot)
    }
}

// MARK: - Quick Dial Bar Slot Pill

private struct GallerySlotPill: View {
    let slot: Int
    let loadout: Loadout?
    let isCameraConnected: Bool
    let onDropRecipe: (Recipe) -> Void

    @State private var isTargeted = false

    private var accent: Color { slotAccent(slot) }
    private var isFilled: Bool { loadout?.hasAnySettings ?? false }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(isTargeted ? Theme.fujiAmber : (isFilled ? accent : Color.white.opacity(0.2)))
                .frame(width: 7, height: 7)
                .shadow(color: (isTargeted || isFilled) ? (isTargeted ? Theme.fujiAmber : accent).opacity(0.7) : Color.clear, radius: 3)

            Text("C\(slot)")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(isTargeted ? Theme.fujiAmber : (isFilled ? Color.white : Theme.textTertiary))

            if let name = loadout?.contentName {
                Text(name)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 85)
            } else {
                Text("Empty")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isTargeted ? Theme.fujiAmber.opacity(0.2) : (isFilled ? Color.white.opacity(0.06) : Color.white.opacity(0.02)))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(isTargeted ? Theme.fujiAmber : (isFilled ? accent.opacity(0.4) : Color.white.opacity(0.06)), lineWidth: 1)
                )
        )
        .scaleEffect(isTargeted ? 1.06 : 1.0)
        .animation(.spring(response: 0.22, dampingFraction: 0.78), value: isTargeted)
        .dropDestination(for: Recipe.self) { items, _ in
            guard let recipe = items.first else { return false }
            onDropRecipe(recipe)
            return true
        } isTargeted: { targeted in
            isTargeted = targeted
        }
        .help("Drag a recipe here to load into C\(slot)")
    }
}

// MARK: - Ultra-Sleek Recipe Card

private struct RecipeCard: View {
    let recipe: Recipe
    let isExpanded: Bool
    var isSelected: Bool = false
    @ObservedObject var favorites: FavoritesStore
    let loadouts: LoadoutStore
    let isCustomRecipe: Bool
    var onSelect: (() -> Void)? = nil
    var onQuickLook: (() -> Void)? = nil
    let onToggleExpand: () -> Void
    let onQuickLoadToSlot: (Int) -> Void
    let onLoadToSlot: () -> Void
    let onSelectPhoto: (String) -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onDuplicate: () -> Void

    @State private var isHovered = false

    private var isFavorite: Bool {
        favorites.isFavorite(recipe.id)
    }

    private var simName: String {
        recipe.filmSimulation?.displayName ?? recipe.settings?["filmSimulation"] ?? "Custom Sim"
    }

    private var accent: Color {
        Theme.filmSimColor(for: simName)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Main Card Header
            headerWithActions

            // Expanded Recipe Formula & Details
            if isExpanded {
                expandedContent
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .top)),
                        removal: .opacity.combined(with: .scale(scale: 0.98))
                    ))
            }
        }
        .glassCard(
            padding: 0,
            radius: Glass.cardRadius,
            tint: isSelected ? Theme.fujiAmber.opacity(0.12) : (isHovered ? Color.white.opacity(0.07) : Theme.glassPanelBg),
            borderColor: isSelected ? Theme.fujiAmber.opacity(0.85) : (isHovered ? accent.opacity(0.45) : nil)
        )
        .overlay(
            // Top Accent Color Ribbon & Selection Ring
            RoundedRectangle(cornerRadius: Glass.cardRadius, style: .continuous)
                .stroke(
                    isSelected ? Theme.fujiAmber.opacity(0.9) : (isHovered ? accent.opacity(0.7) : Color.white.opacity(0.08)),
                    lineWidth: isSelected ? 1.8 : 1.0
                )
                .allowsHitTesting(false)
        )
        .scaleEffect(isHovered ? 1.012 : 1.0)
        .shadow(color: isHovered ? accent.opacity(0.18) : (isSelected ? Theme.fujiAmber.opacity(0.15) : Color.clear), radius: 14, y: 6)
        .animation(.spring(response: 0.26, dampingFraction: 0.76), value: isHovered)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: isExpanded)
        .animation(.spring(response: 0.26, dampingFraction: 0.76), value: isSelected)
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onSelect?()
                onQuickLook?()
            }
        )
        .onHover { isHovered = $0 }
        .draggable(recipe) {
            RecipeDragPreview(recipe: recipe)
        }
        .contextMenu {
            Button("Quick Look Formula (Spacebar)") {
                onSelect?()
                onQuickLook?()
            }
            .keyboardShortcut(.space, modifiers: [])

            Divider()

            Button {
                onDuplicate()
            } label: {
                Label("Duplicate to My Recipes", systemImage: "plus.square.on.square")
            }
            .accessibilityIdentifier("recipe-duplicate-menu-\(recipe.id)")

            Divider()

            Section("Stage to Camera Dial Slot") {
                ForEach(1...7, id: \.self) { slot in
                    let slotName = loadouts.loadout(for: slot)?.contentName ?? "Empty"
                    Button {
                        onQuickLoadToSlot(slot)
                    } label: {
                        Label("Stage to C\(slot) (\(slotName))", systemImage: "dial.low.fill")
                    }
                }
            }
            Divider()
            Button(isFavorite ? "Remove from Favorites" : "Add to Favorites") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                    favorites.toggleFavorite(for: recipe.id)
                }
            }
            if isCustomRecipe {
                Divider()
                Button("Edit Recipe…", action: onEdit)
                Button("Delete Recipe", role: .destructive, action: onDelete)
            }
        }
    }

    private var headerWithActions: some View {
        HStack(alignment: .top, spacing: 12) {
            // Recipe Thumbnail (clean, completely unobstructed)
            previewThumbnail
                .onTapGesture {
                    onSelect?()
                    onToggleExpand()
                }

            // Recipe Details (Tappable to expand formula)
            VStack(alignment: .leading, spacing: 4) {
                // Film Sim Badge + Dynamic Range Chip + Custom Recipe Tag
                HStack(spacing: 5) {
                    FilmSimBadge(name: simName, isCompact: true)

                    if isCustomRecipe {
                        Text("MY RECIPE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.fujiAmber)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.fujiAmber.opacity(0.16))
                            .clipShape(Capsule())
                    }

                    if let dr = recipe.dynamicRange {
                        Text(dr.badgeLabel)
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.emeraldGreen)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.emeraldGreen.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                // Recipe Title
                Text(recipe.name)
                    .font(.system(size: 14, weight: .bold))
                    .glassPrimary()
                    .lineLimit(2)
                    .minimumScaleFactor(0.88)

                // Tone Curve Radar & Kelvin Swatch
                toneAndKelvinCluster
            }
            .contentShape(Rectangle())
            .onTapGesture {
                onSelect?()
                onToggleExpand()
            }

            Spacer(minLength: 4)

            // Dedicated Card Actions Column (Clean, never collides with thumbnail or text!)
            VStack(alignment: .trailing, spacing: 8) {
                // "Stage to C1–C7 ▾" Clean Menu Button
                Menu {
                    Section("Stage to Camera Dial Slot") {
                        ForEach(1...7, id: \.self) { slot in
                            let slotName = loadouts.loadout(for: slot)?.contentName ?? "Empty"
                            Button {
                                onQuickLoadToSlot(slot)
                            } label: {
                                Label("Stage to C\(slot): \(slotName)", systemImage: "dial.low.fill")
                            }
                            .accessibilityIdentifier("send-to-dial-slot-\(slot)")
                        }
                    }
                    Divider()
                    Button("Slot Matrix / Options…") {
                        onLoadToSlot()
                    }
                    .accessibilityIdentifier("open-slot-matrix-\(recipe.id)")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "dial.low.fill")
                            .font(.system(size: 10, weight: .bold))
                        Text("Stage ▾")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(isHovered ? Theme.fujiAmber.opacity(0.24) : Color.white.opacity(0.08))
                    )
                    .overlay(
                        Capsule()
                            .stroke(isHovered ? Theme.fujiAmber.opacity(0.55) : Color.white.opacity(0.14), lineWidth: 1)
                    )
                    .foregroundStyle(isHovered ? Theme.fujiAmber : Color.white)
                }
                .menuStyle(.borderlessButton)
                .help("Stage \"\(recipe.name)\" to custom dial slot (C1–C7)")
                .accessibilityIdentifier("send-to-dial-\(recipe.id)")

                HStack(spacing: 8) {
                    // Duplicate to My Recipes Button
                    Button {
                        onDuplicate()
                    } label: {
                        Label("Duplicate to My Recipes", systemImage: "plus.square.on.square")
                    }
                    .labelStyle(.iconOnly)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isHovered ? Theme.textPrimary : Theme.textTertiary)
                    .padding(6)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.06))
                    )
                    .buttonStyle(.plain)
                    .help("Duplicate & Customize recipe formula into My Recipes")
                    .accessibilityLabel("Duplicate to My Recipes")
                    .accessibilityIdentifier("recipe-duplicate-\(recipe.id)")

                    // Quick Look eye button
                    Button(action: {
                        onSelect?()
                        onQuickLook?()
                    }) {
                        Image(systemName: "eye")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isHovered ? Theme.textPrimary : Theme.textTertiary)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Quick Look recipe formula (Spacebar or double-click)")
                    .accessibilityLabel("Quick Look \(recipe.name)")
                    .accessibilityIdentifier("recipe-quick-look-\(recipe.id)")

                    // Favorite star button
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                            favorites.toggleFavorite(for: recipe.id)
                        }
                    }) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isFavorite ? Theme.warmGold : Theme.textTertiary)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(isFavorite ? Theme.warmGold.opacity(0.18) : Color.white.opacity(0.06))
                            )
                            .symbolEffect(.bounce, value: isFavorite)
                    }
                    .buttonStyle(.plain)
                    .help(isFavorite ? "Remove favorite" : "Add to favorites")
                    .accessibilityLabel(isFavorite ? "Remove \(recipe.name) from favorites" : "Add \(recipe.name) to favorites")

                    // Expand / Collapse Chevron Button
                    Button(action: onToggleExpand) {
                        Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(isExpanded ? Theme.textPrimary : (isHovered ? Theme.textSecondary : Theme.textTertiary))
                            .animation(.spring(response: 0.28, dampingFraction: 0.75), value: isExpanded)
                    }
                    .buttonStyle(.plain)
                    .help(isExpanded ? "Collapse recipe formula" : "Expand recipe formula")
                    .accessibilityLabel(isExpanded ? "Collapse \(recipe.name) formula" : "Expand \(recipe.name) formula")
                }
            }
        }
        .padding(12)
        .frame(minHeight: 104)
    }

    private var previewThumbnail: some View {
        Group {
            if let urlString = recipe.previewImageUrl ?? recipe.imageUrls.first,
               let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        thumbnailPlaceholder
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    case .failure:
                        thumbnailPlaceholder
                    @unknown default:
                        thumbnailPlaceholder
                    }
                }
            } else {
                thumbnailPlaceholder
            }
        }
        .frame(width: 72, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 6, y: 3)
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [accent.opacity(0.2), Color.white.opacity(0.04)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                Image(systemName: "film")
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(accent.opacity(0.7))
            )
    }

    private var toneAndKelvinCluster: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                radarView
                kelvinView
            }
            VStack(alignment: .leading, spacing: 4) {
                radarView
                kelvinView
            }
        }
        .padding(.top, 2)
    }

    private var radarView: some View {
        ToneCurveRadar(tones: recipe.toneTenths, accentColor: accent)
    }

    private var kelvinView: some View {
        KelvinChip(
            kelvin: recipe.colorTempK,
            modeName: recipe.whiteBalanceMode?.displayName ?? recipe.settings?["whiteBalance"]
        )
    }

    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider()
                .overlay(Theme.specularBorder)
                .padding(.horizontal, 12)

            // Sample Photos Carousel
            if !recipe.imageUrls.isEmpty {
                samplePhotosSection
            }

            // Recipe Camera Menu Formula Grid
            provenanceSection

            formulaGridSection

            // Actions & Links
            Group {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        sourceLink
                        Spacer(minLength: 8)
                        sendToDialButton
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        sourceLink
                        sendToDialButton
                            .frame(maxWidth: .infinity)
                    }
                }
                HStack(spacing: 8) {
                    Button {
                        onDuplicate()
                    } label: {
                        Label("Duplicate to My Recipes", systemImage: "plus.square.on.square")
                    }
                    .buttonStyle(GlassBorderedButtonStyle(accentColor: Theme.fujiAmber, height: 26))
                    .accessibilityIdentifier("recipe-duplicate-expanded-\(recipe.id)")

                    if isCustomRecipe {
                        Button("Edit", action: onEdit)
                            .accessibilityIdentifier("custom-recipe-edit-\(recipe.id)")
                        Button("Delete", role: .destructive, action: onDelete)
                            .accessibilityIdentifier("custom-recipe-delete-\(recipe.id)")
                    }
                }
                .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var sourceLink: some View {
        if let sourceUrl = recipe.sourceUrl, let url = URL(string: sourceUrl) {
            Link(destination: url) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.right.square")
                    Text("Recipe Guide")
                }
                .font(.caption.weight(.medium))
                .lineLimit(1)
            }
            .buttonStyle(.link)
        }
    }

    private var sendToDialButton: some View {
        Button(action: onLoadToSlot) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.right.circle.fill")
                Text("Send to Dial (C1–C7)")
            }
            .font(.caption.weight(.semibold))
            .lineLimit(1)
        }
        .buttonStyle(GlassBorderedButtonStyle(accentColor: Theme.fujiAmber, height: 28))
        .accessibilityIdentifier("send-to-dial-expanded-\(recipe.id)")
    }

    private var samplePhotosSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("SAMPLE SHOTS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Text("CLICK TO ZOOM")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 12)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(recipe.imageUrls.prefix(8), id: \.self) { urlString in
                        if let url = URL(string: urlString) {
                            SampleThumbnailButton(urlString: urlString, url: url, onSelect: onSelectPhoto)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }
        }
    }

    private var formulaGridSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CAMERA PARAMETER FORMULA")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 12)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 6)], spacing: 6) {
                ForEach(recipe.formulaSettingItems, id: \.label) { item in
                    HStack(spacing: 6) {
                        Text(item.label)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text(item.value)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.24))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.06), lineWidth: 0.6)
                    )
                }
            }
            .padding(.horizontal, 12)
        }
    }

    @ViewBuilder
    private var provenanceSection: some View {
        if recipe.dateString != nil || !recipe.source.isEmpty || !(recipe.tags ?? []).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("RECIPE NOTES")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)

                HStack(spacing: 6) {
                    if !recipe.source.isEmpty {
                        Label(recipe.source, systemImage: "book.closed")
                    }
                    if let date = recipe.dateString {
                        Label(date, systemImage: "calendar")
                    }
                }
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)

                if let tags = recipe.tags, !tags.isEmpty {
                    Text(tags.prefix(4).joined(separator: "  ·  "))
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 12)
        }
    }
}

// MARK: - Drag Preview Badge

private struct RecipeDragPreview: View {
    let recipe: Recipe

    private var simName: String {
        recipe.filmSimulation?.displayName ?? recipe.settings?["filmSimulation"] ?? "Custom Sim"
    }

    private var accent: Color {
        Theme.filmSimColor(for: simName)
    }

    var body: some View {
        HStack(spacing: 8) {
            FilmSimBadge(name: simName, isCompact: true)

            Text(recipe.name)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)

            if let dr = recipe.dynamicRange {
                Text(dr.badgeLabel)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.emeraldGreen)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Theme.emeraldGreen.opacity(0.18))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Theme.deepCharcoal.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [accent, Theme.fujiAmber],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1.2
                )
        )
        .shadow(color: accent.opacity(0.4), radius: 8, y: 3)
    }
}

private struct SampleThumbnailButton: View {
    let urlString: String
    let url: URL
    let onSelect: (String) -> Void
    @State private var isHovered = false

    var body: some View {
        Button {
            onSelect(urlString)
        } label: {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.05))
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure:
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color.white.opacity(0.05))
                @unknown default:
                    EmptyView()
                }
            }
            .frame(width: 120, height: 80)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isHovered ? Theme.fujiAmber.opacity(0.6) : Color.white.opacity(0.12), lineWidth: isHovered ? 1.2 : 0.8)
            )
            .scaleEffect(isHovered ? 1.05 : 1.0)
            .shadow(color: isHovered ? Theme.fujiAmber.opacity(0.3) : Color.black.opacity(0.3), radius: isHovered ? 8 : 4, y: 2)
            .animation(.spring(response: 0.24, dampingFraction: 0.72), value: isHovered)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel("Open sample photo")
        .accessibilityHint("Shows the selected sample photo at a larger size.")
    }
}

fileprivate struct FormulaSettingItem {
    let label: String
    let value: String
}

extension Recipe {
    fileprivate var formulaSettingItems: [FormulaSettingItem] {
        var items: [FormulaSettingItem] = []
        let raw = settings ?? [:]

        func add(_ key: String, display: String) {
            if let val = raw[key], !val.isEmpty {
                items.append(FormulaSettingItem(label: display, value: val))
            }
        }

        add("filmSimulation", display: "Film Sim")
        add("dynamicRange", display: "Dynamic Range")
        add("grainEffect", display: "Grain")
        add("colorChromeEffect", display: "Color Chrome")
        add("colorChromeFxBlue", display: "Chrome FX Blue")
        add("whiteBalance", display: "White Balance")
        if let r = wbShiftRed, let b = wbShiftBlue {
            items.append(FormulaSettingItem(label: "WB Shift", value: "R:\(r.formatValue) B:\(b.formatValue)"))
        }
        add("highlight", display: "Highlight")
        add("shadow", display: "Shadow")
        add("color", display: "Color")
        add("sharpness", display: "Sharpness")
        add("highIsoNr", display: "Noise Reduction")
        add("clarity", display: "Clarity")
        add("iso", display: "ISO")
        add("exposureCompensation", display: "Exp. Comp")

        return items
    }
}

// MARK: - Lightbox Image Modal

public struct PhotoLightboxView: View {
    let imageUrl: URL
    @Binding var isPresented: Bool

    public var body: some View {
        ZStack {
            Theme.obsidianBlack.ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close photo viewer")
                    .accessibilityHint("Closes the enlarged sample photo.")
                    .padding()
                }

                AsyncImage(url: imageUrl) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(Theme.fujiAmber)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .shadow(color: Color.black.opacity(0.6), radius: 24, y: 8)
                            .transition(.scale(scale: 0.95).combined(with: .opacity))
                    case .failure:
                        Text("Unable to load full photo").foregroundStyle(Theme.textSecondary)
                    @unknown default:
                        EmptyView()
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }
}

// MARK: - Recipe Quick Look Lightbox

public struct RecipeQuickLookView: View {
    public let recipe: Recipe
    public let isFavorite: Bool
    public let loadouts: LoadoutStore
    public let isCameraConnected: Bool
    public let onToggleFavorite: () -> Void
    public let onDismiss: () -> Void
    public let onStageToSlot: (Int) -> Void
    public let onSelectPhoto: (String) -> Void
    public var onDuplicate: (() -> Void)? = nil

    public init(
        recipe: Recipe,
        isFavorite: Bool,
        loadouts: LoadoutStore,
        isCameraConnected: Bool,
        onToggleFavorite: @escaping () -> Void,
        onDismiss: @escaping () -> Void,
        onStageToSlot: @escaping (Int) -> Void,
        onSelectPhoto: @escaping (String) -> Void,
        onDuplicate: (() -> Void)? = nil
    ) {
        self.recipe = recipe
        self.isFavorite = isFavorite
        self.loadouts = loadouts
        self.isCameraConnected = isCameraConnected
        self.onToggleFavorite = onToggleFavorite
        self.onDismiss = onDismiss
        self.onStageToSlot = onStageToSlot
        self.onSelectPhoto = onSelectPhoto
        self.onDuplicate = onDuplicate
    }

    private var simName: String {
        recipe.filmSimulation?.displayName ?? recipe.settings?["filmSimulation"] ?? "Custom Sim"
    }

    private var accent: Color {
        Theme.filmSimColor(for: simName)
    }

    public var body: some View {
        ZStack {
            // Dark Frosted Backdrop
            Theme.obsidianBlack.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            // Lightbox Modal Card
            VStack(spacing: 0) {
                // Header Bar
                HStack(alignment: .center, spacing: 10) {
                    FilmSimBadge(name: simName, isCompact: false)

                    if let dr = recipe.dynamicRange {
                        Text(dr.badgeLabel)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.emeraldGreen)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Theme.emeraldGreen.opacity(0.18))
                            .clipShape(Capsule())
                    }

                    KelvinChip(
                        kelvin: recipe.colorTempK,
                        modeName: recipe.whiteBalanceMode?.displayName ?? recipe.settings?["whiteBalance"]
                    )

                    Spacer()

                    // Duplicate & Customize Button
                    if let onDuplicate = onDuplicate {
                        Button(action: onDuplicate) {
                            Image(systemName: "plus.square.on.square")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(6)
                                .background(Circle().fill(Color.white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                        .help("Duplicate & Customize recipe formula into My Recipes")
                        .accessibilityLabel("Duplicate to My Recipes")
                        .accessibilityIdentifier("recipe-quick-look-duplicate-header")
                    }

                    // Favorite Button
                    Button(action: onToggleFavorite) {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(isFavorite ? Theme.warmGold : Theme.textTertiary)
                            .padding(6)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                    .help(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                    .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                    .accessibilityIdentifier("recipe-quick-look-favorite")

                    // Close Button
                    Button(action: onDismiss) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .help("Close Quick Look (Space or Esc)")
                    .accessibilityLabel("Close Quick Look")
                    .accessibilityIdentifier("recipe-quick-look-close")
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 12)

                Divider().overlay(Color.white.opacity(0.1))

                // Scrollable Body
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Title & Metadata
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recipe.name)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Color.white)
                                .accessibilityIdentifier("recipe-quick-look-title")

                            HStack(spacing: 12) {
                                if !recipe.source.isEmpty {
                                    Label(recipe.source, systemImage: "book.closed")
                                }
                                if let date = recipe.dateString {
                                    Label(date, systemImage: "calendar")
                                }
                                if let cams = recipe.compatibleCameras, !cams.isEmpty {
                                    Label(cams.joined(separator: ", "), systemImage: "camera")
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)

                            if let tags = recipe.tags, !tags.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 6) {
                                        ForEach(tags, id: \.self) { tag in
                                            Text("#\(tag)")
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(accent.opacity(0.85))
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(accent.opacity(0.12))
                                                .clipShape(Capsule())
                                        }
                                    }
                                }
                                .trailingScrollFade()
                                .padding(.top, 2)
                            }
                        }

                        // Sample Photos Carousel
                        if !recipe.imageUrls.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("SAMPLE PHOTOGRAPHS")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)

                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 10) {
                                        ForEach(recipe.imageUrls, id: \.self) { urlString in
                                            if let url = URL(string: urlString) {
                                                SampleThumbnailButton(
                                                    urlString: urlString,
                                                    url: url,
                                                    onSelect: onSelectPhoto
                                                )
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        // Tone Curve Radar & Key Visual Readout
                        HStack(alignment: .top, spacing: 16) {
                            ToneCurveRadar(tones: recipe.toneTenths, accentColor: accent)
                            .fixedSize()
                            .frame(minWidth: 110, minHeight: 95)
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.black.opacity(0.25))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                            )

                            VStack(alignment: .leading, spacing: 6) {
                                Text("KEY PARAMETERS")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundStyle(Theme.textTertiary)

                                let items = recipe.formulaSettingItems.prefix(6)
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                                    ForEach(Array(items), id: \.label) { item in
                                        HStack {
                                            Text(item.label)
                                                .font(.caption2)
                                                .foregroundStyle(Theme.textTertiary)
                                            Spacer()
                                            Text(item.value)
                                                .font(.caption2.weight(.bold))
                                                .foregroundStyle(Color.white)
                                        }
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.white.opacity(0.04))
                                        .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }
                                }
                            }
                        }

                        // Full Parameter Formula
                        VStack(alignment: .leading, spacing: 8) {
                            Text("FULL CAMERA PARAMETER FORMULA")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(Theme.textTertiary)

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                                ForEach(recipe.formulaSettingItems, id: \.label) { item in
                                    HStack(spacing: 6) {
                                        Text(item.label)
                                            .font(.system(size: 11))
                                            .foregroundStyle(Theme.textTertiary)
                                        Spacer(minLength: 4)
                                        Text(item.value)
                                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                                            .foregroundStyle(Theme.textPrimary)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 7)
                                    .background(Color.black.opacity(0.3))
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color.white.opacity(0.08), lineWidth: 0.8)
                                    )
                                }
                            }
                        }
                    }
                    .padding(20)
                }
                .frame(maxHeight: 380)

                Divider().overlay(Color.white.opacity(0.1))

                // Footer Bar with 1-click Dial Staging (C1–C7)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        stageToDialLabel
                        stageSlotButtons
                        Spacer()
                        footerActions
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            stageToDialLabel
                            stageSlotButtons
                        }
                        HStack(spacing: 8) {
                            Spacer()
                            footerActions
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        stageToDialLabel
                        HStack(spacing: 8) {
                            stageSlotButtons
                        }
                        HStack(spacing: 8) {
                            Spacer()
                            footerActions
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color.black.opacity(0.2))
            }
            .frame(maxWidth: 640)
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.deepCharcoal.opacity(0.96))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [accent.opacity(0.7), Color.white.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1.2
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: Color.black.opacity(0.7), radius: 36, y: 16)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Quick Look, \(recipe.name)")
            .accessibilityAddTraits(.isModal)
            .accessibilityIdentifier("recipe-quick-look-modal")
            .padding(24)
        }
    }

    private var stageToDialLabel: some View {
        Text("STAGE TO DIAL:")
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundStyle(Theme.textTertiary)
    }

    private var stageSlotButtons: some View {
        ForEach(1...7, id: \.self) { slot in
            let slotName = loadouts.loadout(for: slot)?.contentName ?? "Empty"
            Button {
                onStageToSlot(slot)
            } label: {
                Text("C\(slot)")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(slotAccent(slot))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(slotAccent(slot).opacity(0.16))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(slotAccent(slot).opacity(0.4), lineWidth: 0.8)
                    )
            }
            .buttonStyle(.plain)
            .help("Stage to C\(slot), currently \(slotName)")
            .accessibilityLabel("Stage to C\(slot), currently \(slotName)")
            .accessibilityIdentifier("recipe-quick-look-stage-\(slot)")
        }
    }

    @ViewBuilder
    private var footerActions: some View {
        if let onDuplicate = onDuplicate {
            Button {
                onDuplicate()
            } label: {
                Label("Duplicate to My Recipes", systemImage: "plus.square.on.square")
            }
            .buttonStyle(GlassBorderedButtonStyle(accentColor: Theme.fujiAmber, height: 28))
            .accessibilityIdentifier("recipe-quick-look-duplicate")
        }

        Button("Done") {
            onDismiss()
        }
        .keyboardShortcut(.defaultAction)
        .buttonStyle(GlassBorderedButtonStyle(accentColor: Theme.fujiAmber, height: 28))
    }
}

// MARK: - Formatting helpers

public extension Int32 {
    var formatValue: String {
        if self > 0 { return "+\(self)" }
        return "\(self)"
    }
}
