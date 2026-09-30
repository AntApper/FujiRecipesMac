@preconcurrency import Dispatch
import Foundation
import FujiRecipesCore
import OSLog

/// A lease on one attached device. The provider must not hand out another lease
/// for the same device until `releaseLease` is called, even if opening timed out.
protocol NativePTPDevice: AnyObject, Sendable {
    var deviceID: UUID { get }
    var name: String { get }
    var canSendPTPCommands: Bool { get }
    func setSessionEventHandler(_ handler: (@Sendable (NativePTPDeviceEvent) -> Void)?)
    func openSession(completion: @escaping @Sendable (Error?) -> Void)
    func closeSession(completion: @escaping @Sendable (Error?) -> Void)
    func sendCommand(_ command: Data, outData: Data?, completion: @escaping @Sendable (Data, Data, Error?) -> Void)
    func releaseLease()
}

enum NativePTPDeviceEvent: Sendable {
    case removed
    case sessionClosed
    case error(String)
}

protocol NativePTPDeviceProvider: Sendable {
    func acquireCamera(timeout: TimeInterval) async throws -> any NativePTPDevice
    func addRemovalHandler(for deviceID: UUID, _ handler: @escaping @Sendable (UUID) -> Void) -> UUID
    func removeRemovalHandler(_ id: UUID)
}

enum NativePTPDeadline: Sendable, Equatable {
    case open, command, close

    var seconds: TimeInterval {
        switch self {
        case .open: 15
        case .command: 20
        case .close: 5
        }
    }
}

protocol NativePTPCancellable: Sendable {
    func cancel()
}

protocol NativePTPDeadlineScheduler: Sendable {
    func schedule(_ deadline: NativePTPDeadline, on queue: DispatchQueue, action: @escaping @Sendable () -> Void) -> any NativePTPCancellable
}

struct DispatchPTPDeadlineScheduler: NativePTPDeadlineScheduler {
    func schedule(_ deadline: NativePTPDeadline, on queue: DispatchQueue, action: @escaping @Sendable () -> Void) -> any NativePTPCancellable {
        let item = DispatchWorkItem(block: action)
        queue.asyncAfter(deadline: .now() + deadline.seconds, execute: item)
        return ScheduledPTPDeadline(item: item)
    }
}

private struct ScheduledPTPDeadline: NativePTPCancellable, @unchecked Sendable {
    let item: DispatchWorkItem
    func cancel() { item.cancel() }
}

/// All lifecycle state, including whole command lifetimes, belongs to `queue`.
/// Native callbacks carry their connection and request identities back here;
/// an old callback can only clean up its own retired connection.
final class NativePTPSession: @unchecked Sendable {
    private static let logger = Logger(subsystem: "com.ant.fuji-recipes", category: "NativePTPSession")
    private let queue = DispatchQueue(label: "com.ant.fuji-recipes.image-capture-core.session")
    private let provider: any NativePTPDeviceProvider
    private let scheduler: any NativePTPDeadlineScheduler
    private var generation: UInt64 = 0
    private var connection: Connection?
    private var retired: [UInt64: Connection] = [:]
    private var connected = false
    private var transactionID: UInt32 = 0
    private var activeCommand: Command?
    private var pendingCommands: [Command] = []
    private var onDisconnect: (@Sendable () -> Void)?

    init(provider: any NativePTPDeviceProvider, scheduler: any NativePTPDeadlineScheduler = DispatchPTPDeadlineScheduler()) {
        self.provider = provider
        self.scheduler = scheduler
    }

    var isConnected: Bool { queue.sync { connected } }
    var cameraName: String { queue.sync { connection?.device?.name ?? "Not connected" } }

    func setDisconnectHandler(_ handler: (@Sendable () -> Void)?) {
        queue.sync { onDisconnect = handler }
    }

    func connect() async throws {
        let id = UUID()
        let gate = NativePTPContinuationGate<Void>()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                queue.async {
                    guard gate.isPending else { return }
                    guard self.connection == nil else {
                        gate.finishThrowing(PTPError.connectionFailed("Camera session is already active."))
                        return
                    }
                    self.generation &+= 1
                    let attempt = Connection(id: id, generation: self.generation, gate: gate)
                    self.connection = attempt
                    attempt.discovery = Task {
                        do {
                            let device = try await self.provider.acquireCamera(timeout: 15)
                            self.queue.async { self.didAcquire(device, for: attempt) }
                        } catch {
                            self.queue.async {
                                guard self.connection === attempt else { return }
                                self.retire(attempt, connectError: error)
                            }
                        }
                    }
                }
            }
        } onCancel: {
            gate.cancel()
            self.queue.async {
                guard let attempt = self.connection, attempt.id == id else { return }
                self.retire(attempt, connectError: CancellationError())
            }
        }
    }

    private func didAcquire(_ device: any NativePTPDevice, for attempt: Connection) {
        attempt.discovery = nil
        guard connection === attempt, attempt.gate.isPending else {
            device.releaseLease()
            if connection === attempt { retire(attempt, connectError: CancellationError()) }
            return
        }
        // Also enforce ownership here for injected providers. The native
        // provider reserves the device before returning the lease.
        guard !retired.values.contains(where: { $0.device?.deviceID == device.deviceID }) else {
            device.releaseLease()
            retire(attempt, connectError: PTPError.connectionFailed("The previous camera session is still closing. Wait or reconnect the USB cable before retrying."))
            return
        }
        guard device.canSendPTPCommands else {
            device.releaseLease()
            retire(attempt, connectError: PTPError.connectionFailed("The X100VI was found, but ImageCaptureCore does not expose raw PTP command support."))
            return
        }

        attempt.device = device
        attempt.removalHandler = provider.addRemovalHandler(for: device.deviceID) { [weak self, weak attempt] removedID in
            guard let self, let attempt else { return }
            self.queue.async {
                guard removedID == device.deviceID else { return }
                self.deviceRemoved(attempt)
            }
        }
        device.setSessionEventHandler { [weak self, weak attempt] event in
            guard let self, let attempt else { return }
            self.queue.async { self.deviceEvent(event, for: attempt) }
        }
        attempt.openPending = true
        attempt.openTimeout = scheduler.schedule(.open, on: queue) { [weak self] in
            guard let self, self.connection === attempt, attempt.openPending else { return }
            self.retire(attempt, connectError: PTPError.connectionFailed("ImageCaptureCore session open timed out."))
        }
        device.openSession { error in
            self.queue.async { self.didOpen(attempt, error: error) }
        }
    }

    private func didOpen(_ attempt: Connection, error: Error?) {
        guard attempt.openPending else { return }
        attempt.openPending = false
        attempt.openTimeout?.cancel()
        attempt.openTimeout = nil

        guard connection === attempt, attempt.gate.isPending else {
            // A close sent while open was pending may have closed nothing. A
            // late successful open therefore requires another close, but never
            // touches the current connection or its delegate/command state.
            guard retired[attempt.generation] === attempt else { return }
            if error == nil { attempt.needsClose = true }
            if attempt.needsClose, !attempt.closePending { requestClose(attempt) }
            else { releaseIfClosed(attempt) }
            return
        }
        if let error {
            retire(attempt, connectError: PTPError.connectionFailed("ImageCaptureCore session open failed: \(error.localizedDescription)"))
        } else {
            connected = true
            transactionID = 0
            attempt.gate.finishReturning(())
        }
    }

    func disconnect(completion: (@Sendable () -> Void)? = nil) {
        queue.async {
            if let current = self.connection {
                self.retire(current, connectError: PTPError.connectionFailed("Camera connection was cancelled."), completion: completion)
            } else if let closing = self.retired.values.first {
                if let completion {
                    if closing.closeDeadlineExpired { completion() }
                    else { closing.closeCompletions.append(completion) }
                }
                if closing.needsClose, !closing.closePending { self.requestClose(closing) }
            } else { completion?() }
        }
    }

    private func deviceEvent(_ event: NativePTPDeviceEvent, for attempt: Connection) {
        if case .removed = event {
            deviceRemoved(attempt)
        } else if connection === attempt {
            let reason: String
            switch event {
            case .error(let message): reason = message
            default: reason = "The camera session closed."
            }
            retire(attempt, connectError: PTPError.connectionFailed(reason), notify: true)
        }
    }

    private func deviceRemoved(_ attempt: Connection) {
        guard connection === attempt || retired[attempt.generation] === attempt else { return }
        attempt.removed = true
        if connection === attempt {
            retire(attempt, connectError: PTPError.connectionFailed("The X100VI was disconnected while opening its session."), notify: true)
        } else {
            // Removal ends ownership even if ImageCaptureCore never completes
            // its pending open/close. The next attachment has a new device ID.
            attempt.openPending = false
            attempt.closePending = false
            attempt.needsClose = false
            releaseIfClosed(attempt)
        }
    }

    private func retire(
        _ attempt: Connection,
        connectError: Error,
        commandError: Error = PTPError.notConnected,
        notify: Bool = false,
        completion: (@Sendable () -> Void)? = nil
    ) {
        guard connection === attempt else { completion?(); return }
        let shouldNotify = connected && notify
        connection = nil
        connected = false
        transactionID = 0
        attempt.discovery?.cancel()
        attempt.discovery = nil
        attempt.openTimeout?.cancel()
        attempt.openTimeout = nil
        attempt.gate.finishThrowing(connectError)
        failCommands(activeError: commandError)

        if attempt.device != nil {
            retired[attempt.generation] = attempt
            if let completion { attempt.closeCompletions.append(completion) }
            if attempt.removed {
                attempt.openPending = false
                attempt.needsClose = false
                releaseIfClosed(attempt)
            } else {
                attempt.needsClose = true
                requestClose(attempt)
            }
        } else { completion?() }
        if shouldNotify, let handler = onDisconnect {
            // A handler may read the client's synchronous state properties.
            DispatchQueue.global().async(execute: handler)
        }
    }

    private func requestClose(_ attempt: Connection) {
        guard let device = attempt.device, !attempt.closePending, !attempt.released else { return }
        attempt.needsClose = false
        attempt.closePending = true
        attempt.closeDeadlineExpired = false
        attempt.closeTimeout = scheduler.schedule(.close, on: queue) { [weak self] in
            guard let self, self.retired[attempt.generation] === attempt, attempt.closePending else { return }
            attempt.closeDeadlineExpired = true
            attempt.closeTimeout = nil
            Self.logger.error("Session close timed out; retaining device ownership for generation \(attempt.generation).")
            self.finishCloseCompletions(attempt)
        }
        device.closeSession { error in
            self.queue.async {
                guard self.retired[attempt.generation] === attempt, attempt.closePending else { return }
                attempt.closeTimeout?.cancel()
                attempt.closeTimeout = nil
                attempt.closePending = false
                if let error {
                    attempt.needsClose = true
                    attempt.closeDeadlineExpired = true
                    Self.logger.error("Session close failed for generation \(attempt.generation): \(error.localizedDescription, privacy: .public)")
                    self.finishCloseCompletions(attempt)
                } else if attempt.needsClose {
                    self.requestClose(attempt)
                } else {
                    self.releaseIfClosed(attempt)
                    // A pending open still owns this lease, but synchronous
                    // disconnect need not wait indefinitely for that callback.
                    self.finishCloseCompletions(attempt)
                }
            }
        }
    }

    private func releaseIfClosed(_ attempt: Connection) {
        guard !attempt.openPending, !attempt.closePending, !attempt.needsClose, !attempt.released else { return }
        attempt.released = true
        attempt.openTimeout?.cancel()
        attempt.closeTimeout?.cancel()
        if let id = attempt.removalHandler { provider.removeRemovalHandler(id) }
        attempt.device?.setSessionEventHandler(nil)
        attempt.device?.releaseLease()
        retired.removeValue(forKey: attempt.generation)
        finishCloseCompletions(attempt)
    }

    private func finishCloseCompletions(_ attempt: Connection) {
        let completions = attempt.closeCompletions
        attempt.closeCompletions.removeAll()
        for completion in completions { completion() }
    }

    struct PTPResult: Sendable {
        let response: Data
        let data: Data?
    }

    func send(command: Data, outData: Data?) async throws -> PTPResult {
        let id = UUID()
        let gate = NativePTPContinuationGate<PTPResult>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                queue.async {
                    guard gate.isPending else { return }
                    guard self.connected, let current = self.connection else {
                        gate.finishThrowing(PTPError.notConnected)
                        return
                    }
                    self.pendingCommands.append(Command(id: id, generation: current.generation, packet: command, outData: outData, gate: gate))
                    self.startNextCommand()
                }
            }
        } onCancel: {
            gate.cancel()
            self.queue.async {
                if self.activeCommand?.id == id, let current = self.connection {
                    // There is no native per-command cancellation API. Closing
                    // the session prevents a cancelled write from overlapping
                    // the next request; all queued callers are completed too.
                    self.retire(current, connectError: CancellationError(), commandError: CancellationError(), notify: true)
                } else {
                    self.pendingCommands.removeAll { $0.id == id }
                }
            }
        }
    }

    private func startNextCommand() {
        guard activeCommand == nil, connected, let current = connection, let device = current.device else { return }
        while !pendingCommands.isEmpty {
            let request = pendingCommands.removeFirst()
            guard request.gate.isPending else { continue }
            guard request.generation == current.generation else {
                request.gate.finishThrowing(PTPError.notConnected)
                continue
            }
            activeCommand = request
            transactionID &+= 1
            var packet = request.packet
            packet.setU32LE(transactionID, at: 8)
            request.timeout = scheduler.schedule(.command, on: queue) { [weak self] in
                guard let self, self.activeCommand === request, self.connection === current else { return }
                self.retire(current, connectError: PTPError.notConnected, commandError: PTPError.commandFailed(request.operation, "ImageCaptureCore command timed out after 20 seconds."), notify: true)
            }
            device.sendCommand(packet, outData: request.outData) { data, response, error in
                self.queue.async { self.didComplete(request, data: data, response: response, error: error) }
            }
            return
        }
    }

    private func didComplete(_ request: Command, data: Data, response: Data, error: Error?) {
        guard activeCommand === request, let current = connection, current.generation == request.generation else { return }
        if let error {
            retire(current, connectError: PTPError.notConnected, commandError: PTPError.commandFailed(request.operation, error.localizedDescription), notify: true)
            return
        }
        guard response.count >= 12 else {
            let hex = response.map { String(format: "%02x", $0) }.joined(separator: " ")
            retire(current, connectError: PTPError.notConnected, commandError: PTPError.invalidResponse("ImageCaptureCore returned an incomplete PTP response: count=\(response.count), bytes=[\(hex)]."), notify: true)
            return
        }
        request.timeout?.cancel()
        activeCommand = nil
        let responseCode = response.u16LE(at: 6)
        if responseCode == 0x2001 {
            request.gate.finishReturning(PTPResult(response: response, data: data.isEmpty ? nil : data))
        } else {
            request.gate.finishThrowing(PTPError.unknown(responseCode))
        }
        startNextCommand()
    }

    private func failCommands(activeError: Error) {
        let active = activeCommand
        activeCommand = nil
        active?.timeout?.cancel()
        active?.gate.finishThrowing(activeError)
        let waiting = pendingCommands
        pendingCommands.removeAll()
        for request in waiting { request.gate.finishThrowing(PTPError.notConnected) }
    }

    private final class Connection: @unchecked Sendable {
        let id: UUID
        let generation: UInt64
        let gate: NativePTPContinuationGate<Void>
        var device: (any NativePTPDevice)?
        var discovery: Task<Void, Never>?
        var removalHandler: UUID?
        var openTimeout: (any NativePTPCancellable)?
        var closeTimeout: (any NativePTPCancellable)?
        var openPending = false
        var closePending = false
        var needsClose = false
        var closeDeadlineExpired = false
        var released = false
        var removed = false
        var closeCompletions: [@Sendable () -> Void] = []

        init(id: UUID, generation: UInt64, gate: NativePTPContinuationGate<Void>) {
            self.id = id
            self.generation = generation
            self.gate = gate
        }
    }

    private final class Command: @unchecked Sendable {
        let id: UUID
        let generation: UInt64
        let packet: Data
        let outData: Data?
        let gate: NativePTPContinuationGate<PTPResult>
        var timeout: (any NativePTPCancellable)?
        var operation: UInt16 { packet.u16LE(at: 6) }

        init(id: UUID, generation: UInt64, packet: Data, outData: Data?, gate: NativePTPContinuationGate<PTPResult>) {
            self.id = id
            self.generation = generation
            self.packet = packet
            self.outData = outData
            self.gate = gate
        }
    }
}

/// Cancellation may arrive before a continuation is installed. Terminal
/// state is retained so installation and every later callback are single-use.
final class NativePTPContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var finished = false
    private var cancelled = false

    var isPending: Bool { lock.withLock { !finished && continuation != nil } }

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        let wasCancelled = lock.withLock {
            if cancelled { return true }
            self.continuation = continuation
            return false
        }
        if wasCancelled { continuation.resume(throwing: CancellationError()) }
    }

    func cancel() {
        let continuation = lock.withLock {
            cancelled = true
            finished = true
            let previous = self.continuation
            self.continuation = nil
            return previous
        }
        continuation?.resume(throwing: CancellationError())
    }

    @discardableResult
    func finishReturning(_ value: Value) -> Bool {
        let continuation = takeContinuation()
        continuation?.resume(returning: value)
        return continuation != nil
    }

    @discardableResult
    func finishThrowing(_ error: Error) -> Bool {
        let continuation = takeContinuation()
        continuation?.resume(throwing: error)
        return continuation != nil
    }

    private func takeContinuation() -> CheckedContinuation<Value, Error>? {
        lock.withLock {
            guard !finished, let continuation else { return nil }
            finished = true
            self.continuation = nil
            return continuation
        }
    }
}
