import XCTest
@testable import FujiRecipesCore

@MainActor
final class CustomRecipeLibraryTests: XCTestCase {
    func testSavePersistsAndReloadsRecipe() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("custom-recipes-v1.json")
        let library = CustomRecipeLibrary(storageURL: url, loadOnInit: false)

        try library.save(recipe(id: "custom-night", name: "Night Walk"))

        let reloaded = CustomRecipeLibrary(storageURL: url)
        XCTAssertEqual(reloaded.recipes.map(\.name), ["Night Walk"])
    }

    func testExportAndImportMergeByStableID() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = CustomRecipeLibrary(storageURL: directory.appendingPathComponent("first.json"), loadOnInit: false)
        try first.save(recipe(id: "custom-shared", name: "Original"))
        let exported = try first.exportData()

        let second = CustomRecipeLibrary(storageURL: directory.appendingPathComponent("second.json"), loadOnInit: false)
        try second.save(recipe(id: "custom-shared", name: "Older Local Copy"))
        XCTAssertEqual(try second.import(exported), 1)

        XCTAssertEqual(second.recipes.map(\.name), ["Original"])
    }

    func testImportRejectsUnsupportedAndDuplicateRecords() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = CustomRecipeLibrary(storageURL: directory.appendingPathComponent("library.json"), loadOnInit: false)
        let unsupported = try JSONEncoder().encode(CustomRecipeLibraryExport(version: 99, recipes: []))
        XCTAssertEqual(try error(from: { try library.import(unsupported) }), .unsupportedVersion(99))

        let duplicate = recipe(id: "custom-duplicate", name: "Duplicate")
        let archive = CustomRecipeLibraryExport(recipes: [duplicate, duplicate])
        XCTAssertEqual(
            try error(from: { try library.import(JSONEncoder().encode(archive)) }),
            .duplicateID("custom-duplicate")
        )
    }

    private func error(from operation: () throws -> Void) throws -> CustomRecipeLibraryError {
        do {
            try operation()
            XCTFail("Expected a CustomRecipeLibraryError")
            return .invalidFile("Missing expected error")
        } catch let error as CustomRecipeLibraryError {
            return error
        }
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func recipe(id: String, name: String) -> Recipe {
        Recipe(
            id: id,
            name: name,
            source: "My Recipes",
            sourceUrl: nil,
            filmSimulation: .classicChrome,
            dynamicRange: .dr100,
            grainEffect: .off,
            whiteBalanceMode: .auto,
            wbShiftRed: 0,
            wbShiftBlue: 0,
            highlight: 0,
            shadow: 0,
            color: 0,
            sharpness: 0,
            highIsoNr: 0,
            clarity: 0,
            settings: [:],
            sensorGeneration: "X-Trans V",
            compatibleCameras: ["X100VI"],
            tags: ["My Recipes"]
        )
    }
}
