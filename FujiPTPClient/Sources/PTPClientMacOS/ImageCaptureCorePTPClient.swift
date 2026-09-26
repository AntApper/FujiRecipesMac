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
        state.disconnect()
    }

    public func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse {
        let result = try await state.send(
            command: PTPPacket.command(operation: 0x1015, parameters: [UInt32(code)]),
            outData: nil
        )
        guard let payload = result.data else {
            throw PTPError.readFailed(code, "Camera returned no property data.")
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

        try await writeProperty(0xD18C, value: Int32(index))
        if !data.name.isEmpty {
            try await writeRawProperty(0xD18D, payload: Self.ptpString(data.name))
        }

        let fields: [(UInt16, Int32?)] = [
            (0xD18E, data.imageSize.map(Int32.init)),
            (0xD18F, data.imageQuality.map(Int32.init)),
            (0xD190, data.dynamicRange.map(Int32.init)),
            (0xD192, data.filmSimulation.map(Int32.init)),
            (0xD193, data.monoWarmCool),
            (0xD194, data.monoMagentaGreen),
            (0xD195, data.grainEffect.map(Int32.init)),
            (0xD196, data.colorChrome.map(Int32.init)),
            (0xD197, data.colorChromeFxBlue.map(Int32.init)),
            (0xD198, data.smoothSkin.map(Int32.init)),
            (0xD199, data.whiteBalance.map(Int32.init)),
            (0xD19A, data.wbShiftRed),
            (0xD19B, data.wbShiftBlue),
            (0xD19C, data.colorTemp.map(Int32.init)),
            (0xD19D, data.highlight),
            (0xD19E, data.shadow),
            (0xD19F, data.color),
            (0xD1A0, data.sharpness),
            (0xD1A1, data.highIsoNr.map(Int32.init)),
            (0xD1A2, data.clarity),
            (0xD1A3, data.longExpNr.map(Int32.init)),
            (0xD1A4, data.colorSpace.map(Int32.init))
        ]
        for (code, value) in fields {
            if let value {
                try await writeProperty(code, value: value)
            }
        }

        let observed = try await readPresetSlot(index)
        return PTPPresetSlotWriteResult(
            slot: index,
            warnings: [],
            observedSnapshot: observed
        )
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
            try await writeProperty(0xD199, value: Int32(value.actualPTPValue))
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
        case .uint32(let value): return Int32(bitPattern: value)
        case .int32(let value): return value
        default: return nil
        }
    }

    private static func stringValue(_ response: PTPPropertyResponse?) -> String {
        guard case .data(let data) = response, data.count >= 1 else { return "" }
        let characterCount = max(0, min(Int(data[0]) - 1, (data.count - 1) / 2))
        var scalars = String.UnicodeScalarView()
        for index in 0..<characterCount {
            let offset = 1 + index * 2
            let scalar = UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
            if let unicode = UnicodeScalar(scalar) {
                scalars.append(unicode)
            }
        }
        return String(scalars)
    }

    private static func ptpString(_ value: String) -> Data {
        let ascii = value
            .precomposedStringWithCompatibilityMapping
            .unicodeScalars
            .filter { $0.value < 0x80 && $0.value >= 0x20 }
            .prefix(15)
        var result = Data([UInt8(ascii.count + 1)])
        for scalar in ascii {
            result.append(UInt8(scalar.value))
            result.append(0)
        }
        result.append(0)
        result.append(0)
        return result
    }

    private func writeRawProperty(_ code: UInt16, payload: Data) async throws {
        _ = try await state.send(
            command: PTPPacket.command(operation: 0x1016, parameters: [UInt32(code)]),
            outData: payload
        )
    }
}

private final class State: NSObject, @unchecked Sendable {
    let queue = DispatchQueue(label: "com.ant.fuji-recipes.image-capture-core")
    var browser: ICDeviceBrowser?
    var camera: ICCameraDevice?
    var connected = false
    var closing = false
    var transactionID: UInt32 = 0
    var connectWaiter: CheckedContinuation<Void, Error>?
    var closeWaiter: CheckedContinuation<Void, Never>?
    var connectTimeout: DispatchWorkItem?
    var activeCommandFailure: (() -> Void)?
    var activeCommandTimeout: DispatchWorkItem?

    func connect() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                guard !self.connected, !self.closing, self.connectWaiter == nil else {
                    continuation.resume(throwing: PTPError.connectionFailed("Camera session is already active."))
                    return
                }

                self.connectWaiter = continuation
                let browser = ICDeviceBrowser()
                browser.delegate = self
                browser.browsedDeviceTypeMask = .camera
                self.browser = browser
                browser.start()

                let timeout = DispatchWorkItem { [self] in
                    self.queue.async {
                        guard let waiter = self.connectWaiter else { return }
                        self.connectWaiter = nil
                        self.browser?.stop()
                        self.browser = nil
                        self.camera = nil
                        self.connected = false
                        self.transactionID = 0
                        waiter.resume(throwing: PTPError.connectionFailed(
                            "ImageCaptureCore did not find an X100VI camera within 15 seconds."
                        ))
                    }
                }
                self.connectTimeout = timeout
                self.transactionID = 0
                self.queue.asyncAfter(deadline: .now() + 15, execute: timeout)
            }
        }
    }

    func disconnect() {
        queue.async {
            self.connectTimeout?.cancel()
            self.connectTimeout = nil
            self.browser?.stop()
            self.browser = nil
            let cameraToClose = self.camera
            self.failActiveCommand()

            if let waiter = self.connectWaiter {
                self.connectWaiter = nil
                self.camera = nil
                self.connected = false
                self.transactionID = 0
                waiter.resume(throwing: PTPError.connectionFailed(
                    "Camera connection was cancelled."
                ))
            }

            guard let camera = cameraToClose else {
                self.connected = false
                self.closeWaiter?.resume()
                self.closeWaiter = nil
                return
            }

            self.connected = false
            self.camera = nil
            self.closing = true
            self.queue.asyncAfter(deadline: .now() + 5) {
                guard !self.connected, self.camera == nil else { return }
                self.closing = false
            }
            self.transactionID = 0
            camera.requestCloseSession { [self] error in
                self.queue.async {
                    self.closing = false
                    self.closeWaiter?.resume()
                    self.closeWaiter = nil
                }
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
                let expectedTransaction = self.transactionID
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
                camera.requestSendPTPCommand(command, outData: outData) { response, data, error in
                    self.queue.async {
                        if let error {
                            self.clearActiveCommand()
                            self.invalidateSessionOnQueue()
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
                            if gate.finishThrowing(PTPError.invalidResponse(
                                "ImageCaptureCore returned an incomplete PTP response."
                            )) {
                                timeout.cancel()
                            }
                            return
                        }
                        let responseCode = response.u16LE(at: 6)
                        let responseTransaction = response.u32LE(at: 8)
                        guard responseTransaction == expectedTransaction else {
                            self.clearActiveCommand()
                            self.invalidateSessionOnQueue()
                            if gate.finishThrowing(PTPError.invalidResponse(
                                "PTP transaction mismatch: expected \(expectedTransaction), got \(responseTransaction)."
                            )) {
                                timeout.cancel()
                            }
                            return
                        }
                        guard responseCode == 0x2001 else {
                            self.clearActiveCommand()
                            if gate.finishThrowing(PTPError.unknown(responseCode)) {
                                timeout.cancel()
                            }
                            return
                        }
                        self.clearActiveCommand()
                        if gate.finishReturning(PTPResult(response: response, data: data)) {
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
        browser?.stop()
        browser = nil
        guard let waiter = connectWaiter else { return }
        connectWaiter = nil
        switch result {
        case .success:
            connected = true
            waiter.resume()
        case .failure(let error):
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

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
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

extension State: ICDeviceBrowserDelegate {
    func deviceBrowser(
        _ browser: ICDeviceBrowser,
        didAdd device: ICDevice,
        moreComing: Bool
    ) {
        guard let camera = device as? ICCameraDevice else { return }
        guard camera.usbVendorID == 0x04CB, camera.usbProductID == 0x0305 else { return }
        guard camera.transportType == ICDeviceTransport.transportTypeUSB.rawValue else { return }
        guard camera.capabilities.contains(
            ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue
        ) else {
            queue.async {
                self.finishConnect(with: .failure(
                    PTPError.connectionFailed(
                        "The X100VI was found, but ImageCaptureCore does not expose raw PTP command support."
                    )
                ))
            }
            return
        }
        queue.async {
            guard self.connectWaiter != nil else { return }
            guard self.camera == nil else { return }
            self.camera = camera
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

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        queue.async {
            if self.connectWaiter != nil {
                self.finishConnect(with: .failure(
                    PTPError.connectionFailed("The X100VI was disconnected while opening its session.")
                ))
                return
            }

            guard self.connected,
                  let camera = self.camera,
                  camera === (device as? ICCameraDevice)
            else { return }

            self.failActiveCommand()
            self.connected = false
            self.camera = nil
            self.closing = false
            self.transactionID = 0
        }
    }
}
