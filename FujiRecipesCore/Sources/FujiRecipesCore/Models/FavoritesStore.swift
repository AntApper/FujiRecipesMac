import Foundation

public struct FavoritesRecoveryNotice: Equatable, Sendable {
    public let backupKey: String
    public let reason: String

    public var message: String {
        "FujiRecipes couldn’t read your favorites (\(reason)), so favorites start empty. The original value was kept in the app’s preferences as “\(backupKey)”. Your recipes and staged drafts weren’t changed."
    }
}

/// Persisted favorites store using UserDefaults.
/// Thread-safe for concurrent access.
@MainActor
public final class FavoritesStore: ObservableObject {
    @Published private(set) public var favoriteIDs: Set<String> = []
    @Published private(set) public var recoveryNotice: FavoritesRecoveryNotice?
    
    private let favoritesKey = "com.ant.fuji-recipes.favorites"
    private let defaults: UserDefaults
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadFavorites()
        print("✅ FavoritesStore initialized — \(favoriteIDs.count) favorites")
    }
    
    // MARK: - Persistence

    public func acknowledgeRecoveryNotice() {
        recoveryNotice = nil
    }
    
    private func loadFavorites() {
        guard let storedValue = defaults.object(forKey: favoritesKey) else { return }
        do {
            let ids = try JSONDecoder().decode([String].self, from: storedJSONData(storedValue))
            favoriteIDs = Set(ids)
        } catch {
            let backupKey = backUpUnreadableStoredValue(storedValue, forKey: favoritesKey, in: defaults)
            favoriteIDs = []
            // Replace only after the original has been copied. The next launch
            // then loads cleanly without repeating the same recovery notice.
            saveFavorites()
            recoveryNotice = FavoritesRecoveryNotice(backupKey: backupKey, reason: storedDataFailureReason(error))
        }
    }
    
    private func saveFavorites() {
        if let data = try? JSONEncoder().encode(favoriteIDs.sorted()) {
            defaults.set(data, forKey: favoritesKey)
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
