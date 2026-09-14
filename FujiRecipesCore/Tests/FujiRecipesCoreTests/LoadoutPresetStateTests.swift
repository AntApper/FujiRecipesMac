import XCTest
@testable import FujiRecipesCore

@MainActor
final class LoadoutPresetStateTests: XCTestCase {
    private let loadoutsKey = "com.ant.fuji-recipes.loadouts"

    func testCameraSyncRetainsEveryPresetFieldAndRoundTripsIt() throws {
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: loadoutsKey)
        defer {
            if let original {
                defaults.set(original, forKey: loadoutsKey)
            } else {
                defaults.removeObject(forKey: loadoutsKey)
            }
        }
        defaults.removeObject(forKey: loadoutsKey)

        let observed = PTPClientPresetData(
            slot: 3,
            name: "C3 Complete",
            imageQuality: 4,
            imageSize: 2,
            dynamicRange: 400,
            filmSimulation: FilmSimulation.classicChrome.rawValue,
            monoWarmCool: -3,
            monoMagentaGreen: 2,
            grainEffect: 5,
            colorChrome: 3,
            colorChromeFxBlue: 2,
            smoothSkin: 1,
            whiteBalance: WhiteBalanceMode.colorTemperature.actualPTPValue,
            wbShiftRed: -4,
            wbShiftBlue: 5,
            colorTemp: 5_600,
            // Non-multiple tenths verify that the raw observation—not the
            // lossy UI value—is sent back to the camera.
            highlight: 15,
            shadow: -20,
            color: 30,
            sharpness: -40,
            highIsoNr: 0x7000,
            clarity: 25,
            longExpNr: 1,
            colorSpace: 2
        )

        let store = LoadoutStore()
        store.syncFromCameraPresetData([observed])

        let loadout = try XCTUnwrap(store.loadout(for: 3))
        XCTAssertEqual(loadout.imageQuality, 4)
        XCTAssertEqual(loadout.monoWarmCool, -3)
        XCTAssertEqual(loadout.colorChrome, .strong)
        XCTAssertEqual(loadout.wbShiftBlue, 5)
        XCTAssertEqual(loadout.highIsoNr, -3)
        XCTAssertEqual(loadout.longExpNr, 1)
        XCTAssertEqual(loadout.rawPreset?.highlight, 15)

        let encoded = try CSlotPresetEncoder.encode(loadout: loadout, slot: 3)
        XCTAssertEqual(encoded, observed)
    }

    func testApplyingRecipeKeepsItsExtendedPresetSettings() throws {
        let recipe = Recipe(
            id: "complete",
            name: "Complete",
            source: "test",
            sourceUrl: nil,
            filmSimulation: .classicChrome,
            dynamicRange: .dr400,
            grainEffect: .strongLarge,
            colorChrome: .strong,
            colorChromeFxBlue: .weak,
            smoothSkin: .off,
            whiteBalanceMode: .colorTemperature,
            wbShiftRed: -2,
            wbShiftBlue: 3,
            colorTempK: 5_600,
            highlight: 2,
            shadow: -1,
            color: 4,
            sharpness: -4,
            highIsoNr: 3,
            clarity: -5
        )
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: loadoutsKey)
        defer {
            if let original {
                defaults.set(original, forKey: loadoutsKey)
            } else {
                defaults.removeObject(forKey: loadoutsKey)
            }
        }
        defaults.removeObject(forKey: loadoutsKey)

        let store = LoadoutStore()
        store.applyRecipe(recipe, to: 1)
        let loadout = try XCTUnwrap(store.loadout(for: 1))
        let encoded = try CSlotPresetEncoder.encode(loadout: loadout, slot: 1)

        XCTAssertEqual(encoded.colorChrome, 3)
        XCTAssertEqual(encoded.colorChromeFxBlue, 2)
        XCTAssertEqual(encoded.smoothSkin, 1)
        XCTAssertEqual(encoded.wbShiftRed, -2)
        XCTAssertEqual(encoded.wbShiftBlue, 3)
        XCTAssertEqual(encoded.colorTemp, 5_600)
        XCTAssertEqual(encoded.highIsoNr, 0x6000)
        XCTAssertEqual(encoded.clarity, -50)
    }

    func testSavingDirectEditorChangesOverridesRawValuesAndPreservesUnknowns() throws {
        let defaults = UserDefaults.standard
        let original = defaults.data(forKey: loadoutsKey)
        defer {
            if let original {
                defaults.set(original, forKey: loadoutsKey)
            } else {
                defaults.removeObject(forKey: loadoutsKey)
            }
        }
        defaults.removeObject(forKey: loadoutsKey)

        let observed = PTPClientPresetData(
            slot: 2,
            name: "C2",
            imageQuality: 4,
            filmSimulation: FilmSimulation.classicChrome.rawValue,
            colorChrome: 3,
            colorChromeFxBlue: 99,
            highlight: 15,
            colorSpace: 0xFEED
        )
        let store = LoadoutStore()
        store.syncFromCameraPresetData([observed])

        var editorDraft = try XCTUnwrap(store.loadout(for: 2))
        editorDraft.highlight = 2
        editorDraft.colorChrome = nil
        store.saveLocalDraft(editorDraft)

        let saved = try XCTUnwrap(store.loadout(for: 2))
        let encoded = try CSlotPresetEncoder.encode(loadout: saved, slot: 2)

        XCTAssertEqual(encoded.highlight, 20, "The editor's UI value overrides raw tenths.")
        XCTAssertNil(encoded.colorChrome, "An intentional UI clear removes stale raw state.")
        XCTAssertEqual(encoded.imageQuality, 4, "Unedited camera-only fields round-trip.")
        XCTAssertEqual(encoded.colorChromeFxBlue, 99, "Unknown uneditable values round-trip.")
        XCTAssertEqual(encoded.colorSpace, 0xFEED, "Unknown camera-only values round-trip.")
    }
}
