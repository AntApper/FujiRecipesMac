// X100VIHelperClient.swift
// Implements PTPClientProtocol by spawning the x100vi_helper C executable.

import Foundation
import FujiRecipesCore

#if !canImport(Darwin)
extension FileHandle {
    struct LinuxAsyncBytes: AsyncSequence {
        typealias Element = UInt8
        let handle: FileHandle

        struct AsyncIterator: AsyncIteratorProtocol {
            let handle: FileHandle
            var buffer = Data()
            var index = 0

            mutating func next() async throws -> UInt8? {
                if index < buffer.count {
                    let byte = buffer[index]
                    index += 1
                    return byte
                }
                buffer = handle.readData(ofLength: 4096)
                index = 0
                if buffer.isEmpty { return nil }
                let byte = buffer[index]
                index += 1
                return byte
            }
        }

        func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(handle: handle)
        }

        var lines: LinuxAsyncLineSequence<LinuxAsyncBytes> {
            LinuxAsyncLineSequence(self)
        }
    }

    var bytes: LinuxAsyncBytes {
        LinuxAsyncBytes(handle: self)
    }
}

struct LinuxAsyncLineSequence<Base: AsyncSequence>: AsyncSequence where Base.Element == UInt8 {
    typealias Element = String
    let base: Base

    init(_ base: Base) {
        self.base = base
    }

    struct AsyncIterator: AsyncIteratorProtocol {
        var baseIterator: Base.AsyncIterator

        mutating func next() async throws -> String? {
            var lineBytes: [UInt8] = []
            while let byte = try await baseIterator.next() {
                if byte == UInt8(ascii: "\n") {
                    return String(decoding: lineBytes, as: UTF8.self)
                }
                if byte != UInt8(ascii: "\r") {
                    lineBytes.append(byte)
                }
            }
            if !lineBytes.isEmpty {
                return String(decoding: lineBytes, as: UTF8.self)
            }
            return nil
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(baseIterator: base.makeAsyncIterator())
    }
}
#endif

/// PTPClientProtocol implementation that spawns the x100vi_helper C executable.
/// The C helper uses libusb to send PTP containers directly to the X100VI.
///
/// Communication is line-delimited JSON (one request line, one response line).
/// Because the helper is a long-lived process, its stdout is consumed as an
/// `AsyncSequence` of lines; requests are funnelled through a single serial
/// worker so responses always match the order in which they were sent.
public final class X100VIHelperClient: PTPClientProtocol, @unchecked Sendable {
    public init() {}

    private var process: Process?
    private var inputPipe: Pipe?
    private var errorPipe: Pipe?
    private var lineIterator: AsyncThrowingStream<String, any Error>.Iterator?
    private var requestStreamContinuation: AsyncStream<PendingRequest>.Continuation?
    private var requestProcessorTask: Task<Void, Never>?
    private var stderrReaderTask: Task<Void, Never>?
    private var stderrTail = ""
    private var terminationSummary: String?
    private var isConnectedFlag = false
    private var transactionID = 0
    private var pendingRequests: [String: PendingRequest] = [:]
    private var _cameraInfo: PTPCameraInfo = PTPCameraInfo(model: "Not connected")
    private var lifecycle: HelperLifecycle = .idle
    private var shutdownTask: Task<Void, Never>?

    // All mutable state is touched only inside the serial `queue`.  The public
    // `async` entry points dispatch to it; the request-processor task (which
    // owns the line iterator) runs on the cooperative thread pool.
    private let queue = DispatchQueue(label: "com.fujirecipes.x100vi-helper")

    private enum HelperLifecycle {
        case idle
        case connecting
        case connected
        case disconnecting
    }

    public var isConnected: Bool {
        queue.sync { isConnectedFlag }
    }

    public var cameraInfo: PTPCameraInfo {
        get { queue.sync { _cameraInfo } }
        set { queue.sync { _cameraInfo = newValue } }
    }

    // MARK: - PTPClientProtocol

    public func connect() async throws {
        if let pendingShutdown = queue.sync(execute: { shutdownTask }) {
            await pendingShutdown.value
        }
        let canStart = queue.sync { () -> Bool in
            guard lifecycle == .idle else { return false }
            lifecycle = .connecting
            return true
        }
        guard canStart else {
            throw PTPError.connectionFailed("X100VI helper connection is already active")
        }

        do {
            try await withTimeout(timeout: 30) {
                try await self.connectInternal()
            }
        } catch {
            disconnect()
            throw error
        }
    }

    private func connectInternal() async throws {
        guard let helperPath = findHelper() else {
            throw PTPError.connectionFailed("x100vi_helper not found")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: helperPath)

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()

        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.terminationHandler = { [weak self] terminatedProcess in
            guard let client = self else { return }
            let reason = terminatedProcess.terminationReason == .uncaughtSignal
                ? "signal \(terminatedProcess.terminationStatus)"
                : "exit \(terminatedProcess.terminationStatus)"
            client.queue.async {
                guard client.process === terminatedProcess else { return }
                client.terminationSummary = reason
                client.isConnectedFlag = false
                if client.shutdownTask == nil {
                    client.lifecycle = .idle
                }
                client.failAllPendingLocked(
                    PTPError.notConnected
                )
            }
        }

        try process.run()

        // Build an async line iterator over the helper's stdout.  We bridge
        // FileHandle's bytes.lines into an AsyncThrowingStream so the iterator
        // type is simple and Sendable-friendly.
        let (lines, linesContinuation) = AsyncThrowingStream<String, any Error>.makeStream()
        Task {
            do {
                for try await rawLine in stdoutPipe.fileHandleForReading.bytes.lines {
                    linesContinuation.yield(String(rawLine))
                }
                linesContinuation.finish()
            } catch {
                linesContinuation.finish(throwing: error)
            }
        }

        // The helper emits useful libusb/PTP diagnostics on stderr.  Drain it
        // continuously (to avoid a full pipe stalling a long write) and retain
        // only a small tail for an actionable error if the child terminates.
        let stderrReader = Task { [weak self] in
            do {
                for try await rawLine in stderrPipe.fileHandleForReading.bytes.lines {
                    self?.appendHelperStderr(String(rawLine))
                }
            } catch {
                self?.appendHelperStderr("stderr reader failed: \(error.localizedDescription)")
            }
        }

        let (requestStream, requestContinuation) = AsyncStream<PendingRequest>.makeStream()

        self.queue.sync {
            self.process = process
            self.inputPipe = stdinPipe
            self.errorPipe = stderrPipe
            self.lineIterator = lines.makeAsyncIterator()
            self.requestStreamContinuation = requestContinuation
            self.stderrReaderTask = stderrReader
            self.stderrTail = ""
            self.terminationSummary = nil
        }

        // Start the single worker that owns the iterator and serialises I/O.
        let processor = Task { [weak self] in
            guard let self else { return }
            await self.processRequests(from: requestStream)
        }
        self.queue.sync { self.requestProcessorTask = processor }

        do {
            // First verify the JSON protocol, then claim the USB interface and
            // open the PTP session. `ping` only proves that the child process
            // started; it does not connect the camera.
            let pingResponse = try await sendCommand("ping", params: [:])
            guard pingResponse["success"] as? Bool == true else {
                throw PTPError.connectionFailed("Helper did not respond to ping")
            }

            let connectionResponse = try await sendCommand("connect", params: [:])
            guard connectionResponse["success"] as? Bool == true else {
                throw PTPError.connectionFailed(
                    helperConnectionFailure(in: connectionResponse).userActionableDescription
                )
            }

            self.cameraInfo = PTPCameraInfo(
                model: "Fuji X100VI",
                vendorExtensionId: 0x0000000E
            )
            self.queue.sync {
                self.isConnectedFlag = true
                self.lifecycle = .connected
            }
        } catch {
            // A failed handshake must not leave the child process or a claimed
            // USB interface alive for the next connection attempt.
            disconnect()
            throw error
        }
    }

    public func disconnect() {
        let processToStop: Process? = queue.sync {
            guard shutdownTask == nil else { return nil }
            isConnectedFlag = false
            lifecycle = .disconnecting
            guard let process else {
                lifecycle = .idle
                return nil
            }
            return process
        }
        guard let processToStop else { return }

        // PTPClientProtocol intentionally exposes synchronous disconnect.
        // Keep that API stable while serialising a graceful JSON teardown
        // behind it; a following connect awaits this task before spawning.
        let task = Task { [weak self] in
            guard let self else { return }
            await self.shutdownHelperGracefully(processToStop)
        }
        queue.sync { shutdownTask = task }
    }

    public func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse {
        let response = try await sendCommand("read_property", params: ["code": Int(code)])

        guard response["success"] as? Bool == true,
              let result = response["result"] as? [String: Any] else {
            throw PTPError.readFailed(code, "Helper returned error")
        }

        if let errorCode = result["error_code"] as? Int {
            throw PTPError.readFailed(code, "Error code: \(String(format: "0x%04X", errorCode))")
        }

        if let raw = jsonUInt32(result["value"]) {
            return .uint32(raw)
        }
        if let raw = jsonInt32(result["value"]) {
            return .int32(raw)
        }
        if let string = result["value"] as? String {
            return .string(string)
        }
        if let string = result["display"] as? String {
            return .string(string)
        }
        if let array = result["value"] as? [UInt8] {
            return .data(Data(array))
        }

        return .unsupported
    }

    public func writeProperty(_ code: UInt16, value: Int32) async throws {
        let response = try await sendCommand("write_property", params: [
            "code": Int(code),
            "value": Int(value)
        ])

        guard response["success"] as? Bool == true else {
            throw PTPError.writeFailed(code, "Helper returned error")
        }
    }

    public func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        let response = try await sendCommand("read_preset_slot", params: ["index": index])

        if let retryCode = transientSlotSelectionCode(in: response) {
            do {
                try await reconnect()
            } catch {
                throw PTPError.readFailed(
                    0xD18C,
                    "slot_selection failed (\(formattedHelperCode(retryCode))); reconnect retry failed: \(error.localizedDescription)"
                )
            }
            return try await readPresetSlotWithoutRetry(index)
        }

        if let propertyFailure = presetPropertyReadFailure(in: response) {
            do {
                try await reconnect()
            } catch {
                throw PTPError.readFailed(
                    0xD18C,
                    "\(propertyFailure); reconnect retry failed: \(error.localizedDescription)"
                )
            }
            return try await readPresetSlotWithoutRetry(index)
        }

        return try parsePresetSlotResponse(response, index: index)
    }

    private func readPresetSlotWithoutRetry(_ index: Int) async throws -> PTPClientPresetData {
        let response = try await sendCommand("read_preset_slot", params: ["index": index])
        return try parsePresetSlotResponse(response, index: index)
    }

    private func parsePresetSlotResponse(
        _ response: [String: Any],
        index: Int
    ) throws -> PTPClientPresetData {
        guard response["success"] as? Bool == true,
              let result = response["result"] as? [String: Any],
              let properties = result["properties"] as? [String: [String: Any]] else {
            let reason = presetSlotFailureDetails(response)
            throw PTPError.readFailed(0xD18C, reason)
        }
        if let propertyFailure = presetPropertyReadFailure(in: response) {
            throw PTPError.readFailed(0xD18C, propertyFailure)
        }
        let isEmptySlot = result["is_empty_slot"] as? Bool ?? false

        var name = ""
        var imageQuality: UInt32?
        var imageSize: UInt32?
        var dynamicRange: UInt32?
        var filmSimulation: UInt32?
        var monoWarmCool: Int32?
        var monoMagentaGreen: Int32?
        var grainEffect: UInt32?
        var colorChrome: UInt32?
        var colorChromeFxBlue: UInt32?
        var smoothSkin: UInt32?
        var whiteBalance: UInt32?
        var wbShiftRed: Int32?
        var wbShiftBlue: Int32?
        var colorTemp: UInt32?
        var highlight: Int32?
        var shadow: Int32?
        var color: Int32?
        var sharpness: Int32?
        var highIsoNr: UInt32?
        var clarity: Int32?
        var longExpNr: UInt32?
        var colorSpace: UInt32?

        for (key, value) in properties {
            guard let codeHex = key.components(separatedBy: "_").first,
                  let code = UInt16(codeHex.dropFirst(2), radix: 16) else { continue }

            switch code {
            case 0xD18D:
                if let display = value["display"] as? String, !display.isEmpty {
                    name = display
                }
            case 0xD18E: imageSize = jsonUInt32(value["raw"])
            case 0xD18F: imageQuality = jsonUInt32(value["raw"])
            case 0xD190: dynamicRange = jsonUInt32(value["raw"])
            case 0xD192: filmSimulation = jsonUInt32(value["raw"])
            case 0xD193: monoWarmCool = jsonPTPInt16(value["raw"])
            case 0xD194: monoMagentaGreen = jsonPTPInt16(value["raw"])
            case 0xD195: grainEffect = jsonUInt32(value["raw"])
            case 0xD196: colorChrome = jsonUInt32(value["raw"])
            case 0xD197: colorChromeFxBlue = jsonUInt32(value["raw"])
            case 0xD198: smoothSkin = jsonUInt32(value["raw"])
            case 0xD199: whiteBalance = jsonUInt32(value["raw"])
            case 0xD19A: wbShiftRed = jsonPTPInt16(value["raw"])
            case 0xD19B: wbShiftBlue = jsonPTPInt16(value["raw"])
            case 0xD19C: colorTemp = jsonUInt32(value["raw"])
            case 0xD19D: highlight = jsonPTPInt16(value["raw"])
            case 0xD19E: shadow = jsonPTPInt16(value["raw"])
            case 0xD19F: color = jsonPTPInt16(value["raw"])
            case 0xD1A0: sharpness = jsonPTPInt16(value["raw"])
            case 0xD1A1: highIsoNr = jsonUInt32(value["raw"])
            case 0xD1A2: clarity = jsonPTPInt16(value["raw"])
            case 0xD1A3: longExpNr = jsonUInt32(value["raw"])
            case 0xD1A4: colorSpace = jsonUInt32(value["raw"])
            default: break
            }
        }

        return PTPClientPresetData(
            slot: index,
            name: name,
            isEmptySlot: isEmptySlot,
            imageQuality: imageQuality,
            imageSize: imageSize,
            dynamicRange: dynamicRange,
            filmSimulation: filmSimulation,
            monoWarmCool: monoWarmCool,
            monoMagentaGreen: monoMagentaGreen,
            grainEffect: grainEffect,
            colorChrome: colorChrome,
            colorChromeFxBlue: colorChromeFxBlue,
            smoothSkin: smoothSkin,
            whiteBalance: whiteBalance,
            wbShiftRed: wbShiftRed,
            wbShiftBlue: wbShiftBlue,
            colorTemp: colorTemp,
            highlight: highlight,
            shadow: shadow,
            color: color,
            sharpness: sharpness,
            highIsoNr: highIsoNr,
            clarity: clarity,
            longExpNr: longExpNr,
            colorSpace: colorSpace
        )
    }

    public func writePresetSlot(_ index: Int, data: PTPClientPresetData) async throws -> PTPPresetSlotWriteResult {
        try validatePresetPayload(data)
        let params = Self.presetWriteParameters(index: index, data: data)

        let response = try await sendCommand("write_preset_slot", params: params)
        return try parsePresetWriteResponse(response, index: index)
    }

    private func parsePresetWriteResponse(
        _ response: [String: Any],
        index: Int
    ) throws -> PTPPresetSlotWriteResult {
        let result = response["result"] as? [String: Any]
        guard response["success"] as? Bool == true,
              let result,
              result["verified"] as? Bool == true else {
            let details = presetWriteFailureDetails(response: response, result: result)
            throw PTPError.writeFailed(0xD18C, details)
        }

        let warnings = presetWriteWarnings(from: result)
        if !warnings.isEmpty {
            let details = warnings.joined(separator: ", ")
            NSLog("X100VI C-slot write completed with inapplicable fields: %@", details)
        }
        return PTPPresetSlotWriteResult(
            slot: index,
            createdFromEmpty: result["created_from_empty"] as? Bool ?? false,
            warnings: warnings
        )
    }

    public func readNativeProfile() async throws -> Data {
        let tempDir = FileManager.default.temporaryDirectory
        let profilePath = tempDir.appendingPathComponent("native_profile.dat").path

        let response = try await sendCommand("get_profile", params: ["output": profilePath])

        guard response["success"] as? Bool == true else {
            throw PTPError.readFailed(0xD185, "Helper returned error")
        }

        let url = URL(fileURLWithPath: profilePath)
        let profileData = try Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        return profileData
    }

    public func writePTPSettings(from recipe: Recipe) async throws {
        if let fs = recipe.filmSimulation {
            try await writeProperty(0xD192, value: Int32(fs.rawValue))
        }
        if let dr = recipe.dynamicRange {
            try await writeProperty(0xD190, value: Int32(dr.rawValue))
        }
        if let grain = recipe.grainEffect {
            try await writeProperty(0xD195, value: Int32(grain.rawValue))
        }
        if let chrome = recipe.colorChrome {
            try await writeProperty(0xD196, value: Int32(chrome.rawValue))
        }
        if let chromeFx = recipe.colorChromeFxBlue {
            try await writeProperty(0xD197, value: Int32(chromeFx.rawValue))
        }
        if let smoothSkin = recipe.smoothSkin {
            try await writeProperty(0xD198, value: Int32(smoothSkin.rawValue))
        }
        if let wb = recipe.whiteBalanceMode {
            try await writeProperty(0xD199, value: Int32(wb.rawValue))
        }
        if let ct = recipe.colorTempK {
            try await writeProperty(0xD19C, value: Int32(ct))
        }
        if let v = recipe.wbShiftRed {
            try await writeProperty(0xD19A, value: v)
        }
        if let v = recipe.wbShiftBlue {
            try await writeProperty(0xD19B, value: v)
        }
        if let v = recipe.highlight {
            try await writeProperty(0xD19D, value: v)
        }
        if let v = recipe.shadow {
            try await writeProperty(0xD19E, value: v)
        }
        if let v = recipe.color {
            try await writeProperty(0xD19F, value: v)
        }
        if let v = recipe.sharpness {
            try await writeProperty(0xD1A0, value: v)
        }
        if let v = recipe.clarity {
            try await writeProperty(0xD1A2, value: v)
        }
        if let v = recipe.highIsoNr {
            try await writeProperty(0xD1A1, value: v)
        }
    }

    public func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)?) async -> RAFConversionOutcome {
        // Profile modification is unsupported because the camera-verified
        // pipeline builds a default profile from scratch for X100VI.
        _ = profileModifier

        let tempDir = FileManager.default.temporaryDirectory
        let rafPath = tempDir.appendingPathComponent("input.RAF").path
        let jpegPath = tempDir.appendingPathComponent("output.jpg").path

        do {
            try raf.data.write(to: URL(fileURLWithPath: rafPath))
        } catch {
            return .failed(message: "Could not stage RAF input: \(error.localizedDescription)")
        }

        defer {
            try? FileManager.default.removeItem(atPath: rafPath)
            try? FileManager.default.removeItem(atPath: jpegPath)
        }

        let response: [String: Any]
        do {
            response = try await sendCommand("convert_raf", params: [
                "input": rafPath,
                "output": jpegPath
            ], phase: .conversionPipeline)
        } catch is CancellationError {
            return .cancelled
        } catch {
            return .failed(message: error.localizedDescription)
        }

        let result = response["result"] as? [String: Any]
        guard response["success"] as? Bool == true,
              let result,
              let status = result["status"] as? String,
              status == "jpeg_downloaded",
              (result["diagnostics"] as? [String: Any])?["delivery_verified"] as? Bool == true,
              let size = helperInteger(result["size"]),
              size > 0 else {
            if let evidence = conversionDeliveryEvidence(from: response) {
                return .triggerAcceptedOutputNotRetrievable(reason: evidence)
            }
            let reason = result?["error"] as? String ?? response["error"] as? String ?? "unknown"
            return .failed(message: "Conversion failed: \(reason)")
        }

        do {
            let jpegData = try Data(contentsOf: URL(fileURLWithPath: jpegPath))
            return .downloadedJPEG(JPEGFile(
            name: "converted_\(raf.name)",
            data: jpegData,
            size: UInt32(size),
            storageID: 0, // Helper currently reports handle but not storage ID.
            objectHandle: UInt32(helperInteger(result["candidate_handle"]) ?? 0)
            ))
        } catch {
            return .triggerAcceptedOutputNotRetrievable(
                reason: "Helper reported a JPEG but macOS could not read it: \(error.localizedDescription)"
            )
        }
    }

    public func reconnect() async throws {
        let response = try await sendCommand("reconnect", params: [:])
        guard response["success"] as? Bool == true else {
            throw PTPError.connectionFailed(
                helperConnectionFailure(in: response).userActionableDescription
            )
        }
    }

    public func loadRAF(_ raf: RAFFile) async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let rafPath = tempDir.appendingPathComponent("upload.RAF").path

        try raf.data.write(to: URL(fileURLWithPath: rafPath))
        defer { try? FileManager.default.removeItem(atPath: rafPath) }

        let response = try await sendCommand("load_raf", params: ["path": rafPath])
        guard response["success"] as? Bool == true else {
            throw PTPError.platformError("RAF load failed")
        }
    }

    public func triggerConversion() async throws {
        let response = try await sendCommand("trigger_conversion", params: [:])
        guard response["success"] as? Bool == true else {
            throw PTPError.platformError("Trigger conversion failed")
        }
    }

    public func setProfile(_ data: Data) async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let profPath = tempDir.appendingPathComponent("profile.dat").path

        try data.write(to: URL(fileURLWithPath: profPath))
        defer { try? FileManager.default.removeItem(atPath: profPath) }

        let response = try await sendCommand("set_profile", params: ["path": profPath])
        guard response["success"] as? Bool == true else {
            throw PTPError.writeFailed(0xD185, "Helper returned error")
        }
    }

    public func waitConversionResult(outputName: String, timeoutMs: Int = 30000) async throws -> JPEGFile {
        let tempDir = FileManager.default.temporaryDirectory
        let jpegPath = tempDir.appendingPathComponent(outputName).path

        let response = try await sendCommand("wait_result", params: [
            "output": jpegPath,
            "timeout_ms": timeoutMs
        ])

        guard response["success"] as? Bool == true,
              let result = response["result"] as? [String: Any],
              result["status"] as? String == "jpeg_downloaded",
              (result["diagnostics"] as? [String: Any])?["delivery_verified"] as? Bool == true,
              let size = helperInteger(result["size"]),
              size > 0 else {
            throw PTPError.platformError(conversionDeliveryEvidence(from: response) ?? "No verified JPEG was returned")
        }

        let jpegData = try Data(contentsOf: URL(fileURLWithPath: jpegPath))
        return JPEGFile(
            name: outputName,
            data: jpegData,
            size: UInt32(size),
            storageID: 0,
            objectHandle: UInt32(helperInteger(result["candidate_handle"]) ?? 0)
        )
    }

    public func capturePreview() async throws -> JPEGFile? {
        throw PTPError.platformError("Preview capture not yet implemented")
    }

    // MARK: - Command Communication

    private final class PendingRequest: @unchecked Sendable {
        let id: String
        let command: String
        let params: [String: any Sendable]
        private let lock = NSLock()
        private var continuation: CheckedContinuation<ResponseBox, any Error>?
        private(set) var cancelled = false

        init(id: String, command: String, params: [String: any Sendable]) {
            self.id = id
            self.command = command
            self.params = params
        }

        func install(_ continuation: CheckedContinuation<ResponseBox, any Error>) {
            lock.lock()
            defer { lock.unlock() }
            if cancelled {
                continuation.resume(throwing: CancellationError())
            } else {
                self.continuation = continuation
            }
        }

        func succeed(_ response: ResponseBox) {
            finish(.success(response))
        }

        func fail(_ error: Error) {
            finish(.failure(error))
        }

        func cancel() {
            lock.lock()
            cancelled = true
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(throwing: CancellationError())
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return cancelled
        }

        private func finish(_ result: Result<ResponseBox, Error>) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            guard let continuation else { return }
            continuation.resume(with: result)
        }
    }

    private enum HelperRequestPhase {
        case handshake
        case shutdown
        case property
        case preset
        case transfer
        case conversionPipeline

        var timeout: TimeInterval {
            switch self {
            case .handshake: 10
            case .shutdown: 3
            case .property: 15
            case .preset: 30
            case .transfer: 90
            case .conversionPipeline: 90
            }
        }

        static func forCommand(_ command: String) -> Self {
            switch command {
            case "ping", "connect", "reconnect": .handshake
            case "disconnect", "exit": .shutdown
            case "read_preset_slot", "write_preset_slot": .preset
            case "load_raf", "get_profile", "set_profile", "wait_result": .transfer
            case "convert_raf": .conversionPipeline
            default: .property
            }
        }
    }

    /// The exact JSON field names accepted by `x100vi_helper` for a raw C-slot
    /// write. Kept separate from transport so object-to-request tests exercise
    /// the same mapping that reaches the physical helper.
    static func presetWriteParameters(
        index: Int,
        data: PTPClientPresetData
    ) -> [String: any Sendable] {
        var params: [String: any Sendable] = ["index": index]

        // x100vi_helper.c refuses a whole write whose name exceeds its
        // FUJI_PRESET_NAME_MAX_CHARACTERS of 15.
        if !data.name.isEmpty { params["name"] = String(data.name.prefix(15)) }
        if let v = data.filmSimulation { params["film_simulation"] = Int(v) }
        if let v = data.dynamicRange { params["dynamic_range"] = Int(v) }
        if let v = data.grainEffect { params["grain_effect"] = Int(v) }
        if let v = data.colorChrome { params["color_chrome"] = Int(v) }
        if let v = data.colorChromeFxBlue { params["color_chrome_fx_blue"] = Int(v) }
        if let v = data.smoothSkin { params["smooth_skin"] = Int(v) }
        if let v = data.whiteBalance { params["white_balance"] = Int(v) }
        if let v = data.wbShiftRed { params["wb_shift_r"] = Int(v) }
        if let v = data.wbShiftBlue { params["wb_shift_b"] = Int(v) }
        if let v = data.colorTemp { params["color_temp"] = Int(v) }
        if let v = data.highlight { params["highlight"] = Int(v) }
        if let v = data.shadow { params["shadow"] = Int(v) }
        if let v = data.color { params["color"] = Int(v) }
        if let v = data.sharpness { params["sharpness"] = Int(v) }
        if let v = data.highIsoNr { params["high_iso_nr"] = Int(v) }
        if let v = data.clarity { params["clarity"] = Int(v) }
        if let v = data.monoWarmCool { params["mono_warm_cool"] = Int(v) }
        if let v = data.monoMagentaGreen { params["mono_magenta_green"] = Int(v) }
        if let v = data.imageSize { params["image_size"] = Int(v) }
        if let v = data.imageQuality { params["image_quality"] = Int(v) }
        if let v = data.longExpNr { params["long_exp_nr"] = Int(v) }
        if let v = data.colorSpace { params["color_space"] = Int(v) }
        return params
    }

    static func helperRequestData(
        id: String,
        command: String,
        params: [String: any Sendable]
    ) throws -> Data {
        var request: [String: Any] = ["id": id, "command": command]
        for (key, value) in params {
            request[key] = value
        }
        return try JSONSerialization.data(withJSONObject: request)
    }

    /// Serialise a command to the helper and return its parsed JSON response.
    /// Each request carries a unique protocol ID; cancellation removes its
    /// continuation while the serial worker consumes its eventual response so
    /// it cannot be mistaken for the following request.
    @discardableResult
    private func sendCommand(
        _ command: String,
        params: [String: any Sendable],
        phase: HelperRequestPhase? = nil
    ) async throws -> [String: Any] {
        let id = queue.sync {
            let current = transactionID
            transactionID += 1
            return String(current)
        }
        let request = PendingRequest(id: id, command: command, params: params)
        let selectedPhase = phase ?? .forCommand(command)
        let box = try await withTimeout(timeout: selectedPhase.timeout) {
            try await withTaskCancellationHandler(operation: {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ResponseBox, any Error>) in
                    request.install(continuation)
                    self.queue.sync {
                        guard let requestStreamContinuation = self.requestStreamContinuation else {
                            request.fail(PTPError.notConnected)
                            return
                        }
                        self.pendingRequests[id] = request
                        requestStreamContinuation.yield(request)
                    }
                }
            }, onCancel: {
                self.cancelPendingRequest(request)
            })
        }
        return box.dict
    }

    /// Non-Sendable JSON dictionaries from `JSONSerialization` cannot be returned
    /// directly from `withTimeout`'s `@Sendable` closure.  This box passes the
    /// dictionary across without claiming it is generally thread-safe.
    private final class ResponseBox: @unchecked Sendable {
        let dict: [String: Any]
        init(_ dict: [String: Any]) { self.dict = dict }
    }

    /// The single worker that owns the helper's stdout iterator and processes
    /// one request at a time.  This guarantees request/response ordering.
    private func processRequests(from stream: AsyncStream<PendingRequest>) async {
        for await request in stream {
            // A request can time out while waiting behind a long transfer.
            // Do not write cancelled queued work to the camera.
            if request.isCancelled {
                continue
            }
            do {
                var (iterator, inputPipe, process) = self.queue.sync { () -> (AsyncThrowingStream<String, any Error>.Iterator, Pipe, Process) in
                    guard let iterator = self.lineIterator,
                          let inputPipe = self.inputPipe,
                          let process = self.process else {
                        fatalError("Request processor started before connect")
                    }
                    return (iterator, inputPipe, process)
                }

                guard process.isRunning else {
                    throw PTPError.notConnected
                }

                guard let data = try? Self.helperRequestData(
                    id: request.id,
                    command: request.command,
                    params: request.params
                ),
                      let line = String(data: data, encoding: .utf8),
                      let lineData = (line + "\n").data(using: .utf8) else {
                    throw PTPError.invalidResponse("Failed to encode request")
                }

                inputPipe.fileHandleForWriting.write(lineData)

                guard let responseLine = try await iterator.next() else {
                    throw PTPError.invalidResponse(self.helperTerminationDetails(for: process))
                }

                // Store the mutated iterator back (AsyncThrowingStream iterators
                // are value types that share read state via internal reference).
                self.queue.sync { self.lineIterator = iterator }

                guard let responseData = responseLine.data(using: String.Encoding.utf8),
                      let json = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
                    throw PTPError.invalidResponse("Failed to parse JSON: \(responseLine)")
                }
                guard String(describing: json["id"] ?? "") == request.id else {
                    throw PTPError.invalidResponse(
                        "Helper response ID \(String(describing: json["id"] ?? "missing")) did not match request \(request.id)"
                    )
                }

                _ = self.queue.sync { self.pendingRequests.removeValue(forKey: request.id) }
                request.succeed(ResponseBox(json))
            } catch {
                _ = self.queue.sync { self.pendingRequests.removeValue(forKey: request.id) }
                request.fail(error)
            }
        }
    }

    private func cancelPendingRequest(_ request: PendingRequest) {
        queue.async {
            self.pendingRequests.removeValue(forKey: request.id)
            request.cancel()
        }
    }

    /// Sends the helper's camera disconnect command, then asks its process to
    /// exit normally. Only a missing/late response or a late process exit
    /// falls back to SIGTERM, preserving CloseSession whenever the helper can
    /// still communicate with the camera.
    private func shutdownHelperGracefully(_ expectedProcess: Process) async {
        if expectedProcess.isRunning {
            do {
                let disconnectResponse = try await sendCommand(
                    "disconnect",
                    params: [:],
                    phase: .shutdown
                )
                guard disconnectResponse["success"] as? Bool == true else {
                    throw PTPError.invalidResponse("Helper rejected disconnect")
                }

                let exitResponse = try await sendCommand(
                    "exit",
                    params: [:],
                    phase: .shutdown
                )
                guard exitResponse["success"] as? Bool == true else {
                    throw PTPError.invalidResponse("Helper rejected exit")
                }
            } catch {
                appendHelperStderr("Graceful shutdown failed: \(error.localizedDescription)")
            }

            // Closing stdin after the exit response also lets helpers built
            // before the exit acknowledgement exit by EOF.
            queue.sync {
                guard process === expectedProcess else { return }
                inputPipe?.fileHandleForWriting.closeFile()
            }

            if !(await waitForProcessExit(expectedProcess, timeout: 2)) {
                appendHelperStderr("Helper did not exit after graceful shutdown; terminating")
                expectedProcess.terminate()
                _ = await waitForProcessExit(expectedProcess, timeout: 1)
            }
        }
        cleanupHelper(expectedProcess)
    }

    private func waitForProcessExit(_ process: Process, timeout: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning, Date() < deadline {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return !process.isRunning
    }

    private func cleanupHelper(_ expectedProcess: Process) {
        queue.sync {
            guard process === expectedProcess else { return }
            isConnectedFlag = false
            failAllPendingLocked(PTPError.notConnected)
            requestStreamContinuation?.finish()
            requestStreamContinuation = nil
            requestProcessorTask?.cancel()
            requestProcessorTask = nil
            stderrReaderTask?.cancel()
            stderrReaderTask = nil
            inputPipe = nil
            errorPipe = nil
            lineIterator = nil
            process = nil
            lifecycle = .idle
            shutdownTask = nil
        }
    }

    /// Called only while `queue` is held. Every queued or in-flight caller
    /// must be released when the child exits or explicit disconnect begins.
    private func failAllPendingLocked(_ error: Error) {
        let requests = pendingRequests.values
        pendingRequests.removeAll()
        for request in requests {
            request.fail(error)
        }
    }

    private func appendHelperStderr(_ line: String) {
        queue.sync {
            let updated = self.stderrTail.isEmpty ? line : "\(self.stderrTail)\n\(line)"
            // Preserve the most recent diagnostics without allowing a verbose
            // helper session to retain unbounded data in the app process.
            self.stderrTail = String(updated.suffix(4_096))
        }
    }

    private func helperTerminationDetails(for process: Process) -> String {
        queue.sync {
            let summary: String
            if let terminationSummary {
                summary = terminationSummary
            } else if !process.isRunning {
                summary = process.terminationReason == .uncaughtSignal
                    ? "signal \(process.terminationStatus)"
                    : "exit \(process.terminationStatus)"
            } else {
                summary = "while still marked running"
            }
            let stderr = stderrTail.trimmingCharacters(in: .whitespacesAndNewlines)
            return stderr.isEmpty
                ? "Helper closed stdout (\(summary)); no stderr output"
                : "Helper closed stdout (\(summary)): \(stderr)"
        }
    }

    // MARK: - Helper Discovery

    private func findHelper() -> String? {
        // A packaged app must use the helper sealed inside its own bundle.
        // In particular, a Release build must never substitute a binary from
        // PATH or a developer checkout: that would bypass the bundle's
        // provenance, signing, and libusb runtime checks.
        if let bundlePath = Bundle.main.resourcePath {
            let bundledHelper = bundlePath + "/x100vi_helper"
            if FileManager.default.isExecutableFile(atPath: bundledHelper) {
                return bundledHelper
            }
        }

        #if DEBUG
        // Development-only escape hatch for SwiftPM/Xcode runs that are not
        // packaged as an app. It is deliberately explicit so release behavior
        // cannot silently depend on a developer machine's PATH.
        if let configuredHelper = ProcessInfo.processInfo.environment["FUJI_RECIPES_X100VI_HELPER"],
           FileManager.default.isExecutableFile(atPath: configuredHelper) {
            return configuredHelper
        }

        var developmentPaths: [String] = []
        let sourceDir = URL(fileURLWithPath: #file)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .path
        developmentPaths.append("\(sourceDir)/poc-x100vi-reader/x100vi_helper")

        // Preserve convenient local workflows, but only in a Debug build.
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                developmentPaths.append("\(dir)/x100vi_helper")
            }
        }
        developmentPaths.append(contentsOf: [
            "/usr/local/bin/x100vi_helper",
            "/opt/homebrew/bin/x100vi_helper",
        ])

        for path in developmentPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        #endif

        return nil
    }
}

// MARK: - JSON Numeric Bridging Helpers

/// Extract a UInt32 from JSONSerialization output, which decodes numbers as
/// `Int`/`NSNumber` rather than Swift unsigned types.
private func jsonUInt32(_ value: Any?) -> UInt32? {
    if let int = value as? Int { return UInt32(int) }
    if let num = value as? NSNumber { return num.uint32Value }
    if let str = value as? String, let int = UInt32(str) { return int }
    return nil
}

/// Extract an Int32 from JSONSerialization output.
private func jsonInt32(_ value: Any?) -> Int32? {
    if let int = value as? Int { return Int32(int) }
    if let num = value as? NSNumber { return num.int32Value }
    if let str = value as? String, let int = Int32(str) { return int }
    return nil
}

private func helperInteger(_ value: Any?) -> Int? {
    if let value = value as? Int { return value }
    if let value = value as? NSNumber { return value.intValue }
    if let value = value as? String { return Int(value) }
    return nil
}

/// The helper reports stable machine-readable connection failures. Keep their
/// interpretation separate from transport orchestration so callers receive a
/// recovery instruction without taking destructive action against macOS
/// services or replaying a camera mutation.
enum HelperConnectionFailure: Equatable {
    case cameraNotFound
    case interfaceUnavailable(transportCode: Int?)
    case sessionOpenFailed(code: Int?)
    case alreadyConnected
    case notConnected
    case unknown(error: String, code: Int?)

    var userActionableDescription: String {
        switch self {
        case .cameraNotFound:
            return "No Fuji X100VI was detected. Turn the camera on, reconnect its USB-C cable, and select USB RAW CONVERSION mode before trying again."
        case .interfaceUnavailable(let transportCode):
            let code = transportCode.map { " (\(formattedHelperCode($0)))" } ?? ""
            return "macOS could not claim the X100VI USB interface\(code). Another camera app or the system PTP service may be using it. Close camera-accessing apps, unplug and reconnect the camera, then try again."
        case .sessionOpenFailed(let code):
            let detail = code.map { " (\(formattedHelperCode($0)))" } ?? ""
            return "The X100VI did not complete its PTP session handshake\(detail). Power-cycle the camera or reconnect USB, then try again."
        case .alreadyConnected:
            return "The X100VI helper already has an active connection. Disconnect it before starting another connection."
        case .notConnected:
            return "The X100VI is no longer connected. Reconnect the camera before retrying."
        case .unknown(let error, let code):
            let detail = code.map { " (\(formattedHelperCode($0)))" } ?? ""
            return "The X100VI helper could not connect: \(error)\(detail). Check the USB connection and try again."
        }
    }
}

func helperConnectionFailure(in response: [String: Any]) -> HelperConnectionFailure {
    let error = (response["error"] as? String ?? "unknown error").lowercased()
    let transportCode = helperInteger(response["transport_code"])
    let code = (transportCode == 0 ? nil : transportCode) ?? helperInteger(response["code"])
    let normalizedError = error.hasPrefix("reconnect_")
        ? String(error.dropFirst("reconnect_".count))
        : error

    switch normalizedError {
    case "camera_not_found":
        return .cameraNotFound
    case "interface_claim_failed":
        return .interfaceUnavailable(transportCode: code)
    case "session_open_failed":
        return .sessionOpenFailed(code: code)
    case "already_connected":
        return .alreadyConnected
    case "not_connected":
        return .notConnected
    default:
        return .unknown(error: error, code: code)
    }
}

/// Turns the helper's structured retrieval state into user-facing evidence.
/// This intentionally distinguishes "no observed object" from "an object
/// existed but could not be identified/downloaded".
func conversionDeliveryEvidence(from response: [String: Any]) -> String? {
    guard let result = response["result"] as? [String: Any],
          let status = result["status"] as? String else { return nil }
    let diagnostics = result["diagnostics"] as? [String: Any]
    let newCount = helperInteger(diagnostics?["new_handle_count"]) ?? 0
    let inspectedCount = helperInteger(diagnostics?["inspected_object_count"]) ?? 0
    let candidate = result["candidate_name"] as? String

    switch status {
    case "no_new_object":
        return "The trigger was accepted, but no new PTP object was observed during polling. JPEG delivery is unverified."
    case "no_jpeg_candidate":
        return "The trigger was accepted and \(newCount) new object(s) appeared, but none identified itself as JPEG metadata. JPEG delivery is unverified."
    case "indeterminate_multiple_jpeg_candidates":
        return "The trigger was accepted, but \(inspectedCount) new object(s) produced multiple JPEG-like candidates. Nothing was downloaded automatically."
    case "candidate_not_downloaded":
        let label = candidate?.isEmpty == false ? " (\(candidate!))" : ""
        return "A new JPEG-like object\(label) was identified but its bytes could not be verified or saved. It was not deleted."
    case "indeterminate_no_baseline":
        return "No pre-trigger object inventory was available, so the helper will not select an existing camera object as a result."
    case "inventory_failed", "object_info_failed":
        return "The trigger may have been accepted, but retrieval evidence could not be collected (\(status)). No camera object was deleted."
    default:
        return nil
    }
}

func formattedHelperCode(_ code: Int) -> String {
    code >= 0
        ? String(format: "PTP 0x%04X (%d)", code, code)
        : "transport \(code)"
}

func transientSlotSelectionCode(in response: [String: Any]) -> Int? {
    guard let result = response["result"] as? [String: Any],
          result["failure_stage"] as? String == "slot_selection",
          let code = helperInteger(result["slot_select_rc"]) else {
        return nil
    }

    // DeviceBusy can clear after a fresh PTP session. Negative results are
    // helper/libusb transport failures; retrying a selector-only failure is
    // safe because no C-slot field has been written yet.
    guard code == 0x2019 || (code < 0 && code != -400) else { return nil }
    return code
}

func presetSlotFailureDetails(_ response: [String: Any]) -> String {
    let result = response["result"] as? [String: Any]
    let error = response["error"] as? String
        ?? result?["error"] as? String
        ?? "invalid preset slot response"
    guard let stage = result?["failure_stage"] as? String,
          let code = helperInteger(result?["slot_select_rc"]) else {
        return error
    }
    return "\(stage) failed (\(formattedHelperCode(code))): \(error)"
}

func presetPropertyReadFailure(in response: [String: Any]) -> String? {
    guard let result = response["result"] as? [String: Any],
          let properties = result["properties"] as? [String: [String: Any]] else {
        return nil
    }

    for key in properties.keys.sorted() {
        guard let code = helperInteger(properties[key]?["rc"]), code != 0 else { continue }
        return "\(key) read failed (\(formattedHelperCode(code)))"
    }
    return nil
}

/// Fuji's C-slot signed properties are transmitted as raw two-byte little-endian
/// values.  JSON exposes that raw UInt16 so reconstruct its Int16 bit pattern.
private func jsonPTPInt16(_ value: Any?) -> Int32? {
    guard let raw = jsonUInt32(value), raw <= UInt32(UInt16.max) else { return nil }
    return Int32(Int16(bitPattern: UInt16(raw)))
}

private func presetWriteWarnings(from result: [String: Any]) -> [String] {
    (result["warnings"] as? [[String: Any]])?.compactMap { warning in
        guard let property = warning["property"] as? String else { return nil }
        let responseCode = warning["response_code"] as? String
        return responseCode.map { "\(property): \($0)" } ?? property
    } ?? []
}

private func presetWriteFailureDetails(
    response: [String: Any],
    result: [String: Any]?
) -> String {
    let errors = (result?["errors"] as? [[String: Any]])?.compactMap { error -> String? in
        let stage = (error["stage"] as? String).map { "\($0): " } ?? ""
        let property = error["property"] as? String ?? error["key"] as? String ?? "unknown property"
        let raw = (error["requested_raw"] as? String).map { " requested \($0)" } ?? ""
        let rc = error["rc"].map { String(describing: $0) } ?? "unknown error"
        return "\(stage)\(property)\(raw): \(rc)"
    } ?? []
    if !errors.isEmpty { return errors.joined(separator: ", ") }
    if let error = response["error"] as? String { return error }
    if let error = result?["error"] as? String { return error }
    return "Helper write or readback verification failed"
}

/// The helper writes every C-slot setting as a two-byte payload. Validate the
/// bridge representation before issuing `D18C`, so an invalid app/client value
/// cannot select or partially mutate a slot.
private func validatePresetPayload(_ data: PTPClientPresetData) throws {
    guard (1...7).contains(data.slot) else {
        throw PTPError.invalidResponse("Preset slot must be 1–7")
    }

    let unsigned: [(UInt16, UInt32?)] = [
        (0xD18E, data.imageSize), (0xD18F, data.imageQuality),
        (0xD190, data.dynamicRange), (0xD192, data.filmSimulation),
        (0xD195, data.grainEffect), (0xD196, data.colorChrome),
        (0xD197, data.colorChromeFxBlue), (0xD198, data.smoothSkin),
        (0xD199, data.whiteBalance), (0xD19C, data.colorTemp),
        (0xD1A1, data.highIsoNr), (0xD1A3, data.longExpNr),
        (0xD1A4, data.colorSpace)
    ]
    for (property, value) in unsigned {
        if let value, value > UInt32(UInt16.max) {
            throw PTPError.invalidResponse(
                "C-slot property 0x\(String(property, radix: 16)) raw value \(value) exceeds UInt16"
            )
        }
    }

    let signed: [(UInt16, Int32?)] = [
        (0xD193, data.monoWarmCool), (0xD194, data.monoMagentaGreen),
        (0xD19A, data.wbShiftRed), (0xD19B, data.wbShiftBlue),
        (0xD19D, data.highlight), (0xD19E, data.shadow),
        (0xD19F, data.color), (0xD1A0, data.sharpness), (0xD1A2, data.clarity)
    ]
    for (property, value) in signed {
        if let value, !(Int32(Int16.min)...Int32(Int16.max)).contains(value) {
            throw PTPError.invalidResponse(
                "C-slot property 0x\(String(property, radix: 16)) raw signed value \(value) exceeds Int16"
            )
        }
    }
}


