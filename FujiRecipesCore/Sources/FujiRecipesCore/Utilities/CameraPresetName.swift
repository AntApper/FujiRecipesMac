import Foundation

/// A camera-safe label for Fujifilm custom preset slots.
///
/// The camera has accepted a 15-character printable-ASCII `0xD18D` label and
/// rejected the app's 17-character label, even though its property readback
/// reserves a larger PTP string field. Use the proven-safe 15-character limit
/// until a hardware boundary test establishes whether 16 characters are valid.
/// The recipe title remains unchanged; this value is only the label stored on
/// camera.
public enum CameraPresetName {
    public static let maximumCharacterCount = 15

    /// Converts a library recipe title into the deterministic label sent to
    /// `0xD18D`. Unsupported punctuation is replaced with a space, repeated
    /// whitespace is collapsed, and the result is clipped on an ASCII boundary.
    public static func label(for recipeName: String) -> String {
        let normalized = recipeName.precomposedStringWithCompatibilityMapping
        let mapped = normalized.unicodeScalars.map { scalar -> Character in
            switch scalar.value {
            case 0x20...0x7E:
                return Character(String(scalar))
            case 0x00A0, 0x2018, 0x2019, 0x201A, 0x201B:
                return scalar.value == 0x00A0 ? " " : "'"
            case 0x2010...0x2015:
                return "-"
            default:
                return " "
            }
        }
        let collapsed = String(mapped)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return String(collapsed.prefix(maximumCharacterCount))
    }

    /// Standard PTP string bytes: count including the NUL, ASCII/UCS-2LE
    /// characters, and a terminating UCS-2 NUL. The input must be a validated
    /// camera label so its scalar and UTF-16 counts are identical.
    public static func ptpPayload(forCameraLabel label: String) -> Data {
        precondition(label.unicodeScalars.allSatisfy { $0.value >= 0x20 && $0.value <= 0x7E })
        precondition(label.count <= maximumCharacterCount)

        var bytes = [UInt8(label.count + 1)]
        for scalar in label.unicodeScalars {
            bytes.append(UInt8(scalar.value))
            bytes.append(0)
        }
        bytes.append(contentsOf: [0, 0])
        return Data(bytes)
    }
}
