import Foundation

/// Arrow-key movement through items laid out row by row, `columns` per row.
public enum GridNavigation {
    public enum Move: Sendable {
        case left, right, up, down
    }

    public static func columnCount(width: Double, minimum: Double, spacing: Double) -> Int {
        max(1, Int((width + spacing) / (minimum + spacing)))
    }

    /// Down into a shorter last row lands on its last item.
    public static func index(from index: Int, move: Move, count: Int, columns: Int) -> Int {
        let columns = max(1, columns)
        switch move {
        case .left:
            return max(index - 1, 0)
        case .right:
            return min(index + 1, count - 1)
        case .up:
            return index >= columns ? index - columns : index
        case .down:
            if index + columns < count { return index + columns }
            let lastRowStart = (count - 1) / columns * columns
            return index < lastRowStart ? count - 1 : index
        }
    }
}
