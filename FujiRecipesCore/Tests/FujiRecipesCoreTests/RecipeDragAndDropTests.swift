import XCTest
@testable import FujiRecipesCore

final class RecipeDragAndDropTests: XCTestCase {
    private let loadoutsKey = "com.ant.fuji-recipes.loadouts"

    func testRecipeCodableSerializationRoundTrip() throws {
        let recipe = Recipe(
            id: "vintage-kodachrome",
            name: "Vintage Kodachrome",
            source: "FujiWeekly",
            sourceUrl: "https://example.com/vintage-kodachrome",
            previewImageUrl: "https://example.com/preview.jpg",
            imageUrls: ["https://example.com/1.jpg", "https://example.com/2.jpg"],
            filmSimulation: .classicChrome,
            dynamicRange: .dr400,
            grainEffect: .strongSmall,
            colorChrome: .strong,
            colorChromeFxBlue: .weak,
            smoothSkin: .off,
            whiteBalanceMode: .daylight,
            wbShiftRed: 2,
            wbShiftBlue: -4,
            colorTempK: 5600,
            highlight: -1,
            shadow: 2,
            color: 3,
            sharpness: -2,
            highIsoNr: -4,
            clarity: -3,
            iso: "Auto up to 6400",
            exposureCompensation: "+1/3",
            settings: [
                "filmSimulation": "Classic Chrome",
                "dynamicRange": "DR400",
                "grainEffect": "Strong Small"
            ],
            sensorGeneration: "X-Trans V",
            compatibleCameras: ["X100VI"],
            tags: ["Vintage", "Street"],
            parseStatus: .ok
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(recipe)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(Recipe.self, from: data)

        XCTAssertEqual(decoded.id, "vintage-kodachrome")
        XCTAssertEqual(decoded.name, "Vintage Kodachrome")
        XCTAssertEqual(decoded.filmSimulation, .classicChrome)
        XCTAssertEqual(decoded.dynamicRange, .dr400)
        XCTAssertEqual(decoded.grainEffect, .strongSmall)
        XCTAssertEqual(decoded.colorChrome, .strong)
        XCTAssertEqual(decoded.colorChromeFxBlue, .weak)
        XCTAssertEqual(decoded.smoothSkin, .off)
        XCTAssertEqual(decoded.whiteBalanceMode, .daylight)
        XCTAssertEqual(decoded.wbShiftRed, 2)
        XCTAssertEqual(decoded.wbShiftBlue, -4)
        XCTAssertEqual(decoded.colorTempK, 5600)
        XCTAssertEqual(decoded.highlight, -1)
        XCTAssertEqual(decoded.shadow, 2)
        XCTAssertEqual(decoded.color, 3)
        XCTAssertEqual(decoded.sharpness, -2)
        XCTAssertEqual(decoded.highIsoNr, -4)
        XCTAssertEqual(decoded.clarity, -3)
        XCTAssertEqual(decoded.tags, ["Vintage", "Street"])
    }

    @MainActor
    func testApplyRecipeToLoadoutSlotStagesCorrectly() async throws {
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
        let recipe = Recipe(
            id: "reala-cinematic",
            name: "Reala Cinematic",
            source: "Community",
            sourceUrl: nil,
            filmSimulation: .realaAce,
            dynamicRange: .dr200,
            grainEffect: .weakSmall,
            colorChrome: .weak,
            colorChromeFxBlue: .strong,
            smoothSkin: .off,
            whiteBalanceMode: .auto,
            wbShiftRed: 1,
            wbShiftBlue: -2,
            highlight: 1,
            shadow: -1,
            color: 2,
            sharpness: 1,
            highIsoNr: -2,
            clarity: 2
        )

        store.applyRecipe(recipe, to: 3)

        let loadout = try XCTUnwrap(store.loadout(for: 3))
        XCTAssertEqual(loadout.slot, 3)
        XCTAssertEqual(loadout.name, "Reala Cinematic")
        XCTAssertEqual(loadout.recipeName, "Reala Cinematic")
        XCTAssertEqual(loadout.recipeID, "reala-cinematic")
        XCTAssertEqual(loadout.filmSim, .realaAce)
        XCTAssertEqual(loadout.dr, .dr200)
        XCTAssertEqual(loadout.grain, .weakSmall)
        XCTAssertEqual(loadout.colorChrome, .weak)
        XCTAssertEqual(loadout.colorChromeFxBlue, .strong)
        XCTAssertEqual(loadout.smoothSkin, .off)
        XCTAssertEqual(loadout.wb, .auto)
        XCTAssertEqual(loadout.wbShiftRed, 1)
        XCTAssertEqual(loadout.wbShiftBlue, -2)
        XCTAssertEqual(loadout.highlight, 1)
        XCTAssertEqual(loadout.shadow, -1)
        XCTAssertEqual(loadout.color, 2)
        XCTAssertEqual(loadout.sharpness, 1)
        XCTAssertEqual(loadout.highIsoNr, -2)
        XCTAssertEqual(loadout.clarity, 2)
        XCTAssertEqual(loadout.provenance, .localDraft)
        XCTAssertTrue(store.isDirty(3))
        XCTAssertNil(loadout.rawPreset)
    }

    @MainActor
    func testApplyMultipleRecipesToDifferentSlots() async throws {
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
        let recipe1 = Recipe(id: "rec-1", name: "Classic Summer", source: "test", sourceUrl: nil, filmSimulation: .classicChrome)
        let recipe2 = Recipe(id: "rec-2", name: "Velvia Nature", source: "test", sourceUrl: nil, filmSimulation: .velvia)
        let recipe7 = Recipe(id: "rec-7", name: "Acros Noir", source: "test", sourceUrl: nil, filmSimulation: .acros)

        store.applyRecipe(recipe1, to: 1)
        store.applyRecipe(recipe2, to: 2)
        store.applyRecipe(recipe7, to: 7)

        XCTAssertEqual(store.loadout(for: 1)?.name, "Classic Summer")
        XCTAssertEqual(store.loadout(for: 1)?.filmSim, .classicChrome)
        XCTAssertEqual(store.loadout(for: 2)?.name, "Velvia Nature")
        XCTAssertEqual(store.loadout(for: 2)?.filmSim, .velvia)
        XCTAssertEqual(store.loadout(for: 7)?.name, "Acros Noir")
        XCTAssertEqual(store.loadout(for: 7)?.filmSim, .acros)
        XCTAssertEqual(store.loadoutCountWithSettings(), 3)
        XCTAssertTrue(store.isDirty(1))
        XCTAssertTrue(store.isDirty(2))
        XCTAssertTrue(store.isDirty(7))
        XCTAssertFalse(store.isDirty(4))
    }
}
