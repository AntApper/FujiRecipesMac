import XCTest
@testable import FujiRecipesCore

final class LoadoutPresetStateTests: XCTestCase {
    private let loadoutsKey = "com.ant.fuji-recipes.loadouts"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
        super.tearDown()
    }

    @MainActor
    func testCameraSyncRetainsEveryPresetFieldAndRoundTripsIt() async throws {
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
            whiteBalance: WhiteBalanceMode.colorTemperature.rawValue,
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

    @MainActor
    func testApplyingRecipeKeepsItsExtendedPresetSettings() async throws {
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

    @MainActor
    func testSavingDirectEditorChangesOverridesRawValuesAndPreservesUnknowns() async throws {
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

    // MARK: - Objective 2: Empty Slot Handling

    @MainActor
    func testEmptySlotReadExplicitlyClearsLocalDraftAndRemovesDirtyFlag() async throws {
        let store = LoadoutStore()

        // 1. Stage recipe into slot 1 and slot 2
        let recipe1 = Recipe(
            id: "draft-recipe-1",
            name: "Vintage Draft",
            source: "test",
            sourceUrl: nil,
            filmSimulation: .classicChrome,
            dynamicRange: .dr200,
            highlight: 2,
            shadow: -1
        )
        store.applyRecipe(recipe1, to: 1)
        store.applyRecipe(recipe1, to: 2)
        store.updateName(for: 2, name: "Custom Named Draft")

        XCTAssertTrue(store.isDirty(1))
        XCTAssertTrue(store.isDirty(2))
        XCTAssertTrue(try XCTUnwrap(store.loadout(for: 1)).hasAnySettings)
        XCTAssertTrue(try XCTUnwrap(store.loadout(for: 2)).hasAnySettings)
        XCTAssertFalse(store.isCameraSlotEmpty(1))
        XCTAssertFalse(store.isCameraSlotEmpty(2))

        // 2. Camera reports slot 1 is empty, with overwriteDirtyDrafts = true
        let emptySlot1 = PTPClientPresetData(slot: 1, isEmptySlot: true)
        store.syncFromCameraPresetData([emptySlot1], overwriteDirtyDrafts: true)

        XCTAssertFalse(store.isDirty(1), "Dirty flag should be cleared when slot is synced as empty with overwrite")
        XCTAssertTrue(store.isCameraSlotEmpty(1), "cameraEmptySlots should include slot 1")

        let loadout1 = try XCTUnwrap(store.loadout(for: 1))
        XCTAssertEqual(loadout1.name, "C1", "Cleared empty slot should reset name to default C1")
        XCTAssertNil(loadout1.recipeName, "Cleared empty slot should have nil recipeName")
        XCTAssertNil(loadout1.filmSim, "Cleared empty slot should have nil filmSim")
        XCTAssertNil(loadout1.dr, "Cleared empty slot should have nil dr")
        XCTAssertNil(loadout1.highlight, "Cleared empty slot should have nil highlight")
        XCTAssertNil(loadout1.shadow, "Cleared empty slot should have nil shadow")
        XCTAssertFalse(loadout1.hasAnySettings, "Cleared empty slot should have no settings")
        XCTAssertEqual(loadout1.displayLabel, "C1")

        // 3. Camera reports slot 2 is empty, but overwriteDirtyDrafts = false
        let emptySlot2 = PTPClientPresetData(slot: 2, isEmptySlot: true)
        store.syncFromCameraPresetData([emptySlot2], overwriteDirtyDrafts: false)

        XCTAssertTrue(store.isDirty(2), "Dirty draft should NOT be overwritten when overwriteDirtyDrafts is false")
        XCTAssertFalse(store.isCameraSlotEmpty(2), "Slot 2 should not be marked cameraEmpty when draft was preserved")
        XCTAssertEqual(store.loadout(for: 2)?.name, "Custom Named Draft")

        // 4. Now overwrite slot 2 with overwriteDirtyDrafts = true
        store.syncFromCameraPresetData([emptySlot2], overwriteDirtyDrafts: true)

        XCTAssertFalse(store.isDirty(2))
        XCTAssertTrue(store.isCameraSlotEmpty(2))
        let loadout2 = try XCTUnwrap(store.loadout(for: 2))
        XCTAssertEqual(loadout2.name, "C2")
        XCTAssertNil(loadout2.recipeName)
        XCTAssertFalse(loadout2.hasAnySettings)
    }

    @MainActor
    func testSyncFromCameraPresetDataTransitionsPopulatedSlotToEmptySlot() async throws {
        let store = LoadoutStore()

        // Sync a populated slot
        let populated = PTPClientPresetData(
            slot: 4,
            name: "Kodachrome",
            filmSimulation: FilmSimulation.classicChrome.rawValue
        )
        store.syncFromCameraPresetData([populated])

        let loadoutBefore = try XCTUnwrap(store.loadout(for: 4))
        XCTAssertEqual(loadoutBefore.name, "Kodachrome")
        XCTAssertNil(loadoutBefore.recipeName)
        XCTAssertEqual(loadoutBefore.filmSim, .classicChrome)
        XCTAssertFalse(store.isCameraSlotEmpty(4))

        // Now camera reports slot 4 was reset to empty
        let empty = PTPClientPresetData(slot: 4, isEmptySlot: true)
        store.syncFromCameraPresetData([empty], overwriteDirtyDrafts: true)

        XCTAssertTrue(store.isCameraSlotEmpty(4))
        let loadoutAfter = try XCTUnwrap(store.loadout(for: 4))
        XCTAssertEqual(loadoutAfter.name, "C4")
        XCTAssertNil(loadoutAfter.recipeName)
        XCTAssertFalse(loadoutAfter.hasAnySettings)
    }

    // MARK: - Objective 2: Custom Names & Unicode Handling

    @MainActor
    func testSyncFromCameraPresetDataWithCustomNamesIncludingUnicodeAndSpecialCharacters() async throws {
        let store = LoadoutStore()

        let testCases: [(slot: Int, cameraName: String, expectedLabel: String)] = [
            (1, "B&W Mono", "B&W Mono"),
            (2, "Warm 35mm", "Warm 35mm"),
            (3, "Café", "Café"),
            (4, "Cinéma 800T", "Cinéma 800T"),
            (5, "日落 (Sunset)", "日落 (Sunset)"),
            (6, "  Padded Name  ", "Padded Name"),
            (7, "", "C7")
        ]

        let presets = testCases.map { tc in
            PTPClientPresetData(
                slot: tc.slot,
                name: tc.cameraName,
                isEmptySlot: false,
                filmSimulation: FilmSimulation.provia.rawValue,
                highlight: 10
            )
        }

        store.syncFromCameraPresetData(presets)

        for tc in testCases {
            let loadout = try XCTUnwrap(store.loadout(for: tc.slot))
            XCTAssertEqual(loadout.name, tc.expectedLabel, "loadout.name should match slotLabel for slot \(tc.slot)")
            XCTAssertNil(loadout.recipeName, "A camera slot that did not come from a recipe has no recipe name (slot \(tc.slot))")
            XCTAssertNil(loadout.recipeID, "Camera sync should clear recipeID")
            XCTAssertEqual(loadout.provenance, .cameraSynced, "Provenance should be cameraSynced")
            XCTAssertFalse(store.isDirty(tc.slot), "Slot \(tc.slot) should not be dirty after sync")
            XCTAssertFalse(store.isCameraSlotEmpty(tc.slot), "Slot \(tc.slot) should not be marked empty")
        }
    }

    // MARK: - Objective 2: Loadout and LoadoutCard Display Properties

    @MainActor
    func testLoadoutDisplayPropertiesAndCardTitleResolutionWithCameraSyncedNames() async throws {
        let store = LoadoutStore()

        // 1. Unconfigured slot displayLabel is "C\(slot)"
        let defaultLoadout = try XCTUnwrap(store.loadout(for: 3))
        XCTAssertEqual(defaultLoadout.displayLabel, "C3")

        // 2. Sync from camera with a custom Unicode name "Café"
        let cafePreset = PTPClientPresetData(
            slot: 3,
            name: "Café",
            filmSimulation: FilmSimulation.classicChrome.rawValue,
            highlight: 20
        )
        store.syncFromCameraPresetData([cafePreset])

        let syncedLoadout = try XCTUnwrap(store.loadout(for: 3))
        XCTAssertEqual(syncedLoadout.name, "Café")
        XCTAssertNil(syncedLoadout.recipeName)
        XCTAssertEqual(syncedLoadout.displayLabel, "Café")
        XCTAssertEqual(syncedLoadout.provenance, .cameraSynced)
        XCTAssertFalse(store.isDirty(3))

        // 3. User edits the draft locally
        store.updateName(for: 3, name: "Local Edit")
        let editedLoadout = try XCTUnwrap(store.loadout(for: 3))
        XCTAssertTrue(store.isDirty(3))
        XCTAssertEqual(editedLoadout.provenance, .localDraft)
        XCTAssertNil(editedLoadout.recipeName)
        XCTAssertEqual(editedLoadout.displayLabel, "Local Edit")

        // 4. Syncing again with overwriteDirtyDrafts = true resets back to camera name
        store.syncFromCameraPresetData([cafePreset], overwriteDirtyDrafts: true)
        let resyncedLoadout = try XCTUnwrap(store.loadout(for: 3))
        XCTAssertEqual(resyncedLoadout.name, "Café")
        XCTAssertNil(resyncedLoadout.recipeName)
        XCTAssertEqual(resyncedLoadout.displayLabel, "Café")
        XCTAssertFalse(store.isDirty(3))
    }
}
