import Foundation

/// Values retrieved from UserDefaults are valid property-list objects, but an
/// older or damaged value may not be the JSON Data these stores expect.
func storedJSONData(_ value: Any) throws -> Data {
    guard let data = value as? Data else {
        throw DecodingError.typeMismatch(Data.self, .init(
            codingPath: [],
            debugDescription: "Expected JSON data in the app’s preferences"
        ))
    }
    return data
}

/// Keep the original value before replacing it with recovered state. This also
/// preserves incorrectly typed preferences, not just malformed JSON bytes.
func backUpUnreadableStoredValue(_ value: Any, forKey key: String, in defaults: UserDefaults) -> String {
    let baseKey = "\(key).unreadable-\(storedDataRecoveryTimestamp())"
    var attempt = 1
    var backupKey = baseKey
    while defaults.object(forKey: backupKey) != nil {
        attempt += 1
        backupKey = "\(baseKey)-\(attempt)"
    }
    defaults.set(value, forKey: backupKey)
    return backupKey
}

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
