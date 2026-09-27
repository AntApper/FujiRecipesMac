import XCTest
@testable import FujiRecipesCore

final class CustomRecipeLibraryTests: XCTestCase {
    @MainActor
    func testOnlyReleaseIdentityUsesTheReleaseSupportFolder() {
        XCTAssertEqual(AppSupportDirectory.url(forBundleIdentifier: "com.ant.fuji-recipes-mac").lastPathComponent, "FujiRecipes")
        XCTAssertEqual(
            AppSupportDirectory.url(forBundleIdentifier: "com.ant.fuji-recipes-mac.debug").lastPathComponent,
            "FujiRecipes-com.ant.fuji-recipes-mac.debug"
        )
        XCTAssertEqual(AppSupportDirectory.url(forBundleIdentifier: nil).lastPathComponent, "FujiRecipes-unbundled")
        XCTAssertNotEqual(CustomRecipeLibrary.defaultStorageURL().deletingLastPathComponent().lastPathComponent, "FujiRecipes")
    }

    @MainActor
    func testSavePersistsAndReloadsRecipe() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("custom-recipes-v1.json")
        let library = CustomRecipeLibrary(storageURL: url, loadOnInit: false)

        try library.save(recipe(id: "custom-night", name: "Night Walk"))

        let reloaded = CustomRecipeLibrary(storageURL: url)
        XCTAssertEqual(reloaded.recipes.map(\.name), ["Night Walk"])
    }

    @MainActor
    func testExportAndImportMergeByStableID() async throws {
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

    @MainActor
    func testImportRejectsUnsupportedAndDuplicateRecords() async throws {
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

    // MARK: - Objective 3: Stress and Boundary Tests

    @MainActor
    func testImportRejectsInvalidJSON() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = CustomRecipeLibrary(storageURL: directory.appendingPathComponent("invalid.json"), loadOnInit: false)

        let invalidPayloads: [Data] = [
            Data("not json at all".utf8),
            Data("{\"version\": 1, recipes: [".utf8),
            Data("{\"version\": 1, \"recipes\": \"string_not_array\"}".utf8),
            Data("{\"version\": 1, \"recipes\": [{\"id\": 12345}]}".utf8),
            Data("{\"unexpected\": true}".utf8),
            Data("{".utf8)
        ]

        for payload in invalidPayloads {
            do {
                _ = try library.import(payload)
                XCTFail("Expected invalidFile error for payload: \(String(decoding: payload, as: UTF8.self))")
            } catch let error as CustomRecipeLibraryError {
                if case .invalidFile = error {
                    // Success: correctly identified invalid file
                } else {
                    XCTFail("Expected .invalidFile, got: \(error)")
                }
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    @MainActor
    func testImportRejectsEmptyDataAndWhitespace() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = CustomRecipeLibrary(storageURL: directory.appendingPathComponent("empty.json"), loadOnInit: false)

        let emptyPayloads: [Data] = [
            Data(),
            Data("".utf8),
            Data("   \n\t  ".utf8)
        ]

        for payload in emptyPayloads {
            do {
                _ = try library.import(payload)
                XCTFail("Expected invalidFile error for empty payload")
            } catch let error as CustomRecipeLibraryError {
                guard case .invalidFile = error else {
                    XCTFail("Expected .invalidFile, got: \(error)")
                    return
                }
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    @MainActor
    func testImportRejectsCorruptedUnicode() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = CustomRecipeLibrary(storageURL: directory.appendingPathComponent("corrupted.json"), loadOnInit: false)

        let corruptedPayloads: [Data] = [
            Data([0xFF, 0xFE, 0xFD, 0x80, 0xC0]),
            Data([0x7B, 0x22, 0x76, 0x65, 0x72, 0x73, 0x69, 0x6F, 0x6E, 0x22, 0x3A, 0x20, 0x31, 0x2C, 0x20, 0x22, 0x72, 0x65, 0x63, 0x69, 0x70, 0x65, 0x73, 0x22, 0x3A, 0x20, 0x5B, 0x22, 0xC3, 0x22, 0x5D, 0x7D])
        ]

        for payload in corruptedPayloads {
            do {
                _ = try library.import(payload)
                XCTFail("Expected invalidFile error for corrupted unicode payload")
            } catch let error as CustomRecipeLibraryError {
                guard case .invalidFile = error else {
                    XCTFail("Expected .invalidFile, got: \(error)")
                    return
                }
            } catch {
                XCTFail("Unexpected error type: \(error)")
            }
        }
    }

    @MainActor
    func testConcurrentImportsMergeDeterministicState() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = CustomRecipeLibrary(storageURL: directory.appendingPathComponent("concurrent.json"), loadOnInit: false)

        // Generate 5 batches of exports with partial overlap
        let batches: [Data] = try (0..<5).map { batchIndex in
            let recipes = (0..<10).map { i in
                self.recipe(id: "recipe-\(batchIndex * 5 + i)", name: "Recipe \(batchIndex * 5 + i)")
            }
            let export = CustomRecipeLibraryExport(recipes: recipes)
            return try JSONEncoder().encode(export)
        }

        try await withThrowingTaskGroup(of: Int.self) { group in
            for batch in batches {
                group.addTask { @MainActor in
                    try library.import(batch)
                }
            }
            var totalImported = 0
            for try await count in group {
                totalImported += count
            }
            XCTAssertEqual(totalImported, 50)
        }

        // Total unique IDs across batches (0..29) is 30
        XCTAssertEqual(library.recipes.count, 30)

        // Verify alphabetical sorting
        for i in 0..<(library.recipes.count - 1) {
            let current = library.recipes[i].name
            let next = library.recipes[i + 1].name
            XCTAssertTrue(current.localizedCaseInsensitiveCompare(next) != .orderedDescending)
        }

        // Verify reloaded library from disk matches memory state
        let reloaded = CustomRecipeLibrary(storageURL: directory.appendingPathComponent("concurrent.json"))
        XCTAssertEqual(reloaded.recipes.count, 30)
        XCTAssertEqual(reloaded.recipes.map(\.id), library.recipes.map(\.id))
    }

    @MainActor
    func testRecipeValidationRejectsBlankIdentifiersAndInvalidKelvin() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = CustomRecipeLibrary(storageURL: directory.appendingPathComponent("validation.json"), loadOnInit: false)

        // Blank ID
        let blankId = Recipe(id: "   ", name: "Valid Name", source: "test", sourceUrl: nil)
        XCTAssertEqual(
            try error(from: { try library.save(blankId) }),
            .invalidRecipe("a stable ID is required.")
        )

        // Blank Name
        let blankName = Recipe(id: "valid-id", name: "   ", source: "test", sourceUrl: nil)
        XCTAssertEqual(
            try error(from: { try library.save(blankName) }),
            .invalidRecipe("a name is required.")
        )

        // Color temperature WB with out of range Kelvin
        let lowKelvin = Recipe(
            id: "low-k",
            name: "Low Kelvin",
            source: "test",
            sourceUrl: nil,
            whiteBalanceMode: .colorTemperature,
            colorTempK: 2499
        )
        XCTAssertEqual(
            try error(from: { try library.save(lowKelvin) }),
            .invalidRecipe("Color Temperature white balance needs a Kelvin value from 2500 to 10000.")
        )

        let highKelvin = Recipe(
            id: "high-k",
            name: "High Kelvin",
            source: "test",
            sourceUrl: nil,
            whiteBalanceMode: .colorTemperature,
            colorTempK: 10001
        )
        XCTAssertEqual(
            try error(from: { try library.save(highKelvin) }),
            .invalidRecipe("Color Temperature white balance needs a Kelvin value from 2500 to 10000.")
        )
    }

    @MainActor
    func testCorruptFileAtInitThenSaveKeepsTheOriginalFile() throws {
        let unreadableFiles = [
            Data("{\"version\": 1, \"recipes\": [".utf8),
            try JSONEncoder().encode(CustomRecipeLibraryExport(version: 2, recipes: [recipe(id: "custom-future", name: "Future")]))
        ]
        for original in unreadableFiles {
            let directory = try makeDirectory()
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("custom-recipes-v1.json")
            try original.write(to: url)

            let library = CustomRecipeLibrary(storageURL: url)
            XCTAssertThrowsError(try library.save(recipe(id: "custom-new", name: "New")))

            XCTAssertEqual(try Data(contentsOf: url), original)
            let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent != url.lastPathComponent }
            XCTAssertEqual(try backups.map { try Data(contentsOf: $0) }, [original])
        }
    }

    @MainActor
    func testOneUnreadableRecipeDoesNotHideTheOthers() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("custom-recipes-v1.json")
        let archive = CustomRecipeLibraryExport(recipes: [
            recipe(id: "custom-good", name: "Good"),
            recipe(id: "custom-bad", name: "Bad")
        ])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        var recipes = try XCTUnwrap(json["recipes"] as? [[String: Any]])
        recipes[1]["filmSimulation"] = 9999
        json["recipes"] = recipes
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let library = CustomRecipeLibrary(storageURL: url)

        XCTAssertEqual(library.recipes.map(\.name), ["Good"])
    }

    @MainActor
    func testSavingTwoCopiesOfOneRecipeGivesEachAUniqueName() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("custom-recipes-v1.json")
        let library = CustomRecipeLibrary(storageURL: url, loadOnInit: false)
        let bundled = recipe(id: "kodak-portra-400", name: "Kodak Portra 400")

        try library.saveCopy(of: bundled)
        try library.saveCopy(of: bundled)

        XCTAssertEqual(
            CustomRecipeLibrary(storageURL: url).recipes.map(\.name),
            ["Kodak Portra 400 (Custom 2)", "Kodak Portra 400 (Custom)"]
        )
    }

    @MainActor
    func testUnreadableLibraryBlocksSavingUntilTheIssueIsAcknowledged() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("custom-recipes-v1.json")
        let original = Data("{\"version\": 1, \"recipes\": [".utf8)
        try original.write(to: url)

        let library = CustomRecipeLibrary(storageURL: url)
        let issue = try XCTUnwrap(library.loadIssue)

        XCTAssertEqual(issue.problem, .unreadableFile(reason: "The given data was not valid JSON"))
        XCTAssertEqual(try error(from: { try library.save(recipe(id: "custom-new", name: "New")) }), .persistenceBlocked)
        library.acknowledgeLoadIssue()
        try library.save(recipe(id: "custom-new", name: "New"))

        let backupURL = try XCTUnwrap(issue.backupURL)
        XCTAssertNotNil(backupURL.lastPathComponent.range(
            of: #"^custom-recipes-v1\.unreadable-\d{8}-\d{6}\.json$"#,
            options: .regularExpression
        ))
        XCTAssertEqual(try Data(contentsOf: backupURL), original)
        XCTAssertEqual(CustomRecipeLibrary(storageURL: url).recipes.map(\.name), ["New"])
    }

    @MainActor
    func testUnreadableRecipeIsReportedAndBlocksSavingUntilAcknowledged() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("custom-recipes-v1.json")
        let archive = CustomRecipeLibraryExport(recipes: [
            recipe(id: "custom-good", name: "Good"),
            recipe(id: "custom-bad", name: "Bad")
        ])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        var recipes = try XCTUnwrap(json["recipes"] as? [[String: Any]])
        recipes[1]["filmSimulation"] = 9999
        json["recipes"] = recipes
        let original = try JSONSerialization.data(withJSONObject: json)
        try original.write(to: url)

        let library = CustomRecipeLibrary(storageURL: url)
        let issue = try XCTUnwrap(library.loadIssue)

        XCTAssertEqual(issue.problem, .skippedRecipes([
            .init(name: "Bad", reason: "filmSimulation: Cannot initialize FilmSimulation from invalid UInt32 value 9999")
        ]))
        XCTAssertEqual(try error(from: { try library.save(recipe(id: "custom-new", name: "New")) }), .persistenceBlocked)
        XCTAssertEqual(try error(from: { try library.delete(id: "custom-good") }), .persistenceBlocked)
        XCTAssertEqual(library.recipes.map(\.name), ["Good"])

        library.acknowledgeLoadIssue()
        try library.save(recipe(id: "custom-new", name: "New"))

        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(issue.backupURL)), original)
        XCTAssertEqual(CustomRecipeLibrary(storageURL: url).recipes.map(\.name), ["Good", "New"])
    }

    @MainActor
    func testInvalidAndDuplicateStoredRecipesAreSkippedByName() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("custom-recipes-v1.json")
        let archive = CustomRecipeLibraryExport(recipes: [
            recipe(id: "custom-shared", name: "Good"),
            recipe(id: "custom-shared", name: "Other"),
            recipe(id: "custom-unnamed", name: "  ")
        ])
        try JSONEncoder().encode(archive).write(to: url)

        let library = CustomRecipeLibrary(storageURL: url)

        XCTAssertEqual(library.recipes.map(\.name), ["Good"])
        XCTAssertEqual(library.loadIssue?.problem, .skippedRecipes([
            .init(name: "Other", reason: "another recipe in the file already uses the ID “custom-shared”"),
            .init(name: "Recipe 3", reason: "a name is required")
        ]))
    }

    @MainActor
    func testMissingLibraryFileLoadsEmptyWithoutAnIssue() throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("custom-recipes-v1.json")

        let library = CustomRecipeLibrary(storageURL: url)
        XCTAssertNil(library.loadIssue)
        try library.save(recipe(id: "custom-new", name: "New"))

        XCTAssertEqual(CustomRecipeLibrary(storageURL: url).recipes.map(\.name), ["New"])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["custom-recipes-v1.json"])
    }

    func testLoadIssueMessagesNameTheSkippedRecipesAndTheCopy() {
        let skipped = CustomRecipeLibraryLoadIssue(
            problem: .skippedRecipes([
                .init(name: "Night Walk", reason: "a name is required"),
                .init(name: "Recipe 4", reason: "filmSimulation: Cannot initialize FilmSimulation from invalid UInt32 value 9999")
            ]),
            backupURL: URL(fileURLWithPath: "/tmp/custom-recipes-v1.unreadable-20260927-012400.json")
        )
        let unreadable = CustomRecipeLibraryLoadIssue(
            problem: .unreadableFile(reason: "The given data was not valid JSON"),
            backupURL: nil
        )

        XCTAssertEqual(
            skipped.message,
            "2 custom recipes couldn’t be read and were left out: “Night Walk” (a name is required), “Recipe 4” (filmSimulation: Cannot initialize FilmSimulation from invalid UInt32 value 9999). The original file was copied to “custom-recipes-v1.unreadable-20260927-012400.json”. Changes to My Recipes won’t be saved until you dismiss this."
        )
        XCTAssertEqual(
            unreadable.message,
            "FujiRecipes couldn’t read your custom recipe library (The given data was not valid JSON). FujiRecipes couldn’t make a copy of the original file, so it was left untouched. Changes to My Recipes won’t be saved until you dismiss this."
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
