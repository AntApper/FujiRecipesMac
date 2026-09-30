import XCTest
import FujiRecipesCore

/// Uses isolated recipe/defaults fixtures and never connects a camera.
/// The DEBUG root scene must map FUJI_RECIPES_UI_TEST_REDUCE_MOTION=0/1
/// to recipeReduceMotionOverride when a UI-test library path is supplied.
/// Without an override, recipeReduceMotion follows the system preference.
final class RecipeAccessibilityUITests: XCTestCase {
    private let alphaID = "r7-accessibility-alpha"
    private let betaID = "r7-accessibility-beta"
    private let alphaName = "R7 Accessibility Alpha"
    private let betaName = "R7 Accessibility Beta"
    private let defaultsSuite = "RecipeAccessibilityUITests-\(UUID().uuidString)"
    private var fixtureDirectory: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let fixtures = [(alphaID, alphaName), (betaID, betaName)]
        let defaultsSuite = defaultsSuite
        let setup = try MainActor.assumeIsolated { () throws -> (URL, XCUIApplication) in
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("RecipeAccessibilityUITests-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let libraryURL = directory.appendingPathComponent("custom-recipes-v1.json")
            let recipes = fixtures.map { id, name in
                Recipe(
                    id: id,
                    name: name,
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
                    settings: ["filmSimulation": "Provia", "highlight": "0"],
                    sensorGeneration: "X-Trans V",
                    compatibleCameras: ["X100VI"],
                    tags: ["My Recipes"]
                )
            }
            try JSONEncoder().encode(CustomRecipeLibraryExport(recipes: recipes)).write(to: libraryURL)
            let app = XCUIApplication()
            app.launchEnvironment["FUJI_RECIPES_CUSTOM_LIBRARY_PATH"] = libraryURL.path
            app.launchEnvironment["FUJI_RECIPES_DEFAULTS_SUITE"] = defaultsSuite
            return (directory, app)
        }
        fixtureDirectory = setup.0
        app = setup.1
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
    func testStandardMotionRetainsHoverFeedbackAndKeyboardSelection() {
        launchFixture(reduceMotion: false)
        assertHoverBehavior(reduceMotion: false)
        assertKeyboardSelectionAndQuickLook()
    }

    @MainActor
    func testReducedMotionKeepsHoverSizeAndKeyboardSelection() {
        launchFixture(reduceMotion: true)
        assertHoverBehavior(reduceMotion: true)
        assertKeyboardSelectionAndQuickLook()
    }

    @MainActor
    func testCardActionsRemainSeparateAccessibilityControls() {
        launchFixture(reduceMotion: true)
        let card = element("recipe-card-\(alphaID)")
        assertSelection(nil)
        let favorite = card.buttons["recipe-favorite-\(alphaID)"]
        let quickLook = card.buttons["recipe-quick-look-\(alphaID)"]
        let expand = card.buttons["recipe-expand-\(alphaID)"]
        let send = card.descendants(matching: .any)["send-to-dial-\(alphaID)"]
        for control in [favorite, quickLook, expand, send] {
            XCTAssertTrue(control.exists, "The card swallowed an independently accessible action")
            XCTAssertTrue(control.isHittable)
        }

        favorite.click()
        waitForAttribute("label", of: favorite, toEqual: "Remove \(alphaName) from favorites")
        expand.click()
        waitForAttribute("label", of: expand, toEqual: "Collapse \(alphaName) formula")
        assertSelection(alphaID)
        expand.click()
        waitForAttribute("label", of: expand, toEqual: "Expand \(alphaName) formula")
        assertSelection(alphaID)
        for control in [favorite, quickLook, expand, send] {
            XCTAssertTrue(control.exists)
            XCTAssertTrue(control.isHittable)
        }

        send.click()
        let matrix = app.menuItems["Slot Matrix / Options…"]
        XCTAssertTrue(matrix.waitForExistence(timeout: 3))
        matrix.click()
        XCTAssertTrue(element("c-slot-picker-local-draft-notice").waitForExistence(timeout: 3))
        element("c-slot-picker-cancel").click()
        assertKeyboardSelectionAndQuickLook()
        let snapshot = XCTAttachment(string: app.debugDescription)
        snapshot.name = "Recipe selection and independent accessibility controls"
        snapshot.lifetime = .keepAlways
        add(snapshot)
    }

    @MainActor
    func testClearingAdditionalFiltersKeepsTheCurrentCollection() {
        launchFixture(reduceMotion: true)
        element("recipe-favorite-\(alphaID)").click()
        let collections = [
            (identifier: "recipe-collection-my-recipes", includesBeta: true),
            (identifier: "recipe-collection-favorites", includesBeta: false)
        ]
        for collection in collections {
            let collectionButton = element(collection.identifier)
            collectionButton.click()
            let search = app.searchFields.firstMatch
            XCTAssertTrue(search.waitForExistence(timeout: 3))
            search.click()
            search.typeText("r7-filter-no-matching-recipe")
            let clear = element("recipe-clear-additional-filters")
            XCTAssertTrue(clear.waitForExistence(timeout: 3))
            XCTAssertEqual(clear.label, "Clear Additional Filters")
            clear.click()
            waitForAttribute("value", of: collectionButton, toEqual: "Selected")
            XCTAssertTrue(element("recipe-card-\(alphaID)").waitForExistence(timeout: 3))
            XCTAssertEqual(element("recipe-card-\(betaID)").exists, collection.includesBeta)
            XCTAssertEqual(search.value as? String, "")
            waitForAttribute("value", of: element("recipe-collection-all"), toEqual: "Not selected")
        }
    }

    @MainActor
    private func launchFixture(reduceMotion: Bool) {
        app.launchEnvironment["FUJI_RECIPES_UI_TEST_REDUCE_MOTION"] = reduceMotion ? "1" : "0"
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
        let myRecipes = element("recipe-collection-my-recipes")
        XCTAssertTrue(myRecipes.waitForExistence(timeout: 10))
        myRecipes.click()
        XCTAssertTrue(element("recipe-card-\(alphaID)").waitForExistence(timeout: 5))
        XCTAssertTrue(element("recipe-card-\(betaID)").waitForExistence(timeout: 5))
    }

    @MainActor
    private func assertHoverBehavior(reduceMotion: Bool) {
        let card = element("recipe-card-\(alphaID)")
        app.searchFields.firstMatch.hover()
        settleHover()
        let restingFrame = card.frame
        card.hover()
        settleHover()
        if reduceMotion {
            XCTAssertEqual(card.frame.width, restingFrame.width, accuracy: 0.5)
            XCTAssertEqual(card.frame.height, restingFrame.height, accuracy: 0.5)
        } else {
            XCTAssertGreaterThan(card.frame.width, restingFrame.width + 1)
        }
    }

    @MainActor
    private func assertKeyboardSelectionAndQuickLook() {
        element("recipe-quick-look-\(alphaID)").click()
        XCTAssertTrue(element("recipe-quick-look-close").waitForExistence(timeout: 3))
        element("recipe-quick-look-close").click()
        assertSelection(alphaID)

        app.typeKey(.rightArrow, modifierFlags: [])
        assertSelection(betaID)
        app.typeKey(.space, modifierFlags: [])
        let title = element("recipe-quick-look-title")
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        // A native macOS Text exposes its content as AXValue. The modal's
        // explicit name also identifies the recipe when VoiceOver enters it.
        waitForAttribute("value", of: title, toEqual: betaName)
        waitForAttribute("label", of: element("recipe-quick-look-modal"), toEqual: "Quick Look, \(betaName)")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(title.waitForNonExistence(timeout: 3))
        assertSelection(betaID)
    }

    @MainActor
    private func assertSelection(_ selectedID: String?, file: StaticString = #filePath, line: UInt = #line) {
        // The macOS Group/Other roles export names, but no string AXValue.
        // Check the full recipe name and state on the grid and both cards.
        let fixtures = [(alphaID, alphaName), (betaID, betaName)]
        let selectedName = fixtures.first { $0.0 == selectedID }?.1
        let gridLabel = selectedName.map { "Recipes. Selected recipe: \($0)" } ?? "Recipes. No recipe selected"
        waitForAttribute("label", of: element("recipe-grid"), toEqual: gridLabel, file: file, line: line)
        for (id, name) in fixtures {
            let state = id == selectedID ? "selected" : "not selected"
            waitForAttribute("label", of: element("recipe-card-\(id)"), toEqual: "\(name), \(state)",
                             file: file, line: line)
        }
    }

    @MainActor
    private func settleHover() {
        // Wait past the ordinary spring; an immediate frame could conceal a
        // regression where Reduce Motion still allowed hover enlargement.
        let settled = expectation(description: "Hover feedback has settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
    }

    @MainActor
    private func waitForAttribute(_ key: String, of element: XCUIElement, toEqual expected: String,
                                  file: StaticString = #filePath, line: UInt = #line) {
        let change = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "%K == %@", key, expected),
            object: element
        )
        let result = XCTWaiter.wait(for: [change], timeout: 5)
        if result != .completed {
            let snapshot = XCTAttachment(string: app.debugDescription)
            snapshot.name = "Accessibility tree while waiting for \(key): \(expected)"
            snapshot.lifetime = .keepAlways
            add(snapshot)
        }
        XCTAssertEqual(result, .completed,
                       "Expected \(key) to become \(expected)", file: file, line: line)
    }

    @MainActor
    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
