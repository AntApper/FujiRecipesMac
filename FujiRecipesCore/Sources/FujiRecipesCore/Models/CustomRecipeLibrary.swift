#if canImport(Combine)
import Combine
#endif
import Foundation

/// The portable, versioned format used for a user's locally authored recipes.
public struct CustomRecipeLibraryExport: Codable, Sendable {
    public static let currentVersion = 1

    public let version: Int
    public let recipes: [Recipe]

    public init(version: Int = Self.currentVersion, recipes: [Recipe]) {
        self.version = version
        self.recipes = recipes
    }
}

public enum CustomRecipeLibraryError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case invalidRecipe(String)
    case duplicateID(String)
    case invalidFile(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "This recipe library uses version \(version), but this app supports version \(CustomRecipeLibraryExport.currentVersion)."
        case .invalidRecipe(let message):
            return "This recipe cannot be saved: \(message)"
        case .duplicateID(let id):
            return "The import contains more than one recipe with ID “\(id)”. Give each recipe a unique ID and try again."
        case .invalidFile(let message):
            return "Couldn’t import this recipe library: \(message)"
        }
    }
}

/// A small, file-backed library for recipes authored or imported by the user.
///
/// Bundled gallery recipes are deliberately not persisted here. The app merges
/// this library into its in-memory gallery, keeping source data read-only.
@MainActor
public final class CustomRecipeLibrary: ObservableObject {
    @Published public private(set) var recipes: [Recipe] = []

    public let storageURL: URL
    private let fileManager: FileManager

    public init(
        storageURL: URL = CustomRecipeLibrary.defaultStorageURL(),
        fileManager: FileManager = .default,
        loadOnInit: Bool = true
    ) {
        self.storageURL = storageURL
        self.fileManager = fileManager
        if loadOnInit {
            do {
                try load()
            } catch {
                // A caller can surface and recover from the same error via `load()`.
                recipes = []
            }
        }
    }

    public func load() throws {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            recipes = []
            return
        }
        recipes = try Self.decode(Data(contentsOf: storageURL))
    }

    public func conflictingRecipe(named name: String, excludingID: String? = nil) -> Recipe? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return recipes.first { existing in
            existing.id != excludingID &&
            existing.name.localizedCaseInsensitiveCompare(trimmed) == .orderedSame
        }
    }

    public func validateNameUniqueness(for recipe: Recipe) throws {
        if let conflict = conflictingRecipe(named: recipe.name, excludingID: recipe.id) {
            throw CustomRecipeLibraryError.invalidRecipe("A recipe named “\(conflict.name)” already exists.")
        }
    }

    public func save(_ recipe: Recipe, disallowNameCollision: Bool = false) throws {
        try Self.validate(recipe)
        if disallowNameCollision {
            try validateNameUniqueness(for: recipe)
        }
        if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
            recipes[index] = recipe
        } else {
            recipes.append(recipe)
        }
        recipes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try persist()
    }

    public func delete(id: Recipe.ID) throws {
        recipes.removeAll { $0.id == id }
        try persist()
    }

    /// Merges an exported library by stable ID, replacing matching local recipes.
    @discardableResult
    public func `import`(_ data: Data) throws -> Int {
        let imported = try Self.decode(data)
        for recipe in imported {
            if let index = recipes.firstIndex(where: { $0.id == recipe.id }) {
                recipes[index] = recipe
            } else {
                recipes.append(recipe)
            }
        }
        recipes.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        try persist()
        return imported.count
    }

    public func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(CustomRecipeLibraryExport(recipes: recipes))
    }

    public static func defaultStorageURL() -> URL {
        let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return root
            .appendingPathComponent("FujiRecipes", isDirectory: true)
            .appendingPathComponent("custom-recipes-v1.json")
    }

    private func persist() throws {
        try fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try exportData().write(to: storageURL, options: .atomic)
    }

    private static func decode(_ data: Data) throws -> [Recipe] {
        let archive: CustomRecipeLibraryExport
        do {
            archive = try JSONDecoder().decode(CustomRecipeLibraryExport.self, from: data)
        } catch {
            throw CustomRecipeLibraryError.invalidFile("Expected a FujiRecipes custom library JSON file. \(error.localizedDescription)")
        }
        guard archive.version == CustomRecipeLibraryExport.currentVersion else {
            throw CustomRecipeLibraryError.unsupportedVersion(archive.version)
        }

        var ids = Set<String>()
        for recipe in archive.recipes {
            try validate(recipe)
            guard ids.insert(recipe.id).inserted else {
                throw CustomRecipeLibraryError.duplicateID(recipe.id)
            }
        }
        return archive.recipes
    }

    private static func validate(_ recipe: Recipe) throws {
        guard !recipe.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CustomRecipeLibraryError.invalidRecipe("a stable ID is required.")
        }
        guard !recipe.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CustomRecipeLibraryError.invalidRecipe("a name is required.")
        }
        if recipe.whiteBalanceMode == .colorTemperature,
           !(2_500...10_000).contains(recipe.colorTempK ?? 0) {
            throw CustomRecipeLibraryError.invalidRecipe("Color Temperature white balance needs a Kelvin value from 2500 to 10000.")
        }
    }
}
