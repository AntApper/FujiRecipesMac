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

        XCTAssertEqual(notice.reason, "wb: Cannot initialize WhiteBalanceMode from invalid UInt32 value 9999")
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
}
