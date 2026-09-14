/// White Balance mode values for PTP property 0x5005 / 0xD199.
public enum WhiteBalanceMode: UInt32, Codable, Sendable {
    case asShot = 0
    case auto = 2
    case daylight = 4
    case cloudy = 6
    case tungsten = 5  // Incandescent (maps to same PTP value as cloudy on Fuji; distinct raw for enum purposes)
    case fluorescent1 = 32769
    case fluorescent2 = 32770
    case fluorescent3 = 32771
    case shade = 32774
    case colorTemperature = 32775
    case ambiencePriority = 32801
    case underwater = 8

    /// PTP value actually used for this WB mode on Fuji cameras.
    /// Some Fuji modes share PTP values — tungsten maps to 6 (cloudy).
    public var actualPTPValue: UInt32 {
        if self == .tungsten { return 6 }
        return rawValue
    }

    public var displayName: String {
        switch self {
        case .asShot: return "As Shot"
        case .auto: return "Auto (AWB)"
        case .daylight: return "Daylight"
        case .cloudy: return "Cloudy"
        case .tungsten: return "Tungsten"
        case .fluorescent1: return "Fluorescent 1"
        case .fluorescent2: return "Fluorescent 2"
        case .fluorescent3: return "Fluorescent 3"
        case .shade: return "Shade"
        case .colorTemperature: return "Color Temperature"
        case .ambiencePriority: return "Ambience Priority"
        case .underwater: return "Underwater"
        }
    }
}
