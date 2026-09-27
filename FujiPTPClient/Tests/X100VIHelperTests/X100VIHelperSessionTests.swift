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

    private var requestLog: URL { directory.appendingPathComponent("requests.log") }

    /// Logs every request line, answers `read_property` with its code as the
    /// value, and answers every other command with success. It writes
    /// nothing to stderr.
    private func installFakeHelper(extraCases: String = "") throws {
        let script = """
        #!/bin/bash
        while IFS= read -r line; do
          printf '%s\\n' "$line" >> '\(requestLog.path)'
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

    func testConnectWaitsOutTheHelpersStaleSessionRecovery() async throws {
        try installFakeHelper(extraCases: """
            *'"command":"connect"'*) sleep 11.5 ;;
        """)
        let client = X100VIHelperClient()

        try await client.connect()

        XCTAssertTrue(client.isConnected)
        client.disconnect()
    }

    func testDisconnectFailsARequestQueuedBehindAHelperThatExited() async throws {
        // Code 1 makes the helper exit without a reply while a child keeps
        // its stdout open, so the worker still holds the first request when
        // disconnect tears the session down. Whether the worker then sees
        // the queued request depends on AsyncStream cancellation timing, so
        // the test repeats the teardown.
        try installFakeHelper(extraCases: """
            *'"code":1,'*|*'"code":1}'*) sleep 2 & exit 0 ;;
        """)
        let client = X100VIHelperClient()

        for _ in 1...10 {
            try await client.connect()
            let unanswered = Task { try await client.readProperty(1) }
            try await Task.sleep(for: .milliseconds(100))
            let queued = Task { try await client.readProperty(2) }
            while client.isConnected { try await Task.sleep(for: .milliseconds(10)) }
            client.disconnect()

            do {
                _ = try await queued.value
                XCTFail("A request queued behind a dead helper must fail")
            } catch PTPError.notConnected {
            }
            _ = try? await unanswered.value
        }

        try await client.connect()
        let response = try await client.readProperty(3)
        client.disconnect()
        XCTAssertEqual(value(of: response), 3)
        let requests = try String(contentsOf: requestLog, encoding: .utf8)
        XCTAssertFalse(requests.contains("\"code\":2"), "The queued request reached a helper:\n\(requests)")
    }
}
