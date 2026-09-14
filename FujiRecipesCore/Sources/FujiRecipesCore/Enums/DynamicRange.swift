/// Dynamic Range modes for active property 0xD007.
public enum DynamicRange: UInt32, Codable, Sendable {
    case auto = 0xFFFF  // 65535
    case dr100 = 100
    case dr200 = 200
    case dr400 = 400

    public var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .dr100: return "DR100"
        case .dr200: return "DR200"
        case .dr400: return "DR400"
        }
    }
}
