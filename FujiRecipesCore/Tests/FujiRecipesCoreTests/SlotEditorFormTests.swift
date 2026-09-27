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
        var session = SlotEditorSession(try XCTUnwrap(store.loadout(for: 3)))

        store.save(&session)

        XCTAssertFalse(store.isDirty(3))
        XCTAssertEqual(store.loadout(for: 3)?.provenance, .cameraSynced)
    }

    func testRevertingTheFormAfterAnEarlierSaveRestoresTheOriginalValues() throws {
        let store = storeWithCameraSyncedC3()
        var session = SlotEditorSession(try XCTUnwrap(store.loadout(for: 3)))
        let original = session.form
        session.form.filmSim = .classicChrome
        store.save(&session)

        session.form = original
        store.save(&session)

        XCTAssertEqual(store.loadout(for: 3)?.filmSim, .nostalgicNegative)
    }

    func testEditingAFormReloadedFromTheReadbackKeepsTheCameraLabel() throws {
        let store = storeWithCameraSyncedC3()
        var session = SlotEditorSession(try XCTUnwrap(store.loadout(for: 3)))
        session.form.filmSim = .classicChrome

        store.save(&session)

        XCTAssertTrue(store.isDirty(3))
        let saved = try XCTUnwrap(store.loadout(for: 3))
        XCTAssertEqual(saved.filmSim, .classicChrome)
        XCTAssertEqual(saved.name, "Appalachian Neg")
    }

    func testSavingAFormOpenedBeforeACameraWriteKeepsTheWrite() throws {
        let store = storeWithCameraSyncedC3()
        var session = SlotEditorSession(try XCTUnwrap(store.loadout(for: 3)))
        store.adoptCameraWrite(PTPClientPresetData(slot: 3, name: "Kodak Portra", filmSimulation: FilmSimulation.classicChrome.rawValue), ifUnchangedSince: store.revision(of: 3))

        store.save(&session)

        XCTAssertEqual(store.loadout(for: 3)?.filmSim, .classicChrome, "saving an untouched editor reverted the camera write")
        XCTAssertEqual(store.loadout(for: 3)?.name, "Kodak Portra")
        XCTAssertFalse(store.isDirty(3))
    }

    func testAnUntouchedEditorShowsACameraWriteThatLandsWhileItIsOpen() throws {
        let store = storeWithCameraSyncedC3()
        var session = SlotEditorSession(try XCTUnwrap(store.loadout(for: 3)))
        store.adoptCameraWrite(PTPClientPresetData(slot: 3, name: "Kodak Portra", filmSimulation: FilmSimulation.classicChrome.rawValue), ifUnchangedSince: store.revision(of: 3))

        session.follow(try XCTUnwrap(store.loadout(for: 3)))

        XCTAssertEqual(session.form.name, "Kodak Portra")
        XCTAssertEqual(session.form.filmSim, .classicChrome)
        XCTAssertFalse(session.isEdited)
    }

    func testAnEditedEditorKeepsItsEditsWhenACameraWriteLands() throws {
        let store = storeWithCameraSyncedC3()
        var session = SlotEditorSession(try XCTUnwrap(store.loadout(for: 3)))
        session.form.name = "Evening Neg"
        store.adoptCameraWrite(PTPClientPresetData(slot: 3, name: "Kodak Portra", filmSimulation: FilmSimulation.classicChrome.rawValue), ifUnchangedSince: store.revision(of: 3))
        let written = try XCTUnwrap(store.loadout(for: 3))

        session.follow(written)

        XCTAssertEqual(session.form.name, "Evening Neg")
        XCTAssertEqual(session.form.filmSim, .nostalgicNegative)
        XCTAssertTrue(session.conflicts(with: written))
    }

    func testAChangeToASettingTheEditorDoesNotShowIsNotAConflict() throws {
        let store = storeWithCameraSyncedC3()
        var session = SlotEditorSession(try XCTUnwrap(store.loadout(for: 3)))
        session.form.name = "Evening Neg"
        store.adoptCameraWrite(PTPClientPresetData(slot: 3, name: "Appalachian Neg", dynamicRange: 400, filmSimulation: 19, grainEffect: 2, colorChrome: 1, colorChromeFxBlue: 1, smoothSkin: 1, whiteBalance: 4, wbShiftRed: 2, wbShiftBlue: -2, colorTemp: 10000, highlight: 0, shadow: 0, color: 40, sharpness: 20, highIsoNr: 0x8000, clarity: 0), ifUnchangedSince: store.revision(of: 3))
        let written = try XCTUnwrap(store.loadout(for: 3))
        XCTAssertEqual(written.colorChrome, .off)

        XCTAssertFalse(session.conflicts(with: written))
    }

    func testAnEditMadeDuringTheEditorsOwnWriteSurvivesTheReadback() throws {
        let store = storeWithCameraSyncedC3()
        var session = SlotEditorSession(try XCTUnwrap(store.loadout(for: 3)))
        session.form.filmSim = .classicChrome
        store.save(&session)
        XCTAssertTrue(store.adoptCameraWrite(PTPClientPresetData(slot: 3, name: "Appalachian Neg", dynamicRange: 400, filmSimulation: FilmSimulation.classicChrome.rawValue, grainEffect: 2, colorChrome: 3, colorChromeFxBlue: 1, smoothSkin: 1, whiteBalance: 4, wbShiftRed: 2, wbShiftBlue: -2, colorTemp: 5600, highlight: 0, shadow: 0, color: 40, sharpness: 20, highIsoNr: 0x8000, clarity: 0), ifUnchangedSince: store.revision(of: 3)))
        session.form.name = "Evening Neg"
        let readback = try XCTUnwrap(store.loadout(for: 3))

        session.follow(readback)

        XCTAssertEqual(session.form.name, "Evening Neg")
        XCTAssertFalse(session.conflicts(with: readback))
        store.save(&session)
        XCTAssertTrue(store.isDirty(3))
        XCTAssertEqual(store.loadout(for: 3)?.name, "Evening Neg")
        XCTAssertEqual(store.loadout(for: 3)?.filmSim, .classicChrome)
    }

    func testSwitchingToColorTemperatureAndBackLeavesTheSlotClean() throws {
        let store = storeWithCameraSyncedC3()
        var session = SlotEditorSession(try XCTUnwrap(store.loadout(for: 3)))
        session.form.whiteBalance = .colorTemperature
        session.form.colorTemperature = 7_000
        session.form.whiteBalance = .daylight

        store.save(&session)

        XCTAssertFalse(store.isDirty(3))
    }

    func testTurningAToneOnAndOffAgainLeavesTheSlotClean() throws {
        let store = LoadoutStore()
        store.syncFromCameraPresetData([PTPClientPresetData(slot: 3, name: "No Tones", filmSimulation: 19)], overwriteDirtyDrafts: true)
        var session = SlotEditorSession(try XCTUnwrap(store.loadout(for: 3)))
        session.form.includesHighlight = true
        session.form.highlight = 10
        session.form.includesHighlight = false

        store.save(&session)

        XCTAssertFalse(store.isDirty(3))
    }

    func testClearingTheNameOfAnUnnamedSlotLeavesTheSlotClean() throws {
        let store = LoadoutStore()
        store.syncFromCameraPresetData([PTPClientPresetData(slot: 3, name: "", filmSimulation: 19)], overwriteDirtyDrafts: true)
        var session = SlotEditorSession(try XCTUnwrap(store.loadout(for: 3)))
        session.form.name = " "

        store.save(&session)

        XCTAssertFalse(store.isDirty(3))
        XCTAssertEqual(store.loadout(for: 3)?.name, "C3")
    }

    func testFollowingAnUnchangedSlotKeepsWhatTheUserTyped() throws {
        let store = LoadoutStore()
        store.syncFromCameraPresetData([PTPClientPresetData(slot: 2, name: "", filmSimulation: 19)], overwriteDirtyDrafts: true)
        var session = SlotEditorSession(try XCTUnwrap(store.loadout(for: 2)))
        session.form.name = "Foo"
        session.form.name = ""

        session.follow(try XCTUnwrap(store.loadout(for: 2)))

        XCTAssertEqual(session.form.name, "", "the name field snapped back to the slot label while the user was typing")
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
