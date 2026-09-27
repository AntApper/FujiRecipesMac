import Foundation

/// White balance codes for PTP property 0x5005 / 0xD199, in the order of the
/// X100VI's white balance menu.
public enum WhiteBalanceMode: UInt32, CaseIterable, Codable, Sendable {
    case autoWhitePriority = 0x8020
    case auto = 0x0002
    case ambiencePriority = 0x8021
    case custom1 = 0x8008
    case custom2 = 0x8009
    case custom3 = 0x800A
    case colorTemperature = 0x8007
    case daylight = 0x0004
    case shade = 0x8006
    case fluorescent1 = 0x8001
    case fluorescent2 = 0x8002
    case fluorescent3 = 0x8003
    case incandescent = 0x0006
    case underwater = 0x0008
    case asShot = 0

    /// The X100VI (firmware 1.31) accepts exactly these for a C slot. It
    /// rejects As Shot, which stays only so drafts saved with it still load.
    public static let cameraModes: [WhiteBalanceMode] = allCases.filter { $0 != .asShot }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(UInt32.self)
        // 5 is the retired Tungsten case, which wrote Incandescent's 6 to the camera.
        if raw == 5 {
            self = .incandescent
            return
        }
        guard let mode = WhiteBalanceMode(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot initialize WhiteBalanceMode from invalid UInt32 value \(raw)"
            )
        }
        self = mode
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var displayName: String {
        switch self {
        case .autoWhitePriority: return "White Priority"
        case .auto: return "Auto (AWB)"
        case .ambiencePriority: return "Ambience Priority"
        case .custom1: return "Custom 1"
        case .custom2: return "Custom 2"
        case .custom3: return "Custom 3"
        case .colorTemperature: return "Color Temperature"
        case .daylight: return "Daylight"
        case .shade: return "Shade"
        case .fluorescent1: return "Fluorescent 1"
        case .fluorescent2: return "Fluorescent 2"
        case .fluorescent3: return "Fluorescent 3"
        case .incandescent: return "Incandescent"
        case .underwater: return "Underwater"
        case .asShot: return "As Shot"
        }
    }
}
