import Foundation

/// A short clause explaining why stored data couldn't be read, such as
/// `filmSimulation: Cannot initialize FilmSimulation from invalid UInt32 value 9999`.
func storedDataFailureReason(_ error: Error) -> String {
    let reason: String
    switch error {
    case DecodingError.typeMismatch(_, let context),
         DecodingError.valueNotFound(_, let context),
         DecodingError.dataCorrupted(let context):
        reason = describe(context, codingPath: context.codingPath)
    case DecodingError.keyNotFound(let key, let context):
        reason = describe(context, codingPath: context.codingPath + [key])
    default:
        reason = error.localizedDescription
    }
    return reasonClause(reason)
}

/// Reasons are shown inside parentheses in the middle of a sentence.
func reasonClause(_ reason: String) -> String {
    reason.hasSuffix(".") ? String(reason.dropLast()) : reason
}

/// Names the copy of unreadable data, for example `20260927-012400`.
func storedDataRecoveryTimestamp(_ date: Date = Date()) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyyMMdd-HHmmss"
    return formatter.string(from: date)
}

private func describe(_ context: DecodingError.Context, codingPath: [any CodingKey]) -> String {
    guard let key = codingPath.last else { return context.debugDescription }
    return "\(key.stringValue): \(context.debugDescription)"
}
