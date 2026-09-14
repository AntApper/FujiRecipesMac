/// Grain effect values for active property 0xD023 and preset property 0xD195.
public enum GrainEffect: UInt32, Codable, Sendable {
    case off = 1
    case weakSmall = 2
    case strongSmall = 3
    case weakLarge = 4
    case strongLarge = 5

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
