// MacOS+PTPBridge.swift
// Bridges MacOSSession to FujiPTPHelper via Process pipes.
// The helper process handles all dlopen() calls, avoiding the dyld4 deadlock.

import Foundation
import FujiRecipesCore
import PTPClient

// MARK: - PTPHelper Bridge

final class PTPHelperBridge: @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.fujirecipes.ptphelper")
    private var process: Process?
    private var stdin: FileHandle?
    private var stdout: FileHandle?
    private var outputSource: DispatchSourceRead?
    private var responseID = 0
    private var pendingResponse: String? = nil
    private var pendingResult: String? = nil
    private var pendingError: String? = nil
    private let lock = NSLock()

    init() {
        queue.async { [weak self] in
            self?.launch()
        }
    }

    deinit {
        queue.async { [weak self] in
            self?.outputSource?.cancel()
            self?.process?.terminate()
            try? self?.stdin?.close()
            try? self?.stdout?.close()
        }
    }

    private func launch() {
        process?.terminate()
        try? stdin?.close()
        try? stdout?.close()
        outputSource?.cancel()
        outputSource = nil

        guard let helperURL = Self.findHelperExecutable() else { return }

        let process = Process()
        process.executableURL = helperURL

        let stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe.fileHandleForReading
        process.standardOutput = stdoutPipe.fileHandleForWriting

        do { try process.run() } catch {}

        stdin = stdinPipe.fileHandleForWriting
        try? stdinPipe.fileHandleForReading.close()
        stdout = stdoutPipe.fileHandleForReading
        try? stdoutPipe.fileHandleForWriting.close()

        // Use DispatchSourceRead for non-blocking stdout
        let source = DispatchSource.makeReadSource(fileDescriptor: stdout!.fileDescriptor, queue: queue)
        source.setEventHandler { [weak self] in
            guard let self = self, let stdout = self.stdout else { return }
            let data = stdout.availableData
            if data.count > 0, let text = String(data: data, encoding: .utf8) {
                self.processOutput(text)
            }
        }
        source.resume()
        outputSource = source
    }

    func sendCommand(_ command: String, parameters: [String: Any] = [:], timeout: TimeInterval = 15.0) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: PTPError.platformError("Bridge destroyed"))
                    return
                }

                if self.process?.isRunning != true {
                    self.launch()
                }

                guard let stdin = self.stdin else {
                    continuation.resume(throwing: PTPError.platformError("No stdin pipe"))
                    return
                }

                self.responseID += 1
                let id = String(self.responseID)

                let request: [String: Any] = [
                    "id": id,
                    "command": [command: parameters]
                ]

                guard let json = try? JSONSerialization.data(withJSONObject: request),
                      let line = String(data: json, encoding: .utf8) else {
                    continuation.resume(throwing: PTPError.platformError("Encode failed"))
                    return
                }

                let writeData = (line + "\n").data(using: .utf8)!
                do { try stdin.write(contentsOf: writeData) }
                catch {
                    continuation.resume(throwing: PTPError.platformError("Write failed: \(error.localizedDescription)"))
                    return
                }

                // Set up timeout
                let deadline = Date().addingTimeInterval(timeout)
                while Date() < deadline {
                    self.lock.lock()
                    let got = (self.pendingResponse == id)
                    if got {
                        let result = self.pendingResult
                        let err = self.pendingError
                        self.pendingResponse = nil
                        self.pendingResult = nil
                        self.pendingError = nil
                        self.lock.unlock()
                        if let error = err {
                            continuation.resume(throwing: PTPError.connectionFailed(error))
                        } else {
                            continuation.resume(returning: result ?? "ok")
                        }
                        return
                    }
                    self.lock.unlock()
                    Thread.sleep(forTimeInterval: 0.005)
                }

                continuation.resume(throwing: PTPError.connectionFailed("Helper timed out after \(Int(timeout))s"))
            }
        }
    }

    private func processOutput(_ text: String) {
        var buffer = text
        while let newlineRange = buffer.rangeOfCharacter(from: CharacterSet.newlines) {
            let line = String(buffer[..<newlineRange.lowerBound])
            buffer.removeSubrange(...newlineRange.lowerBound)
            handleLine(line)
        }
    }

    private func handleLine(_ line: String) {
        guard let data = line.data(using: .utf8) else { return }
        guard let response = try? JSONDecoder().decode(PTPHelperResponse.self, from: data) else { return }

        let id = response.id
        let isSuccess = response.success
        let result = response.result ?? "ok"
        let errorMsg = !isSuccess ? (response.error ?? "unknown") : nil

        lock.lock()
        pendingResponse = id
        pendingResult = result
        pendingError = errorMsg
        lock.unlock()
    }

    static func findHelperExecutable() -> URL? {
        // Try app bundle Contents/MacOS
        let bundlePath = Bundle.main.bundlePath
        do {
            let url = URL(fileURLWithPath: bundlePath)
                .appendingPathComponent("Contents/MacOS")
            let contents = try FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles)
            if let helper = contents.first(where: { $0.lastPathComponent == "FujiPTPHelper" }) {
                return helper
            }
        } catch {}

        // Try package build dir
        let cwd = FileManager.default.currentDirectoryPath
        for build in ["debug", "release"] {
            let path = "\(cwd)/.build/\(build)/FujiPTPHelper"
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }

        return nil
    }
}

// MARK: - Response Type

private struct PTPHelperResponse: Codable {
    let id: String
    let success: Bool
    let result: String?
    let error: String?
}
