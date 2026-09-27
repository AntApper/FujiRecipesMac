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

    func testEveryRecipeWritesEveryCSlotFieldItsCardShows() throws {
        for source in try bundledRecipeCatalog().recipes {
            let text = source.settings
            let recipe = RecipeLoader.recipe(from: source)
            let raw = try CSlotPresetEncoder.encode(recipe: recipe, slot: 1)
            let id = source.id

            XCTAssertNotNil(raw.filmSimulation, "\(id) film simulation")
            XCTAssertNotNil(raw.dynamicRange, "\(id) dynamic range")
            XCTAssertNotNil(raw.grainEffect, "\(id) grain")
            XCTAssertNotNil(raw.colorChrome, "\(id) Color Chrome")
            XCTAssertNotNil(raw.colorChromeFxBlue, "\(id) FX Blue")
            XCTAssertEqual(raw.highlight, try cardTenths(text["highlight"]), "\(id) highlight")
            XCTAssertEqual(raw.shadow, try cardTenths(text["shadow"]), "\(id) shadow")
            XCTAssertEqual(raw.sharpness, try cardTenths(text["sharpness"]), "\(id) sharpness")
            XCTAssertEqual(raw.clarity, try cardTenths(text["clarity"]), "\(id) clarity")
            if recipe.filmSimulation.map(Self.monochrome.contains) == true {
                XCTAssertNil(raw.color, "\(id) color")
            } else {
                XCTAssertEqual(raw.color, try cardTenths(text["color"]), "\(id) color")
            }
            XCTAssertEqual(recipe.highIsoNr, text["highIsoNr"].flatMap { Int32($0) }, "\(id) High ISO NR")
            XCTAssertNotNil(raw.highIsoNr, "\(id) High ISO NR")

            let whiteBalance = try XCTUnwrap(text["whiteBalance"]).components(separatedBy: ", ")
            let shifts = whiteBalance[1].components(separatedBy: " ")
            let kelvin = whiteBalance[0].hasSuffix("K") ? UInt32(whiteBalance[0].dropLast()) : nil
            let mode = kelvin == nil ? Self.cardWhiteBalanceModes[whiteBalance[0]] : .colorTemperature
            XCTAssertNotNil(mode, "\(id) white balance text \(whiteBalance[0])")
            XCTAssertEqual(recipe.whiteBalanceMode, mode, "\(id) white balance")
            XCTAssertEqual(raw.whiteBalance, mode?.rawValue, "\(id) white balance")
            XCTAssertEqual(raw.colorTemp, kelvin, "\(id) color temperature")
            XCTAssertEqual(raw.wbShiftRed, Int32(shifts[0]), "\(id) red shift")
            XCTAssertEqual(raw.wbShiftBlue, Int32(shifts[3]), "\(id) blue shift")
        }
    }

    func testEveryRecipeHasASortableDate() throws {
        for source in try bundledRecipeCatalog().recipes {
            XCTAssertNotNil(RecipeLoader.recipe(from: source).date, "\(source.id) date \(source.date ?? "nil")")
        }
        let summer = try XCTUnwrap(bundledRecipeCatalog().recipes.first { $0.date == "2026-05-02" })
        XCTAssertEqual(RecipeLoader.recipe(from: summer).date?.timeIntervalSince1970, 1_777_680_000)
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

    private static let monochrome: Set<FilmSimulation> = [
        .monochrome, .monochromeY, .monochromeR, .monochromeG,
        .sepia, .acros, .acrosY, .acrosR, .acrosG
    ]

    private static let cardWhiteBalanceModes: [String: WhiteBalanceMode] = [
        "Auto": .auto,
        "Daylight": .daylight,
        "Incandescent": .incandescent,
        "Fluorescent 1": .fluorescent1,
        "Fluorescent 3": .fluorescent3,
        "Shade": .shade,
        "Ambience Priority": .ambiencePriority
    ]

    private func cardTenths(_ text: String?) throws -> Int32 {
        let value = try XCTUnwrap(text.flatMap(Double.init), "card tone \(text ?? "nil")")
        return Int32((value * 10).rounded())
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
