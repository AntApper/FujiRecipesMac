@preconcurrency import Dispatch
import Foundation
import FujiRecipesCore
@preconcurrency import ImageCaptureCore

/// Discovery is shared, but each attached camera has one leased session owner.
/// A timed-out opening keeps that lease until its late completion is cleaned up
/// or the device is physically removed.
final class ImageCaptureCoreDeviceProvider: NSObject, ICDeviceBrowserDelegate, NativePTPDeviceProvider, @unchecked Sendable {
    static let shared = ImageCaptureCoreDeviceProvider()

    private let queue = DispatchQueue(label: "com.ant.fuji-recipes.image-capture-core.discovery")
    private let browser = ICDeviceBrowser()
    private var matchingCamera: CameraRecord?
    private var cameras: [ObjectIdentifier: CameraRecord] = [:]
    private var leases: [UUID: UUID] = [:]
    private var waiters: [UUID: CameraWaiter] = [:]
    private var removalHandlers: [UUID: RemovalObserver] = [:]

    override private init() {
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = .camera
        browser.start()
    }

    func addRemovalHandler(for deviceID: UUID, _ handler: @escaping @Sendable (UUID) -> Void) -> UUID {
        let id = UUID()
        queue.sync {
            removalHandlers[id] = RemovalObserver(deviceID: deviceID, handler: handler)
            // Discovery may have returned this lease just before a removal.
            // Register and check presence on the same queue as browser events.
            if !cameras.values.contains(where: { $0.id == deviceID }) {
                handler(deviceID)
            }
        }
        return id
    }

    func removeRemovalHandler(_ id: UUID) {
        queue.async { self.removalHandlers.removeValue(forKey: id) }
    }

    func acquireCamera(timeout: TimeInterval) async throws -> any NativePTPDevice {
        let id = UUID()
        let gate = NativePTPContinuationGate<any NativePTPDevice>()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                queue.async {
                    guard gate.isPending else { return }
                    if self.matchingCamera == nil {
                        for device in self.browser.devices ?? [] {
                            if let camera = device as? ICCameraDevice, Self.isTargetCamera(camera) {
                                self.matchingCamera = self.record(for: camera)
                                break
                            }
                        }
                    }
                    if let camera = self.matchingCamera {
                        self.provide(camera, to: gate)
                        return
                    }
                    let timer = DispatchWorkItem {
                        self.waiters.removeValue(forKey: id)
                        gate.finishThrowing(PTPError.connectionFailed("ImageCaptureCore did not find an X100VI camera within \(Int(timeout)) seconds."))
                    }
                    self.waiters[id] = CameraWaiter(gate: gate, timeout: timer)
                    self.queue.asyncAfter(deadline: .now() + timeout, execute: timer)
                }
            }
        } onCancel: {
            gate.cancel()
            self.queue.async { self.waiters.removeValue(forKey: id)?.timeout.cancel() }
        }
    }

    private func provide(_ camera: CameraRecord, to gate: NativePTPContinuationGate<any NativePTPDevice>) {
        guard gate.isPending else { return }
        guard leases[camera.id] == nil else {
            gate.finishThrowing(PTPError.connectionFailed("The previous camera session is still active or closing. Wait or reconnect the USB cable before retrying."))
            return
        }
        let lease = UUID()
        leases[camera.id] = lease
        let session = ImageCaptureCoreSessionDevice(camera: camera.camera, deviceID: camera.id) { [weak self] in
            self?.queue.async { [weak self] in
                guard let self, self.leases[camera.id] == lease else { return }
                self.leases.removeValue(forKey: camera.id)
            }
        }
        if !gate.finishReturning(session) { session.releaseLease() }
    }

    private func record(for camera: ICCameraDevice) -> CameraRecord {
        let key = ObjectIdentifier(camera)
        if let existing = cameras[key] { return existing }
        let record = CameraRecord(camera: camera)
        cameras[key] = record
        return record
    }

    private static func isTargetCamera(_ camera: ICCameraDevice) -> Bool {
        camera.usbVendorID == 0x04CB && camera.usbProductID == 0x0305 &&
            camera.transportType == ICDeviceTransport.transportTypeUSB.rawValue
    }

    private func discovered(_ camera: ICCameraDevice) {
        let camera = record(for: camera)
        matchingCamera = camera
        let waiting = waiters
        waiters.removeAll()
        for waiter in waiting.values {
            waiter.timeout.cancel()
            provide(camera, to: waiter.gate)
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        queue.async {
            guard let camera = device as? ICCameraDevice, Self.isTargetCamera(camera) else { return }
            self.discovered(camera)
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        queue.async {
            // Only this attachment's identity is removed. Another camera's
            // removal must not clear the cached X100VI or its session owner.
            guard let camera = self.cameras.removeValue(forKey: ObjectIdentifier(device)) else { return }
            if self.matchingCamera?.id == camera.id { self.matchingCamera = nil }
            self.leases.removeValue(forKey: camera.id)
            for observer in self.removalHandlers.values where observer.deviceID == camera.id {
                observer.handler(camera.id)
            }
        }
    }

    func deviceBrowserDidEnumerateLocalDevices(_ browser: ICDeviceBrowser) {
        queue.async {
            guard self.matchingCamera == nil else { return }
            for device in browser.devices ?? [] {
                if let camera = device as? ICCameraDevice, Self.isTargetCamera(camera) {
                    self.discovered(camera)
                    break
                }
            }
        }
    }

    private struct CameraRecord: @unchecked Sendable {
        let id = UUID()
        let camera: ICCameraDevice
    }

    private struct CameraWaiter {
        let gate: NativePTPContinuationGate<any NativePTPDevice>
        let timeout: DispatchWorkItem
    }

    private struct RemovalObserver {
        let deviceID: UUID
        let handler: @Sendable (UUID) -> Void
    }
}

/// The native API and delegate stay behind this boundary. Tests provide a
/// device that records operations and controls their completions instead.
private final class ImageCaptureCoreSessionDevice: NSObject, ICDeviceDelegate, NativePTPDevice, @unchecked Sendable {
    let deviceID: UUID
    let name: String
    let canSendPTPCommands: Bool
    private let camera: ICCameraDevice
    private let onRelease: @Sendable () -> Void
    private let lock = NSLock()
    private var eventHandler: (@Sendable (NativePTPDeviceEvent) -> Void)?
    private var expectedClose = false
    private var released = false

    init(camera: ICCameraDevice, deviceID: UUID, onRelease: @escaping @Sendable () -> Void) {
        self.camera = camera
        self.deviceID = deviceID
        self.name = camera.name ?? "Fuji X100VI"
        self.canSendPTPCommands = camera.capabilities.contains(ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue)
        self.onRelease = onRelease
        super.init()
    }

    func setSessionEventHandler(_ handler: (@Sendable (NativePTPDeviceEvent) -> Void)?) {
        lock.withLock { eventHandler = handler }
    }

    func openSession(completion: @escaping @Sendable (Error?) -> Void) {
        lock.withLock { expectedClose = false }
        camera.delegate = self
        camera.requestOpenSession(completion: completion)
    }

    func closeSession(completion: @escaping @Sendable (Error?) -> Void) {
        lock.withLock { expectedClose = true }
        camera.requestCloseSession(completion: completion)
    }

    func sendCommand(_ command: Data, outData: Data?, completion: @escaping @Sendable (Data, Data, Error?) -> Void) {
        // ImageCaptureCore's first argument is the property payload; the
        // second is the 12-byte-or-longer PTP response container.
        camera.requestSendPTPCommand(command, outData: outData, completion: completion)
    }

    func releaseLease() {
        let shouldRelease = lock.withLock {
            guard !released else { return false }
            released = true
            eventHandler = nil
            return true
        }
        guard shouldRelease else { return }
        if camera.delegate === self { camera.delegate = nil }
        onRelease()
    }

    func didRemove(_ device: ICDevice) { emit(.removed) }
    func deviceDidBecomeReady(_ device: ICDevice) {}
    func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {}

    func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        guard !lock.withLock({ expectedClose }) else { return }
        emit(.sessionClosed)
    }

    func device(_ device: ICDevice, didEncounterError error: (any Error)?) {
        emit(.error(error?.localizedDescription ?? "ImageCaptureCore reported a camera error."))
    }

    private func emit(_ event: NativePTPDeviceEvent) {
        let handler = lock.withLock { eventHandler }
        handler?(event)
    }
}
