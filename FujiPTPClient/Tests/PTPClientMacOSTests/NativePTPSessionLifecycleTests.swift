import Foundation
import XCTest
import FujiRecipesCore
@testable import PTPClientMacOS

/// No test in this suite constructs the native browser or uses USB hardware.
final class NativePTPSessionLifecycleTests: XCTestCase, @unchecked Sendable {
    func testUnrelatedRemovalPreservesConnectionAndOwnRemovalFinishesEveryCaller() async throws {
        let device = FakeNativeDevice()
        let provider = FakeNativeProvider(devices: [device])
        let client = ImageCaptureCorePTPClient(deviceProvider: provider, scheduler: ManualPTPDeadlines())
        let notifications = CompletionCounter()
        client.setDisconnectHandler { notifications.increment() }
        try await connect(client, to: device)
        let first = read(client, code: 1)
        try await waitUntil { device.commandCount == 1 }
        let second = read(client, code: 2)

        provider.emitRemoval(UUID())
        device.completeCommand(0, value: 11)
        try await waitUntil { device.commandCount == 2 }
        try await assertOutcome(first, .value(11))
        XCTAssertTrue(client.isConnected)
        XCTAssertEqual(device.closeCount, 0)

        let queued = read(client, code: 3)
        provider.emitRemoval(device.deviceID)
        try await assertOutcome(second, .notConnected)
        try await assertOutcome(queued, .notConnected)
        try await waitUntil { notifications.value == 1 && device.releaseCount == 1 }
        provider.emitRemoval(device.deviceID)
        device.completeCommand(1, value: 22)
        XCTAssertFalse(client.isConnected)
        XCTAssertEqual(device.commandCount, 2)
        XCTAssertEqual(notifications.value, 1)
        XCTAssertEqual(second.completionCount, 1)
        XCTAssertEqual(queued.completionCount, 1)
    }

    func testOpenTimeoutClosesLateOpenWithoutChangingNewSession() async throws {
        let old = FakeNativeDevice(name: "old attachment")
        let fresh = FakeNativeDevice(name: "new attachment")
        let deadlines = ManualPTPDeadlines()
        let provider = FakeNativeProvider(devices: [old, fresh])
        let client = ImageCaptureCorePTPClient(deviceProvider: provider, scheduler: deadlines)
        let timedOut = connecting(client)
        try await waitUntil { old.openCount == 1 }
        XCTAssertTrue(deadlines.fireNext(.open))
        try await assertOutcome(timedOut, .connectionFailed)
        try await waitUntil { old.closeCount == 1 }
        XCTAssertEqual(old.releaseCount, 0, "An unresolved open still owns its device")

        try await connect(client, to: fresh)
        old.completeOpen()
        try await waitUntil { old.closeCount == 2 && old.releaseCount == 1 }
        old.emitRecordedEvent(.sessionClosed)
        old.completeOpen(error: FixtureError.failure)
        XCTAssertTrue(client.isConnected)
        XCTAssertEqual(client.cameraInfo.model, "new attachment")
        XCTAssertEqual(timedOut.completionCount, 1)
        XCTAssertEqual(fresh.closeCount, 0)
        client.disconnect()
    }

    func testLateOldOpenCannotCompleteOrCancelNewPendingOpen() async throws {
        let old = FakeNativeDevice()
        let fresh = FakeNativeDevice()
        let deadlines = ManualPTPDeadlines()
        let client = ImageCaptureCorePTPClient(deviceProvider: FakeNativeProvider(devices: [old, fresh]), scheduler: deadlines)
        let first = connecting(client)
        try await waitUntil { old.openCount == 1 }
        XCTAssertTrue(deadlines.fireNext(.open))
        try await assertOutcome(first, .connectionFailed)
        let second = connecting(client)
        try await waitUntil { fresh.openCount == 1 }
        old.completeOpen()
        try await waitUntil { old.releaseCount == 1 }
        XCTAssertNil(second.result)
        XCTAssertFalse(client.isConnected)
        XCTAssertTrue(deadlines.fireNext(.open))
        try await assertOutcome(second, .connectionFailed)
        fresh.completeOpen(error: FixtureError.failure)
        try await waitUntil { fresh.releaseCount == 1 }
    }

    func testCloseDuringPendingOpenMustBeFollowedByCloseAfterLateSuccess() async throws {
        let old = FakeNativeDevice()
        old.automaticallyClose = false
        let fresh = FakeNativeDevice(deviceID: old.deviceID)
        let premature = FakeNativeDevice(deviceID: old.deviceID)
        let deadlines = ManualPTPDeadlines()
        let provider = FakeNativeProvider(devices: [old, premature, fresh])
        let client = ImageCaptureCorePTPClient(deviceProvider: provider, scheduler: deadlines)
        let first = connecting(client)
        try await waitUntil { old.openCount == 1 }
        XCTAssertTrue(deadlines.fireNext(.open))
        try await assertOutcome(first, .connectionFailed)
        try await waitUntil { old.closeCount == 1 }

        let blockedReuse = connecting(client)
        try await assertOutcome(blockedReuse, .connectionFailed)
        XCTAssertEqual(premature.openCount, 0)
        old.completeOpen()
        old.completeClose(0)
        try await waitUntil { old.closeCount == 2 }
        XCTAssertEqual(old.releaseCount, 0)
        old.completeClose(1)
        try await waitUntil { old.releaseCount == 1 }

        try await connect(client, to: fresh)
        old.completeClose(0, error: FixtureError.failure)
        old.completeOpen()
        XCTAssertTrue(client.isConnected)
        XCTAssertEqual(fresh.closeCount, 0)
        client.disconnect()
    }

    func testCloseTimeoutRetainsOwnershipUntilCloseActuallyCompletes() async throws {
        let old = FakeNativeDevice()
        old.automaticallyClose = false
        let premature = FakeNativeDevice(deviceID: old.deviceID)
        let fresh = FakeNativeDevice(deviceID: old.deviceID)
        let deadlines = ManualPTPDeadlines()
        let client = ImageCaptureCorePTPClient(deviceProvider: FakeNativeProvider(devices: [old, premature, fresh]), scheduler: deadlines)
        try await connect(client, to: old)
        let disconnected = Task { client.disconnect() }
        try await waitUntil { old.closeCount == 1 }
        XCTAssertTrue(deadlines.fireNext(.close))
        await disconnected.value
        XCTAssertEqual(old.releaseCount, 0)
        try await assertOutcome(connecting(client), .connectionFailed)
        old.completeClose(0)
        try await waitUntil { old.releaseCount == 1 }
        try await connect(client, to: fresh)
        old.completeClose(0)
        XCTAssertTrue(client.isConnected)
        client.disconnect()
    }

    func testCancelledOpenStillCleansUpLateSuccessExactlyOnce() async throws {
        let device = FakeNativeDevice()
        let client = ImageCaptureCorePTPClient(deviceProvider: FakeNativeProvider(devices: [device]), scheduler: ManualPTPDeadlines())
        let cancelled = connecting(client)
        try await waitUntil { device.openCount == 1 }
        cancelled.cancel()
        try await assertOutcome(cancelled, .cancelled)
        try await waitUntil { device.closeCount == 1 }
        device.completeOpen()
        try await waitUntil { device.closeCount == 2 && device.releaseCount == 1 }
        device.completeOpen()
        XCTAssertFalse(client.isConnected)
        XCTAssertEqual(cancelled.completionCount, 1)
    }

    func testOwnRemovalWhileOpeningFailsImmediatelyAndIgnoresLateOpen() async throws {
        let old = FakeNativeDevice()
        let fresh = FakeNativeDevice()
        let provider = FakeNativeProvider(devices: [old, fresh])
        let client = ImageCaptureCorePTPClient(deviceProvider: provider, scheduler: ManualPTPDeadlines())
        let interrupted = connecting(client)
        try await waitUntil { old.openCount == 1 }
        provider.emitRemoval(old.deviceID)
        try await assertOutcome(interrupted, .connectionFailed)
        try await waitUntil { old.releaseCount == 1 }
        try await connect(client, to: fresh)
        old.completeOpen()
        XCTAssertTrue(client.isConnected)
        XCTAssertEqual(interrupted.completionCount, 1)
        XCTAssertEqual(fresh.closeCount, 0)
        client.disconnect()
    }

    func testDroppingAConnectedClientClosesAndReleasesItsLease() async throws {
        let device = FakeNativeDevice()
        var client: ImageCaptureCorePTPClient? = ImageCaptureCorePTPClient(deviceProvider: FakeNativeProvider(devices: [device]), scheduler: ManualPTPDeadlines())
        try await connect(try XCTUnwrap(client), to: device)
        client = nil
        try await waitUntil { device.releaseCount == 1 }
        XCTAssertEqual(device.closeCount, 1)
    }

    func testCancelledDiscoveryReleasesADeviceReturnedLate() async throws {
        let device = FakeNativeDevice()
        let provider = FakeNativeProvider(devices: [])
        provider.delaysAcquisition = true
        let client = ImageCaptureCorePTPClient(deviceProvider: provider, scheduler: ManualPTPDeadlines())
        let cancelled = connecting(client)
        try await waitUntil { provider.acquisitionCount == 1 }
        cancelled.cancel()
        try await assertOutcome(cancelled, .cancelled)
        provider.finishDelayedAcquisition(device)
        try await waitUntil { device.releaseCount == 1 }
        XCTAssertEqual(device.openCount, 0)
        XCTAssertFalse(client.isConnected)
    }

    func testConcurrentCommandsSerializeWholeLifetimes() async throws {
        let device = FakeNativeDevice()
        let client = ImageCaptureCorePTPClient(deviceProvider: FakeNativeProvider(devices: [device]), scheduler: ManualPTPDeadlines())
        try await connect(client, to: device)
        let first = read(client, code: 1)
        try await waitUntil { device.commandCount == 1 }
        let second = read(client, code: 2)
        device.completeCommand(0, value: 10)
        try await waitUntil { device.commandCount == 2 }
        // A duplicated old callback must not fail or clear the second request.
        device.completeCommand(0, error: FixtureError.failure)
        device.completeCommand(1, value: 20)
        try await assertOutcome(first, .value(10))
        try await assertOutcome(second, .value(20))
        XCTAssertEqual(device.maximumInFlight, 1)
        XCTAssertEqual(device.transactionIDs, [1, 2])
        XCTAssertTrue(client.isConnected)
        client.disconnect()
    }

    func testPTPErrorReplyFinishesItsCallerAndAllowsNextQueuedCommand() async throws {
        let device = FakeNativeDevice()
        let client = ImageCaptureCorePTPClient(deviceProvider: FakeNativeProvider(devices: [device]), scheduler: ManualPTPDeadlines())
        try await connect(client, to: device)
        let rejected = read(client, code: 1)
        try await waitUntil { device.commandCount == 1 }
        let next = read(client, code: 2)
        device.completeCommand(0, responseCode: 0x201C)
        try await waitUntil { device.commandCount == 2 }
        device.completeCommand(1, value: 20)
        try await assertOutcome(rejected, .ptpError(0x201C))
        try await assertOutcome(next, .value(20))
        XCTAssertTrue(client.isConnected)
        XCTAssertEqual(device.maximumInFlight, 1)
        client.disconnect()
    }

    func testCommandTimeoutFinishesActiveAndQueuedAndLateCallbacksCannotTouchReconnect() async throws {
        let old = FakeNativeDevice()
        let fresh = FakeNativeDevice()
        let deadlines = ManualPTPDeadlines()
        let client = ImageCaptureCorePTPClient(deviceProvider: FakeNativeProvider(devices: [old, fresh]), scheduler: deadlines)
        let notifications = CompletionCounter()
        client.setDisconnectHandler { notifications.increment() }
        try await connect(client, to: old)
        let first = read(client, code: 1)
        try await waitUntil { old.commandCount == 1 }
        let queued = read(client, code: 2)
        XCTAssertTrue(deadlines.fireNext(.command))
        try await assertOutcome(first, .commandFailed)
        try await assertOutcome(queued, .notConnected)
        try await waitUntil { old.releaseCount == 1 && notifications.value == 1 }
        XCTAssertEqual(old.commandCount, 1)

        try await connect(client, to: fresh)
        let current = read(client, code: 3)
        try await waitUntil { fresh.commandCount == 1 }
        old.completeCommand(0, error: FixtureError.failure)
        old.emitRecordedEvent(.error("stale session error"))
        fresh.completeCommand(0, value: 30)
        try await assertOutcome(current, .value(30))
        XCTAssertEqual(first.completionCount, 1)
        XCTAssertEqual(queued.completionCount, 1)
        XCTAssertTrue(client.isConnected)
        XCTAssertEqual(notifications.value, 1)
        client.disconnect()
    }

    func testDisconnectFinishesActiveAndQueuedAndStaleDeadlineCannotFailNewRequest() async throws {
        let old = FakeNativeDevice()
        let fresh = FakeNativeDevice()
        let deadlines = ManualPTPDeadlines()
        let client = ImageCaptureCorePTPClient(deviceProvider: FakeNativeProvider(devices: [old, fresh]), scheduler: deadlines)
        try await connect(client, to: old)
        let first = read(client, code: 1)
        try await waitUntil { old.commandCount == 1 }
        let queued = read(client, code: 2)
        client.disconnect()
        try await assertOutcome(first, .notConnected)
        try await assertOutcome(queued, .notConnected)
        try await connect(client, to: fresh)
        let current = read(client, code: 3)
        try await waitUntil { fresh.commandCount == 1 }
        XCTAssertTrue(deadlines.fireNext(.command, includingCancelled: true))
        old.completeCommand(0, error: FixtureError.failure)
        fresh.completeCommand(0, value: 30)
        try await assertOutcome(current, .value(30))
        XCTAssertTrue(client.isConnected)
        XCTAssertEqual(first.completionCount, 1)
        XCTAssertEqual(queued.completionCount, 1)
        client.disconnect()
    }

    func testQueuedCancellationNeverSendsCancelledCommandOrDisconnectsActiveRequest() async throws {
        let device = FakeNativeDevice()
        let client = ImageCaptureCorePTPClient(deviceProvider: FakeNativeProvider(devices: [device]), scheduler: ManualPTPDeadlines())
        try await connect(client, to: device)
        let first = read(client, code: 1)
        try await waitUntil { device.commandCount == 1 }
        let cancelled = read(client, code: 2)
        cancelled.cancel()
        try await assertOutcome(cancelled, .cancelled)
        let third = read(client, code: 3)
        device.completeCommand(0, value: 10)
        try await waitUntil { device.commandCount == 2 }
        XCTAssertEqual(device.propertyCodes, [1, 3])
        device.completeCommand(1, value: 30)
        try await assertOutcome(first, .value(10))
        try await assertOutcome(third, .value(30))
        XCTAssertEqual(device.maximumInFlight, 1)
        XCTAssertTrue(client.isConnected)
        client.disconnect()
    }

    func testActiveCancellationFinishesQueueAndIgnoresLaterNativeCompletion() async throws {
        let device = FakeNativeDevice()
        let client = ImageCaptureCorePTPClient(deviceProvider: FakeNativeProvider(devices: [device]), scheduler: ManualPTPDeadlines())
        try await connect(client, to: device)
        let active = read(client, code: 1)
        try await waitUntil { device.commandCount == 1 }
        let queued = read(client, code: 2)
        active.cancel()
        try await assertOutcome(active, .cancelled)
        try await assertOutcome(queued, .notConnected)
        try await waitUntil { device.releaseCount == 1 }
        device.completeCommand(0, value: 10)
        XCTAssertFalse(client.isConnected)
        XCTAssertEqual(device.commandCount, 1)
        XCTAssertEqual(active.completionCount, 1)
        XCTAssertEqual(queued.completionCount, 1)
    }

    func testCancellationBeforeContinuationInstallationDoesNotAcquireOrSend() async throws {
        let device = FakeNativeDevice()
        let provider = FakeNativeProvider(devices: [device])
        let client = ImageCaptureCorePTPClient(deviceProvider: provider, scheduler: ManualPTPDeadlines())
        let cancelledConnect = CallOutcome()
        cancelledConnect.start {
            withUnsafeCurrentTask { $0?.cancel() }
            try await client.connect()
            return .connected
        }
        try await assertOutcome(cancelledConnect, .cancelled)
        XCTAssertEqual(provider.acquisitionCount, 0)
        try await connect(client, to: device)
        let cancelledRead = CallOutcome()
        cancelledRead.start {
            withUnsafeCurrentTask { $0?.cancel() }
            _ = try await client.readProperty(1)
            return .value(0)
        }
        try await assertOutcome(cancelledRead, .cancelled)
        XCTAssertEqual(device.commandCount, 0)
        XCTAssertTrue(client.isConnected)
        client.disconnect()
    }

    private func connect(_ client: ImageCaptureCorePTPClient, to device: FakeNativeDevice) async throws {
        let connection = connecting(client)
        try await waitUntil { device.openCount == 1 }
        device.completeOpen()
        try await assertOutcome(connection, .connected)
    }

    private func connecting(_ client: ImageCaptureCorePTPClient) -> CallOutcome {
        let record = CallOutcome()
        record.start { try await client.connect(); return .connected }
        return record
    }

    private func read(_ client: ImageCaptureCorePTPClient, code: UInt16) -> CallOutcome {
        let record = CallOutcome()
        record.start {
            guard case .uint32(let value) = try await client.readProperty(code) else { return .other("Unexpected property type") }
            return .value(value)
        }
        return record
    }

    private func assertOutcome(_ call: CallOutcome, _ expected: CallOutcome.Value, file: StaticString = #filePath, line: UInt = #line) async throws {
        let actual = try await outcome(call)
        XCTAssertEqual(actual, expected, file: file, line: line)
    }

    private func outcome(_ call: CallOutcome) async throws -> CallOutcome.Value {
        try await waitUntil { call.result != nil }
        return try XCTUnwrap(call.result)
    }

    private func waitUntil(_ predicate: @Sendable () -> Bool) async throws {
        for _ in 0..<200 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("The fake lifecycle operation did not finish within two seconds")
        throw FixtureError.failure
    }
}

private enum FixtureError: Error { case failure }

private final class CallOutcome: @unchecked Sendable {
    enum Value: Sendable, Equatable {
        case connected, value(UInt32), cancelled, notConnected, connectionFailed, commandFailed, ptpError(UInt16), other(String)
    }
    private let lock = NSLock()
    private var task: Task<Void, Never>?
    private var storedResult: Value?
    private var count = 0
    var result: Value? { lock.withLock { storedResult } }
    var completionCount: Int { lock.withLock { count } }

    func start(_ operation: @escaping @Sendable () async throws -> Value) {
        let task = Task {
            let value: Value
            do { value = try await operation() }
            catch is CancellationError { value = .cancelled }
            catch PTPError.notConnected { value = .notConnected }
            catch PTPError.connectionFailed { value = .connectionFailed }
            catch PTPError.commandFailed { value = .commandFailed }
            catch PTPError.unknown(let code) { value = .ptpError(code) }
            catch { value = .other(error.localizedDescription) }
            self.lock.withLock { self.count += 1; self.storedResult = value }
        }
        lock.withLock { self.task = task }
    }

    func cancel() { lock.withLock { task }?.cancel() }
}

private final class CompletionCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

private final class FakeNativeProvider: NativePTPDeviceProvider, @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [FakeNativeDevice]
    private var handlers: [UUID: @Sendable (UUID) -> Void] = [:]
    private var delayed: NativePTPContinuationGate<any NativePTPDevice>?
    private var count = 0
    var delaysAcquisition = false
    var acquisitionCount: Int { lock.withLock { count } }

    init(devices: [FakeNativeDevice]) { self.devices = devices }

    func acquireCamera(timeout: TimeInterval) async throws -> any NativePTPDevice {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                count += 1
                if delaysAcquisition {
                    let gate = NativePTPContinuationGate<any NativePTPDevice>()
                    gate.install(continuation)
                    delayed = gate
                } else if !devices.isEmpty { continuation.resume(returning: devices.removeFirst()) }
                else { continuation.resume(throwing: PTPError.connectionFailed("No fixture device")) }
            }
        }
    }

    func finishDelayedAcquisition(_ device: FakeNativeDevice) {
        lock.withLock { delayed }?.finishReturning(device)
    }

    func addRemovalHandler(for deviceID: UUID, _ handler: @escaping @Sendable (UUID) -> Void) -> UUID {
        let id = UUID()
        lock.withLock { handlers[id] = handler }
        return id
    }

    func removeRemovalHandler(_ id: UUID) { _ = lock.withLock { handlers.removeValue(forKey: id) } }
    func emitRemoval(_ id: UUID) {
        let current = lock.withLock { Array(handlers.values) }
        for handler in current { handler(id) }
    }
}

private final class FakeNativeDevice: NativePTPDevice, @unchecked Sendable {
    let deviceID: UUID
    let name: String
    let canSendPTPCommands = true
    private let lock = NSLock()
    private var openCallbacks: [@Sendable (Error?) -> Void] = []
    private var closeCallbacks: [@Sendable (Error?) -> Void] = []
    private var commands: [SubmittedCommand] = []
    private var eventHandler: (@Sendable (NativePTPDeviceEvent) -> Void)?
    private var recordedHandler: (@Sendable (NativePTPDeviceEvent) -> Void)?
    private var inFlight = 0
    private var peakInFlight = 0
    private var releases = 0
    var automaticallyClose = true

    init(deviceID: UUID = UUID(), name: String = "Fake X100VI") { self.deviceID = deviceID; self.name = name }
    var openCount: Int { lock.withLock { openCallbacks.count } }
    var closeCount: Int { lock.withLock { closeCallbacks.count } }
    var commandCount: Int { lock.withLock { commands.count } }
    var releaseCount: Int { lock.withLock { releases } }
    var maximumInFlight: Int { lock.withLock { peakInFlight } }
    var transactionIDs: [UInt32] { lock.withLock { commands.map { $0.packet.u32LE(at: 8) } } }
    var propertyCodes: [UInt32] { lock.withLock { commands.map { $0.packet.u32LE(at: 12) } } }

    func setSessionEventHandler(_ handler: (@Sendable (NativePTPDeviceEvent) -> Void)?) {
        lock.withLock { eventHandler = handler; if handler != nil { recordedHandler = handler } }
    }
    func emitRecordedEvent(_ event: NativePTPDeviceEvent) { lock.withLock { recordedHandler }?(event) }
    func openSession(completion: @escaping @Sendable (Error?) -> Void) { lock.withLock { openCallbacks.append(completion) } }
    func completeOpen(error: Error? = nil) { lock.withLock { openCallbacks.first }?(error) }
    func closeSession(completion: @escaping @Sendable (Error?) -> Void) {
        lock.withLock { closeCallbacks.append(completion) }
        if automaticallyClose { completion(nil) }
    }
    func completeClose(_ index: Int, error: Error? = nil) { lock.withLock { closeCallbacks[index] }(error) }
    func releaseLease() { lock.withLock { releases += 1 } }

    func sendCommand(_ command: Data, outData: Data?, completion: @escaping @Sendable (Data, Data, Error?) -> Void) {
        lock.withLock {
            commands.append(SubmittedCommand(packet: command, completion: completion))
            inFlight += 1
            peakInFlight = max(peakInFlight, inFlight)
        }
    }

    func completeCommand(_ index: Int, value: UInt16 = 0, responseCode: UInt16 = 0x2001, error: Error? = nil) {
        let request = lock.withLock {
            if !commands[index].finished { commands[index].finished = true; inFlight -= 1 }
            return commands[index]
        }
        var response = Data(count: 12)
        response.setU32LE(12, at: 0)
        response.setU16LE(3, at: 4)
        response.setU16LE(responseCode, at: 6)
        response.setU32LE(request.packet.u32LE(at: 8), at: 8)
        request.completion(Data([UInt8(value & 0xff), UInt8(value >> 8)]), response, error)
    }

    private struct SubmittedCommand {
        let packet: Data
        let completion: @Sendable (Data, Data, Error?) -> Void
        var finished = false
    }
}

private final class ManualPTPDeadlines: NativePTPDeadlineScheduler, @unchecked Sendable {
    private let lock = NSLock()
    private var scheduled: [Entry] = []

    func schedule(_ deadline: NativePTPDeadline, on queue: DispatchQueue, action: @escaping @Sendable () -> Void) -> any NativePTPCancellable {
        let token = Token()
        lock.withLock { scheduled.append(Entry(deadline: deadline, queue: queue, action: action, token: token)) }
        return token
    }

    func fireNext(_ deadline: NativePTPDeadline, includingCancelled: Bool = false) -> Bool {
        let entry: Entry? = lock.withLock {
            guard let index = scheduled.firstIndex(where: { $0.deadline == deadline && (includingCancelled || !$0.token.isCancelled) }) else { return nil }
            return scheduled.remove(at: index)
        }
        guard let entry else { return false }
        entry.queue.async(execute: entry.action)
        return true
    }

    private struct Entry {
        let deadline: NativePTPDeadline
        let queue: DispatchQueue
        let action: @Sendable () -> Void
        let token: Token
    }

    private final class Token: NativePTPCancellable, @unchecked Sendable {
        private let lock = NSLock()
        private var cancelled = false
        var isCancelled: Bool { lock.withLock { cancelled } }
        func cancel() { lock.withLock { cancelled = true } }
    }
}
