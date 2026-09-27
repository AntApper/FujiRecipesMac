/// Grain effect values for active property 0xD023 and preset property 0xD195.
public enum GrainEffect: UInt32, Codable, Sendable {
    case off = 1
    case weakSmall = 2
    case strongSmall = 3
    case weakLarge = 4
    case strongLarge = 5

    /// The camera also stores 6 (Off, Small) and 7 (Off, Large) when grain is
    /// turned off in its own menu, and rejects both in a write with 0x201C.
    public init?(cameraValue: UInt32) {
        switch cameraValue {
        case 6, 7: self = .off
        default: self.init(rawValue: cameraValue)
        }
    }

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .weakSmall: return "Weak, Small"
        case .strongSmall: return "Strong, Small"
        case .weakLarge: return "Weak, Large"
        case .strongLarge: return "Strong, Large"
        }
    }
}
