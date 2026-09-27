import XCTest
@testable import FujiRecipesCore

final class CameraPresetNameTests: XCTestCase {
    private static let tMaxHard = "Kodak T-Max 100 Hard Tone - A Film Simulation Recipe for Fujifilm X-Trans IV & X-Trans V Cameras (Part 1)"
    private static let tMaxSoft = "Kodak T-Max 100 Soft Tone - A Film Simulation Recipe for Fujifilm X-Trans IV & X-Trans V Cameras (Part 2)"

    func testLongRecipeTitlesFoldToWholeWordsWithinTwentyFiveCharacters() {
        XCTAssertEqual(CameraPresetName.label(for: Self.tMaxHard, slot: 3), "Kodak T-Max 100 Hard Tone")
        XCTAssertEqual(CameraPresetName.label(for: Self.tMaxSoft, slot: 3), "Kodak T-Max 100 Soft Tone")
        XCTAssertEqual(
            CameraPresetName.label(for: "Summer of '59 - A Fujifilm Recipe for Fifth-Generation Cameras", slot: 3),
            "Summer of '59 - A"
        )
    }

    func testNamesThatFitAreKept() {
        XCTAssertEqual(CameraPresetName.label(for: "Fujicolor 100 Industrial", slot: 3), "Fujicolor 100 Industrial")
    }

    func testNonASCIICharactersFoldToTheirASCIIEquivalents() {
        XCTAssertEqual(CameraPresetName.label(for: "Café Noir", slot: 3), "Cafe Noir")
        XCTAssertEqual(CameraPresetName.label(for: "Ciné—Film\u{00A0}’86", slot: 3), "Cine-Film '86")
        XCTAssertEqual(CameraPresetName.label(for: "日本", slot: 3), "ri ben")
    }

    func testNamesWithNothingPrintableFallBackToTheSlot() {
        XCTAssertEqual(CameraPresetName.label(for: "📷🎞️", slot: 3), "C3")
        XCTAssertEqual(CameraPresetName.label(for: "", slot: 3), "C3")
    }

    func testASingleOverlongWordIsCutToTwentyFiveLetters() {
        XCTAssertEqual(
            CameraPresetName.label(for: "Abcdefghijklmnopqrstuvwxyzabcd", slot: 3),
            "Abcdefghijklmnopqrstuvwxy"
        )
    }

    func testEveryBundledRecipeGetsADistinctCameraLabel() throws {
        let names = try bundledRecipeCatalog().recipes.map(\.name)
        let labels = names.map { CameraPresetName.label(for: $0, slot: 1) }

        XCTAssertEqual(Set(labels).count, names.count)
        for (name, label) in zip(names, labels) {
            XCTAssertFalse(label.isEmpty, name)
            XCTAssertLessThanOrEqual(label.count, 25, name)
            XCTAssertTrue(label.unicodeScalars.allSatisfy { (0x20...0x7E).contains($0.value) }, name)
        }
    }

    func testPayloadCountsTheNulAndEncodesUCS2LittleEndian() {
        XCTAssertEqual(Array(CameraPresetName.ptpPayload(for: "AB", slot: 3)), [3, 0x41, 0, 0x42, 0, 0, 0])
    }

    @MainActor
    func testCameraSyncKeepsTheRecipeLinkWhenTheCameraShowsItsLabel() throws {
        let store = LoadoutStore(defaults: try isolatedDefaults())
        let recipe = Recipe(id: "tmax-hard", name: Self.tMaxHard, source: "test", sourceUrl: nil, filmSimulation: .acros)
        store.applyRecipe(recipe, to: 3)

        let adopted = store.adoptCameraWrite(
            PTPClientPresetData(slot: 3, name: "Kodak T-Max 100 Hard Tone", filmSimulation: FilmSimulation.acros.rawValue),
            ifUnchangedSince: store.revision(of: 3)
        )

        XCTAssertTrue(adopted)
        let loadout = try XCTUnwrap(store.loadout(for: 3))
        XCTAssertEqual(loadout.name, "Kodak T-Max 100 Hard Tone")
        XCTAssertEqual(loadout.recipeName, Self.tMaxHard)
        XCTAssertEqual(loadout.recipeID, "tmax-hard")
    }

    @MainActor
    func testCameraSyncDropsTheRecipeLinkWhenTheCameraShowsAnotherName() throws {
        let store = LoadoutStore(defaults: try isolatedDefaults())
        let recipe = Recipe(id: "tmax-hard", name: Self.tMaxHard, source: "test", sourceUrl: nil, filmSimulation: .acros)
        store.applyRecipe(recipe, to: 3)

        store.syncFromCameraPresetData(
            [PTPClientPresetData(slot: 3, name: "Street Mono", filmSimulation: FilmSimulation.acros.rawValue)],
            overwriteDirtyDrafts: true
        )

        let loadout = try XCTUnwrap(store.loadout(for: 3))
        XCTAssertEqual(loadout.name, "Street Mono")
        XCTAssertNil(loadout.recipeName)
        XCTAssertNil(loadout.recipeID)
    }

    private func isolatedDefaults() throws -> UserDefaults {
        let suite = "CameraPresetNameTests.\(UUID().uuidString)"
        addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
        return try XCTUnwrap(UserDefaults(suiteName: suite))
    }
}
