import XCTest
import FujiRecipesCore
@testable import PTPClientMacOS

final class PresetSlotReadTests: XCTestCase {
    private static let numericCodes: [UInt16] = [
        0xD18E, 0xD18F, 0xD190, 0xD192, 0xD193, 0xD194, 0xD195, 0xD196,
        0xD197, 0xD198, 0xD199, 0xD19A, 0xD19B, 0xD19C, 0xD19D, 0xD19E,
        0xD19F, 0xD1A0, 0xD1A1, 0xD1A2, 0xD1A3, 0xD1A4
    ]
    private static let emptyName = Data([0])
    private static let nameAB = Data([3, 0x41, 0, 0x42, 0, 0, 0])

    func testAnUnnamedSlotWithEveryValueZeroIsEmpty() {
        let preset = ImageCaptureCorePTPClient.presetData(slot: 3, values: values(name: Self.emptyName))

        XCTAssertEqual(preset.slot, 3)
        XCTAssertEqual(preset.name, "")
        XCTAssertTrue(preset.isEmptySlot)
    }

    func testAFilmSimulationMeansTheSlotIsNotEmpty() {
        let preset = ImageCaptureCorePTPClient.presetData(
            slot: 3,
            values: values(name: Self.emptyName, overriding: [0xD192: 0x13])
        )

        XCTAssertEqual(preset.filmSimulation, 0x13)
        XCTAssertFalse(preset.isEmptySlot)
    }

    func testAnUnnamedSlotWithANonzeroToneIsNotEmpty() {
        let preset = ImageCaptureCorePTPClient.presetData(
            slot: 3,
            values: values(name: Self.emptyName, overriding: [0xD19D: 10])
        )

        XCTAssertEqual(preset.highlight, 10)
        XCTAssertFalse(preset.isEmptySlot)
    }

    func testANamedSlotWithEveryValueZeroIsNotEmpty() {
        let preset = ImageCaptureCorePTPClient.presetData(slot: 3, values: values(name: Self.nameAB))

        XCTAssertEqual(preset.name, "AB")
        XCTAssertFalse(preset.isEmptySlot)
    }

    private func values(name: Data, overriding overrides: [UInt16: UInt32] = [:]) -> [UInt16: PTPPropertyResponse] {
        var values: [UInt16: PTPPropertyResponse] = [0xD18D: .data(name)]
        for code in Self.numericCodes {
            values[code] = .uint32(overrides[code] ?? 0)
        }
        return values
    }
}
