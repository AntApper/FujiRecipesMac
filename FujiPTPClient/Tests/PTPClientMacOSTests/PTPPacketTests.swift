import XCTest
@testable import PTPClientMacOS

final class PTPPacketTests: XCTestCase {
    func testCommandUsesPTPLittleEndianContainerFraming() {
        let packet = PTPPacket.command(
            operation: 0x1015,
            parameters: [0xD18C]
        )

        XCTAssertEqual(packet.count, 16)
        XCTAssertEqual(packet.u32LE(at: 0), 16)
        XCTAssertEqual(packet.u16LE(at: 4), 0x0001)
        XCTAssertEqual(packet.u16LE(at: 6), 0x1015)
        XCTAssertEqual(packet.u32LE(at: 8), 0)
        XCTAssertEqual(packet.u32LE(at: 12), 0xD18C)
    }

    func testCommandSupportsMultiplePTPParametersInOrder() {
        let packet = PTPPacket.command(
            operation: 0x1002,
            parameters: [1, 0x02030405, 0xFFFFFFFF]
        )

        XCTAssertEqual(packet.count, 24)
        XCTAssertEqual(packet.u32LE(at: 12), 1)
        XCTAssertEqual(packet.u32LE(at: 16), 0x02030405)
        XCTAssertEqual(packet.u32LE(at: 20), 0xFFFFFFFF)
    }
}
