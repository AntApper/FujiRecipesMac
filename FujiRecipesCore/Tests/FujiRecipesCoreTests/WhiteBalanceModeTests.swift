import XCTest
@testable import FujiRecipesCore

final class WhiteBalanceModeTests: XCTestCase {
    func testStoredRawValuesDecodeToTheModeTheCameraWrites() throws {
        XCTAssertEqual(try decode("5"), .incandescent)
        XCTAssertEqual(try decode("6"), .incandescent)
        XCTAssertEqual(try decode("32800"), .autoWhitePriority)
    }

    func testAnUnknownRawValueDoesNotDecode() {
        XCTAssertThrowsError(try decode("1"))
    }

    func testIncandescentEncodesAsTheCameraCode() throws {
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(WhiteBalanceMode.incandescent), as: UTF8.self), "6")
    }

    func testCameraModesAreTheFourteenCodesTheX100VIAccepts() {
        XCTAssertEqual(WhiteBalanceMode.cameraModes.count, 14)
        XCTAssertEqual(
            Set(WhiteBalanceMode.cameraModes.map(\.rawValue)),
            [0x0002, 0x0004, 0x0006, 0x0008, 0x8001, 0x8002, 0x8003, 0x8006, 0x8007, 0x8008, 0x8009, 0x800A, 0x8020, 0x8021]
        )
    }

    func testCatalogWhiteBalanceComesFromPresetSettings() {
        let recipe = RecipeLoader.recipe(from: RecipeJSON(
            id: "shade-walk",
            name: "Shade Walk",
            sensorGeneration: "X-Trans V",
            filmSimulation: nil,
            filmSimEnum: nil,
            settings: [:],
            ptpSettings: ["whiteBalance": 4],
            presetSettings: ["whiteBalance": 32774],
            sourceUrl: nil,
            previewImageUrl: nil,
            imageUrls: nil,
            date: nil,
            compatibleCameras: nil
        ))

        XCTAssertEqual(recipe.whiteBalanceMode?.displayName, "Shade")
    }

    func testCatalogWhiteBalanceSixReadsAsIncandescentAndWritesSix() throws {
        let recipe = RecipeLoader.recipe(from: RecipeJSON(
            id: "classic-bw",
            name: "Classic B&W",
            sensorGeneration: "X-Trans V",
            filmSimulation: nil,
            filmSimEnum: nil,
            settings: [:],
            ptpSettings: ["whiteBalance": 6],
            presetSettings: [:],
            sourceUrl: nil,
            previewImageUrl: nil,
            imageUrls: nil,
            date: nil,
            compatibleCameras: nil
        ))

        XCTAssertEqual(recipe.whiteBalanceMode?.displayName, "Incandescent")
        XCTAssertEqual(try CSlotPresetEncoder.encode(recipe: recipe, slot: 1).whiteBalance, 6)
    }

    @MainActor
    func testAStagedDraftSavedWithTheOldTungstenValueStillLoads() throws {
        let suite = "WhiteBalanceModeTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.set(
            Data(#"[{"slot":1,"name":"Night Walk","wb":5,"provenance":"localDraft"}]"#.utf8),
            forKey: "com.ant.fuji-recipes.loadouts"
        )

        let store = LoadoutStore(defaults: defaults)

        XCTAssertNil(store.recoveryNotice)
        XCTAssertEqual(store.loadout(for: 1)?.wb, .incandescent)
    }

    @MainActor
    func testACustomRecipeSavedWithTheOldTungstenValueStillLoads() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("custom-recipes-v1.json")
        let archive = CustomRecipeLibraryExport(recipes: [
            Recipe(id: "custom-night", name: "Night Walk", source: "My Recipes", sourceUrl: nil, filmSimulation: .acros, whiteBalanceMode: .auto)
        ])
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(archive)) as? [String: Any])
        var recipes = try XCTUnwrap(json["recipes"] as? [[String: Any]])
        recipes[0]["whiteBalanceMode"] = 5
        json["recipes"] = recipes
        try JSONSerialization.data(withJSONObject: json).write(to: url)

        let library = CustomRecipeLibrary(storageURL: url)

        XCTAssertNil(library.loadIssue)
        XCTAssertEqual(library.recipes.first?.whiteBalanceMode, .incandescent)
    }

    private func decode(_ json: String) throws -> WhiteBalanceMode {
        try JSONDecoder().decode(WhiteBalanceMode.self, from: Data(json.utf8))
    }
}
