import XCTest
@testable import FujiRecipesCore

/// Recipe cards show `settings` text, while camera writes use the decoded
/// `presetSettings`. These tests hold the two together for every bundled recipe.
final class BundledCatalogTests: XCTestCase {
    func testDecodedEffectsMatchCardText() throws {
        for source in try bundledRecipeCatalog().recipes {
            let recipe = RecipeLoader.recipe(from: source)
            XCTAssertEqual(recipe.grainEffect?.displayName, source.settings["grainEffect"], "\(source.id) grain")
            XCTAssertEqual(recipe.colorChrome?.displayName, source.settings["colorChromeEffect"], "\(source.id) Color Chrome")
            XCTAssertEqual(recipe.colorChromeFxBlue?.displayName, source.settings["colorChromeFxBlue"], "\(source.id) FX Blue")
            XCTAssertEqual(recipe.dynamicRange?.displayName, source.settings["dynamicRange"], "\(source.id) dynamic range")
        }
    }

    func testLoaderDropsRawValuesThatAreNotExactCameraValues() {
        let recipe = RecipeLoader.recipe(from: RecipeJSON(
            id: "inexact",
            name: "Inexact",
            sensorGeneration: "X-Trans V",
            filmSimulation: nil,
            filmSimEnum: nil,
            settings: [:],
            ptpSettings: [:],
            presetSettings: [
                "grainEffect": -1,
                "colorChromeEffect": 2.5,
                "dynamicRange": 200.5,
                "highlightTone": 1e12,
                "wbShiftRed": -0.5
            ],
            sourceUrl: nil,
            previewImageUrl: nil,
            imageUrls: nil,
            date: nil,
            compatibleCameras: nil
        ))

        XCTAssertNil(recipe.grainEffect)
        XCTAssertNil(recipe.colorChrome)
        XCTAssertNil(recipe.dynamicRange)
        XCTAssertNil(recipe.highlight)
        XCTAssertNil(recipe.wbShiftRed)
    }
}

func bundledRecipeCatalog() throws -> RecipesData {
    try JSONDecoder().decode(RecipesData.self, from: Data(contentsOf: bundledRecipeCatalogURL()))
}

func bundledRecipeCatalogURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // FujiRecipesCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // FujiRecipesCore
        .deletingLastPathComponent() // repository root
        .appendingPathComponent("macos/Resources/recipes-data.json")
}
