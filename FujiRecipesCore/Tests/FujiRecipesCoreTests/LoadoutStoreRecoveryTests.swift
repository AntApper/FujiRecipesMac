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
}
