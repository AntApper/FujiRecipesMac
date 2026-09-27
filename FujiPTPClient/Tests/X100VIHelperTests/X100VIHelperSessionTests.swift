import Foundation
import XCTest
@testable import X100VIHelper
import FujiRecipesCore

/// Drives `X100VIHelperClient` against a shell script that speaks the
/// helper's line protocol, so no camera is needed.
final class X100VIHelperSessionTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("x100vi-helper-session-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        unsetenv("FUJI_RECIPES_X100VI_HELPER")
        try? FileManager.default.removeItem(at: directory)
    }

    /// Answers `read_property` with its code as the value and every other
    /// command with success. It writes nothing to stderr.
    private func installFakeHelper(extraCases: String = "") throws {
        let script = """
        #!/bin/bash
        while IFS= read -r line; do
          id=$(printf '%s' "$line" | sed -E 's/.*"id":"([0-9]+)".*/\\1/')
          case "$line" in
        \(extraCases)
          esac
          code=$(printf '%s' "$line" | sed -nE 's/.*"code":([0-9]+).*/\\1/p')
          printf '{"id":"%s","success":true,"result":{"value":%s}}\\n' "$id" "${code:-0}"
        done
        """
        let url = directory.appendingPathComponent("x100vi_helper")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        setenv("FUJI_RECIPES_X100VI_HELPER", url.path, 1)
    }

    private func value(of response: PTPPropertyResponse) -> UInt32? {
        guard case .uint32(let value) = response else { return nil }
        return value
    }

    func testRequestRoundTripsThroughAHelperWithSilentStderr() async throws {
        try installFakeHelper()
        let client = X100VIHelperClient()

        try await client.connect()
        let response = try await client.readProperty(0xD192)
        client.disconnect()

        XCTAssertEqual(value(of: response), 0xD192)
    }
}
