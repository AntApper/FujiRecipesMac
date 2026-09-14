/// Standard effect intensity enum (Color Chrome, Smooth Skin, etc.)
/// Used in preset properties (1=Off, 2=Weak, 3=Strong).
public enum EffectIntensity: UInt32, Codable, Sendable {
    case off = 1
    case weak = 2
    case strong = 3

    public var displayName: String {
        switch self {
        case .off: return "Off"
        case .weak: return "Weak"
        case .strong: return "Strong"
        }
    }
}
