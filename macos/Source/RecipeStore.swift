import Foundation
import SwiftUI
import FujiRecipesCore
import Combine

// MARK: - Modern 2026 Recipe Store with Multi-Dimensional Filtering & Sorting

@MainActor
public final class RecipeStore: ObservableObject {
    public enum LoadingState: Equatable {
        case idle
        case loading
        case loaded
        case failed
    }

    public typealias RecipeLoading = @MainActor () throws -> [Recipe]

    public let favorites = FavoritesStore()
    public let loadouts = LoadoutStore()
    public let customRecipes: CustomRecipeLibrary

    @Published public var recipes: [Recipe] = []
    @Published public private(set) var loadingState: LoadingState = .idle
    @Published public var selectedFilterCategory: FilterCategory? = nil
    @Published public var selectedFilmSimFamily: FilmSimFamily = .all
    @Published public var selectedDRFilter: DRFilter = .all
    @Published public var selectedWhiteBalance: WhiteBalanceMode?
    @Published public var selectedKeyword: String?
    @Published public var sortOrder: SortOrder = .recommended
    @Published public var searchQuery: String = ""
    @Published public var lastError: String?

    public enum FilterCategory: String, CaseIterable, Identifiable, Hashable {
        case favorites

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .favorites: return "Favorites"
            }
        }
    }

    public enum FilmSimFamily: String, CaseIterable, Identifiable {
        case all = "All Sims"
        case classicChrome = "Classic Chrome"
        case realaAce = "Reala Ace"
        case classicNeg = "Classic Neg"
        case velvia = "Velvia"
        case acros = "Acros / B&W"
        case nostalgicNeg = "Nostalgic Neg"
        case proviaAstia = "Provia / Astia"
        case eterna = "Eterna"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .all: return "square.stack.3d.up.fill"
            case .classicChrome: return "camera.filters"
            case .realaAce: return "sparkles"
            case .classicNeg: return "film"
            case .velvia: return "sun.max.fill"
            case .acros: return "circle.lefthalf.filled"
            case .nostalgicNeg: return "clock.arrow.circlepath"
            case .proviaAstia: return "camera.aperture"
            case .eterna: return "video.fill"
            }
        }
    }

    public enum DRFilter: String, CaseIterable, Identifiable {
        case all = "All DR"
        case dr400 = "DR400"
        case dr200 = "DR200"
        case dr100 = "DR100"

        public var id: String { rawValue }
    }

    public enum SortOrder: String, CaseIterable, Identifiable {
        case recommended = "Featured"
        case alphabetical = "Name (A–Z)"
        case filmSim = "By Film Sim"
        case newest = "Newest"

        public var id: String { rawValue }

        public var icon: String {
            switch self {
            case .recommended: return "sparkles"
            case .alphabetical: return "textformat.abc"
            case .filmSim: return "film"
            case .newest: return "calendar"
            }
        }
    }

    private let recipeLoading: RecipeLoading
    private var catalog = RecipeCatalog(recipes: [])
    private var bundledRecipes: [Recipe] = []
    private var customRecipeSubscription: AnyCancellable?

    /// The loader is injectable so previews and macOS UI tests can exercise
    /// loaded, empty, and failure states without relying on the app bundle.
    public init(
        recipeLoading: RecipeLoading? = nil,
        customRecipes: CustomRecipeLibrary = CustomRecipeLibrary()
    ) {
        self.recipeLoading = recipeLoading ?? {
            if let recipes = try? RecipeLoader.loadRecipes(from: .main) {
                return recipes
            }
            return try RecipeLoader.loadRecipes(from: .module)
        }
        self.customRecipes = customRecipes
        customRecipeSubscription = customRecipes.$recipes.dropFirst().sink { [weak self] _ in
            self?.rebuildGallery()
        }
    }

    public var filteredRecipes: [Recipe] {
        var filters = RecipeCatalog.Filters()
        filters.favoriteIDs = favorites.favoriteIDs
        filters.favoritesOnly = selectedFilterCategory == .favorites
        filters.dynamicRange = selectedDRFilter.dynamicRange
        filters.whiteBalance = selectedWhiteBalance
        filters.keyword = selectedKeyword
        filters.searchText = searchQuery
        filters.sortOrder = sortOrder.catalogSortOrder

        return catalog.recipes(matching: filters)
            .filter { selectedFilmSimFamily.matches($0.filmSimulation) }
    }

    public var availableWhiteBalances: [WhiteBalanceMode] { catalog.whiteBalances }
    public var availableKeywords: [RecipeCatalog.Keyword] { catalog.keywords }

    public func loadRecipes() async {
        loadingState = .loading
        // Give SwiftUI one run-loop turn to render an honest loading state.
        await Task.yield()
        loadRecipesSynchronously()
    }

    /// Synchronous entry point for deterministic snapshot generation and
    /// focused view-model tests. Application UI should use `loadRecipes()`.
    public func loadRecipesSynchronously() {
        do {
            bundledRecipes = try recipeLoading()
            rebuildGallery()
            lastError = nil
            loadingState = .loaded
            DebugLogger.info("Loaded \(recipes.count) recipes", category: .recipes)
        } catch {
            lastError = error.localizedDescription
            loadingState = .failed
            DebugLogger.error("Failed to load recipes: \(error.localizedDescription)", category: .recipes)
        }
    }

    public func isCustomRecipe(_ recipe: Recipe) -> Bool {
        customRecipes.recipes.contains { $0.id == recipe.id }
    }

    private func rebuildGallery() {
        // A locally imported recipe intentionally wins on ID collision: it is
        // the editable user-owned copy in this application's gallery.
        let localIDs = Set(customRecipes.recipes.map(\.id))
        recipes = bundledRecipes.filter { !localIDs.contains($0.id) } + customRecipes.recipes
        catalog = RecipeCatalog(recipes: recipes)
    }
}

private extension RecipeStore.FilmSimFamily {
    func matches(_ simulation: FilmSimulation?) -> Bool {
        guard self != .all else { return true }
        let name = simulation?.displayName ?? ""
        switch self {
        case .all: return true
        case .classicChrome: return name == "Classic Chrome"
        case .realaAce: return name == "Reala Ace"
        case .classicNeg: return name == "Classic Negative"
        case .velvia: return name.contains("Velvia")
        case .acros: return name.contains("ACROS") || name.contains("Monochrome")
        case .nostalgicNeg: return name == "Nostalgic Negative"
        case .proviaAstia: return name.contains("PROVIA") || name.contains("ASTIA") || name.contains("PRO Neg")
        case .eterna: return name.contains("ETERNA")
        }
    }
}

private extension RecipeStore.DRFilter {
    var dynamicRange: DynamicRange? {
        switch self {
        case .all: nil
        case .dr100: .dr100
        case .dr200: .dr200
        case .dr400: .dr400
        }
    }
}

private extension RecipeStore.SortOrder {
    var catalogSortOrder: RecipeCatalog.SortOrder {
        switch self {
        case .recommended: .featured
        case .alphabetical: .name
        case .filmSim: .filmSimulation
        case .newest: .newest
        }
    }
}
