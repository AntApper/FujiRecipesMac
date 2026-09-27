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
    case persistenceBlocked
    case backupUnavailable

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
        case .persistenceBlocked:
            return "My Recipes didn’t load cleanly. Dismiss the notice about it before saving changes."
        case .backupUnavailable:
            return "FujiRecipes still can’t make a copy of the original My Recipes file, so it won’t replace that file. Your change wasn’t saved."
        }
    }
}

/// Why the stored library didn't load in full.
public struct CustomRecipeLibraryLoadIssue: Equatable, Sendable {
    public struct SkippedRecipe: Equatable, Sendable {
        /// The stored name when it is readable, otherwise “Recipe N” by file position.
        public let name: String
        public let reason: String
    }

    public enum Problem: Equatable, Sendable {
        case unreadableFile(reason: String)
        case skippedRecipes([SkippedRecipe])
    }

    public let problem: Problem
    /// `nil` only when copying the original file aside failed.
    public let backupURL: URL?

    public var message: String {
        let finding: String
        switch problem {
        case .unreadableFile(let reason):
            finding = "FujiRecipes couldn’t read your custom recipe library (\(reason))."
        case .skippedRecipes(let skipped):
            let recipes = skipped.count == 1 ? "1 custom recipe" : "\(skipped.count) custom recipes"
            let verb = skipped.count == 1 ? "was" : "were"
            let list = skipped.map { "“\($0.name)” (\($0.reason))" }.joined(separator: ", ")
            finding = "\(recipes) couldn’t be read and \(verb) left out: \(list)."
        }
        let backup = backupURL.map { "The original file was copied to “\($0.lastPathComponent)”." }
            ?? "FujiRecipes couldn’t make a copy of the original file, so it was left untouched."
        return "\(finding) \(backup) Changes to My Recipes won’t be saved until you dismiss this."
    }
}

/// A small, file-backed library for recipes authored or imported by the user.
///
/// Bundled gallery recipes are deliberately not persisted here. The app merges
/// this library into its in-memory gallery, keeping source data read-only.
@MainActor
public final class CustomRecipeLibrary: ObservableObject {
    @Published public private(set) var recipes: [Recipe] = []
    /// While set, every change is refused so nothing replaces the stored file
    /// before the person has read what the next save leaves out. After it is
    /// dismissed, saves stay refused until that file has been copied aside.
    @Published public private(set) var loadIssue: CustomRecipeLibraryLoadIssue?

    public let storageURL: URL
    private let fileManager: FileManager
    private var storedFileNeedsBackup = false

    public init(
        storageURL: URL = CustomRecipeLibrary.defaultStorageURL(),
        fileManager: FileManager = .default,
        loadOnInit: Bool = true
    ) {
        self.storageURL = storageURL
        self.fileManager = fileManager
        if loadOnInit {
            load()
        }
    }

    public func load() {
        guard fileManager.fileExists(atPath: storageURL.path) else {
            recipes = []
            loadIssue = nil
            storedFileNeedsBackup = false
            return
        }
        let problem: CustomRecipeLibraryLoadIssue.Problem?
        do {
            let stored = try Self.readStoredLibrary(Data(contentsOf: storageURL))
            recipes = stored.recipes
            problem = stored.skipped.isEmpty ? nil : .skippedRecipes(stored.skipped)
        } catch {
            recipes = []
            problem = .unreadableFile(reason: storedDataFailureReason(error))
        }
        let backupURL = problem == nil ? nil : backUpStoredFile()
        storedFileNeedsBackup = problem != nil && backupURL == nil
        loadIssue = problem.map { CustomRecipeLibraryLoadIssue(problem: $0, backupURL: backupURL) }
    }

    public func acknowledgeLoadIssue() {
        loadIssue = nil
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
        try ensurePersistenceAllowed()
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

    @discardableResult
    public func saveCopy(of recipe: Recipe) throws -> Recipe {
        let baseName = recipe.name.isEmpty ? "Recipe" : recipe.name
        var copy = recipe.duplicated()
        var number = 1
        while conflictingRecipe(named: copy.name) != nil {
            number += 1
            copy = recipe.duplicated(name: "\(baseName) (Custom \(number))")
        }
        try save(copy, disallowNameCollision: true)
        return copy
    }

    public func delete(id: Recipe.ID) throws {
        try ensurePersistenceAllowed()
        recipes.removeAll { $0.id == id }
        try persist()
    }

    /// Merges an exported library by stable ID, replacing matching local recipes.
    @discardableResult
    public func `import`(_ data: Data) throws -> Int {
        try ensurePersistenceAllowed()
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
        AppSupportDirectory.current.appendingPathComponent("custom-recipes-v1.json")
    }

    private func ensurePersistenceAllowed() throws {
        if loadIssue != nil {
            throw CustomRecipeLibraryError.persistenceBlocked
        }
        if storedFileNeedsBackup {
            guard backUpStoredFile() != nil else {
                throw CustomRecipeLibraryError.backupUnavailable
            }
            storedFileNeedsBackup = false
        }
    }

    private func persist() throws {
        try fileManager.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try exportData().write(to: storageURL, options: .atomic)
    }

    /// Copies, never moves, so the stored file stays in place until the
    /// person acknowledges the issue and saves again.
    private func backUpStoredFile() -> URL? {
        let directory = storageURL.deletingLastPathComponent()
        let stem = storageURL.deletingPathExtension().lastPathComponent
        let pathExtension = storageURL.pathExtension.isEmpty ? "" : ".\(storageURL.pathExtension)"
        let existingBackups = ((try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter {
                $0.lastPathComponent.hasPrefix("\(stem).unreadable-") &&
                $0.lastPathComponent.hasSuffix(pathExtension)
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        if let identical = existingBackups.first(where: {
            fileManager.contentsEqual(atPath: $0.path, andPath: storageURL.path)
        }) {
            return directory.appendingPathComponent(identical.lastPathComponent)
        }
        let baseName = "\(stem).unreadable-\(storedDataRecoveryTimestamp())"
        var attempt = 1
        var backupURL = directory.appendingPathComponent(baseName + pathExtension)
        while fileManager.fileExists(atPath: backupURL.path) {
            attempt += 1
            backupURL = directory.appendingPathComponent("\(baseName)-\(attempt)\(pathExtension)")
        }
        do {
            try fileManager.copyItem(at: storageURL, to: backupURL)
            return backupURL
        } catch {
            return nil
        }
    }

    /// Reads each stored recipe on its own so one unreadable or invalid
    /// recipe is left out instead of hiding the rest.
    private static func readStoredLibrary(
        _ data: Data
    ) throws -> (recipes: [Recipe], skipped: [CustomRecipeLibraryLoadIssue.SkippedRecipe]) {
        let archive = try JSONDecoder().decode(StoredLibrary.self, from: data)
        guard archive.version == CustomRecipeLibraryExport.currentVersion else {
            throw CustomRecipeLibraryError.unsupportedVersion(archive.version)
        }

        var recipes: [Recipe] = []
        var skipped: [CustomRecipeLibraryLoadIssue.SkippedRecipe] = []
        var ids = Set<String>()
        for (index, stored) in archive.recipes.enumerated() {
            do {
                let recipe = try stored.recipe.get()
                try validate(recipe)
                guard ids.insert(recipe.id).inserted else {
                    throw CustomRecipeLibraryError.duplicateID(recipe.id)
                }
                recipes.append(recipe)
            } catch {
                let storedName = stored.name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                skipped.append(.init(
                    name: storedName.isEmpty ? "Recipe \(index + 1)" : storedName,
                    reason: skippedRecipeReason(error)
                ))
            }
        }
        return (recipes, skipped)
    }

    private static func skippedRecipeReason(_ error: Error) -> String {
        switch error {
        case CustomRecipeLibraryError.invalidRecipe(let message):
            return reasonClause(message)
        case CustomRecipeLibraryError.duplicateID(let id):
            return "another recipe in the file already uses the ID “\(id)”"
        default:
            return storedDataFailureReason(error)
        }
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

private struct StoredLibrary: Decodable {
    let version: Int
    let recipes: [StoredRecipe]
}

private struct StoredRecipe: Decodable {
    private enum CodingKeys: String, CodingKey {
        case name
    }

    let name: String?
    let recipe: Result<Recipe, any Error>

    init(from decoder: any Decoder) throws {
        name = try? decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(String.self, forKey: .name)
        recipe = Result { try Recipe(from: decoder) }
    }
}
