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

    private func classicAmber() throws -> Recipe {
        let source = try XCTUnwrap(bundledRecipeCatalog().recipes.first { $0.id == "classic-amber" })
        return RecipeLoader.recipe(from: source)
    }

    @MainActor
    private func encodedSlot3(_ store: LoadoutStore) throws -> PTPClientPresetData {
        try CSlotPresetEncoder.encode(loadout: XCTUnwrap(store.loadout(for: 3)), slot: 3)
    }
}
