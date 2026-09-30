import XCTest
@testable import FujiRecipesCore

final class FavoritesStoreRecoveryTests: XCTestCase {
    private let favoritesKey = "com.ant.fuji-recipes.favorites"
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "FavoritesStoreRecoveryTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    @MainActor
    func testMissingFavoritesLoadWithoutARecoveryNoticeOrWrite() {
        let store = FavoritesStore(defaults: defaults)

        XCTAssertTrue(store.favoriteIDs.isEmpty)
        XCTAssertNil(store.recoveryNotice)
        XCTAssertNil(defaults.object(forKey: favoritesKey))
    }

    @MainActor
    func testValidFavoritesKeepAllIDsAndSaveInDeterministicOrder() throws {
        let original = Data(#"["zulu","missing-recipe","alpha","alpha"]"#.utf8)
        defaults.set(original, forKey: favoritesKey)
        let store = FavoritesStore(defaults: defaults)

        XCTAssertNil(store.recoveryNotice)
        XCTAssertEqual(store.favoriteIDs, ["zulu", "missing-recipe", "alpha"])
        XCTAssertEqual(defaults.data(forKey: favoritesKey), original)

        store.addFavorite("beta")
        let saved = try XCTUnwrap(defaults.data(forKey: favoritesKey))
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: saved), ["alpha", "beta", "missing-recipe", "zulu"])
        XCTAssertEqual(FavoritesStore(defaults: defaults).favoriteIDs, store.favoriteIDs)
    }

    @MainActor
    func testUnreadableFavoritesStayRecoverableThroughTheNextSave() throws {
        let original = Data(#"["alpha",{"id":"beta"}]"#.utf8)
        defaults.set(original, forKey: favoritesKey)

        let store = FavoritesStore(defaults: defaults)
        let notice = try XCTUnwrap(store.recoveryNotice)
        XCTAssertTrue(store.favoriteIDs.isEmpty)
        XCTAssertEqual(defaults.data(forKey: notice.backupKey), original)

        store.toggleFavorite(for: "new-favorite")

        XCTAssertEqual(defaults.data(forKey: notice.backupKey), original)
        XCTAssertEqual(FavoritesStore(defaults: defaults).favoriteIDs, ["new-favorite"])
        XCTAssertEqual(backupKeys(), [notice.backupKey])
    }

    @MainActor
    func testUnreadableFavoritesAreNoticedOnceAndAcknowledgementKeepsTheCopy() throws {
        let original = Data("[\"alpha\"".utf8)
        defaults.set(original, forKey: favoritesKey)
        let store = FavoritesStore(defaults: defaults)
        let notice = try XCTUnwrap(store.recoveryNotice)

        store.acknowledgeRecoveryNotice()

        XCTAssertNil(store.recoveryNotice)
        XCTAssertNil(FavoritesStore(defaults: defaults).recoveryNotice)
        XCTAssertEqual(defaults.data(forKey: notice.backupKey), original)
        XCTAssertEqual(backupKeys(), [notice.backupKey])
    }

    @MainActor
    func testDifferentUnreadableValuesNeverReplaceAnEarlierCopy() throws {
        let first = Data("[".utf8)
        defaults.set(first, forKey: favoritesKey)
        let firstNotice = try XCTUnwrap(FavoritesStore(defaults: defaults).recoveryNotice)
        let second = Data("{".utf8)
        defaults.set(second, forKey: favoritesKey)
        let secondNotice = try XCTUnwrap(FavoritesStore(defaults: defaults).recoveryNotice)

        XCTAssertNotEqual(firstNotice.backupKey, secondNotice.backupKey)
        XCTAssertEqual(defaults.data(forKey: firstNotice.backupKey), first)
        XCTAssertEqual(defaults.data(forKey: secondNotice.backupKey), second)
        XCTAssertEqual(backupKeys().count, 2)
    }

    @MainActor
    func testIncorrectPreferenceTypeIsCopiedBeforeItIsReplaced() throws {
        let original = ["unexpected": "favorite IDs"]
        defaults.set(original, forKey: favoritesKey)
        let store = FavoritesStore(defaults: defaults)
        let notice = try XCTUnwrap(store.recoveryNotice)

        XCTAssertEqual(notice.reason, "Expected JSON data in the app’s preferences")
        XCTAssertEqual(defaults.dictionary(forKey: notice.backupKey) as? [String: String], original)
        store.addFavorite("new")
        XCTAssertEqual(defaults.dictionary(forKey: notice.backupKey) as? [String: String], original)
        XCTAssertEqual(FavoritesStore(defaults: defaults).favoriteIDs, ["new"])
    }

    @MainActor
    func testFavoritesRecoveryDoesNotTouchRecipesOrDraftPreferences() throws {
        let draftsKey = "com.ant.fuji-recipes.loadouts"
        let drafts = Data(#"[{"slot":3,"name":"Night Walk","filmSim":11}]"#.utf8)
        defaults.set(drafts, forKey: draftsKey)
        defaults.set(Data("[".utf8), forKey: favoritesKey)

        _ = FavoritesStore(defaults: defaults)

        XCTAssertEqual(defaults.data(forKey: draftsKey), drafts)
    }

    func testNoticeNamesTheRecoverablePreferenceKey() {
        let notice = FavoritesRecoveryNotice(backupKey: "favorites.unreadable-copy", reason: "invalid JSON")
        XCTAssertTrue(notice.message.contains("favorites.unreadable-copy"))
        XCTAssertTrue(notice.message.contains("invalid JSON"))
    }

    private func backupKeys() -> [String] {
        (defaults.persistentDomain(forName: suiteName) ?? [:]).keys
            .filter { $0.hasPrefix("\(favoritesKey).unreadable-") }
            .sorted()
    }
}
