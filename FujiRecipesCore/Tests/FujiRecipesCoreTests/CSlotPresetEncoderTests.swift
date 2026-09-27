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
            .appendingPathComponent("macos/Resources/recipes-data.json")
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

    func testCameraToneDecodingTruncatesHalfSteps() {
        // Raw +1.5 must stay UI +1 so an editor change to +2 clears the raw tenth.
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: 15), 1)
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: -15), -1)
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: 5), 0)
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: -5), 0)
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: 25), 2)
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: -25), -2)
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: 10), 1)
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: -10), -1)
        XCTAssertEqual(RecipeLoader.catalogTone(from: 5), 1)
        XCTAssertEqual(RecipeLoader.catalogTone(from: -5), -1)
        XCTAssertEqual(RecipeLoader.catalogTone(from: 15), 2)
        XCTAssertEqual(RecipeLoader.catalogTone(from: -15), -2)
        XCTAssertEqual(RecipeLoader.catalogTone(from: 25), 3)
        XCTAssertEqual(RecipeLoader.catalogTone(from: -25), -3)
    }

    func testBundledHalfStepRecipesKeepExactToneTenths() throws {
        let database = try bundledRecipeDatabase()
        let kodachrome = try XCTUnwrap(database.recipes.first { $0.id == "kodachrome-64" })
        let recipe = RecipeLoader.recipe(from: kodachrome)
        XCTAssertEqual(kodachrome.settings["shadow"], "+0.5")
        XCTAssertEqual(recipe.shadow, 1, "UI shadow rounds +0.5 to +1")
        XCTAssertEqual(recipe.sourceRawPreset?.shadow, 5)
        let encoded = try CSlotPresetEncoder.encode(recipe: recipe, slot: 1)
        XCTAssertEqual(encoded.shadow, 5, "C-slot write keeps shadow +0.5")

        let amber = try XCTUnwrap(database.recipes.first { $0.id == "classic-amber" })
        let amberRecipe = RecipeLoader.recipe(from: amber)
        XCTAssertEqual(amber.settings["highlight"], "-1.5")
        XCTAssertEqual(amber.settings["shadow"], "+2.5")
        XCTAssertEqual(amberRecipe.highlight, -2)
        XCTAssertEqual(amberRecipe.shadow, 3)
        let encodedAmber = try CSlotPresetEncoder.encode(recipe: amberRecipe, slot: 2)
        XCTAssertEqual(encodedAmber.highlight, -15, "C-slot write keeps highlight -1.5")
        XCTAssertEqual(encodedAmber.shadow, 25, "C-slot write keeps shadow +2.5")
    }

    func testRejectsOutOfRangeValuesBeforePTPWrite() {
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(shadow: 5), slot: 1)) {
            XCTAssertEqual(
                $0 as? CSlotPresetEncodingError,
                .outOfRange(property: 0xD19E, value: 5, valid: "-2...4")
            )
        }
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(highIsoNr: 5), slot: 1))
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(wb: .colorTemperature, colorTemp: 12_000), slot: 1)) {
            XCTAssertEqual(
                $0 as? CSlotPresetEncodingError,
                .outOfRange(property: 0xD19C, value: 12_000, valid: "2500...10000 K")
            )
        }
    }

    func testColorTemperatureDefaultsTo5500WhenMissing() throws {
        let preset = try CSlotPresetEncoder.encode(recipe: recipe(wb: .colorTemperature), slot: 1)
        XCTAssertEqual(preset.whiteBalance, 0x8007)
        XCTAssertEqual(preset.colorTemp, 5_500)
    }

    // MARK: - Objective 3: Extreme Kelvin Boundary Tests

    func testExtremeKelvinValuesAndBoundaryRejections() throws {
        // Valid exact lower bound: 2500K
        let minKelvin = try CSlotPresetEncoder.encode(
            recipe: recipe(wb: .colorTemperature, colorTemp: 2_500),
            slot: 1
        )
        XCTAssertEqual(minKelvin.colorTemp, 2_500)

        // Valid exact upper bound: 10000K
        let maxKelvin = try CSlotPresetEncoder.encode(
            recipe: recipe(wb: .colorTemperature, colorTemp: 10_000),
            slot: 1
        )
        XCTAssertEqual(maxKelvin.colorTemp, 10_000)

        // Out of bounds: 2499K (1 Kelvin below minimum)
        XCTAssertThrowsError(
            try CSlotPresetEncoder.encode(
                recipe: recipe(wb: .colorTemperature, colorTemp: 2_499),
                slot: 1
            )
        ) { error in
            XCTAssertEqual(
                error as? CSlotPresetEncodingError,
                .outOfRange(property: 0xD19C, value: 2_499, valid: "2500...10000 K")
            )
        }

        // Out of bounds: 10001K (1 Kelvin above maximum)
        XCTAssertThrowsError(
            try CSlotPresetEncoder.encode(
                recipe: recipe(wb: .colorTemperature, colorTemp: 10_001),
                slot: 1
            )
        ) { error in
            XCTAssertEqual(
                error as? CSlotPresetEncodingError,
                .outOfRange(property: 0xD19C, value: 10_001, valid: "2500...10000 K")
            )
        }

        // Extreme values: 0 and 25000
        XCTAssertThrowsError(
            try CSlotPresetEncoder.encode(
                recipe: recipe(wb: .colorTemperature, colorTemp: 0),
                slot: 1
            )
        )
        XCTAssertThrowsError(
            try CSlotPresetEncoder.encode(
                recipe: recipe(wb: .colorTemperature, colorTemp: 25_000),
                slot: 1
            )
        )

        // Non-colorTemperature WB mode ignores Kelvin value and encodes nil
        let autoWithKelvin = try CSlotPresetEncoder.encode(
            recipe: recipe(wb: .auto, colorTemp: 2_500),
            slot: 1
        )
        XCTAssertNil(autoWithKelvin.colorTemp)
        XCTAssertEqual(autoWithKelvin.whiteBalance, 2)
    }

    // MARK: - Objective 3: Tone Curves (-4 to +4) and Boundary Validation

    func testExtremeToneCurvesAndBoundaryValidation() throws {
        // Highlight range is -2...4
        let minHighlight = try CSlotPresetEncoder.encode(recipe: recipe(highlight: -2), slot: 1)
        XCTAssertEqual(minHighlight.highlight, -20)
        let maxHighlight = try CSlotPresetEncoder.encode(recipe: recipe(highlight: 4), slot: 1)
        XCTAssertEqual(maxHighlight.highlight, 40)

        // Highlight below -2 (e.g. -3, -4) must throw
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(highlight: -3), slot: 1)) {
            XCTAssertEqual($0 as? CSlotPresetEncodingError, .outOfRange(property: 0xD19D, value: -3, valid: "-2...4"))
        }
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(highlight: -4), slot: 1)) {
            XCTAssertEqual($0 as? CSlotPresetEncodingError, .outOfRange(property: 0xD19D, value: -4, valid: "-2...4"))
        }
        // Highlight above +4 must throw
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(highlight: 5), slot: 1)) {
            XCTAssertEqual($0 as? CSlotPresetEncodingError, .outOfRange(property: 0xD19D, value: 5, valid: "-2...4"))
        }

        // Shadow range is -2...4
        let minShadow = try CSlotPresetEncoder.encode(recipe: recipe(shadow: -2), slot: 1)
        XCTAssertEqual(minShadow.shadow, -20)
        let maxShadow = try CSlotPresetEncoder.encode(recipe: recipe(shadow: 4), slot: 1)
        XCTAssertEqual(maxShadow.shadow, 40)

        // Shadow below -2 must throw
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(shadow: -3), slot: 1)) {
            XCTAssertEqual($0 as? CSlotPresetEncodingError, .outOfRange(property: 0xD19E, value: -3, valid: "-2...4"))
        }
        // Shadow above +4 must throw
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(shadow: 5), slot: 1)) {
            XCTAssertEqual($0 as? CSlotPresetEncodingError, .outOfRange(property: 0xD19E, value: 5, valid: "-2...4"))
        }

        // Color range is -4...4
        for val: Int32 in -4...4 {
            let encoded = try CSlotPresetEncoder.encode(recipe: recipe(filmSimulation: .provia, color: val), slot: 1)
            XCTAssertEqual(encoded.color, val * 10, "Color \(val) should encode to \(val * 10)")
        }
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(color: -5), slot: 1)) {
            XCTAssertEqual($0 as? CSlotPresetEncodingError, .outOfRange(property: 0xD19F, value: -5, valid: "-4...4"))
        }
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(color: 5), slot: 1)) {
            XCTAssertEqual($0 as? CSlotPresetEncodingError, .outOfRange(property: 0xD19F, value: 5, valid: "-4...4"))
        }

        // Sharpness range is -4...4
        for val: Int32 in -4...4 {
            let encoded = try CSlotPresetEncoder.encode(recipe: recipe(sharpness: val), slot: 1)
            XCTAssertEqual(encoded.sharpness, val * 10, "Sharpness \(val) should encode to \(val * 10)")
        }
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(sharpness: -5), slot: 1)) {
            XCTAssertEqual($0 as? CSlotPresetEncodingError, .outOfRange(property: 0xD1A0, value: -5, valid: "-4...4"))
        }
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(sharpness: 5), slot: 1)) {
            XCTAssertEqual($0 as? CSlotPresetEncodingError, .outOfRange(property: 0xD1A0, value: 5, valid: "-4...4"))
        }

        // Clarity range is -5...5
        let minClarity = try CSlotPresetEncoder.encode(recipe: recipe(clarity: -5), slot: 1)
        XCTAssertEqual(minClarity.clarity, -50)
        let maxClarity = try CSlotPresetEncoder.encode(recipe: recipe(clarity: 5), slot: 1)
        XCTAssertEqual(maxClarity.clarity, 50)
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(clarity: -6), slot: 1))
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(clarity: 6), slot: 1))

        // White Balance Shift range is -9...9
        let minWBRed = try CSlotPresetEncoder.encode(recipe: recipe(wbShiftRed: -9), slot: 1)
        XCTAssertEqual(minWBRed.wbShiftRed, -9)
        let maxWBRed = try CSlotPresetEncoder.encode(recipe: recipe(wbShiftRed: 9), slot: 1)
        XCTAssertEqual(maxWBRed.wbShiftRed, 9)
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(wbShiftRed: -10), slot: 1))
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(wbShiftRed: 10), slot: 1))

        let minWBBlue = try CSlotPresetEncoder.encode(recipe: recipe(wbShiftBlue: -9), slot: 1)
        XCTAssertEqual(minWBBlue.wbShiftBlue, -9)
        let maxWBBlue = try CSlotPresetEncoder.encode(recipe: recipe(wbShiftBlue: 9), slot: 1)
        XCTAssertEqual(maxWBBlue.wbShiftBlue, 9)
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(wbShiftBlue: -10), slot: 1))
        XCTAssertThrowsError(try CSlotPresetEncoder.encode(recipe: recipe(wbShiftBlue: 10), slot: 1))

        // UITone boundary conversions
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: 40), 4)
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: -40), -4)
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: 0), 0)
        XCTAssertEqual(CSlotPresetEncoder.uiTone(from: -20), -2)
        XCTAssertNil(CSlotPresetEncoder.uiTone(from: nil))
        XCTAssertNil(CSlotPresetEncoder.uiTone(from: Int32(Int16.min)))
    }

    // MARK: - Objective 3: Monochrome Recipe Edge Cases

    func testAllMonochromeSimulationsOmitColorAndRetainMonochromeToning() throws {
        let monochromeSimulations: [FilmSimulation] = [
            .monochrome,
            .monochromeY,
            .monochromeR,
            .monochromeG,
            .sepia,
            .acros,
            .acrosY,
            .acrosR,
            .acrosG
        ]

        for sim in monochromeSimulations {
            // Recipe specifies color: 4, but monochrome must force raw.color to nil
            let r = recipe(
                filmSimulation: sim,
                highlight: 2,
                color: 4,
                shadow: -1,
                sharpness: 3,
                clarity: -2
            )
            let encoded = try CSlotPresetEncoder.encode(recipe: r, slot: 1)

            XCTAssertNil(encoded.color, "\(sim) must omit color property (0xD19F)")
            XCTAssertEqual(encoded.highlight, 20, "\(sim) must preserve highlight tenths")
            XCTAssertEqual(encoded.shadow, -10, "\(sim) must preserve shadow tenths")
            XCTAssertEqual(encoded.sharpness, 30, "\(sim) must preserve sharpness tenths")
            XCTAssertEqual(encoded.clarity, -20, "\(sim) must preserve clarity tenths")
        }

        // Test Loadout with monochrome toning (monoWarmCool, monoMagentaGreen)
        var loadout = Loadout(slot: 2, name: "Acros Warm", filmSim: .acros)
        loadout.color = 4 // Staged color
        loadout.monoWarmCool = 3
        loadout.monoMagentaGreen = -2
        loadout.highlight = 1
        loadout.shadow = -1

        let encodedLoadout = try CSlotPresetEncoder.encode(loadout: loadout, slot: 2)
        XCTAssertNil(encodedLoadout.color, "Acros loadout must omit color")
        XCTAssertEqual(encodedLoadout.monoWarmCool, 3, "Acros loadout must pass monoWarmCool")
        XCTAssertEqual(encodedLoadout.monoMagentaGreen, -2, "Acros loadout must pass monoMagentaGreen")
        XCTAssertEqual(encodedLoadout.highlight, 10)
        XCTAssertEqual(encodedLoadout.shadow, -10)

        // Non-monochrome simulation MUST include color
        let proviaRecipe = recipe(filmSimulation: .provia, color: 3)
        let encodedProvia = try CSlotPresetEncoder.encode(recipe: proviaRecipe, slot: 1)
        XCTAssertEqual(encodedProvia.color, 30, "Color film simulation must encode color tenths")
    }

    func testAllBundledRecipesEncodeSuccessfullyForCSlot() throws {
        let database = try bundledRecipeDatabase()

        XCTAssertEqual(database.recipes.count, 50, "Expected exactly 50 recipes in recipes-data.json")

        let monochrome: Set<FilmSimulation> = [
            .monochrome, .monochromeY, .monochromeR, .monochromeG,
            .sepia, .acros, .acrosY, .acrosR, .acrosG
        ]

        for jsonRecipe in database.recipes {
            let recipe = RecipeLoader.recipe(from: jsonRecipe)
            let encoded = try CSlotPresetEncoder.encode(recipe: recipe, slot: 1)
            let preset = jsonRecipe.presetSettings
            assertTone(preset["highlightTone"], equals: encoded.highlight, recipe: recipe.name, field: "highlight")
            assertTone(preset["shadowTone"], equals: encoded.shadow, recipe: recipe.name, field: "shadow")
            assertTone(preset["sharpness"], equals: encoded.sharpness, recipe: recipe.name, field: "sharpness")
            assertTone(preset["clarity"], equals: encoded.clarity, recipe: recipe.name, field: "clarity")
            if let film = recipe.filmSimulation, monochrome.contains(film) {
                XCTAssertNil(encoded.color, "\(recipe.name) must omit color")
            } else {
                assertTone(preset["color"], equals: encoded.color, recipe: recipe.name, field: "color")
            }
        }
    }

    func testRecipeLoaderFindsCatalogNestedInBundleSubdirectory() throws {
        let bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NestedRecipes-\(UUID().uuidString).bundle", isDirectory: true)
        let nested = bundleURL.appendingPathComponent("Contents/Resources/Resources", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: bundleURL) }
        try FileManager.default.copyItem(
            at: bundledRecipeURL(),
            to: nested.appendingPathComponent("recipes-data.json")
        )
        let bundle = try XCTUnwrap(Bundle(url: bundleURL))

        XCTAssertEqual(try RecipeLoader.loadRecipes(from: bundle, subdirectory: "Resources").count, 50)
        XCTAssertThrowsError(try RecipeLoader.loadRecipes(from: bundle)) { error in
            XCTAssertEqual(error as? RecipeLoaderError, .fileNotFound)
        }
    }

    @MainActor
    func testHalfStepShadowSurvivesRecipeAndLoadoutEncode() throws {
        let defaults = UserDefaults.standard
        let key = "com.ant.fuji-recipes.loadouts"
        let original = defaults.data(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        defaults.removeObject(forKey: key)

        let raw = LoadoutRawPresetState(shadow: 5)
        let recipe = Recipe(
            id: "half-step",
            name: "Half Step",
            source: "test",
            sourceUrl: nil,
            filmSimulation: .classicChrome,
            shadow: 0,
            sourceRawPreset: raw
        )

        let encodedRecipe = try CSlotPresetEncoder.encode(recipe: recipe, slot: 1)
        XCTAssertEqual(encodedRecipe.shadow, 5, "shadow +0.5 must stay raw tenths 5")

        let store = LoadoutStore()
        store.applyRecipe(recipe, to: 2)
        let loadout = try XCTUnwrap(store.loadout(for: 2))
        XCTAssertEqual(loadout.shadow, 0)
        XCTAssertEqual(loadout.rawPreset?.shadow, 5)
        let encodedLoadout = try CSlotPresetEncoder.encode(loadout: loadout, slot: 2)
        XCTAssertEqual(encodedLoadout.shadow, 5)

        let edited = recipe.mutating(shadow: 2)
        XCTAssertNil(edited.sourceRawPreset?.shadow)
        let encodedEdit = try CSlotPresetEncoder.encode(recipe: edited, slot: 1)
        XCTAssertEqual(encodedEdit.shadow, 20)
    }

    private func assertTone(
        _ preset: Double?,
        equals encoded: Int32?,
        recipe: String,
        field: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if let preset {
            XCTAssertEqual(encoded, Int32(preset.rounded(.towardZero)), "\(recipe) \(field)", file: file, line: line)
        } else {
            XCTAssertNil(encoded, "\(recipe) \(field)", file: file, line: line)
        }
    }

    private func bundledRecipeDatabase() throws -> RecipesData {
        try JSONDecoder().decode(RecipesData.self, from: Data(contentsOf: bundledRecipeURL()))
    }

    private func bundledRecipeURL() -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        let repository = testFile
            .deletingLastPathComponent() // FujiRecipesCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // FujiRecipesCore
            .deletingLastPathComponent() // repository root
        return repository.appendingPathComponent("macos/Resources/recipes-data.json")
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
