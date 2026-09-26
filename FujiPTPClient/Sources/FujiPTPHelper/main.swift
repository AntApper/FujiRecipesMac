// main.swift
// FujiPTPHelper — standalone process that loads libgphoto2 via dlopen().
// Communicates with the main app via stdin/stdout line-delimited JSON.

import Foundation

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

// MARK: - Helpers

func writeStderr(_ string: String) {
    if let data = string.data(using: .utf8) {
        FileHandle.standardError.write(data)
    }
}

func writeStdout(_ string: String) {
    guard let data = (string + "\n").data(using: .utf8) else { return }
    stdoutStream.write(data)
}

let stdoutStream = FileHandle.standardOutput

/// Extract a UInt16 from JSONSerialization output (numbers decode as Int/NSNumber).
private func jsonUInt16(_ value: Any?) -> UInt16? {
    if let int = value as? Int { return UInt16(exactly: int) }
    if let num = value as? NSNumber { return num.uint16Value }
    return nil
}

/// Extract an Int32 from JSONSerialization output.
private func jsonInt32(_ value: Any?) -> Int32? {
    if let int = value as? Int { return Int32(exactly: int) }
    if let num = value as? NSNumber { return num.int32Value }
    return nil
}

/// Extract an Int from JSONSerialization output.
private func jsonInt(_ value: Any?) -> Int? {
    if let int = value as? Int { return int }
    if let num = value as? NSNumber { return num.intValue }
    return nil
}

// MARK: - Session

let session = PTPHelperSession()

// MARK: - Command Handler

@MainActor
func handleCommand(_ request: [String: Any]) -> PTPHelperResponse {
    writeStderr("[HELPER] handleCommand called\n")
    guard let id = request["id"] as? String else {
        return PTPHelperResponse(id: "error", success: false, result: nil, error: "missing_id")
    }

    guard let commandDict = request["command"] as? [String: Any],
          let entry = commandDict.first else {
        return PTPHelperResponse(id: id, success: false, result: nil, error: "missing_command")
    }
    let (commandName, paramsAny) = entry
    let params = paramsAny as? [String: Any] ?? [:]

    return executeCommand(commandName, params: params, requestID: id)
}

@MainActor
func executeCommand(_ name: String, params: [String: Any], requestID: String) -> PTPHelperResponse {
    switch name {
    // ── Connection ─────────────────────────────────────────────

    case "connect":
        let result = session.connect()
        return result == "ok"
            ? PTPHelperResponse(id: requestID, success: true, result: "ok", error: nil)
            : PTPHelperResponse(id: requestID, success: false, result: nil, error: result)

    case "disconnect":
        session.disconnect()
        return PTPHelperResponse(id: requestID, success: true, result: "ok", error: nil)

    case "isConnected":
        return PTPHelperResponse(
            id: requestID, success: true,
            result: session.isConnectedStatus(), error: nil
        )

    // ── Camera Info ────────────────────────────────────────────

    case "cameraInfo":
        if let info = session.getCameraInfo() {
            return PTPHelperResponse(id: requestID, success: true, result: info, error: nil)
        }
        return PTPHelperResponse(id: requestID, success: false, result: nil, error: "camera_info_failed")

    // ── Properties ─────────────────────────────────────────────

    case "readProperty":
        guard let code = jsonUInt16(params["code"]) else {
            return PTPHelperResponse(id: requestID, success: false, result: nil, error: "missing_code")
        }
        let result = session.readProperty(code: code)
        if result.hasPrefix("error:") {
            return PTPHelperResponse(id: requestID, success: false, result: nil, error: String(result.dropFirst(6)))
        }
        let value = result.hasPrefix("string:") ? String(result.dropFirst(7)) : result
        return PTPHelperResponse(id: requestID, success: true, result: value, error: nil)

    case "writeProperty":
        guard let code = jsonUInt16(params["code"]),
              let value = jsonInt32(params["value"]) else {
            return PTPHelperResponse(id: requestID, success: false, result: nil, error: "missing_args")
        }
        let result = session.writeProperty(code: code, value: value)
        return result == "ok"
            ? PTPHelperResponse(id: requestID, success: true, result: "ok", error: nil)
            : PTPHelperResponse(id: requestID, success: false, result: nil, error: result)

    // ── Preset Slots ───────────────────────────────────────────

    case "readPresetSlot":
        guard let index = jsonInt(params["index"]) else {
            return PTPHelperResponse(id: requestID, success: false, result: nil, error: "missing_index")
        }
        let result = session.readPresetSlot(index: index)
        if result.hasPrefix("error:") {
            return PTPHelperResponse(id: requestID, success: false, result: nil, error: String(result.dropFirst(6)))
        }
        let dataStr = result.hasPrefix("preset:") ? String(result.dropFirst(7)) : result
        return PTPHelperResponse(id: requestID, success: true, result: dataStr, error: nil)

    case "writePresetSlot":
        guard let index = jsonInt(params["index"]) else {
            return PTPHelperResponse(id: requestID, success: false, result: nil, error: "missing_index")
        }
        guard let dataDict = params["data"] as? [String: Any] else {
            return PTPHelperResponse(id: requestID, success: false, result: nil, error: "missing_data")
        }
        let presetData = PTPHelperPresetData(
            name: dataDict["name"] as? String ?? "",
            imageSize: dataDict["imageSize"] as? UInt32,
            imageQuality: dataDict["imageQuality"] as? UInt32,
            dynamicRange: dataDict["dynamicRange"] as? UInt32,
            filmSimulation: dataDict["filmSimulation"] as? UInt32,
            grainEffect: dataDict["grainEffect"] as? UInt32,
            colorChrome: dataDict["colorChrome"] as? UInt32,
            colorChromeFxBlue: dataDict["colorChromeFxBlue"] as? UInt32,
            smoothSkin: dataDict["smoothSkin"] as? UInt32,
            whiteBalance: dataDict["whiteBalance"] as? UInt32,
            wbShiftRed: dataDict["wbShiftRed"] as? Int32,
            wbShiftBlue: dataDict["wbShiftBlue"] as? Int32,
            colorTemp: dataDict["colorTemp"] as? UInt32,
            highlight: dataDict["highlight"] as? Int32,
            shadow: dataDict["shadow"] as? Int32,
            color: dataDict["color"] as? Int32,
            sharpness: dataDict["sharpness"] as? Int32,
            highIsoNr: dataDict["highIsoNr"] as? UInt32,
            clarity: dataDict["clarity"] as? Int32,
            longExpNr: dataDict["longExpNr"] as? UInt32,
            colorSpace: dataDict["colorSpace"] as? UInt32
        )
        let result = session.writePresetSlot(index: index, data: presetData)
        return result == "ok"
            ? PTPHelperResponse(id: requestID, success: true, result: "ok", error: nil)
            : PTPHelperResponse(id: requestID, success: false, result: nil, error: result)

    // ── Native Profile ─────────────────────────────────────────

    case "readNativeProfile":
        if let result = session.readNativeProfile() {
            let base64 = result.hasPrefix("profile:") ? String(result.dropFirst(8)) : result
            return PTPHelperResponse(id: requestID, success: true, result: base64, error: nil)
        }
        return PTPHelperResponse(id: requestID, success: false, result: nil, error: "read_profile_failed")

    // ── RAF Conversion ─────────────────────────────────────────

    case "convertRAF":
        guard let name = params["name"] as? String,
              let base64 = params["base64"] as? String else {
            return PTPHelperResponse(id: requestID, success: false, result: nil, error: "missing_args")
        }
        if let result = session.convertRAF(name: name, base64: base64) {
            if result.hasPrefix("jpeg:") {
                return PTPHelperResponse(id: requestID, success: true, result: String(result.dropFirst(5)), error: nil)
            } else if result.hasPrefix("error:") {
                return PTPHelperResponse(id: requestID, success: false, result: nil, error: String(result.dropFirst(6)))
            }
            return PTPHelperResponse(id: requestID, success: false, result: nil, error: result)
        }
        return PTPHelperResponse(id: requestID, success: false, result: nil, error: "convert_raf_failed")

    // ── Preview ────────────────────────────────────────────────

    case "capturePreview":
        if let result = session.capturePreview() {
            if result.hasPrefix("jpeg:") {
                return PTPHelperResponse(id: requestID, success: true, result: String(result.dropFirst(5)), error: nil)
            }
            return PTPHelperResponse(id: requestID, success: false, result: nil, error: result)
        }
        return PTPHelperResponse(id: requestID, success: false, result: nil, error: "capture_preview_failed")

    // ── Ping / Exit ────────────────────────────────────────────

    case "ping":
        return PTPHelperResponse(id: requestID, success: true, result: "ok", error: nil)

    case "exit":
        session.disconnect()
        exit(0)

    default:
        return PTPHelperResponse(id: requestID, success: false, result: nil, error: "unknown_command:\(name)")
    }
}

// MARK: - Main Loop

writeStderr("[HELPER] Starting main loop...\n")

// Read stdin line-by-line so the helper stays alive and can process many
// commands.  The previous `readDataToEndOfFile()` blocked forever while the
// parent kept the pipe open.
do {
    for try await rawLine in FileHandle.standardInput.bytes.lines {
        let line = rawLine.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !line.isEmpty else { continue }
        writeStderr("[HELPER] Line: \(line)\n")

        guard let requestData = line.data(using: String.Encoding.utf8),
              let request = try? JSONSerialization.jsonObject(with: requestData) as? [String: Any] else {
            let errorResponse = PTPHelperResponse(id: "error", success: false, result: nil, error: "invalid_json")
            if let json = try? JSONEncoder().encode(errorResponse),
               let str = String(data: json, encoding: .utf8) {
                writeStdout(str)
            }
            continue
        }

        let response = handleCommand(request)

        do {
            let encoded = try JSONEncoder().encode(response)
            if let json = String(data: encoded, encoding: .utf8) {
                writeStdout(json)
            }
        } catch {
            let err = PTPHelperResponse(id: "error", success: false, result: nil, error: "encoding_error")
            if let json = try? JSONEncoder().encode(err),
               let str = String(data: json, encoding: .utf8) {
                writeStdout(str)
            }
        }
    }
} catch {
    writeStderr("[HELPER] stdin read error: \(error)\n")
}

exit(0)
