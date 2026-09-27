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
            let loadouts = [draft] + (2...7).map { Loadout(slot: $0, name: "C\($0)") }
            UserDefaults(suiteName: defaultsSuite)?.set(
                try JSONEncoder().encode(loadouts),
                forKey: "com.ant.fuji-recipes.loadouts"
            )

            let app = XCUIApplication()
            app.launchEnvironment["FUJI_RECIPES_CUSTOM_LIBRARY_PATH"] = libraryURL.path
            app.launchEnvironment["FUJI_RECIPES_DEFAULTS_SUITE"] = defaultsSuite
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
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
