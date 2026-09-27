import XCTest
@testable import FujiRecipesCore

@MainActor
final class SlotEditorFormTests: XCTestCase {
    private let loadoutsKey = "com.ant.fuji-recipes.loadouts"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
        super.tearDown()
    }

    private func storeWithCameraSyncedC3() -> LoadoutStore {
        let store = LoadoutStore()
        store.syncFromCameraPresetData([PTPClientPresetData(slot: 3, name: "Appalachian Neg", dynamicRange: 400, filmSimulation: 19, grainEffect: 2, colorChrome: 3, colorChromeFxBlue: 1, smoothSkin: 1, whiteBalance: 4, wbShiftRed: 2, wbShiftBlue: -2, colorTemp: 10000, highlight: 0, shadow: 0, color: 40, sharpness: 20, highIsoNr: 0x8000, clarity: 0)], overwriteDirtyDrafts: true)
        return store
    }

    func testSavingAnUneditedFormLeavesACameraSyncedSlotClean() throws {
        let store = storeWithCameraSyncedC3()
        let loadout = try XCTUnwrap(store.loadout(for: 3))

        store.saveEditorForm(SlotEditorForm(loadout), editing: loadout)

        XCTAssertFalse(store.isDirty(3))
        XCTAssertEqual(store.loadout(for: 3)?.provenance, .cameraSynced)
    }
}
