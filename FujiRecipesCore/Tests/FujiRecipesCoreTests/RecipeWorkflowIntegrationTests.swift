import XCTest
@testable import FujiRecipesCore

final class RecipeWorkflowIntegrationTests: XCTestCase {
    private var tempDirectory: URL!
    private let loadoutsKey = "com.ant.fuji-recipes.loadouts"

    override func setUpWithError() throws {
        try super.setUpWithError()
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecipeWorkflowIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Comprehensive 11-Step End-to-End Workflow Integration Test

    @MainActor
    func testCompleteEndToEndRecipeWorkflow() async throws {
        // ---------------------------------------------------------------------
        // Step 1: Load bundled recipes catalog into RecipeStore
        // ---------------------------------------------------------------------
        let bundled = try loadBundledRecipes()
        XCTAssertGreaterThan(bundled.count, 20, "Expected a realistic set of bundled recipes from recipes-data.json")

        let customStorageURL = tempDirectory.appendingPathComponent("custom-recipes-v1.json")
        let customLibrary = CustomRecipeLibrary(storageURL: customStorageURL, loadOnInit: false)
        let recipeStore = RecipeStore(
            recipeLoading: { bundled },
            customRecipes: customLibrary
        )

        recipeStore.loadRecipesSynchronously()
        XCTAssertEqual(recipeStore.loadingState, .loaded)
        XCTAssertEqual(recipeStore.recipes.count, bundled.count)
        XCTAssertFalse(recipeStore.recipes.isEmpty)

        // ---------------------------------------------------------------------
        // Step 2: Filter by search query, film simulation family, and White Balance
        // ---------------------------------------------------------------------
        // 2a. Filter by search query
        recipeStore.searchQuery = "Summer"
        XCTAssertFalse(recipeStore.filteredRecipes.isEmpty)
        for recipe in recipeStore.filteredRecipes {
            XCTAssertTrue(
                recipe.name.localizedCaseInsensitiveContains("Summer"),
                "Recipe \(recipe.name) should match search query 'Summer'"
            )
        }

        // 2b. Filter by film simulation family
        recipeStore.searchQuery = ""
        recipeStore.selectedFilmSimFamily = .classicChrome
        XCTAssertFalse(recipeStore.filteredRecipes.isEmpty)
        for recipe in recipeStore.filteredRecipes {
            XCTAssertTrue(
                RecipeStore.FilmSimFamily.classicChrome.matches(recipe.filmSimulation),
                "Recipe \(recipe.name) should match Classic Chrome family"
            )
        }

        // 2c. Filter by White Balance mode
        let targetWB = try XCTUnwrap(
            recipeStore.filteredRecipes.compactMap(\.whiteBalanceMode).first,
            "Expected at least one white balance mode in Classic Chrome filtered recipes"
        )
        recipeStore.selectedWhiteBalance = targetWB
        XCTAssertFalse(recipeStore.filteredRecipes.isEmpty)
        for recipe in recipeStore.filteredRecipes {
            XCTAssertEqual(recipe.whiteBalanceMode, targetWB)
        }

        // Clear filters for subsequent operations
        recipeStore.selectedWhiteBalance = nil
        recipeStore.selectedFilmSimFamily = .all
        recipeStore.searchQuery = ""

        // ---------------------------------------------------------------------
        // Step 3: Duplicate a curated recipe into CustomRecipeLibrary
        // ---------------------------------------------------------------------
        let curatedRecipe = try XCTUnwrap(
            recipeStore.recipes.first { $0.filmSimulation == .classicChrome && $0.hasFullPTPMapped },
            "Expected at least one fully PTP-mapped Classic Chrome recipe in catalog"
        )

        let duplicatedRecipe = curatedRecipe.duplicated()
        XCTAssertNotEqual(duplicatedRecipe.id, curatedRecipe.id)
        XCTAssertTrue(duplicatedRecipe.id.hasPrefix("custom-"))
        XCTAssertEqual(duplicatedRecipe.name, "\(curatedRecipe.name) (Custom)")
        XCTAssertEqual(duplicatedRecipe.source, "Customized from \(curatedRecipe.name)")
        XCTAssertEqual(duplicatedRecipe.filmSimulation, curatedRecipe.filmSimulation)
        XCTAssertEqual(duplicatedRecipe.dynamicRange, curatedRecipe.dynamicRange)
        XCTAssertEqual(duplicatedRecipe.grainEffect, curatedRecipe.grainEffect)
        XCTAssertEqual(duplicatedRecipe.highlight, curatedRecipe.highlight)
        XCTAssertEqual(duplicatedRecipe.shadow, curatedRecipe.shadow)
        XCTAssertEqual(duplicatedRecipe.color, curatedRecipe.color)
        XCTAssertEqual(duplicatedRecipe.sharpness, curatedRecipe.sharpness)
        XCTAssertEqual(duplicatedRecipe.clarity, curatedRecipe.clarity)
        XCTAssertEqual(duplicatedRecipe.highIsoNr, curatedRecipe.highIsoNr)

        // ---------------------------------------------------------------------
        // Step 4: Mutate settings (e.g. adjust Highlight +2, Color -1, Kelvin to 6200K)
        // ---------------------------------------------------------------------
        let mutatedRecipe = duplicatedRecipe.mutating(
            whiteBalanceMode: .colorTemperature,
            colorTempK: 6200,
            highlight: 2,
            color: -1
        )

        XCTAssertEqual(mutatedRecipe.highlight, 2)
        XCTAssertEqual(mutatedRecipe.color, -1)
        XCTAssertEqual(mutatedRecipe.whiteBalanceMode, .colorTemperature)
        XCTAssertEqual(mutatedRecipe.colorTempK, 6200)
        XCTAssertEqual(mutatedRecipe.id, duplicatedRecipe.id)
        XCTAssertEqual(mutatedRecipe.name, "\(curatedRecipe.name) (Custom)")
        XCTAssertEqual(mutatedRecipe.source, "Customized from \(curatedRecipe.name)")

        // ---------------------------------------------------------------------
        // Step 5: Validate duplicate detection and name collision rejection
        // ---------------------------------------------------------------------
        // Save the first customized recipe
        try customLibrary.save(mutatedRecipe, disallowNameCollision: true)
        XCTAssertEqual(customLibrary.recipes.count, 1)

        // Attempt to create another recipe with a distinct ID but identical name
        let collidingRecipe = Recipe(
            id: "custom-another-\(UUID().uuidString.lowercased())",
            name: mutatedRecipe.name,
            source: "Another source",
            sourceUrl: nil,
            filmSimulation: .velvia
        )

        // Validate collision detection finds the conflict
        let conflict = customLibrary.conflictingRecipe(named: collidingRecipe.name, excludingID: collidingRecipe.id)
        XCTAssertNotNil(conflict, "Expected conflict detection for duplicate name")
        XCTAssertEqual(conflict?.id, mutatedRecipe.id)
        XCTAssertEqual(conflict?.name, mutatedRecipe.name)

        // Validate name collision is rejected by uniqueness check
        XCTAssertThrowsError(
            try customLibrary.validateNameUniqueness(for: collidingRecipe),
            "Saving with duplicate name must throw validation error"
        ) { error in
            guard let customError = error as? CustomRecipeLibraryError,
                  case .invalidRecipe(let message) = customError else {
                XCTFail("Expected invalidRecipe error, got \(error)")
                return
            }
            XCTAssertTrue(message.contains(mutatedRecipe.name))
        }

        // Validate that save with disallowNameCollision rejects the collision
        XCTAssertThrowsError(
            try customLibrary.save(collidingRecipe, disallowNameCollision: true)
        )

        // Validate that updating the original recipe with the SAME id is NOT rejected
        XCTAssertNoThrow(try customLibrary.validateNameUniqueness(for: mutatedRecipe))
        XCTAssertNoThrow(try customLibrary.save(mutatedRecipe, disallowNameCollision: true))

        // ---------------------------------------------------------------------
        // Step 6: Save customized recipe to custom library and verify it persists and reloads from disk
        // ---------------------------------------------------------------------
        XCTAssertEqual(customLibrary.recipes.count, 1)

        // Instantiate fresh library from the exact disk file
        let reloadedLibrary = CustomRecipeLibrary(storageURL: customStorageURL)
        XCTAssertEqual(reloadedLibrary.recipes.count, 1)
        let reloaded = try XCTUnwrap(reloadedLibrary.recipes.first)
        XCTAssertEqual(reloaded.id, mutatedRecipe.id)
        XCTAssertEqual(reloaded.name, mutatedRecipe.name)
        XCTAssertEqual(reloaded.source, "Customized from \(curatedRecipe.name)")
        XCTAssertEqual(reloaded.filmSimulation, mutatedRecipe.filmSimulation)
        XCTAssertEqual(reloaded.highlight, 2)
        XCTAssertEqual(reloaded.color, -1)
        XCTAssertEqual(reloaded.whiteBalanceMode, .colorTemperature)
        XCTAssertEqual(reloaded.colorTempK, 6200)

        // Verify RecipeStore automatically reflects the new recipe in My Recipes
        XCTAssertTrue(recipeStore.isCustomRecipe(mutatedRecipe))
        XCTAssertTrue(recipeStore.recipes.contains { $0.id == mutatedRecipe.id })
        recipeStore.selectedFilterCategory = .myRecipes
        XCTAssertEqual(recipeStore.filteredRecipes.count, 1)
        XCTAssertEqual(recipeStore.filteredRecipes.first?.id, mutatedRecipe.id)
        recipeStore.selectedFilterCategory = nil

        // ---------------------------------------------------------------------
        // Step 7: Stage the customized recipe to Custom Dial Slot C3 in LoadoutStore
        // ---------------------------------------------------------------------
        let loadoutStore = LoadoutStore()

        loadoutStore.applyRecipe(mutatedRecipe, to: 3)
        XCTAssertTrue(loadoutStore.isDirty(3))
        XCTAssertEqual(loadoutStore.dirtySlots, [3])
        XCTAssertEqual(loadoutStore.loadout(for: 3)?.provenance, .localDraft)

        // ---------------------------------------------------------------------
        // Step 8: Verify slot C3 adopts all tone curves, Kelvin white balance, and film simulation
        // ---------------------------------------------------------------------
        let slot3 = try XCTUnwrap(loadoutStore.loadout(for: 3))
        XCTAssertEqual(slot3.slot, 3)
        XCTAssertEqual(slot3.name, mutatedRecipe.name)
        XCTAssertEqual(slot3.recipeID, mutatedRecipe.id)
        XCTAssertEqual(slot3.recipeName, mutatedRecipe.name)
        XCTAssertEqual(slot3.filmSim, mutatedRecipe.filmSimulation)
        XCTAssertEqual(slot3.dr, mutatedRecipe.dynamicRange)
        XCTAssertEqual(slot3.grain, mutatedRecipe.grainEffect)
        XCTAssertEqual(slot3.wb, .colorTemperature)
        XCTAssertEqual(slot3.colorTempK, 6200)
        XCTAssertEqual(slot3.highlight, 2)
        XCTAssertEqual(slot3.color, -1)
        XCTAssertEqual(slot3.shadow, mutatedRecipe.shadow)
        XCTAssertEqual(slot3.sharpness, mutatedRecipe.sharpness)
        XCTAssertEqual(slot3.highIsoNr, mutatedRecipe.highIsoNr)
        XCTAssertEqual(slot3.clarity, mutatedRecipe.clarity)
        XCTAssertTrue(slot3.hasAnySettings)

        // ---------------------------------------------------------------------
        // Step 9: Simulate camera connection and batch write all staged slots with mock PTP client
        // ---------------------------------------------------------------------
        let mockClient = WorkflowMockPTPClient()
        let cameraManager = CameraManager()
        await cameraManager.connect(using: mockClient)
        XCTAssertEqual(cameraManager.status, .connected)

        let batchResults = await cameraManager.writeAllStagedSlots(from: loadoutStore)

        // Verify only slot 3 was written
        XCTAssertEqual(batchResults.count, 1)
        XCTAssertEqual(batchResults[0].slot, 3)
        guard case .success(let writeResult) = batchResults[0].result else {
            XCTFail("Expected successful camera write for slot C3")
            return
        }
        XCTAssertEqual(writeResult.slot, 3)
        XCTAssertEqual(mockClient.writtenSlots, [3])

        // Verify the data written to the camera preset matches the customized recipe settings
        let cameraData = try XCTUnwrap(mockClient.slotPresets[3])
        XCTAssertEqual(cameraData.colorTemp, 6200)
        XCTAssertEqual(cameraData.whiteBalance, 0x8007)
        XCTAssertEqual(cameraData.highlight, 20)
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: cameraData.highlight), 2)
        XCTAssertEqual(cameraData.color, -10)
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: cameraData.color), -1)
        XCTAssertEqual(cameraData.filmSimulation, mutatedRecipe.filmSimulation?.rawValue)

        // ---------------------------------------------------------------------
        // Step 10: Verify loadout provenance transitions to .cameraSynced with 0 unsynced drafts
        // ---------------------------------------------------------------------
        let syncedSlot3 = try XCTUnwrap(loadoutStore.loadout(for: 3))
        XCTAssertEqual(syncedSlot3.provenance, .cameraSynced)
        XCTAssertFalse(loadoutStore.isDirty(3))
        XCTAssertEqual(loadoutStore.dirtySlots.count, 0, "All staged drafts must be synced")

        // ---------------------------------------------------------------------
        // Step 11: Verify unassigned slots remain clean and empty
        // ---------------------------------------------------------------------
        let unassignedSlots = [1, 2, 4, 5, 6, 7]
        for slotNumber in unassignedSlots {
            let slot = try XCTUnwrap(loadoutStore.loadout(for: slotNumber))
            XCTAssertEqual(slot.name, "C\(slotNumber)")
            XCTAssertNil(slot.filmSim)
            XCTAssertFalse(slot.hasAnySettings, "Slot C\(slotNumber) must have no settings")
            XCTAssertFalse(loadoutStore.isDirty(slotNumber), "Slot C\(slotNumber) must not be dirty")
        }
        XCTAssertEqual(mockClient.writtenSlots, [3], "Camera PTP write must have touched only slot C3")
    }

    // MARK: - Focused Workflow Sub-Tests

    @MainActor
    func testRecipeDuplicationPreservesAllToneCurveAndPTPFields() throws {
        let original = Recipe(
            id: "test-curated",
            name: "Velvia Vivid Landscape",
            source: "Curated Collection",
            sourceUrl: "https://example.com/velvia",
            previewImageUrl: "https://example.com/thumb.jpg",
            imageUrls: ["https://example.com/1.jpg"],
            filmSimulation: .velvia,
            dynamicRange: .dr400,
            grainEffect: .weakSmall,
            colorChrome: .strong,
            colorChromeFxBlue: .weak,
            smoothSkin: .off,
            whiteBalanceMode: .daylight,
            wbShiftRed: 3,
            wbShiftBlue: -2,
            colorTempK: 5800,
            highlight: 1,
            shadow: -1,
            color: 2,
            sharpness: 1,
            highIsoNr: -2,
            clarity: 1,
            iso: "Auto, up to 6400",
            exposureCompensation: "+1/3",
            settings: ["highlight": "+1", "shadow": "-1"],
            sensorGeneration: "X-Trans V",
            compatibleCameras: ["X100VI"],
            tags: ["Landscape", "Vivid"],
            parseStatus: .ok
        )

        let duplicate = original.duplicated()

        XCTAssertNotEqual(duplicate.id, original.id)
        XCTAssertTrue(duplicate.id.hasPrefix("custom-"))
        XCTAssertEqual(duplicate.name, "Velvia Vivid Landscape (Custom)")
        XCTAssertEqual(duplicate.source, "Customized from Velvia Vivid Landscape")
        XCTAssertEqual(duplicate.filmSimulation, .velvia)
        XCTAssertEqual(duplicate.dynamicRange, .dr400)
        XCTAssertEqual(duplicate.grainEffect, .weakSmall)
        XCTAssertEqual(duplicate.colorChrome, .strong)
        XCTAssertEqual(duplicate.colorChromeFxBlue, .weak)
        XCTAssertEqual(duplicate.smoothSkin, .off)
        XCTAssertEqual(duplicate.whiteBalanceMode, .daylight)
        XCTAssertEqual(duplicate.wbShiftRed, 3)
        XCTAssertEqual(duplicate.wbShiftBlue, -2)
        XCTAssertEqual(duplicate.highlight, 1)
        XCTAssertEqual(duplicate.shadow, -1)
        XCTAssertEqual(duplicate.color, 2)
        XCTAssertEqual(duplicate.sharpness, 1)
        XCTAssertEqual(duplicate.highIsoNr, -2)
        XCTAssertEqual(duplicate.clarity, 1)
        XCTAssertEqual(duplicate.tags, ["My Recipes"])
    }

    @MainActor
    func testRecipeStoreFiltersBySearchSimAndWhiteBalanceTogether() throws {
        let recipes = [
            Recipe(id: "1", name: "Urban Street", source: "A", sourceUrl: nil, filmSimulation: .classicChrome, whiteBalanceMode: .auto),
            Recipe(id: "2", name: "Urban Sunset", source: "A", sourceUrl: nil, filmSimulation: .classicChrome, whiteBalanceMode: .daylight),
            Recipe(id: "3", name: "Nature Green", source: "B", sourceUrl: nil, filmSimulation: .velvia, whiteBalanceMode: .auto),
            Recipe(id: "4", name: "Night Street", source: "C", sourceUrl: nil, filmSimulation: .acros, whiteBalanceMode: .incandescent)
        ]

        let store = RecipeStore(recipeLoading: { recipes })
        store.loadRecipesSynchronously()

        store.searchQuery = "Urban"
        store.selectedFilmSimFamily = .classicChrome
        store.selectedWhiteBalance = .auto

        XCTAssertEqual(store.filteredRecipes.map(\.id), ["1"])

        store.selectedWhiteBalance = .daylight
        XCTAssertEqual(store.filteredRecipes.map(\.id), ["2"])

        store.selectedWhiteBalance = nil
        XCTAssertEqual(store.filteredRecipes.map(\.id), ["1", "2"])
    }

    @MainActor
    func testGalleryFollowsEachCustomRecipeChange() throws {
        let library = CustomRecipeLibrary(storageURL: tempDirectory.appendingPathComponent("custom-recipes-v1.json"))
        let store = RecipeStore(
            recipeLoading: { [Recipe(id: "bundled", name: "Bundled", source: "A", sourceUrl: nil, filmSimulation: .velvia)] },
            customRecipes: library
        )
        store.loadRecipesSynchronously()

        try library.save(Recipe(id: "custom-alpha", name: "Alpha", source: "My Recipes", sourceUrl: nil, filmSimulation: .classicChrome))
        XCTAssertEqual(store.recipes.map(\.name), ["Bundled", "Alpha"])

        try library.save(Recipe(id: "custom-bravo", name: "Bravo", source: "My Recipes", sourceUrl: nil, filmSimulation: .classicChrome))
        try library.delete(id: "custom-alpha")
        XCTAssertEqual(store.recipes.map(\.name), ["Bundled", "Bravo"])
    }

    // MARK: - Helpers

    private func loadBundledRecipes() throws -> [Recipe] {
        let testFile = URL(fileURLWithPath: #filePath)
        let repository = testFile
            .deletingLastPathComponent() // FujiRecipesCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // FujiRecipesCore
            .deletingLastPathComponent() // repository root
        let resource = repository.appendingPathComponent("macos/Resources/recipes-data.json")
        let data = try Data(contentsOf: resource)
        let json = try JSONDecoder().decode(RecipesData.self, from: data)
        return json.recipes
            .filter(RecipeLoader.shouldIncludeInX100VICatalog)
            .map(RecipeLoader.recipe(from:))
    }
}

// MARK: - Workflow Mock PTP Client

private final class WorkflowMockPTPClient: PTPClientProtocol, @unchecked Sendable {
    var isConnected = true
    var cameraInfo = PTPCameraInfo(model: "FUJIFILM X100VI")
    var failSlots: Set<Int> = []
    private(set) var writtenSlots: [Int] = []
    var slotPresets: [Int: PTPClientPresetData] = [:]

    init() {
        for slot in 1...7 {
            slotPresets[slot] = PTPClientPresetData(slot: slot, name: "C\(slot)")
        }
    }

    func connect() async throws { isConnected = true }
    func disconnect() { isConnected = false }

    func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse {
        .unsupported
    }

    func writeProperty(_ code: UInt16, value: Int32) async throws {}

    func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        return slotPresets[index] ?? PTPClientPresetData(slot: index)
    }

    func writePresetSlot(_ index: Int, data: PTPClientPresetData) async throws -> PTPPresetSlotWriteResult {
        if failSlots.contains(index) {
            throw PTPError.writeFailed(0xD18E, "Slot \(index) write error")
        }
        writtenSlots.append(index)
        slotPresets[index] = data
        return PTPPresetSlotWriteResult(
            slot: index,
            createdFromEmpty: false,
            warnings: [],
            baseline: .configured(data),
            rollback: .notNeeded,
            observedSnapshot: data
        )
    }

    func readNativeProfile() async throws -> Data { Data() }
    func writePTPSettings(from recipe: Recipe) async throws {}
    func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)?) async -> RAFConversionOutcome {
        .failed(message: "unsupported")
    }
    func capturePreview() async throws -> JPEGFile? { nil }
}
