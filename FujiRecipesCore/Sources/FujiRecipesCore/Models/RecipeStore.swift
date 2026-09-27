import Foundation
import SwiftUI
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

    public let favorites: FavoritesStore
    public let loadouts: LoadoutStore
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

    public enum FilterCategory: String, CaseIterable, Identifiable, Hashable {
        case favorites
        case myRecipes

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .favorites: return "Favorites"
            case .myRecipes: return "My Recipes"
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
        case auto = "DR Auto"

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
    private var favoritesSubscription: AnyCancellable?
    private var loadoutsSubscription: AnyCancellable?

    /// The loader is injectable so previews, macOS UI tests, and integration tests can exercise
    /// loaded, empty, and failure states without relying on the app bundle.
    public init(
        recipeLoading: RecipeLoading? = nil,
        defaults: UserDefaults = .standard,
        customRecipes: CustomRecipeLibrary = CustomRecipeLibrary()
    ) {
        favorites = FavoritesStore(defaults: defaults)
        loadouts = LoadoutStore(defaults: defaults)
        self.recipeLoading = recipeLoading ?? {
            if let recipes = try? RecipeLoader.loadRecipes(from: .main) {
                return recipes
            }
            if let recipes = try? RecipeLoader.loadRecipes(from: Bundle(for: RecipeStore.self)) {
                return recipes
            }
            throw RecipeLoaderError.fileNotFound
        }
        self.customRecipes = customRecipes
        customRecipeSubscription = customRecipes.$recipes.dropFirst().sink { [weak self] custom in
            self?.rebuildGallery(with: custom)
        }
        favoritesSubscription = favorites.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        loadoutsSubscription = loadouts.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
        rebuildGallery(with: customRecipes.recipes)
    }

    private struct FilterKey: Equatable {
        let filters: RecipeCatalog.Filters
        let filmSimFamily: FilmSimFamily
        let filterCategory: FilterCategory?
        let galleryVersion: Int
    }

    private var galleryVersion: Int = 0
    private var cachedFilterKey: FilterKey?
    private var cachedFilteredList: [Recipe] = []

    public var filteredRecipes: [Recipe] {
        var filters = RecipeCatalog.Filters()
        filters.favoriteIDs = favorites.favoriteIDs
        filters.favoritesOnly = selectedFilterCategory == .favorites
        filters.dynamicRange = selectedDRFilter.dynamicRange
        filters.whiteBalance = selectedWhiteBalance
        filters.keyword = selectedKeyword
        filters.searchText = searchQuery
        filters.sortOrder = sortOrder.catalogSortOrder

        let key = FilterKey(
            filters: filters,
            filmSimFamily: selectedFilmSimFamily,
            filterCategory: selectedFilterCategory,
            galleryVersion: galleryVersion
        )

        if let cached = cachedFilterKey, cached == key {
            return cachedFilteredList
        }

        var result = catalog.recipes(matching: filters)
            .filter { selectedFilmSimFamily.matches($0.filmSimulation) }

        if selectedFilterCategory == .myRecipes {
            let customIDs = Set(customRecipes.recipes.map(\.id))
            result = result.filter { customIDs.contains($0.id) }
        }

        cachedFilterKey = key
        cachedFilteredList = result
        return result
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
            rebuildGallery(with: customRecipes.recipes)
            loadingState = .loaded
            DebugLogger.info("Loaded \(recipes.count) recipes", category: .recipes)
        } catch {
            loadingState = .failed
            DebugLogger.error("Failed to load recipes: \(error.localizedDescription)", category: .recipes)
        }
    }

    public func isCustomRecipe(_ recipe: Recipe) -> Bool {
        customRecipes.recipes.contains { $0.id == recipe.id }
    }

    /// Takes the custom recipes as an argument because `$recipes` publishes
    /// before `customRecipes.recipes` holds the new value.
    private func rebuildGallery(with custom: [Recipe]) {
        // A locally imported recipe intentionally wins on ID collision: it is
        // the editable user-owned copy in this application's gallery.
        let localIDs = Set(custom.map(\.id))
        recipes = bundledRecipes.filter { !localIDs.contains($0.id) } + custom
        catalog = RecipeCatalog(recipes: recipes)
        galleryVersion += 1
        cachedFilterKey = nil
    }
}

public extension RecipeStore.FilmSimFamily {
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
        case .auto: .auto
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
