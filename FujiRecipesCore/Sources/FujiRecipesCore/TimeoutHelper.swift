import Foundation

/// Error thrown when an operation exceeds its allotted time.
public struct TimeoutError: Error, LocalizedError {
    public let timeout: TimeInterval
    public init(_ timeout: TimeInterval) { self.timeout = timeout }
    public var errorDescription: String? { "Operation timed out after \(Int(timeout))s" }
}

/// Helper: run an async task with a timeout.
/// Used by both CameraManager and MacOSSession.
///
/// The operation is cancelled if it exceeds the timeout, ensuring no dangling work
/// and no double-resume of a continuation.
public func withTimeout<T: Sendable>(
    timeout: TimeInterval,
    operation: @Sendable @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw TimeoutError(timeout)
        }
        do {
            guard let result = try await group.next() else {
                group.cancelAll()
                throw TimeoutError(timeout)
            }
            // Cancel the losing task before leaving the group.  The previous
            // implementation drained it first, which meant a successful
            // operation still waited for the timeout sleeper to fire.
            group.cancelAll()
            return result
        } catch {
            group.cancelAll()
            throw error
        }
    }
}
