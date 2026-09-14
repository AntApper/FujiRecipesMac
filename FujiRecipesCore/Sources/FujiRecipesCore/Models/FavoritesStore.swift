import Foundation

/// Persisted favorites store using UserDefaults.
/// Thread-safe for concurrent access.
@MainActor
public final class FavoritesStore: ObservableObject {
    @Published private(set) public var favoriteIDs: Set<String> = []
    
    private let favoritesKey = "com.ant.fuji-recipes.favorites"
    
    public init() {
        loadFavorites()
        print("✅ FavoritesStore initialized — \(favoriteIDs.count) favorites")
    }
    
    // MARK: - Persistence
    
    private func loadFavorites() {
        if let data = UserDefaults.standard.data(forKey: favoritesKey),
           let ids = try? JSONDecoder().decode([String].self, from: data) {
            self.favoriteIDs = Set(ids)
        }
    }
    
    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(Array(favoriteIDs)) {
            UserDefaults.standard.set(data, forKey: favoritesKey)
        }
    }
    
    // MARK: - Operations
    
    public func toggleFavorite(for recipeID: String) {
        if favoriteIDs.contains(recipeID) {
            favoriteIDs.remove(recipeID)
        } else {
            favoriteIDs.insert(recipeID)
        }
        saveFavorites()
    }
    
    public func isFavorite(_ recipeID: String) -> Bool {
        favoriteIDs.contains(recipeID)
    }
    
    public func addFavorite(_ recipeID: String) {
        favoriteIDs.insert(recipeID)
        saveFavorites()
    }
    
    public func removeFavorite(_ recipeID: String) {
        favoriteIDs.remove(recipeID)
        saveFavorites()
    }
}
