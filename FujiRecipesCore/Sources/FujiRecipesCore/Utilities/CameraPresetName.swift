import Foundation

/// A camera-safe label for Fujifilm custom preset slots.
///
/// The X100VI (firmware 1.31) accepts a `0xD18D` name of 0 to 25 printable
/// ASCII characters (0x20...0x7E) and rejects a longer or non-ASCII name with
/// 0x201C. The recipe title remains unchanged; this value is only the label
/// stored on camera.
public enum CameraPresetName {
    public static let maximumCharacterCount = 25

    /// Folds a name into the label sent to `0xD18D`: ASCII transliteration,
    /// collapsed whitespace, and a cut on a word boundary. A name with nothing
    /// printable becomes the slot's own label, such as "C3".
    public static func label(for name: String, slot: Int) -> String {
        let folded = name.applyingTransform(StringTransform("Any-Latin; Latin-ASCII"), reverse: false) ?? name
        let printable = String(String.UnicodeScalarView(folded.unicodeScalars.map {
            (0x20...0x7E).contains($0.value) ? $0 : " "
        }))
        let words = printable.split(separator: " ")
        let label = fit(words)
        return label.isEmpty ? "C\(slot)" : label
    }

    /// Standard PTP string bytes for `label(for:slot:)`: count including the
    /// NUL, UCS-2LE characters, and a terminating UCS-2 NUL.
    public static func ptpPayload(for name: String, slot: Int) -> Data {
        let label = label(for: name, slot: slot)
        var bytes = [UInt8(label.count + 1)]
        for scalar in label.unicodeScalars {
            bytes.append(UInt8(scalar.value))
            bytes.append(0)
        }
        bytes.append(contentsOf: [0, 0])
        return Data(bytes)
    }

    private static func fit(_ words: [Substring]) -> String {
        let joined = words.joined(separator: " ")
        guard joined.count > maximumCharacterCount else { return joined }
        guard words[0].count <= maximumCharacterCount else {
            return String(words[0].prefix(maximumCharacterCount))
        }

        var kept: [Substring] = []
        var length = 0
        for word in words {
            let next = kept.isEmpty ? word.count : length + 1 + word.count
            guard next <= maximumCharacterCount else { break }
            kept.append(word)
            length = next
        }
        while let last = kept.last, !last.contains(where: { $0.isLetter || $0.isNumber }) {
            kept.removeLast()
        }
        return kept.joined(separator: " ")
    }
}
