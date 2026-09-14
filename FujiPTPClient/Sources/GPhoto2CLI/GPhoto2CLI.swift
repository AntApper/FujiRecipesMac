// GPhoto2CLI.swift
// Simple gphoto2 CLI wrapper for Fuji camera communication.
// This avoids all the libgphoto2 FFI issues by using the system gphoto2 binary.

import Foundation

/// Wrapper around the gphoto2 CLI tool.
public final class GPhoto2CLI: @unchecked Sendable {
    public init() {}
    
    /// Run a gphoto2 command and return stdout.
    public func run(_ args: [String]) throws -> String {
        let process = Process()
        guard let executableURL = Self.findExecutable() else {
            throw CLIError(commandFailed: args.joined(separator: " "), stderr: "gphoto2 binary not found in PATH")
        }
        process.executableURL = executableURL
        process.arguments = args
        
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        
        try process.run()
        process.waitUntilExit()
        
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
        
        guard process.terminationStatus == 0 else {
            throw CLIError(commandFailed: args.joined(separator: " "), stderr: stderr)
        }
        
        return String(data: stdoutData, encoding: .utf8) ?? ""
    }
    
    /// Run gphoto2 with arguments that output JSON.
    /// Locate the gphoto2 executable, preferring well-known Homebrew paths
    /// but falling back to PATH lookup.
    private static func findExecutable() -> URL? {
        let candidates = [
            "/opt/homebrew/bin/gphoto2",
            "/usr/local/bin/gphoto2",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let path = "\(dir)/gphoto2"
                if FileManager.default.isExecutableFile(atPath: path) {
                    return URL(fileURLWithPath: path)
                }
            }
        }
        return nil
    }

    public func runJSON(_ args: [String]) throws -> [String: Any] {
        let output = try run(args)
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CLIError.invalidJSON
        }
        return json
    }
    
    public struct CLIError: Error {
        public let commandFailed: String
        public let stderr: String
        
        public static let invalidJSON = CLIError(commandFailed: "", stderr: "Invalid JSON")
        
        public init(commandFailed: String, stderr: String) {
            self.commandFailed = commandFailed
            self.stderr = stderr
        }
    }
}
