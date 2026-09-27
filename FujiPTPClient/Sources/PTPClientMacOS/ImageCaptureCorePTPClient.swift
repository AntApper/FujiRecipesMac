@preconcurrency import Dispatch
import Foundation
import FujiRecipesCore
import PTPClient
@preconcurrency import ImageCaptureCore

/// macOS camera transport backed by Apple's ImageCaptureCore broker.
///
/// This is deliberately separate from the raw-libusb helper while the
/// X100VI vendor-command codec is being validated. ImageCaptureCore owns the
/// camera session, so this transport does not compete with `ptpcamerad`.
public final class ImageCaptureCorePTPClient: PTPClientProtocol, @unchecked Sendable {
    private let state = State()

    public init() {}

    public var isConnected: Bool {
        state.queue.sync { state.connected }
    }

    public var cameraInfo: PTPCameraInfo {
        state.queue.sync {
            PTPCameraInfo(
                model: state.camera?.name ?? "Not connected",
                vendorExtensionId: PTPProperty.fujiVendorExtensionId
            )
        }
    }

    public func connect() async throws {
        try await state.connect()
    }

    public func disconnect() {
        let semaphore = DispatchSemaphore(value: 0)
        state.disconnect {
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 5)
    }

    public func setDisconnectHandler(_ handler: (@Sendable () -> Void)?) {
        state.onDisconnect = handler
    }

    public func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse {
        let result = try await state.send(
            command: PTPPacket.command(operation: 0x1015, parameters: [UInt32(code)]),
            outData: nil
        )
        guard let payload = result.data else {
            throw PTPError.readFailed(code, "Camera returned no property data.")
        }
        if code == 0xD18D {
            return .data(payload)
        }
        switch payload.count {
        case 1:
            return .uint32(UInt32(payload[0]))
        case 2:
            return .uint32(UInt32(payload[0]) | (UInt32(payload[1]) << 8))
        case 4:
            return .uint32(payload.u32LE(at: 0))
        default:
            return .data(payload)
        }
    }

    public func writeProperty(_ code: UInt16, value: Int32) async throws {
        let raw = UInt16(truncatingIfNeeded: value)
        _ = try await state.send(
            command: PTPPacket.command(operation: 0x1016, parameters: [UInt32(code)]),
            outData: Data([UInt8(raw & 0xff), UInt8(raw >> 8)])
        )
    }

    public func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        guard (1...7).contains(index) else {
            throw PTPError.invalidResponse("Preset slot must be 1–7")
        }
        try await writeProperty(0xD18C, value: Int32(index))
        try? await Task.sleep(nanoseconds: 120_000_000)

        let values = try await Self.readPresetValues(using: self)
        return PTPClientPresetData(
            slot: index,
            name: Self.stringValue(values[0xD18D]),
            imageQuality: Self.uintValue(values[0xD18F]),
            imageSize: Self.uintValue(values[0xD18E]),
            dynamicRange: Self.uintValue(values[0xD190]),
            filmSimulation: Self.uintValue(values[0xD192]),
            monoWarmCool: Self.intValue(values[0xD193]),
            monoMagentaGreen: Self.intValue(values[0xD194]),
            grainEffect: Self.uintValue(values[0xD195]),
            colorChrome: Self.uintValue(values[0xD196]),
            colorChromeFxBlue: Self.uintValue(values[0xD197]),
            smoothSkin: Self.uintValue(values[0xD198]),
            whiteBalance: Self.uintValue(values[0xD199]),
            wbShiftRed: Self.intValue(values[0xD19A]),
            wbShiftBlue: Self.intValue(values[0xD19B]),
            colorTemp: Self.uintValue(values[0xD19C]),
            highlight: Self.intValue(values[0xD19D]),
            shadow: Self.intValue(values[0xD19E]),
            color: Self.intValue(values[0xD19F]),
            sharpness: Self.intValue(values[0xD1A0]),
            highIsoNr: Self.uintValue(values[0xD1A1]),
            clarity: Self.intValue(values[0xD1A2]),
            longExpNr: Self.uintValue(values[0xD1A3]),
            colorSpace: Self.uintValue(values[0xD1A4])
        )
    }

    public func writePresetSlot(
        _ index: Int,
        data: PTPClientPresetData
    ) async throws -> PTPPresetSlotWriteResult {
        guard (1...7).contains(index) else {
            throw PTPError.invalidResponse("Preset slot must be 1–7")
        }

        // 1. Select target slot on camera
        try await writeProperty(0xD18C, value: Int32(index))
        let initial = try await readPresetSlot(index)
        let wasEmpty = initial.isEmptySlot

        // 2. Write slot name if provided
        if !data.name.isEmpty {
            try await writeRawProperty(0xD18D, payload: CameraPresetName.ptpPayload(for: data.name, slot: index))
        }

        // 3. Resolve effective modes for conditional field gating
        let effectiveFilmSim = data.filmSimulation ?? initial.filmSimulation
        let effectiveWB = data.whiteBalance ?? initial.whiteBalance
        let isMono = Self.isMonochromeFilmSim(effectiveFilmSim)
        let isColorTempWB = effectiveWB == 0x8007

        var warnings: [String] = []

        // 4. Write film simulation first so camera mode updates before tone/color settings
        if let sim = data.filmSimulation {
            try await writeProperty(0xD192, value: Int32(sim))
        }

        // 5. Write white balance mode next
        if let wb = data.whiteBalance {
            try await writeProperty(0xD199, value: Int32(wb))
        }

        // 6. Write color temperature only when in Color Temperature WB mode (0x8007)
        if isColorTempWB, let colorTemp = data.colorTemp, colorTemp != 0 {
            await writeConditionalProperty(0xD19C, value: Int32(colorTemp), warnings: &warnings)
        }

        // 7. Write white balance shifts
        if let shiftR = data.wbShiftRed {
            try await writeProperty(0xD19A, value: shiftR)
        }
        if let shiftB = data.wbShiftBlue {
            try await writeProperty(0xD19B, value: shiftB)
        }

        // 8. Write tone and saturation settings respecting monochrome eligibility
        if isMono {
            if let warmCool = data.monoWarmCool, warmCool != 0 {
                await writeConditionalProperty(0xD193, value: warmCool, warnings: &warnings)
            }
            if let magentaGreen = data.monoMagentaGreen, magentaGreen != 0 {
                await writeConditionalProperty(0xD194, value: magentaGreen, warnings: &warnings)
            }
        } else {
            if let color = data.color {
                await writeConditionalProperty(0xD19F, value: color, warnings: &warnings)
            }
        }

        // 9. Write remaining preset properties
        let otherProperties: [(UInt16, Int32?, Bool)] = [
            (0xD18E, data.imageSize.map(Int32.init), false),
            (0xD18F, data.imageQuality.map(Int32.init), false),
            (0xD190, data.dynamicRange.map(Int32.init), false),
            (0xD195, data.grainEffect.map(Int32.init), false),
            (0xD196, data.colorChrome.map(Int32.init), false),
            (0xD197, data.colorChromeFxBlue.map(Int32.init), true),
            (0xD198, data.smoothSkin.map(Int32.init), true),
            (0xD19D, data.highlight, false),
            (0xD19E, data.shadow, false),
            (0xD1A0, data.sharpness, false),
            (0xD1A1, data.highIsoNr.map(Int32.init), false),
            (0xD1A2, data.clarity, false),
            (0xD1A3, data.longExpNr.map(Int32.init), false),
            (0xD1A4, data.colorSpace.map(Int32.init), false)
        ]

        for (code, value, conditional) in otherProperties {
            guard let value else { continue }
            if conditional {
                await writeConditionalProperty(code, value: value, warnings: &warnings)
            } else {
                do {
                    try await writeProperty(code, value: value)
                } catch PTPError.unknown(0x201C) {
                    warnings.append(String(format: "0x%04X: 0x201C", code))
                }
            }
        }

        let observed = try await readPresetSlot(index)
        return PTPPresetSlotWriteResult(
            slot: index,
            createdFromEmpty: wasEmpty,
            warnings: warnings,
            observedSnapshot: observed
        )
    }

    private func writeConditionalProperty(_ code: UInt16, value: Int32, warnings: inout [String]) async {
        do {
            try await writeProperty(code, value: value)
        } catch PTPError.unknown(0x201C) {
            warnings.append(String(format: "0x%04X: 0x201C", code))
        } catch {
            warnings.append(String(format: "0x%04X: %@", code, error.localizedDescription))
        }
    }

    public static func isMonochromeFilmSim(_ raw: UInt32?) -> Bool {
        guard let raw else { return false }
        return (raw >= 6 && raw <= 10) || (raw >= 12 && raw <= 15)
    }

    public func readNativeProfile() async throws -> Data {
        let result = try await readProperty(0xD185)
        guard case .data(let data) = result, !data.isEmpty else {
            throw PTPError.readFailed(0xD185, "Camera returned no native profile data.")
        }
        return data
    }

    public func writePTPSettings(from recipe: Recipe) async throws {
        if let value = recipe.filmSimulation {
            try await writeProperty(0xD192, value: Int32(value.rawValue))
        }
        if let value = recipe.dynamicRange {
            try await writeProperty(0xD190, value: Int32(value.rawValue))
        }
        if let value = recipe.grainEffect {
            try await writeProperty(0xD195, value: Int32(value.rawValue))
        }
        if let value = recipe.colorChrome {
            try await writeProperty(0xD196, value: Int32(value.rawValue))
        }
        if let value = recipe.colorChromeFxBlue {
            try await writeProperty(0xD197, value: Int32(value.rawValue))
        }
        if let value = recipe.smoothSkin {
            try await writeProperty(0xD198, value: Int32(value.rawValue))
        }
        if let value = recipe.whiteBalanceMode {
            try await writeProperty(0xD199, value: Int32(value.rawValue))
        }
        if let value = recipe.colorTempK {
            try await writeProperty(0xD19C, value: Int32(value))
        }
        if let value = recipe.wbShiftRed {
            try await writeProperty(0xD19A, value: value)
        }
        if let value = recipe.wbShiftBlue {
            try await writeProperty(0xD19B, value: value)
        }
        if let value = recipe.highlight {
            try await writeProperty(0xD19D, value: value)
        }
        if let value = recipe.shadow {
            try await writeProperty(0xD19E, value: value)
        }
        if let value = recipe.color {
            try await writeProperty(0xD19F, value: value)
        }
        if let value = recipe.sharpness {
            try await writeProperty(0xD1A0, value: value)
        }
        if let value = recipe.clarity {
            try await writeProperty(0xD1A2, value: value)
        }
        if let value = recipe.highIsoNr {
            try await writeProperty(0xD1A1, value: value)
        }
    }

    public func convertRAF(
        _ raf: RAFFile,
        profileModifier: ((inout Data) -> Void)?
    ) async -> RAFConversionOutcome {
        .failed(message: "RAF conversion is not implemented by ImageCaptureCore transport.")
    }

    public func capturePreview() async throws -> JPEGFile? {
        throw PTPError.platformError("Preview capture is not implemented by ImageCaptureCore transport.")
    }

    private static let presetPropertyCodes: [UInt16] = [
        0xD18D, 0xD18E, 0xD18F, 0xD190, 0xD192, 0xD193, 0xD194,
        0xD195, 0xD196, 0xD197, 0xD198, 0xD199, 0xD19A, 0xD19B,
        0xD19C, 0xD19D, 0xD19E, 0xD19F, 0xD1A0, 0xD1A1, 0xD1A2,
        0xD1A3, 0xD1A4
    ]

    private static func readPresetValues(
        using client: ImageCaptureCorePTPClient
    ) async throws -> [UInt16: PTPPropertyResponse] {
        var values: [UInt16: PTPPropertyResponse] = [:]
        for code in presetPropertyCodes {
            values[code] = try await client.readProperty(code)
        }
        return values
    }

    private static func uintValue(_ response: PTPPropertyResponse?) -> UInt32? {
        switch response {
        case .uint32(let value): return value
        case .int32(let value): return UInt32(bitPattern: value)
        default: return nil
        }
    }

    private static func intValue(_ response: PTPPropertyResponse?) -> Int32? {
        switch response {
        case .uint32(let value):
            // Fuji camera tone/shift properties are signed 16-bit values.
            // If the raw response was a 16-bit payload zero-extended to uint32,
            // sign-extend it so e.g. 0xFFF6 (65526) becomes -10 rather than +65526.
            if value > 0x7FFF && value <= 0xFFFF {
                return Int32(Int16(bitPattern: UInt16(value)))
            }
            return Int32(bitPattern: value)
        case .int32(let value):
            return value
        default:
            return nil
        }
    }

    private static func stringValue(_ response: PTPPropertyResponse?) -> String {
        guard case .data(let data) = response, !data.isEmpty else { return "" }
        let numChars = Int(data[0])
        guard numChars > 1 else { return "" }
        let characterCount = min(numChars - 1, (data.count - 1) / 2)
        var scalars = String.UnicodeScalarView()
        for index in 0..<characterCount {
            let offset = 1 + index * 2
            guard offset + 1 < data.count else { break }
            let scalar = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            if scalar != 0, let unicode = UnicodeScalar(scalar) {
                scalars.append(unicode)
            }
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func writeRawProperty(_ code: UInt16, payload: Data) async throws {
        _ = try await state.send(
            command: PTPPacket.command(operation: 0x1016, parameters: [UInt32(code)]),
            outData: payload
        )
    }
}

private struct SendableCamera: @unchecked Sendable {
    let camera: ICCameraDevice
}

private final class DeviceCoordinator: NSObject, ICDeviceBrowserDelegate, @unchecked Sendable {
    static let shared = DeviceCoordinator()

    private let queue = DispatchQueue(label: "com.ant.fuji-recipes.image-capture-core.coordinator")
    private let browser = ICDeviceBrowser()
    private var matchingCamera: ICCameraDevice?
    private var waiters: [(ICCameraDevice) -> Void] = []
    private var removalHandlers: [UUID: @Sendable (ICDevice) -> Void] = [:]

    override private init() {
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = .camera
        browser.start()
    }

    func addRemovalHandler(_ handler: @escaping @Sendable (ICDevice) -> Void) -> UUID {
        let id = UUID()
        queue.async {
            self.removalHandlers[id] = handler
        }
        return id
    }

    func removeRemovalHandler(_ id: UUID) {
        queue.async {
            self.removalHandlers.removeValue(forKey: id)
        }
    }

    func acquireCamera(timeout: TimeInterval = 15.0) async throws -> ICCameraDevice {
        let gate = ContinuationGate<SendableCamera>()
        let sendable = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                gate.install(continuation)
                lookUpCamera(timeout: timeout, gate: gate)
            }
        } onCancel: {
            gate.cancel()
        }
        return sendable.camera
    }

    private func lookUpCamera(timeout: TimeInterval, gate: ContinuationGate<SendableCamera>) {
        queue.async {
            if let camera = self.matchingCamera {
                _ = gate.finishReturning(SendableCamera(camera: camera))
                return
            }

            for device in self.browser.devices ?? [] {
                if let camera = device as? ICCameraDevice, self.isTargetCamera(camera) {
                    self.matchingCamera = camera
                    _ = gate.finishReturning(SendableCamera(camera: camera))
                    return
                }
            }

            let timer = DispatchWorkItem {
                _ = gate.finishThrowing(PTPError.connectionFailed(
                    "ImageCaptureCore did not find an X100VI camera within \(Int(timeout)) seconds."
                ))
            }
            self.queue.asyncAfter(deadline: .now() + timeout, execute: timer)

            self.waiters.append { camera in
                timer.cancel()
                _ = gate.finishReturning(SendableCamera(camera: camera))
            }
        }
    }

    private func isTargetCamera(_ camera: ICCameraDevice) -> Bool {
        guard camera.usbVendorID == 0x04CB, camera.usbProductID == 0x0305 else { return false }
        guard camera.transportType == ICDeviceTransport.transportTypeUSB.rawValue else { return false }
        return true
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        queue.async {
            guard let camera = device as? ICCameraDevice, self.isTargetCamera(camera) else { return }
            self.matchingCamera = camera
            let currentWaiters = self.waiters
            self.waiters.removeAll()
            for waiter in currentWaiters {
                waiter(camera)
            }
        }
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        queue.async {
            if self.matchingCamera === device || (device as? ICCameraDevice).map(self.isTargetCamera) == true {
                self.matchingCamera = nil
            }
            for handler in self.removalHandlers.values {
                handler(device)
            }
        }
    }

    func deviceBrowserDidEnumerateLocalDevices(_ browser: ICDeviceBrowser) {
        queue.async {
            guard self.matchingCamera == nil else { return }
            for device in browser.devices ?? [] {
                if let camera = device as? ICCameraDevice, self.isTargetCamera(camera) {
                    self.matchingCamera = camera
                    let currentWaiters = self.waiters
                    self.waiters.removeAll()
                    for waiter in currentWaiters {
                        waiter(camera)
                    }
                    break
                }
            }
        }
    }
}

private final class State: NSObject, ICDeviceDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.ant.fuji-recipes.image-capture-core")
    var camera: ICCameraDevice?
    var connected = false
    var closing = false
    var transactionID: UInt32 = 0
    var connectWaiter: CheckedContinuation<Void, Error>?
    var closeWaiter: CheckedContinuation<Void, Never>?
    var connectTimeout: DispatchWorkItem?
    var activeCommandFailure: (() -> Void)?
    var activeCommandTimeout: DispatchWorkItem?
    var removalHandlerID: UUID?
    var onDisconnect: (@Sendable () -> Void)?

    func didRemove(_ device: ICDevice) {
        queue.async {
            guard self.connected else { return }
            self.invalidateSessionOnQueue()
            self.onDisconnect?()
        }
    }

    func deviceDidBecomeReady(_ device: ICDevice) {}

    func device(_ device: ICDevice, didOpenSessionWithError error: (any Error)?) {}

    func device(_ device: ICDevice, didCloseSessionWithError error: (any Error)?) {
        queue.async {
            guard self.connected, !self.closing else { return }
            self.invalidateSessionOnQueue()
            self.onDisconnect?()
        }
    }

    func device(_ device: ICDevice, didEncounterError error: (any Error)?) {
        queue.async {
            guard self.connected, !self.closing else { return }
            self.invalidateSessionOnQueue()
            self.onDisconnect?()
        }
    }

    func connect() async throws {
        let camera = try await DeviceCoordinator.shared.acquireCamera(timeout: 15)
        camera.delegate = self
        guard camera.capabilities.contains(
            ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue
        ) else {
            throw PTPError.connectionFailed(
                "The X100VI was found, but ImageCaptureCore does not expose raw PTP command support."
            )
        }

        try Task.checkCancellation()
        try await withTaskCancellationHandler {
            try await openSession(on: camera)
        } onCancel: {
            self.cancelPendingConnect()
        }
    }

    private func openSession(on camera: ICCameraDevice) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard !self.connected, !self.closing, self.connectWaiter == nil else {
                    continuation.resume(throwing: PTPError.connectionFailed("Camera session is already active."))
                    return
                }

                self.connectWaiter = continuation
                self.camera = camera

                let timeout = DispatchWorkItem { [self] in
                    self.queue.async {
                        guard let waiter = self.connectWaiter else { return }
                        self.connectWaiter = nil
                        self.camera = nil
                        self.connected = false
                        self.transactionID = 0
                        waiter.resume(throwing: PTPError.connectionFailed(
                            "ImageCaptureCore session open timed out."
                        ))
                    }
                }
                self.connectTimeout = timeout
                self.transactionID = 0
                self.queue.asyncAfter(deadline: .now() + 15, execute: timeout)

                camera.requestOpenSession { [self] error in
                    self.queue.async {
                        if let error {
                            self.finishConnect(with: .failure(
                                PTPError.connectionFailed("ImageCaptureCore session open failed: \(error.localizedDescription)")
                            ))
                        } else {
                            self.finishConnect(with: .success(()))
                        }
                    }
                }
            }
        }
    }

    func disconnect(completion: (@Sendable () -> Void)? = nil) {
        queue.async {
            self.disconnectOnQueue(completion: completion)
        }
    }

    private func cancelPendingConnect() {
        queue.async {
            guard self.connectWaiter != nil else { return }
            self.disconnectOnQueue(completion: nil)
        }
    }

    private func disconnectOnQueue(completion: (@Sendable () -> Void)?) {
        if let id = removalHandlerID {
            removalHandlerID = nil
            DeviceCoordinator.shared.removeRemovalHandler(id)
        }
        connectTimeout?.cancel()
        connectTimeout = nil
        let cameraToClose = camera
        failActiveCommand()

        if let waiter = connectWaiter {
            connectWaiter = nil
            camera = nil
            connected = false
            transactionID = 0
            waiter.resume(throwing: PTPError.connectionFailed(
                "Camera connection was cancelled."
            ))
        }

        guard let camera = cameraToClose else {
            connected = false
            closeWaiter?.resume()
            closeWaiter = nil
            completion?()
            return
        }

        connected = false
        self.camera = nil
        closing = true
        transactionID = 0
        camera.requestCloseSession { [self] _ in
            self.queue.async {
                self.closing = false
                self.closeWaiter?.resume()
                self.closeWaiter = nil
                completion?()
            }
        }
    }

    struct PTPResult: Sendable {
        let response: Data
        let data: Data?
    }

    func send(command: Data, outData: Data?) async throws -> PTPResult {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PTPResult, Error>) in
            let gate = ContinuationGate(continuation)
            queue.async {
                guard self.connected, let camera = self.camera else {
                    gate.finishThrowing(PTPError.notConnected)
                    return
                }
                self.transactionID &+= 1
                var command = command
                command.setU32LE(self.transactionID, at: 8)
                let operationCode = command.u16LE(at: 6)
                let timeout = DispatchWorkItem { [self] in
                    self.invalidateSession()
                    _ = gate.finishThrowing(PTPError.commandFailed(
                        operationCode,
                        "ImageCaptureCore command timed out after 20 seconds."
                    ))
                }
                self.activeCommandFailure = {
                    _ = gate.finishThrowing(PTPError.notConnected)
                }
                self.activeCommandTimeout = timeout
                self.queue.asyncAfter(deadline: .now() + 20, execute: timeout)
                camera.requestSendPTPCommand(command, outData: outData) { data, response, error in
                    self.queue.async {
                        if let error {
                            self.clearActiveCommand()
                            self.invalidateSessionOnQueue()
                            self.onDisconnect?()
                            if gate.finishThrowing(PTPError.commandFailed(
                                operationCode,
                                error.localizedDescription
                            )) {
                                timeout.cancel()
                            }
                            return
                        }
                        guard response.count >= 12 else {
                            self.clearActiveCommand()
                            self.invalidateSessionOnQueue()
                            let respHex = response.map { String(format: "%02x", $0) }.joined(separator: " ")
                            let dataHex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
                            if gate.finishThrowing(PTPError.invalidResponse(
                                "ImageCaptureCore returned an incomplete PTP response: count=\(response.count) bytes=[\(respHex)] dataCount=\(data.count) [\(dataHex)]."
                            )) {
                                timeout.cancel()
                            }
                            return
                        }
                        let responseCode = response.u16LE(at: 6)
                        guard responseCode == 0x2001 else {
                            self.clearActiveCommand()
                            if gate.finishThrowing(PTPError.unknown(responseCode)) {
                                timeout.cancel()
                            }
                            return
                        }
                        self.clearActiveCommand()
                        let payload = data.isEmpty ? nil : data
                        if gate.finishReturning(PTPResult(response: response, data: payload)) {
                            timeout.cancel()
                        }
                    }
                }
            }
        }
    }

    private func invalidateSession() {
        queue.async {
            self.invalidateSessionOnQueue()
        }
    }

    private func invalidateSessionOnQueue() {
        if let id = removalHandlerID {
            removalHandlerID = nil
            DeviceCoordinator.shared.removeRemovalHandler(id)
        }
        clearActiveCommand()
        guard connected || camera != nil else { return }
        let camera = self.camera
        connected = false
        self.camera = nil
        transactionID = 0
        closing = true
        queue.asyncAfter(deadline: .now() + 5) {
            guard !self.connected, self.camera == nil else { return }
            self.closing = false
        }
        camera?.requestCloseSession { [weak self] _ in
            guard let owner = self else { return }
            owner.queue.async {
                owner.closing = false
            }
        }
    }

    private func clearActiveCommand() {
        activeCommandTimeout?.cancel()
        activeCommandTimeout = nil
        activeCommandFailure = nil
    }

    private func failActiveCommand() {
        let failure = activeCommandFailure
        clearActiveCommand()
        failure?()
    }

    private func finishConnect(with result: Result<Void, Error>) {
        connectTimeout?.cancel()
        connectTimeout = nil
        guard let waiter = connectWaiter else { return }
        connectWaiter = nil
        switch result {
        case .success:
            connected = true
            let id = DeviceCoordinator.shared.addRemovalHandler { [weak self] device in
                guard let self else { return }
                self.queue.async {
                    if self.connectWaiter != nil {
                        self.finishConnect(with: .failure(
                            PTPError.connectionFailed("The X100VI was disconnected while opening its session.")
                        ))
                        return
                    }
                    guard self.connected else { return }
                    self.invalidateSessionOnQueue()
                    self.onDisconnect?()
                }
            }
            removalHandlerID = id
            waiter.resume()
        case .failure(let error):
            if let id = removalHandlerID {
                removalHandlerID = nil
                DeviceCoordinator.shared.removeRemovalHandler(id)
            }
            let cameraToClose = camera
            camera = nil
            connected = false
            if let cameraToClose {
                closing = true
                queue.asyncAfter(deadline: .now() + 5) {
                    guard !self.connected, self.camera == nil else { return }
                    self.closing = false
                }
                cameraToClose.requestCloseSession { [weak self] _ in
                    guard let owner = self else { return }
                    owner.queue.async {
                        owner.closing = false
                    }
                }
            }
            waiter.resume(throwing: error)
        }
    }
}

private final class ContinuationGate<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var cancelled = false

    init() {}

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func install(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        guard !cancelled else {
            lock.unlock()
            continuation.resume(throwing: CancellationError())
            return
        }
        self.continuation = continuation
        lock.unlock()
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: CancellationError())
    }

    @discardableResult
    func finishReturning(_ value: Value) -> Bool {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return false
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(returning: value)
        return true
    }

    @discardableResult
    func finishThrowing(_ error: Error) -> Bool {
        lock.lock()
        guard let continuation else {
            lock.unlock()
            return false
        }
        self.continuation = nil
        lock.unlock()
        continuation.resume(throwing: error)
        return true
    }
}

enum PTPPacket {
    static func command(operation: UInt16, parameters: [UInt32]) -> Data {
        var bytes = Data(count: 12 + parameters.count * 4)
        bytes.setU32LE(UInt32(bytes.count), at: 0)
        bytes.setU16LE(0x0001, at: 4)
        bytes.setU16LE(operation, at: 6)
        bytes.setU32LE(0, at: 8)
        for (index, parameter) in parameters.enumerated() {
            bytes.setU32LE(parameter, at: 12 + index * 4)
        }
        return bytes
    }
}

extension Data {
    func u16LE(at offset: Int) -> UInt16 {
        UInt16(self[offset]) | (UInt16(self[offset + 1]) << 8)
    }

    func u32LE(at offset: Int) -> UInt32 {
        UInt32(self[offset])
            | (UInt32(self[offset + 1]) << 8)
            | (UInt32(self[offset + 2]) << 16)
            | (UInt32(self[offset + 3]) << 24)
    }

    mutating func setU16LE(_ value: UInt16, at offset: Int) {
        self[offset] = UInt8(value & 0xff)
        self[offset + 1] = UInt8(value >> 8)
    }

    mutating func setU32LE(_ value: UInt32, at offset: Int) {
        self[offset] = UInt8(value & 0xff)
        self[offset + 1] = UInt8((value >> 8) & 0xff)
        self[offset + 2] = UInt8((value >> 16) & 0xff)
        self[offset + 3] = UInt8((value >> 24) & 0xff)
    }
}

