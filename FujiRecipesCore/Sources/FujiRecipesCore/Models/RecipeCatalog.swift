import Foundation

/// An in-memory, normalized index for browsing a recipe collection.
///
/// It intentionally derives its facets only from fields present in `Recipe`;
/// labels such as source keywords are never guessed from a recipe's name.
public struct RecipeCatalog: Sendable {
    public enum SortOrder: String, CaseIterable, Sendable {
        case featured
        case name
        case filmSimulation
        case newest
    }

    public struct Filters: Sendable, Equatable {
        public var favoriteIDs: Set<Recipe.ID> = []
        public var favoritesOnly = false
        public var filmSimulation: FilmSimulation?
        public var dynamicRange: DynamicRange?
        public var whiteBalance: WhiteBalanceMode?
        /// An exact source keyword selected from `keywords`.
        public var keyword: String?
        public var searchText = ""
        public var sortOrder: SortOrder = .featured

        public init() {}
    }

    public struct Keyword: Identifiable, Hashable, Sendable {
        public let name: String
        public let count: Int

        public var id: String { name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) }
    }

    private struct IndexedRecipe: Sendable {
        let recipe: Recipe
        let normalizedSearchText: String
        let normalizedKeywords: Set<String>
    }

    private let indexedRecipes: [IndexedRecipe]

    public init(recipes: [Recipe]) {
        indexedRecipes = recipes.map { recipe in
            let keywords = Set(recipe.tags ?? [])
            let searchableParts = [
                recipe.name,
                recipe.source,
                recipe.filmSimulation?.displayName,
                recipe.dynamicRange?.displayName,
                recipe.whiteBalanceMode?.displayName,
                recipe.dateString,
                recipe.sensorGeneration
            ].compactMap { $0 }
            + keywords
            + (recipe.compatibleCameras ?? [])
            + (recipe.settings ?? [:]).flatMap { [$0.key, $0.value] }

            return IndexedRecipe(
                recipe: recipe,
                normalizedSearchText: Self.normalize(searchableParts.joined(separator: " ")),
                normalizedKeywords: Set(keywords.map(Self.normalize))
            )
        }
    }

    public var count: Int { indexedRecipes.count }

    public var filmSimulations: [FilmSimulation] {
        Array(Set(indexedRecipes.compactMap(\.recipe.filmSimulation)))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public var dynamicRanges: [DynamicRange] {
        Array(Set(indexedRecipes.compactMap(\.recipe.dynamicRange)))
            .sorted { $0.rawValue < $1.rawValue }
    }

    public var whiteBalances: [WhiteBalanceMode] {
        Array(Set(indexedRecipes.compactMap(\.recipe.whiteBalanceMode)))
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    /// Source keywords suitable for browse filters. Generic collection and
    /// publisher labels are removed, but all remaining terms originate in the
    /// imported source data.
    public var keywords: [Keyword] {
        let ignored = Set([
            "camera blog", "camera settings", "film simulation",
            "film simulation recipe", "film simulation recipes",
            "film simulation settings", "fuji blog", "fuji x weekly",
            "fuji x weekly blog", "fuji x weekly film simulation",
            "fujifilm", "fujifilm blog", "fujifilm blogger",
            "fujifilm camera blog", "fujifilm camera settings",
            "fujifilm film simulation", "fujifilm recipes",
            "photography blog"
        ].map(Self.normalize))

        var names: [String: (name: String, count: Int)] = [:]
        for indexed in indexedRecipes {
            for tag in indexed.recipe.tags ?? [] {
                let normalized = Self.normalize(tag)
                guard !normalized.isEmpty, !ignored.contains(normalized) else { continue }
                let current = names[normalized] ?? (tag, 0)
                names[normalized] = (current.name, current.count + 1)
            }
        }
        return names.values
            .map { Keyword(name: $0.name, count: $0.count) }
            .sorted {
                $0.count == $1.count
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : $0.count > $1.count
            }
    }

    public func recipes(matching filters: Filters) -> [Recipe] {
        let queryTerms = Self.searchTerms(filters.searchText)
        let normalizedKeyword = filters.keyword.map(Self.normalize)

        let results = indexedRecipes.filter { indexed in
            let recipe = indexed.recipe
            guard !filters.favoritesOnly || filters.favoriteIDs.contains(recipe.id),
                  filters.filmSimulation == nil || recipe.filmSimulation == filters.filmSimulation,
                  filters.dynamicRange == nil || recipe.dynamicRange == filters.dynamicRange,
                  filters.whiteBalance == nil || recipe.whiteBalanceMode == filters.whiteBalance,
                  normalizedKeyword == nil || indexed.normalizedKeywords.contains(normalizedKeyword!),
                  queryTerms.allSatisfy(indexed.normalizedSearchText.contains)
            else {
                return false
            }
            return true
        }.map(\.recipe)

        switch filters.sortOrder {
        case .featured:
            return results
        case .name:
            return results.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .filmSimulation:
            return results.sorted {
                let comparison = ($0.filmSimulation?.displayName ?? "")
                    .localizedCaseInsensitiveCompare($1.filmSimulation?.displayName ?? "")
                return comparison == .orderedSame
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : comparison == .orderedAscending
            }
        case .newest:
            return results.sorted {
                let lhs = $0.date ?? .distantPast
                let rhs = $1.date ?? .distantPast
                return lhs == rhs
                    ? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                    : lhs > rhs
            }
        }
    }

    public static func normalize(_ text: String) -> String {
        text
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func searchTerms(_ query: String) -> [String] {
        normalize(query).split(separator: " ").map(String.init)
    }
}
