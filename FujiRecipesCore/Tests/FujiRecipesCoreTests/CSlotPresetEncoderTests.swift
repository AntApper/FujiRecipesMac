import XCTest
@testable import FujiRecipesCore

final class CSlotPresetEncoderTests: XCTestCase {
    func testFilmKitRawPresetExampleUsesTenthsAndProprietaryNR() throws {
        let recipe = Recipe(
            id: "filmkit-example",
            name: "FilmKit Example",
            source: "test",
            sourceUrl: nil,
            filmSimulation: .classicChrome,
            dynamicRange: .dr400,
            grainEffect: .strongSmall,
            colorChrome: .strong,
            colorChromeFxBlue: .weak,
            smoothSkin: .off,
            whiteBalanceMode: .daylight,
            wbShiftRed: -2,
            wbShiftBlue: 3,
            highlight: 2,
            shadow: -1,
            color: 4,
            sharpness: -4,
            highIsoNr: 3,
            clarity: -5
        )

        let raw = try CSlotPresetEncoder.encode(recipe: recipe, slot: 4)

        XCTAssertEqual(raw.dynamicRange, 400)
        XCTAssertEqual(raw.grainEffect, 3)
        XCTAssertEqual(raw.colorChrome, 3)
        XCTAssertEqual(raw.colorChromeFxBlue, 2)
        XCTAssertEqual(raw.smoothSkin, 1)
        XCTAssertEqual(raw.whiteBalance, 4)
        XCTAssertEqual(raw.wbShiftRed, -2)
        XCTAssertEqual(raw.wbShiftBlue, 3)
        XCTAssertNil(raw.colorTemp)
        XCTAssertEqual(raw.highlight, 20)
        XCTAssertEqual(raw.shadow, -10)
        XCTAssertEqual(raw.color, 40)
        XCTAssertEqual(raw.sharpness, -40)
        XCTAssertEqual(raw.highIsoNr, 0x6000)
        XCTAssertEqual(raw.clarity, -50)
    }

    func testDynamicRangeGrainAndEffectsUseVerifiedRawValues() throws {
        let ranges: [(DynamicRange, UInt32)] = [(.auto, 0xFFFF), (.dr100, 100), (.dr200, 200), (.dr400, 400)]
        let grains: [(GrainEffect, UInt32)] = [
            (.off, 1), (.weakSmall, 2), (.strongSmall, 3), (.weakLarge, 4), (.strongLarge, 5)
        ]
        let effects: [(EffectIntensity, UInt32)] = [(.off, 1), (.weak, 2), (.strong, 3)]

        for (range, expected) in ranges {
            let raw = try CSlotPresetEncoder.encode(recipe: recipe(dynamicRange: range), slot: 1)
            XCTAssertEqual(raw.dynamicRange, expected)
        }
        for (grain, expected) in grains {
            let raw = try CSlotPresetEncoder.encode(recipe: recipe(grain: grain), slot: 1)
            XCTAssertEqual(raw.grainEffect, expected)
        }
        for (effect, expected) in effects {
            let raw = try CSlotPresetEncoder.encode(recipe: recipe(effect: effect), slot: 1)
            XCTAssertEqual(raw.colorChrome, expected)
            XCTAssertEqual(raw.colorChromeFxBlue, expected)
            XCTAssertEqual(raw.smoothSkin, expected)
        }
    }

    func testAllFilmKitHighISONoiseReductionMappings() throws {
        let expected: [Int32: UInt32] = [
            -4: 0x8000, -3: 0x7000, -2: 0x4000, -1: 0x3000,
             0: 0x2000,  1: 0x1000,  2: 0x0000,  3: 0x6000,  4: 0x5000
        ]

        for (ui, rawValue) in expected {
            let raw = try CSlotPresetEncoder.encode(recipe: recipe(highIsoNr: ui), slot: 1)
            XCTAssertEqual(raw.highIsoNr, rawValue, "UI \(ui)")
        }
    }

    func testUniversalNegativeC4SourceRawValuesRoundTripThroughEncoder() throws {
        // This is the production record selected in the C4 UI hardware
        // validation. Its display text describes a multi-recipe article, but
        // C-slot writes must preserve the normalized `presetSettings`.
        let testFile = URL(fileURLWithPath: #filePath)
        let repository = testFile
            .deletingLastPathComponent() // FujiRecipesCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // FujiRecipesCore
            .deletingLastPathComponent() // repository root
        let resource = repository
            .appendingPathComponent("FujiRecipesMac/macos/Resources/recipes-data.json")
        let database = try JSONDecoder().decode(RecipesData.self, from: Data(contentsOf: resource))
        let source = try XCTUnwrap(database.recipes.first {
            $0.id == "universal-negative-14-fujifilm-x100vi-x-trans-v-film-simulation-recipes-yes-14"
        })

        let recipe = RecipeLoader.recipe(from: source)
        let raw = try CSlotPresetEncoder.encode(recipe: recipe, slot: 4)

        XCTAssertEqual(source.settings["colorChromeFxBlue"], "Strong")
        XCTAssertEqual(source.presetSettings["colorChromeFxBlue"], 2)
        XCTAssertEqual(source.settings["highIsoNr"], "-4")
        XCTAssertEqual(source.presetSettings["highIsoNr"], 32_768)
        XCTAssertEqual(recipe.colorChromeFxBlue, .weak)
        XCTAssertEqual(recipe.highIsoNr, -4)
        XCTAssertEqual(raw.colorChromeFxBlue, 2, "D197")
        XCTAssertEqual(raw.highIsoNr, 0x8000, "D1A1")
    }

    func testColorTemperatureIsConditionalOnColorTemperatureWB() throws {
        let colorTemp = try CSlotPresetEncoder.encode(
            recipe: recipe(wb: .colorTemperature, colorTemp: 5_600),
            slot: 1
        )
        let daylight = try CSlotPresetEncoder.encode(
            recipe: recipe(wb: .daylight, colorTemp: 5_600),
            slot: 1
        )

        XCTAssertEqual(colorTemp.whiteBalance, 0x8007)
        XCTAssertEqual(colorTemp.colorTemp, 5_600)
        XCTAssertEqual(daylight.whiteBalance, 4)
        XCTAssertNil(daylight.colorTemp)
    }

    func testMonochromeRecipeOmitsColorButKeepsRawToneValues() throws {
        let raw = try CSlotPresetEncoder.encode(
            recipe: recipe(filmSimulation: .acros, color: 4, shadow: 3, sharpness: -2),
            slot: 1
        )

        XCTAssertNil(raw.color)
        XCTAssertEqual(raw.shadow, 30)
        XCTAssertEqual(raw.sharpness, -20)
    }

    func testRawToneDecodingPreventsLoadoutDoubleScaling() {
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: 40), 4)
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: -20), -2)
        XCTAssertNil(CSlotPresetEncoder.uiTone(from: Int32(Int16.min)))
    }

    func testRejectsOutOfRangeValuesBeforePTPWrite() {
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(shadow: 5), slot: 1)) {
            XCTAssertEqual(
                $0 as? CSlotPresetEncodingError,
                .outOfRange(property: 0xD19E, value: 5, valid: "-2...4")
            )
        }
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(highIsoNr: 5), slot: 1))
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(wb: .colorTemperature), slot: 1))
    }

    private func recipe(
        filmSimulation: FilmSimulation? = .classicChrome,
        dynamicRange: DynamicRange? = nil,
        grain: GrainEffect? = nil,
        effect: EffectIntensity? = nil,
        wb: WhiteBalanceMode? = nil,
        colorTemp: UInt32? = nil,
        wbShiftRed: Int32? = nil,
        wbShiftBlue: Int32? = nil,
        highlight: Int32? = nil,
        color: Int32? = nil,
        shadow: Int32? = nil,
        sharpness: Int32? = nil,
        highIsoNr: Int32? = nil,
        clarity: Int32? = nil
    ) -> Recipe {
        Recipe(
            id: UUID().uuidString,
            name: "Test",
            source: "test",
            sourceUrl: nil,
            filmSimulation: filmSimulation,
            dynamicRange: dynamicRange,
            grainEffect: grain,
            colorChrome: effect,
            colorChromeFxBlue: effect,
            smoothSkin: effect,
            whiteBalanceMode: wb,
            wbShiftRed: wbShiftRed,
            wbShiftBlue: wbShiftBlue,
            colorTempK: colorTemp,
            highlight: highlight,
            shadow: shadow,
            color: color,
            sharpness: sharpness,
            highIsoNr: highIsoNr,
            clarity: clarity
        )
    }
}
