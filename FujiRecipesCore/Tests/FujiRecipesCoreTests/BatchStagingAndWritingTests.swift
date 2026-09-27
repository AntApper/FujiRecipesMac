import XCTest
@testable import FujiRecipesCore

final class BatchStagingAndWritingTests: XCTestCase {
    private let loadoutsKey = "com.ant.fuji-recipes.loadouts"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
        super.tearDown()
    }

    // MARK: - RedScale & Kelvin Fallback Tests

    func testRedScaleRecipeInJSONHasColorTemp10000() throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let repository = testFile
            .deletingLastPathComponent() // FujiRecipesCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // FujiRecipesCore
            .deletingLastPathComponent() // repository root
        let resource = repository.appendingPathComponent("macos/Resources/recipes-data.json")
        let database = try JSONDecoder().decode(RecipesData.self, from: Data(contentsOf: resource))
        let redscale = try XCTUnwrap(database.recipes.first { $0.id == "redscale" })

        XCTAssertEqual(redscale.ptpSettings["colorTemp"], 10000)
        XCTAssertEqual(redscale.presetSettings["colorTemp"], 10000)
        XCTAssertEqual(redscale.settings["whiteBalance"], "10000K, +9 Red & -9 Blue")

        let recipe = RecipeLoader.recipe(from: redscale)
        XCTAssertEqual(recipe.colorTempK, 10000)
        XCTAssertEqual(recipe.whiteBalanceMode, .colorTemperature)
    }

    func testRecipeLoaderColorTempFallbacks() {
        // 1. From presetSettings
        let jsonWithPreset = makeRecipeJSON(
            presetSettings: ["colorTemp": 6200],
            ptpSettings: ["colorTemp": 4000],
            settings: ["whiteBalance": "7000K"]
        )
        XCTAssertEqual(RecipeLoader.recipe(from: jsonWithPreset).colorTempK, 6200)

        // 2. From ptpSettings when presetSettings is missing
        let jsonWithPTP = makeRecipeJSON(
            presetSettings: [:],
            ptpSettings: ["colorTemp": 4200],
            settings: ["whiteBalance": "7000K"]
        )
        XCTAssertEqual(RecipeLoader.recipe(from: jsonWithPTP).colorTempK, 4200)

        // 3. From regex in settings["whiteBalance"] (e.g. 10000K)
        let jsonWithRegex = makeRecipeJSON(
            presetSettings: [:],
            ptpSettings: [:],
            settings: ["whiteBalance": "10000K, +9 Red & -9 Blue"]
        )
        XCTAssertEqual(RecipeLoader.recipe(from: jsonWithRegex).colorTempK, 10000)

        // 4. From regex with space (e.g. "5600 K")
        let jsonWithSpacedRegex = makeRecipeJSON(
            presetSettings: [:],
            ptpSettings: [:],
            settings: ["whiteBalance": "5600 K, -1 Red"]
        )
        XCTAssertEqual(RecipeLoader.recipe(from: jsonWithSpacedRegex).colorTempK, 5600)

        // 5. Default to 5500 when wb is .colorTemperature and no colorTemp is available
        let jsonWithColorTempWB = makeRecipeJSON(
            presetSettings: [:],
            ptpSettings: ["whiteBalance": Double(WhiteBalanceMode.colorTemperature.rawValue)],
            settings: ["whiteBalance": "Custom WB"]
        )
        let recipeColorTempWB = RecipeLoader.recipe(from: jsonWithColorTempWB)
        XCTAssertEqual(recipeColorTempWB.whiteBalanceMode, .colorTemperature)
        XCTAssertEqual(recipeColorTempWB.colorTempK, 5500)

        // 6. WB is not .colorTemperature and no colorTemp available -> nil
        let jsonDaylight = makeRecipeJSON(
            presetSettings: [:],
            ptpSettings: ["whiteBalance": Double(WhiteBalanceMode.daylight.rawValue)],
            settings: ["whiteBalance": "Daylight"]
        )
        let recipeDaylight = RecipeLoader.recipe(from: jsonDaylight)
        XCTAssertEqual(recipeDaylight.whiteBalanceMode, .daylight)
        XCTAssertNil(recipeDaylight.colorTempK)
    }

    func testCSlotPresetEncoderColorTempFallbackTo5500() throws {
        // Recipe with wb == .colorTemperature and colorTempK == nil
        let recipe = Recipe(
            id: "fallback-test",
            name: "Fallback Test",
            source: "test",
            sourceUrl: nil,
            filmSimulation: .classicChrome,
            whiteBalanceMode: .colorTemperature,
            colorTempK: nil
        )

        let encoded = try CSlotPresetEncoder.encode(recipe: recipe, slot: 1)
        XCTAssertEqual(encoded.whiteBalance, 0x8007)
        XCTAssertEqual(encoded.colorTemp, 5500)

        // Loadout with wb == .colorTemperature and colorTempK == nil
        let loadout = Loadout(
            slot: 2,
            name: "Loadout Fallback",
            filmSim: .classicChrome,
            wb: .colorTemperature,
            colorTempK: nil
        )
        let encodedLoadout = try CSlotPresetEncoder.encode(loadout: loadout, slot: 2)
        XCTAssertEqual(encodedLoadout.whiteBalance, 0x8007)
        XCTAssertEqual(encodedLoadout.colorTemp, 5500)
    }

    // MARK: - LoadoutStore Batch Staging Tests

    @MainActor
    func testStageAllTakesUpToSevenRecipesSequentially() {
        let store = LoadoutStore()
        let recipes = (1...9).map { i in
            Recipe(
                id: "recipe-\(i)",
                name: "Recipe \(i)",
                source: "test",
                sourceUrl: nil,
                filmSimulation: .classicChrome
            )
        }

        store.stageAll(recipes: recipes)

        // Should stage exactly the first 7 recipes into C1...C7
        for slot in 1...7 {
            let loadout = store.loadout(for: slot)
            XCTAssertNotNil(loadout)
            XCTAssertEqual(loadout?.name, "Recipe \(slot)")
            XCTAssertEqual(loadout?.recipeID, "recipe-\(slot)")
            XCTAssertEqual(loadout?.provenance, .localDraft)
            XCTAssertTrue(store.isDirty(slot))
            XCTAssertTrue(loadout?.hasAnySettings == true)
        }
    }

    @MainActor
    func testStageAllWithFewerThanSevenRecipes() {
        let store = LoadoutStore()
        let recipes = (1...3).map { i in
            Recipe(
                id: "rec-\(i)",
                name: "Staged \(i)",
                source: "test",
                sourceUrl: nil,
                filmSimulation: .velvia
            )
        }

        store.stageAll(recipes: recipes)

        // Slots 1...3 staged
        for slot in 1...3 {
            let loadout = store.loadout(for: slot)
            XCTAssertEqual(loadout?.name, "Staged \(slot)")
            XCTAssertTrue(store.isDirty(slot))
        }

        // Slots 4...7 remain default unconfigured
        for slot in 4...7 {
            let loadout = store.loadout(for: slot)
            XCTAssertEqual(loadout?.name, "C\(slot)")
            XCTAssertFalse(store.isDirty(slot))
            XCTAssertFalse(loadout?.hasAnySettings == true)
        }
    }

    @MainActor
    func testClearAllStagedClearsAllSevenSlots() {
        let store = LoadoutStore()
        let recipes = (1...7).map { i in
            Recipe(
                id: "rec-\(i)",
                name: "Recipe \(i)",
                source: "test",
                sourceUrl: nil,
                filmSimulation: .acros
            )
        }
        store.stageAll(recipes: recipes)

        // Clear all
        store.clearAllStaged()

        for slot in 1...7 {
            let loadout = store.loadout(for: slot)
            XCTAssertEqual(loadout?.name, "C\(slot)")
            XCTAssertNil(loadout?.filmSim)
            XCTAssertFalse(loadout?.hasAnySettings == true)
            XCTAssertEqual(loadout?.provenance, .localDraft)
            XCTAssertTrue(store.isDirty(slot))
        }
    }

    // MARK: - CameraManager Batch Write Tests

    @MainActor
    func testWriteAllStagedSlotsWritesConfiguredSlotsAndSyncsVerifiedSnapshots() async throws {
        let mockClient = BatchMockPTPClient()
        let manager = CameraManager()
        await manager.connect(using: mockClient)

        let store = LoadoutStore()
        store.applyRecipe(
            Recipe(id: "r1", name: "Recipe One", source: "test", sourceUrl: nil, filmSimulation: .classicChrome),
            to: 1
        )
        store.applyRecipe(
            Recipe(id: "r2", name: "Recipe Two", source: "test", sourceUrl: nil, filmSimulation: .velvia),
            to: 2
        )

        XCTAssertTrue(store.isDirty(1))
        XCTAssertTrue(store.isDirty(2))
        XCTAssertFalse(store.isDirty(3))

        let results = await manager.writeAllStagedSlots(from: store)

        // Only slots 1 and 2 had settings/dirty, so results count is 2
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].slot, 1)
        XCTAssertEqual(results[1].slot, 2)

        guard case .success(let writeResult1) = results[0].result,
              case .success(let writeResult2) = results[1].result else {
            XCTFail("Expected both slot writes to succeed")
            return
        }

        XCTAssertEqual(writeResult1.slot, 1)
        XCTAssertEqual(writeResult2.slot, 2)

        // Mock client wrote slots 1 and 2
        XCTAssertEqual(mockClient.writtenSlots, [1, 2])

        // Loadouts in store are now verified and not dirty
        let loadout1 = store.loadout(for: 1)
        let loadout2 = store.loadout(for: 2)
        XCTAssertEqual(loadout1?.provenance, .cameraSynced)
        XCTAssertEqual(loadout2?.provenance, .cameraSynced)
        XCTAssertFalse(store.isDirty(1))
        XCTAssertFalse(store.isDirty(2))
    }

    @MainActor
    func testWriteAllStagedSlotsHandlesPartialFailures() async {
        let mockClient = BatchMockPTPClient()
        mockClient.failSlots.insert(2) // Slot 2 write fails
        let manager = CameraManager()
        await manager.connect(using: mockClient)

        let store = LoadoutStore()
        store.applyRecipe(
            Recipe(id: "r1", name: "Recipe One", source: "test", sourceUrl: nil, filmSimulation: .classicChrome),
            to: 1
        )
        store.applyRecipe(
            Recipe(id: "r2", name: "Recipe Two", source: "test", sourceUrl: nil, filmSimulation: .velvia),
            to: 2
        )

        let results = await manager.writeAllStagedSlots(from: store)

        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].slot, 1)
        XCTAssertEqual(results[1].slot, 2)

        // Slot 1 should succeed
        guard case .success = results[0].result else {
            XCTFail("Slot 1 should have succeeded")
            return
        }
        XCTAssertEqual(store.loadout(for: 1)?.provenance, .cameraSynced)
        XCTAssertFalse(store.isDirty(1))

        // Slot 2 should fail
        guard case .failure = results[1].result else {
            XCTFail("Slot 2 should have failed")
            return
        }
        XCTAssertEqual(store.loadout(for: 2)?.provenance, .localDraft)
        XCTAssertTrue(store.isDirty(2))
    }

    @MainActor
    func testConnectKeepsStagedDraftsAndSyncsUntouchedSlots() async {
        let mockClient = seededCameraClient()
        let store = LoadoutStore()
        store.applyRecipe(
            Recipe(id: "offline", name: "Offline Draft", source: "test", sourceUrl: nil, filmSimulation: .velvia),
            to: 1
        )

        await CameraManager().connect(using: mockClient, loadouts: store)

        XCTAssertEqual(store.loadout(for: 1)?.name, "Offline Draft")
        XCTAssertTrue(store.isDirty(1))
        XCTAssertEqual(store.loadout(for: 2)?.name, "Camera 2")
        XCTAssertEqual(store.loadout(for: 2)?.provenance, .cameraSynced)
    }

    // MARK: - Helpers

    private func seededCameraClient() -> BatchMockPTPClient {
        let client = BatchMockPTPClient()
        for slot in 1...7 {
            client.slotPresets[slot] = PTPClientPresetData(
                slot: slot,
                name: "Camera \(slot)",
                filmSimulation: FilmSimulation.classicChrome.rawValue
            )
        }
        return client
    }

    private func makeRecipeJSON(
        presetSettings: [String: Double],
        ptpSettings: [String: Double],
        settings: [String: String]
    ) -> RecipeJSON {
        RecipeJSON(
            id: "test",
            name: "Test Recipe",
            sensorGeneration: "X-Trans V",
            filmSimulation: nil,
            filmSimEnum: 11,
            settings: settings,
            ptpSettings: ptpSettings,
            presetSettings: presetSettings,
            sourceUrl: nil,
            previewImageUrl: nil,
            imageUrls: nil,
            date: nil,
            compatibleCameras: ["X100VI"]
        )
    }
}

// MARK: - Mock PTP Client for Batch Testing

private final class BatchMockPTPClient: PTPClientProtocol, @unchecked Sendable {
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
