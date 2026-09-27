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

        store.saveEditorForm(SlotEditorForm(loadout), slot: 3)

        XCTAssertFalse(store.isDirty(3))
        XCTAssertEqual(store.loadout(for: 3)?.provenance, .cameraSynced)
    }

    func testRevertingTheFormAfterAnEarlierSaveRestoresTheOriginalValues() throws {
        let store = storeWithCameraSyncedC3()
        let original = SlotEditorForm(try XCTUnwrap(store.loadout(for: 3)))
        var edited = original
        edited.filmSim = .classicChrome
        store.saveEditorForm(edited, slot: 3)

        store.saveEditorForm(original, slot: 3)

        XCTAssertEqual(store.loadout(for: 3)?.filmSim, .nostalgicNegative)
    }

    func testEditingAFormReloadedFromTheReadbackKeepsTheCameraLabel() throws {
        let store = storeWithCameraSyncedC3()
        let loadout = try XCTUnwrap(store.loadout(for: 3))
        var form = SlotEditorForm(loadout)
        form.filmSim = .classicChrome

        store.saveEditorForm(form, slot: 3)

        XCTAssertTrue(store.isDirty(3))
        let saved = try XCTUnwrap(store.loadout(for: 3))
        XCTAssertEqual(saved.filmSim, .classicChrome)
        XCTAssertEqual(saved.name, "Appalachian Neg")
    }

    func testSavingAFormOpenedBeforeACameraWriteKeepsTheWrite() throws {
        let store = storeWithCameraSyncedC3()
        let opened = SlotEditorForm(try XCTUnwrap(store.loadout(for: 3)))
        store.adoptCameraWrite(PTPClientPresetData(slot: 3, name: "Kodak Portra", filmSimulation: FilmSimulation.classicChrome.rawValue), ifUnchangedSince: store.revision(of: 3))

        store.saveEditorForm(opened, slot: 3)

        XCTAssertEqual(store.loadout(for: 3)?.filmSim, .classicChrome, "saving an untouched editor reverted the camera write")
        XCTAssertEqual(store.loadout(for: 3)?.name, "Kodak Portra")
        XCTAssertFalse(store.isDirty(3))
    }

    func testSwitchingToColorTemperatureAndBackLeavesTheSlotClean() throws {
        let store = storeWithCameraSyncedC3()
        var form = SlotEditorForm(try XCTUnwrap(store.loadout(for: 3)))
        form.whiteBalance = .colorTemperature
        form.colorTemperature = 7_000
        form.whiteBalance = .daylight

        store.saveEditorForm(form, slot: 3)

        XCTAssertFalse(store.isDirty(3))
    }

    func testTurningAToneOnAndOffAgainLeavesTheSlotClean() throws {
        let store = LoadoutStore()
        store.syncFromCameraPresetData([PTPClientPresetData(slot: 3, name: "No Tones", filmSimulation: 19)], overwriteDirtyDrafts: true)
        var form = SlotEditorForm(try XCTUnwrap(store.loadout(for: 3)))
        form.includesHighlight = true
        form.highlight = 10
        form.includesHighlight = false

        store.saveEditorForm(form, slot: 3)

        XCTAssertFalse(store.isDirty(3))
    }

    func testTheFormShowsTheKelvinTheCameraWillGet() throws {
        let loadout = Loadout(slot: 3, name: "Kelvin", wb: .colorTemperature)

        let written = try XCTUnwrap(try CSlotPresetEncoder.encode(loadout: loadout, slot: 3).colorTemp)

        XCTAssertEqual(SlotEditorForm(loadout).colorTemperature, Int(written))
    }

    func testUneditedFormDraftEncodesTheSameCameraRequest() throws {
        let store = storeWithCameraSyncedC3()
        let loadout = try XCTUnwrap(store.loadout(for: 3))
        let form = SlotEditorForm(loadout)

        XCTAssertEqual(try CSlotPresetEncoder.encode(loadout: form.draft(updating: loadout), slot: 3), try CSlotPresetEncoder.encode(loadout: loadout, slot: 3))
    }
}
