import XCTest
@testable import FujiRecipesCore

final class CameraDisconnectAndResilienceTests: XCTestCase {

    // MARK: - Objective 1: Disconnect Handler Registration

    @MainActor
    func testConnectRegistersDisconnectHandlerOnClient() async throws {
        let client = ResilienceMockPTPClient()
        let manager = CameraManager()

        XCTAssertNil(client.disconnectHandler, "Disconnect handler should be nil before connect")
        XCTAssertEqual(client.setDisconnectHandlerCount, 0)

        await manager.connect(using: client)

        XCTAssertEqual(manager.status, .connected)
        XCTAssertNotNil(client.disconnectHandler, "CameraManager.connect must register a disconnect handler on the client")
        XCTAssertEqual(client.setDisconnectHandlerCount, 1)
    }

    // MARK: - Objective 1: Hardware Disconnect Trigger

    @MainActor
    func testClientTriggeringDisconnectHandlerTransitionsManagerToDisconnectedAndResetsState() async throws {
        let client = ResilienceMockPTPClient()
        let manager = CameraManager()

        await manager.connect(using: client)
        XCTAssertEqual(manager.status, .connected)
        XCTAssertNotNil(manager.cameraInfo)

        // Simulate physical USB disconnect reported by hardware client
        client.triggerDisconnectHandler()

        // Wait for the @MainActor Task in the disconnect handler to execute
        let didDisconnect = await waitForCondition(timeout: 2.0) {
            manager.status == .disconnected
        }

        XCTAssertTrue(didDisconnect, "Manager should transition to .disconnected when client triggers disconnect handler")
        XCTAssertEqual(manager.status, .disconnected)
        XCTAssertNil(manager.cameraInfo, "cameraInfo should be reset to nil on disconnect")
        XCTAssertEqual(manager.activeSettingsState, .notRead, "activeSettingsState should be reset to .notRead")
        XCTAssertEqual(manager.operation, .idle, "operation should be reset to .idle")
        XCTAssertNil(manager.lastSlotRefresh, "lastSlotRefresh should be reset to nil")
    }

    // MARK: - Objective 1: Disconnect Cleanup

    @MainActor
    func testDisconnectCancelsMonitorTaskAndClearsClientDisconnectHandler() async throws {
        let client = ResilienceMockPTPClient()
        let manager = CameraManager()

        await manager.connect(using: client)
        XCTAssertEqual(manager.status, .connected)
        XCTAssertNotNil(client.disconnectHandler)

        manager.disconnect()

        XCTAssertEqual(manager.status, .disconnected)
        XCTAssertNil(client.disconnectHandler, "CameraManager.disconnect must clear the client's disconnect handler")
        XCTAssertGreaterThanOrEqual(client.disconnectCallCount, 1, "CameraManager.disconnect must call client.disconnect()")

        // Verify that setting isConnected = false afterwards does not trigger any further action
        client.isConnected = false
        // Yield to allow any rogue background task to run
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(manager.status, .disconnected)
    }

    // MARK: - Objective 1: Background Monitor Heartbeat

    @MainActor
    func testClientIsConnectedFalseTriggersDisconnectViaMonitor() async throws {
        let client = ResilienceMockPTPClient()
        let manager = CameraManager()

        await manager.connect(using: client)
        XCTAssertEqual(manager.status, .connected)

        // Drop the connection state without calling disconnect handler directly.
        // The background connection monitor sleeps 2.0s between checks.
        client.isConnected = false

        // Wait up to 3.5s for the 2-second heartbeat loop to detect the dropped connection
        let didDisconnect = await waitForCondition(timeout: 3.5) {
            manager.status == .disconnected
        }

        XCTAssertTrue(didDisconnect, "Connection monitor task should detect isConnected == false and invoke disconnect()")
        XCTAssertEqual(manager.status, .disconnected)
        XCTAssertNil(manager.cameraInfo)
    }

    // MARK: - Edge Cases & Resilience

    @MainActor
    func testConnectionFailureTransitionsToErrorAndCleansUpSession() async {
        let client = ResilienceMockPTPClient()
        client.shouldFailConnect = true
        let manager = CameraManager()

        await manager.connect(using: client)

        XCTAssertEqual(manager.status, .error)
        XCTAssertNotNil(manager.lastError)
        XCTAssertGreaterThanOrEqual(client.disconnectCallCount, 1, "session.disconnect() should be called on connection error")
        XCTAssertNil(manager.cameraInfo)
    }

    @MainActor
    func testDisconnectIsIdempotentWhenAlreadyDisconnected() async {
        let manager = CameraManager()
        XCTAssertEqual(manager.status, .disconnected)

        // Multiple calls should not crash or throw
        manager.disconnect()
        manager.disconnect()

        XCTAssertEqual(manager.status, .disconnected)
        XCTAssertNil(manager.cameraInfo)
    }

    @MainActor
    func testMultipleRapidDisconnectTriggersAreHandledSafely() async throws {
        let client = ResilienceMockPTPClient()
        let manager = CameraManager()

        await manager.connect(using: client)
        XCTAssertEqual(manager.status, .connected)

        // Fire disconnect handler 5 times rapidly
        for _ in 0..<5 {
            client.triggerDisconnectHandler()
        }

        let didDisconnect = await waitForCondition(timeout: 2.0) {
            manager.status == .disconnected
        }
        XCTAssertTrue(didDisconnect)
        XCTAssertEqual(manager.status, .disconnected)
    }

    @MainActor
    func testReconnectionAfterDisconnectReRegistersHandlerAndReestablishesSession() async throws {
        let client = ResilienceMockPTPClient()
        let manager = CameraManager()

        // 1. Initial connection
        await manager.connect(using: client)
        XCTAssertEqual(manager.status, .connected)
        XCTAssertNotNil(client.disconnectHandler)

        // 2. Hardware disconnect
        client.triggerDisconnectHandler()
        let didDisconnect = await waitForCondition(timeout: 2.0) {
            manager.status == .disconnected
        }
        XCTAssertTrue(didDisconnect)
        XCTAssertNil(client.disconnectHandler)

        // 3. Re-connect with a new or same client
        let newClient = ResilienceMockPTPClient()
        await manager.connect(using: newClient)

        XCTAssertEqual(manager.status, .connected)
        XCTAssertNotNil(newClient.disconnectHandler, "New connection must re-register disconnect handler")
        XCTAssertEqual(manager.cameraInfo?.model, "Fuji X100VI")
    }

    // MARK: - Helpers

    @MainActor
    private func waitForCondition(timeout: TimeInterval, condition: @MainActor () -> Bool) async -> Bool {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
        }
        return condition()
    }
}

// MARK: - Resilience Mock Client

private final class ResilienceMockPTPClient: PTPClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _isConnected = false
    private var _disconnectHandler: (@Sendable () -> Void)?
    private var _disconnectCallCount = 0
    private var _setDisconnectHandlerCount = 0

    var connectDelayNanoseconds: UInt64 = 0
    var shouldFailConnect = false

    var isConnected: Bool {
        get { lock.withLock { _isConnected } }
        set { lock.withLock { _isConnected = newValue } }
    }

    var disconnectHandler: (@Sendable () -> Void)? {
        get { lock.withLock { _disconnectHandler } }
        set { lock.withLock { _disconnectHandler = newValue } }
    }

    var disconnectCallCount: Int {
        lock.withLock { _disconnectCallCount }
    }

    var setDisconnectHandlerCount: Int {
        lock.withLock { _setDisconnectHandlerCount }
    }

    var cameraInfo = PTPCameraInfo(model: "Fuji X100VI", vendorExtensionId: 0x0000000E)

    func connect() async throws {
        if connectDelayNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: connectDelayNanoseconds)
        }
        if shouldFailConnect {
            throw PTPError.connectionFailed("Simulated link failure")
        }
        isConnected = true
    }

    func disconnect() {
        lock.withLock {
            _isConnected = false
            _disconnectCallCount += 1
        }
    }

    func setDisconnectHandler(_ handler: (@Sendable () -> Void)?) {
        lock.withLock {
            _disconnectHandler = handler
            _setDisconnectHandlerCount += 1
        }
    }

    func triggerDisconnectHandler() {
        let handler = lock.withLock { _disconnectHandler }
        handler?()
    }

    func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse {
        .unsupported
    }

    func writeProperty(_ code: UInt16, value: Int32) async throws {}

    func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        PTPClientPresetData(slot: index)
    }

    func writePresetSlot(_ index: Int, data: PTPClientPresetData) async throws -> PTPPresetSlotWriteResult {
        PTPPresetSlotWriteResult(slot: index)
    }

    func readNativeProfile() async throws -> Data { Data() }
    func writePTPSettings(from recipe: Recipe) async throws {}
    func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)?) async -> RAFConversionOutcome {
        .failed(message: "not implemented")
    }
    func capturePreview() async throws -> JPEGFile? { nil }
}
