import XCTest
@testable import FujiRecipesCore

final class HalfStepToneTests: XCTestCase {
    private let loadoutsKey = "com.ant.fuji-recipes.loadouts"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
        super.tearDown()
    }

    func testBundledRecipeWholeStepsTruncateLikeCameraReads() throws {
        let amber = try classicAmber()

        XCTAssertEqual(amber.highlight, -1)
        XCTAssertEqual(amber.shadow, 2)
        XCTAssertEqual(amber.sourceRawPreset?.highlight, -15)
        XCTAssertEqual(amber.sourceRawPreset?.shadow, 25)
    }

    @MainActor
    func testSlotEditorSaveKeepsTheHalfStepItSets() throws {
        let store = LoadoutStore()
        store.applyRecipe(try classicAmber(), to: 3)

        var draft = try XCTUnwrap(store.loadout(for: 3))
        draft.highlight = 2
        draft.rawPreset?.highlight = 25
        store.saveLocalDraft(draft)
        XCTAssertEqual(try encodedSlot3(store).highlight, 25, "-1.5 to +2.5")

        draft = try XCTUnwrap(store.loadout(for: 3))
        draft.highlight = -1
        draft.rawPreset?.highlight = -10
        store.saveLocalDraft(draft)
        XCTAssertEqual(try encodedSlot3(store).highlight, -10, "+2.5 to -1")

        draft = try XCTUnwrap(store.loadout(for: 3))
        draft.shadow = 3
        store.saveLocalDraft(draft)
        XCTAssertEqual(try encodedSlot3(store).shadow, 30, "a whole-step edit still replaces the stale +2.5")
    }

    func testToneTextMatchesRecipeCardFormatting() {
        XCTAssertEqual(ToneTenths.text(-15), "-1.5")
        XCTAssertEqual(ToneTenths.text(5), "+0.5")
        XCTAssertEqual(ToneTenths.text(-5), "-0.5")
        XCTAssertEqual(ToneTenths.text(20), "+2")
        XCTAssertEqual(ToneTenths.text(-20), "-2")
        XCTAssertEqual(ToneTenths.text(0), "0")
    }

    @MainActor
    func testRecipeAndStagedSlotShowTheSameTenths() throws {
        let amber = try classicAmber()
        let expected = ToneTenths(highlight: -1, shadow: 2, color: 4, sharpness: -2, raw: LoadoutRawPresetState(highlight: -15, shadow: 25))
        XCTAssertEqual(amber.toneTenths, expected)
        XCTAssertEqual(amber.toneTenths.highlight, -15)
        XCTAssertEqual(amber.toneTenths.shadow, 25)
        XCTAssertEqual(amber.toneTenths.color, 40)

        let store = LoadoutStore()
        store.applyRecipe(amber, to: 2)
        XCTAssertEqual(try XCTUnwrap(store.loadout(for: 2)).toneTenths, amber.toneTenths)

        let unset = Recipe(id: "unset", name: "Unset", source: "test", sourceUrl: nil)
        XCTAssertNil(unset.toneTenths.highlight)
        let emptySlot = Loadout(slot: 1, name: "C1", rawPreset: LoadoutRawPresetState(highlight: Int32(Int16.min)))
        XCTAssertNil(emptySlot.toneTenths.highlight, "0x8000 is Fuji's unset sentinel")
    }

    private func classicAmber() throws -> Recipe {
        let source = try XCTUnwrap(bundledRecipeCatalog().recipes.first { $0.id == "classic-amber" })
        return RecipeLoader.recipe(from: source)
    }

    @MainActor
    private func encodedSlot3(_ store: LoadoutStore) throws -> PTPClientPresetData {
        try CSlotPresetEncoder.encode(loadout: XCTUnwrap(store.loadout(for: 3)), slot: 3)
    }
}
