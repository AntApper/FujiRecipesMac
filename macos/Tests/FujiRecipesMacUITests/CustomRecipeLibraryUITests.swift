import XCTest
import FujiRecipesCore

final class CustomRecipeLibraryUITests: XCTestCase {
    private let fixtureID = "ui-smoke-custom"
    private let defaultsSuite = "FujiRecipesMacUITests-\(UUID().uuidString)"
    private var fixtureDirectory: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let fixtureID = fixtureID
        let defaultsSuite = defaultsSuite
        let launch = try MainActor.assumeIsolated { () throws -> (URL, XCUIApplication) in
            let fixtureDirectory = FileManager.default.temporaryDirectory
                .appendingPathComponent("FujiRecipesMacUITests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: fixtureDirectory, withIntermediateDirectories: true)

            let libraryURL = fixtureDirectory.appendingPathComponent("custom-recipes-v1.json")
            let fixture = Recipe(
                id: fixtureID,
                name: "UI Smoke Recipe",
                source: "My Recipes",
                sourceUrl: nil,
                filmSimulation: .provia,
                dynamicRange: .dr100,
                grainEffect: .off,
                whiteBalanceMode: .auto,
                wbShiftRed: 0,
                wbShiftBlue: 0,
                highlight: 0,
                shadow: 0,
                color: 0,
                sharpness: 0,
                highIsoNr: 0,
                clarity: 0,
                settings: [:],
                sensorGeneration: "X-Trans V",
                compatibleCameras: ["X100VI"],
                tags: ["My Recipes"]
            )
            try JSONEncoder().encode(CustomRecipeLibraryExport(recipes: [fixture])).write(to: libraryURL)

            let draft = Loadout(slot: 1, name: "UI Suite Draft", filmSim: .classicChrome, recipeName: "UI Suite Draft")
            let nameOnlyDraft = Loadout(slot: 2, name: "Name-only UI Draft")
            let loadouts = [draft, nameOnlyDraft] + (3...7).map { Loadout(slot: $0, name: "C\($0)") }
            // The sandboxed XCTest runner and the app use different preference
            // containers. Pass bytes through the same readable fixture directory
            // as the recipe library, then let the DEBUG app seed its own suite.
            let loadoutsURL = fixtureDirectory.appendingPathComponent("loadouts-v1.json")
            try JSONEncoder().encode(loadouts).write(to: loadoutsURL, options: .atomic)

            let app = XCUIApplication()
            app.launchEnvironment["FUJI_RECIPES_CUSTOM_LIBRARY_PATH"] = libraryURL.path
            app.launchEnvironment["FUJI_RECIPES_DEFAULTS_SUITE"] = defaultsSuite
            app.launchEnvironment["FUJI_RECIPES_UI_TEST_LOADOUTS_PATH"] = loadoutsURL.path
            app.launch()
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10), "The app opened no window")
            return (fixtureDirectory, app)
        }
        fixtureDirectory = launch.0
        app = launch.1
    }

    override func tearDownWithError() throws {
        let app = app
        MainActor.assumeIsolated { app?.terminate() }
        UserDefaults.standard.removePersistentDomain(forName: defaultsSuite)
        if let fixtureDirectory {
            try? FileManager.default.removeItem(at: fixtureDirectory)
        }
    }

    @MainActor
    func testDialSlotsReadTheLaunchDefaultsSuite() {
        let slot = element("sidebar-slot-1")
        XCTAssertTrue(slot.waitForExistence(timeout: 10))
        XCTAssertEqual(slot.label, "Dial Slot C1: UI Suite Draft")
    }

    @MainActor
    func testNameOnlyDraftIsShownAsStagedAndCanBeCleared() {
        let slot = element("sidebar-slot-2")
        XCTAssertTrue(slot.waitForExistence(timeout: 10))
        XCTAssertEqual(slot.label, "Dial Slot C2: Name-only UI Draft")
        XCTAssertEqual(slot.value as? String, "Staged Draft")
        XCTAssertEqual(element("dial-rack-occupied-count").label, "Assigned dial slots: 2 of 7")
        slot.click()

        let clear = element("clear-local-draft-slot-2")
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.click()
        let confirm = app.sheets.buttons["Clear Local Draft"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.click()
        let cleared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Empty Slot"),
            object: slot
        )
        XCTAssertEqual(XCTWaiter.wait(for: [cleared], timeout: 5), .completed)
        XCTAssertEqual(slot.label, "Dial Slot C2: Empty Slot")
        XCTAssertEqual(element("dial-rack-occupied-count").label, "Assigned dial slots: 1 of 7")
        XCTAssertFalse(clear.exists)
    }

    @MainActor
    func testCustomRecipeControlsAreDiscoverable() {
        let libraryMenu = element("custom-recipe-library-menu")
        XCTAssertTrue(libraryMenu.waitForExistence(timeout: 10))
        libraryMenu.click()

        let newRecipe = element("custom-recipe-new")
        XCTAssertTrue(newRecipe.waitForExistence(timeout: 3))
        newRecipe.click()

        let name = element("custom-recipe-name")
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        XCTAssertTrue(element("custom-recipe-source").exists)
        XCTAssertTrue(element("custom-recipe-film-simulation").exists)
        XCTAssertTrue(element("custom-recipe-save").exists)
        element("custom-recipe-cancel").click()
        app.activate()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 3))
        search.click()
        search.typeText("UI Smoke Recipe")

        let sendToDial = element("send-to-dial-\(fixtureID)")
        XCTAssertTrue(sendToDial.waitForExistence(timeout: 5))
        sendToDial.click()
        let slotMatrix = app.menuItems["Slot Matrix / Options…"]
        XCTAssertTrue(slotMatrix.waitForExistence(timeout: 3))
        slotMatrix.click()
        XCTAssertTrue(element("send-to-dial-slot-1").waitForExistence(timeout: 3))
        XCTAssertTrue(element("c-slot-picker-local-draft-notice").waitForExistence(timeout: 3))
    }

    @MainActor
    func testSavedCustomRecipeSurvivesRelaunchSearchAndStagesToSlot() {
        let recipeName = "Persisted UI Recipe"
        let libraryMenu = element("custom-recipe-library-menu")
        XCTAssertTrue(libraryMenu.waitForExistence(timeout: 10))
        libraryMenu.click()
        let newRecipe = element("custom-recipe-new")
        XCTAssertTrue(newRecipe.waitForExistence(timeout: 3))
        newRecipe.click()

        let name = element("custom-recipe-name")
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.click()
        name.typeText(recipeName)
        let save = element("custom-recipe-save")
        XCTAssertTrue(save.isEnabled)
        save.click()
        app.activate()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.click()
        search.typeText(recipeName)
        XCTAssertTrue(app.staticTexts[recipeName].waitForExistence(timeout: 5))

        app.terminate()
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        let relaunchedSearch = app.searchFields.firstMatch
        XCTAssertTrue(relaunchedSearch.waitForExistence(timeout: 5))
        relaunchedSearch.click()
        relaunchedSearch.typeText(recipeName)
        let stageButton = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "send-to-dial-custom-"))
            .firstMatch
        XCTAssertTrue(stageButton.waitForExistence(timeout: 5))
        stageButton.click()

        let slotMatrix = app.menuItems["Slot Matrix / Options…"]
        XCTAssertTrue(slotMatrix.waitForExistence(timeout: 3))
        slotMatrix.click()
        let slot = element("send-to-dial-slot-1")
        XCTAssertTrue(slot.waitForExistence(timeout: 3))
        slot.click()
        XCTAssertTrue(element("sidebar-slot-1").label.contains(recipeName))
    }

    @MainActor
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
