import XCTest
@testable import FujiRecipesCore

final class LoadoutStoreRecoveryTests: XCTestCase {
    private let loadoutsKey = "com.ant.fuji-recipes.loadouts"
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "LoadoutStoreRecoveryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    @MainActor
    func testUnreadableDraftsSurviveTheNextSave() throws {
        let unreadable = Data(#"[{"slot":1,"name":"Night Walk","wb":9999,"provenance":"localDraft"}]"#.utf8)
        defaults.set(unreadable, forKey: loadoutsKey)

        let store = LoadoutStore(defaults: defaults)
        store.applyRecipe(
            Recipe(id: "replacement", name: "Replacement", source: "test", sourceUrl: nil, filmSimulation: .classicChrome),
            to: 2
        )

        let backups = (defaults.persistentDomain(forName: suiteName) ?? [:])
            .filter { $0.key != loadoutsKey }
            .compactMap { $0.value as? Data }
        XCTAssertEqual(backups, [unreadable])
    }

    @MainActor
    func testUnreadableDraftsAreNoticedOnceAndTheBackupIsKept() throws {
        let unreadable = Data(#"[{"slot":1,"name":"Night Walk","wb":9999,"provenance":"localDraft"}]"#.utf8)
        defaults.set(unreadable, forKey: loadoutsKey)

        let notice = try XCTUnwrap(LoadoutStore(defaults: defaults).recoveryNotice)

        XCTAssertEqual(notice.reason, "C1: wb: Cannot initialize WhiteBalanceMode from invalid UInt32 value 9999")
        XCTAssertNotNil(notice.backupKey.range(
            of: #"^com\.ant\.fuji-recipes\.loadouts\.unreadable-\d{8}-\d{6}$"#,
            options: .regularExpression
        ))
        XCTAssertEqual(defaults.data(forKey: notice.backupKey), unreadable)

        let relaunched = LoadoutStore(defaults: defaults)

        XCTAssertNil(relaunched.recoveryNotice)
        XCTAssertEqual(relaunched.loadouts.map(\.slot), [1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(relaunched.loadouts.filter(\.hasAnySettings).count, 0)
        XCTAssertEqual(defaults.data(forKey: notice.backupKey), unreadable)
    }

    @MainActor
    func testDraftsSavedBeforeProvenanceExistedStayLocalDrafts() {
        let stored = Data(#"""
            [{"slot":1,"name":"Night Walk","recipeName":"Night Walk","filmSim":11},
             {"slot":2,"name":"C2"},
             {"slot":3,"name":"Harbor","filmSim":17,"provenance":"cameraSynced"}]
            """#.utf8)
        defaults.set(stored, forKey: loadoutsKey)

        let store = LoadoutStore(defaults: defaults)
        store.syncFromCameraPresetData([PTPClientPresetData(slot: 1, name: "Camera Slot", filmSimulation: 1)])

        XCTAssertNil(store.recoveryNotice)
        XCTAssertEqual(store.loadout(for: 1)?.provenance, .localDraft)
        XCTAssertEqual(store.loadout(for: 1)?.filmSim, .classicChrome)
        XCTAssertEqual(store.loadout(for: 3)?.provenance, .cameraSynced)
        XCTAssertEqual(store.dirtySlots, [1])
        XCTAssertEqual(store.stagedSlots, [1])
        XCTAssertEqual(store.loadouts.map(\.slot), Array(1...7))
    }

    @MainActor
    func testSparseLegacyLayoutFillsMissingSlotsWithoutChangingValidDrafts() throws {
        let original = Data(#"""
            [{"slot":5,"name":"Half Tone","recipeID":"saved-recipe","shadow":0,"rawPreset":{"shadow":5,"colorSpace":2}},
             {"slot":1,"name":"Night Walk","filmSim":11}]
            """#.utf8)
        defaults.set(original, forKey: loadoutsKey)

        let store = LoadoutStore(defaults: defaults)

        XCTAssertNil(store.recoveryNotice)
        XCTAssertEqual(store.loadouts.map(\.slot), Array(1...7))
        XCTAssertEqual(store.dirtySlots, [1, 5])
        XCTAssertEqual(store.loadout(for: 5)?.name, "Half Tone")
        XCTAssertEqual(store.loadout(for: 5)?.recipeID, "saved-recipe")
        XCTAssertEqual(store.loadout(for: 5)?.rawPreset?.shadow, 5)
        XCTAssertEqual(store.loadout(for: 5)?.rawPreset?.colorSpace, 2)
        XCTAssertEqual(defaults.data(forKey: loadoutsKey), original)
        XCTAssertTrue(backupKeys().isEmpty)

        store.updateName(for: 2, name: "New Draft")
        let relaunched = LoadoutStore(defaults: defaults)
        XCTAssertEqual(relaunched.loadout(for: 1)?.filmSim, .classicChrome)
        XCTAssertEqual(relaunched.loadout(for: 5)?.rawPreset?.shadow, 5)
        XCTAssertEqual(relaunched.loadout(for: 5)?.rawPreset?.colorSpace, 2)
    }

    @MainActor
    func testDuplicateSlotRecoversWithoutChoosingOrOverwritingOtherDrafts() throws {
        let original = Data(#"""
            [{"slot":2,"name":"First","filmSim":11},
             {"slot":5,"name":"Keep Me","filmSim":17,"rawPreset":{"shadow":5}},
             {"slot":2,"name":"Second","filmSim":17}]
            """#.utf8)
        defaults.set(original, forKey: loadoutsKey)

        let store = LoadoutStore(defaults: defaults)
        let notice = try XCTUnwrap(store.recoveryNotice)

        XCTAssertEqual(notice.reason, "duplicate entries for C2")
        XCTAssertEqual(notice.preservedSlots, [5])
        XCTAssertTrue(notice.message.contains("Valid entries for C5 were kept"))
        XCTAssertEqual(store.loadouts.map(\.slot), Array(1...7))
        XCTAssertFalse(try XCTUnwrap(store.loadout(for: 2)).hasAnySettings)
        XCTAssertEqual(store.loadout(for: 5)?.name, "Keep Me")
        XCTAssertEqual(store.loadout(for: 5)?.rawPreset?.shadow, 5)
        XCTAssertEqual(store.dirtySlots, [5])
        XCTAssertEqual(defaults.data(forKey: notice.backupKey), original)

        store.updateName(for: 1, name: "New Draft")
        let relaunched = LoadoutStore(defaults: defaults)
        XCTAssertNil(relaunched.recoveryNotice)
        XCTAssertEqual(relaunched.loadout(for: 5)?.name, "Keep Me")
        XCTAssertEqual(relaunched.loadout(for: 5)?.rawPreset?.shadow, 5)
        XCTAssertEqual(defaults.data(forKey: notice.backupKey), original)
        XCTAssertEqual(backupKeys(), [notice.backupKey])
    }

    @MainActor
    func testOutOfRangeSlotsAreCopiedWhileValidSlotsStayIntact() throws {
        let original = Data(#"""
            [{"slot":8,"name":"Outside","filmSim":17},
             {"slot":3,"name":"Keep C3","filmSim":11},
             {"slot":0,"name":"Invalid","filmSim":17}]
            """#.utf8)
        defaults.set(original, forKey: loadoutsKey)

        let store = LoadoutStore(defaults: defaults)
        let notice = try XCTUnwrap(store.recoveryNotice)

        XCTAssertEqual(notice.reason, "slot numbers outside C1–C7: 0, 8")
        XCTAssertEqual(notice.preservedSlots, [3])
        XCTAssertEqual(store.loadouts.map(\.slot), Array(1...7))
        XCTAssertEqual(store.loadout(for: 3)?.name, "Keep C3")
        XCTAssertEqual(store.loadout(for: 3)?.filmSim, .classicChrome)
        XCTAssertEqual(defaults.data(forKey: notice.backupKey), original)
    }

    @MainActor
    func testUnreadableEntryDoesNotHideValidDraftsInOtherSlots() throws {
        let original = Data(#"""
            [{"slot":1,"name":"Unreadable","wb":9999},
             {"slot":4,"name":"Keep C4","filmSim":11,"rawPreset":{"colorSpace":2}}]
            """#.utf8)
        defaults.set(original, forKey: loadoutsKey)

        let store = LoadoutStore(defaults: defaults)
        let notice = try XCTUnwrap(store.recoveryNotice)

        XCTAssertEqual(notice.preservedSlots, [4])
        XCTAssertTrue(notice.reason.contains("C1: wb:"))
        XCTAssertFalse(try XCTUnwrap(store.loadout(for: 1)).hasAnySettings)
        XCTAssertEqual(store.loadout(for: 4)?.name, "Keep C4")
        XCTAssertEqual(store.loadout(for: 4)?.rawPreset?.colorSpace, 2)
        XCTAssertEqual(store.dirtySlots, [4])
        XCTAssertEqual(defaults.data(forKey: notice.backupKey), original)
    }

    @MainActor
    func testUnreadableDuplicateCannotMakeTheOtherOccurrenceWin() throws {
        let original = Data(#"""
            [{"slot":3,"name":"Unreadable","wb":9999},
             {"slot":3,"name":"Other C3","filmSim":11},
             {"slot":6,"name":"Keep C6","filmSim":17}]
            """#.utf8)
        defaults.set(original, forKey: loadoutsKey)

        let store = LoadoutStore(defaults: defaults)
        let notice = try XCTUnwrap(store.recoveryNotice)

        XCTAssertTrue(notice.reason.contains("duplicate entries for C3"))
        XCTAssertTrue(notice.reason.contains("C3: wb:"))
        XCTAssertEqual(notice.preservedSlots, [6])
        XCTAssertFalse(try XCTUnwrap(store.loadout(for: 3)).hasAnySettings)
        XCTAssertEqual(store.loadout(for: 6)?.name, "Keep C6")
        XCTAssertEqual(defaults.data(forKey: notice.backupKey), original)
    }

    @MainActor
    func testEmptyLegacyLayoutHasSevenSlotsWithoutARecoveryNotice() {
        let original = Data("[]".utf8)
        defaults.set(original, forKey: loadoutsKey)

        let store = LoadoutStore(defaults: defaults)

        XCTAssertNil(store.recoveryNotice)
        XCTAssertEqual(store.loadouts.map(\.slot), Array(1...7))
        XCTAssertEqual(defaults.data(forKey: loadoutsKey), original)
        XCTAssertTrue(backupKeys().isEmpty)
    }

    @MainActor
    func testIncorrectPreferenceTypeIsCopiedBeforeReplacement() throws {
        let original = ["slot": "3"]
        defaults.set(original, forKey: loadoutsKey)

        let store = LoadoutStore(defaults: defaults)
        let notice = try XCTUnwrap(store.recoveryNotice)

        XCTAssertEqual(notice.reason, "Expected JSON data in the app’s preferences")
        XCTAssertEqual(defaults.dictionary(forKey: notice.backupKey) as? [String: String], original)
        XCTAssertEqual(store.loadouts.map(\.slot), Array(1...7))
        XCTAssertNil(LoadoutStore(defaults: defaults).recoveryNotice)
    }

    @MainActor
    func testNameOnlyRetryOfASyncedRequestStaysStagedAcrossRelaunch() throws {
        let store = LoadoutStore(defaults: defaults)
        store.syncFromCameraPresetData([PTPClientPresetData(slot: 3, name: "Night Rename")])
        let requestedDraft = try XCTUnwrap(store.loadout(for: 3))
        let requestedPayload = try CSlotPresetEncoder.encode(loadout: requestedDraft, slot: 3)
        XCTAssertFalse(requestedDraft.hasAnySettings)
        XCTAssertTrue(store.hasContent(for: 3))
        XCTAssertEqual(store.stagedSlots, [])

        // CameraManager uses this API to retain an unchanged mismatched request.
        store.saveLocalDraft(requestedDraft)

        XCTAssertTrue(store.isDirty(3))
        XCTAssertEqual(store.stagedSlots, [3])
        XCTAssertEqual(store.loadout(for: 3)?.provenance, .localDraft)
        XCTAssertEqual(store.loadout(for: 3)?.contentName, "Night Rename")
        XCTAssertEqual(store.loadout(for: 3)?.displayLabel, "Night Rename")
        XCTAssertEqual(store.loadoutCountWithContent(), 1)

        let relaunched = LoadoutStore(defaults: defaults)
        XCTAssertTrue(relaunched.isDirty(3))
        XCTAssertEqual(relaunched.stagedSlots, [3])
        XCTAssertEqual(try CSlotPresetEncoder.encode(loadout: XCTUnwrap(relaunched.loadout(for: 3)), slot: 3), requestedPayload)
        XCTAssertEqual(relaunched.loadoutCountWithContent(), 1)
        relaunched.syncFromCameraPresetData([PTPClientPresetData(slot: 3, name: "Different Name")])
        XCTAssertEqual(relaunched.loadout(for: 3)?.name, "Night Rename")
        XCTAssertEqual(relaunched.stagedSlots, [3])
    }

    @MainActor
    func testNameOnlyRecipeImportKeepsItsLinkAndRetryPayloadAcrossRelaunch() throws {
        let recipe = Recipe(id: "name-only-import", name: "Night Rename", source: "test", sourceUrl: nil)
        let store = LoadoutStore(defaults: defaults)

        store.applyRecipe(recipe, to: 4)

        XCTAssertFalse(try XCTUnwrap(store.loadout(for: 4)).hasAnySettings)
        XCTAssertTrue(store.hasContent(for: 4))
        XCTAssertEqual(store.stagedSlots, [4])
        let relaunched = LoadoutStore(defaults: defaults)
        let retained = try XCTUnwrap(relaunched.loadout(for: 4))
        XCTAssertEqual(retained.recipeID, recipe.id)
        XCTAssertEqual(retained.recipeName, recipe.name)
        XCTAssertEqual(retained.contentName, recipe.name)
        XCTAssertTrue(relaunched.isDirty(4))
        XCTAssertEqual(relaunched.stagedSlots, [4])
        XCTAssertEqual(try CSlotPresetEncoder.encode(loadout: retained, slot: 4), try CSlotPresetEncoder.encode(recipe: recipe, slot: 4))
    }

    @MainActor
    func testNameOnlyRecipeNamedC4RemainsStagedWithoutInheritingOldSettings() throws {
        let store = LoadoutStore(defaults: defaults)
        store.syncFromCameraPresetData([
            PTPClientPresetData(slot: 4, name: "Previous Settings", filmSimulation: FilmSimulation.velvia.rawValue, shadow: 5)
        ])
        let recipe = Recipe(id: "default-name-import", name: "C4", source: "test", sourceUrl: nil)

        store.applyRecipe(recipe, to: 4)

        let retained = try XCTUnwrap(store.loadout(for: 4))
        XCTAssertFalse(retained.hasAnySettings)
        XCTAssertNil(retained.rawPreset)
        XCTAssertTrue(store.hasContent(for: 4))
        XCTAssertEqual(retained.contentName, "C4")
        XCTAssertEqual(store.stagedSlots, [4])
        let relaunched = LoadoutStore(defaults: defaults)
        XCTAssertTrue(relaunched.isDirty(4))
        XCTAssertEqual(relaunched.stagedSlots, [4])
        XCTAssertEqual(relaunched.loadout(for: 4)?.recipeID, recipe.id)
        XCTAssertEqual(try CSlotPresetEncoder.encode(loadout: XCTUnwrap(relaunched.loadout(for: 4)), slot: 4), try CSlotPresetEncoder.encode(recipe: recipe, slot: 4))
    }

    @MainActor
    func testLegacyNameOnlyRecipeLinkMakesADefaultLabelRetryable() {
        defaults.set(Data(#"[{"slot":4,"name":"C4","recipeName":"C4"}]"#.utf8), forKey: loadoutsKey)

        let store = LoadoutStore(defaults: defaults)

        XCTAssertNil(store.recoveryNotice)
        XCTAssertTrue(store.hasContent(for: 4))
        XCTAssertEqual(store.loadout(for: 4)?.contentName, "C4")
        XCTAssertEqual(store.dirtySlots, [4])
        XCTAssertEqual(store.stagedSlots, [4])
    }

    @MainActor
    func testRecipeIDAloneMakesADefaultLabelRetryable() {
        defaults.set(Data(#"[{"slot":4,"name":"C4","recipeID":"linked-recipe"}]"#.utf8), forKey: loadoutsKey)

        let store = LoadoutStore(defaults: defaults)

        XCTAssertTrue(store.hasContent(for: 4))
        XCTAssertEqual(store.dirtySlots, [4])
        XCTAssertEqual(store.stagedSlots, [4])
    }

    @MainActor
    func testClearingNameOnlyContentDropsItsRecipeLinkAndPreservesOtherDrafts() throws {
        let store = LoadoutStore(defaults: defaults)
        store.updateName(for: 3, name: "Keep This Name")
        store.applyRecipe(Recipe(id: "linked-recipe", name: "C4", source: "test", sourceUrl: nil), to: 4)
        XCTAssertEqual(store.stagedSlots, [3, 4])

        store.clearLoadout(for: 4)

        let cleared = try XCTUnwrap(store.loadout(for: 4))
        XCTAssertFalse(store.hasContent(for: 4))
        XCTAssertFalse(cleared.hasAnySettings)
        XCTAssertEqual(cleared.name, "C4")
        XCTAssertNil(cleared.recipeID)
        XCTAssertNil(cleared.recipeName)
        XCTAssertNil(cleared.contentName)
        XCTAssertEqual(store.stagedSlots, [3])

        let relaunched = LoadoutStore(defaults: defaults)
        XCTAssertFalse(relaunched.isDirty(4))
        XCTAssertFalse(relaunched.hasContent(for: 4))
        XCTAssertEqual(relaunched.loadout(for: 3)?.name, "Keep This Name")
        XCTAssertEqual(relaunched.stagedSlots, [3])

        relaunched.clearAllStaged()
        XCTAssertEqual(relaunched.stagedSlots, [])
        let clearedAgain = LoadoutStore(defaults: defaults)
        XCTAssertTrue(clearedAgain.dirtySlots.isEmpty)
        XCTAssertEqual(clearedAgain.stagedSlots, [])
        XCTAssertFalse(clearedAgain.loadouts.contains(where: \.hasContent))
    }

    @MainActor
    func testBlankAndDefaultEmptyDraftsStayExcludedEvenWhenMarkedDirty() {
        for name in ["C4", " C4 \n", "", " \n "] {
            let store = LoadoutStore(defaults: defaults)
            store.saveLocalDraft(Loadout(slot: 4, name: name, recipeName: " \n", recipeID: " \n"))

            XCTAssertTrue(store.isDirty(4))
            XCTAssertFalse(store.hasContent(for: 4))
            XCTAssertNil(store.loadout(for: 4)?.contentName)
            XCTAssertEqual(store.loadout(for: 4)?.displayLabel, "C4")
            XCTAssertEqual(store.stagedSlots, [])
            let relaunched = LoadoutStore(defaults: defaults)
            XCTAssertFalse(relaunched.isDirty(4))
            XCTAssertFalse(relaunched.hasContent(for: 4))
            XCTAssertEqual(relaunched.stagedSlots, [])
        }
    }

    @MainActor
    func testVerifiedNameOnlyContentStopsStagingAndStaysSyncedOnRelaunch() {
        let store = LoadoutStore(defaults: defaults)
        store.updateName(for: 3, name: "Verified Rename")
        XCTAssertEqual(store.stagedSlots, [3])

        store.markCameraWriteVerified(slot: 3)

        XCTAssertTrue(store.hasContent(for: 3))
        XCTAssertFalse(store.isDirty(3))
        XCTAssertEqual(store.stagedSlots, [])
        let relaunched = LoadoutStore(defaults: defaults)
        XCTAssertTrue(relaunched.hasContent(for: 3))
        XCTAssertEqual(relaunched.loadout(for: 3)?.contentName, "Verified Rename")
        XCTAssertFalse(relaunched.isDirty(3))
        XCTAssertEqual(relaunched.stagedSlots, [])
    }

    func testRecoveryNoticeMessageNamesTheBackupKey() {
        let notice = LoadoutRecoveryNotice(
            backupKey: "com.ant.fuji-recipes.loadouts.unreadable-20260927-012400",
            reason: "wb: Cannot initialize WhiteBalanceMode from invalid UInt32 value 9999"
        )

        XCTAssertEqual(
            notice.message,
            "FujiRecipes couldn’t read your staged C1–C7 drafts (wb: Cannot initialize WhiteBalanceMode from invalid UInt32 value 9999), so the slots start empty. The unreadable data was kept in the app’s preferences as “com.ant.fuji-recipes.loadouts.unreadable-20260927-012400”. Your camera wasn’t changed."
        )
    }

    private func backupKeys() -> [String] {
        (defaults.persistentDomain(forName: suiteName) ?? [:]).keys
            .filter { $0.hasPrefix("\(loadoutsKey).unreadable-") }
            .sorted()
    }
}
