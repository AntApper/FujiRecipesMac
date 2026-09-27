import XCTest
@testable import FujiRecipesCore

final class LoadoutContentNameTests: XCTestCase {
    func testAnEmptySlotHasNoContentName() {
        XCTAssertNil(Loadout(slot: 3, name: "C3").contentName)
    }

    func testASlotWithItsOwnNameUsesThatName() {
        let loadout = Loadout(slot: 3, name: "Cafe Noir", filmSim: .classicChrome, recipeName: "Café Noir Recipe")
        XCTAssertEqual(loadout.contentName, "Cafe Noir")
    }

    func testASlotStillNamedC3UsesTheRecipeItCameFrom() {
        let loadout = Loadout(slot: 3, name: "C3", filmSim: .classicChrome, recipeName: "Kodak Tri-X 400")
        XCTAssertEqual(loadout.contentName, "Kodak Tri-X 400")
    }

    func testASlotStillNamedC3WithNoRecipeIsACustomPreset() {
        XCTAssertEqual(Loadout(slot: 3, name: "C3", filmSim: .classicChrome).contentName, "Custom Preset")
    }
}
