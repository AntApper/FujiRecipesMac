/// Fuji Film Simulation modes mapped to their PTP uint32 values.
/// Source: FilmKit + libgphoto2 X-T5 dump, confirmed on X100VI via preset scan.
public enum FilmSimulation: UInt32, CaseIterable, Codable, Sendable {
    case provia = 1              // PROVIA/Standard
    case velvia = 2              // Velvia/Vivid
    case astia = 3               // ASTIA/Soft
    case proNegHi = 4            // PRO Neg.Hi
    case proNegStd = 5           // PRO Neg.Std
    case monochrome = 6          // Monochrome (B&W)
    case monochromeY = 7         // Monochrome + Yellow
    case monochromeR = 8         // Monochrome + Red
    case monochromeG = 9         // Monochrome + Green
    case sepia = 10              // Sepia
    case classicChrome = 11      // Classic Chrome
    case acros = 12              // ACROS
    case acrosY = 13             // ACROS + Yellow
    case acrosR = 14             // ACROS + Red
    case acrosG = 15             // ACROS + Green
    case eterna = 16             // ETERNA/Cinema
    case classicNegative = 17    // Classic Negative
    case eternaBb = 18           // ETERNA Bleach Bypass
    case nostalgicNegative = 19  // Nostalgic Negative (X-Trans V only)
    case realaAce = 20           // Reala Ace (X-Trans V only)

    // Human-readable display name
    public var displayName: String {
        switch self {
        case .provia: return "PROVIA/Standard"
        case .velvia: return "Velvia/Vivid"
        case .astia: return "ASTIA/Soft"
        case .proNegHi: return "PRO Neg.Hi"
        case .proNegStd: return "PRO Neg.Std"
        case .monochrome: return "Monochrome"
        case .monochromeY: return "Monochrome + Yellow"
        case .monochromeR: return "Monochrome + Red"
        case .monochromeG: return "Monochrome + Green"
        case .sepia: return "Sepia"
        case .classicChrome: return "Classic Chrome"
        case .acros: return "ACROS"
        case .acrosY: return "ACROS + Yellow"
        case .acrosR: return "ACROS + Red"
        case .acrosG: return "ACROS + Green"
        case .eterna: return "ETERNA/Cinema"
        case .classicNegative: return "Classic Negative"
        case .eternaBb: return "ETERNA Bleach Bypass"
        case .nostalgicNegative: return "Nostalgic Negative"
        case .realaAce: return "Reala Ace"
        }
    }

    /// Whether this film sim is exclusive to X-Trans V+ cameras.
    public var isXTransVOnly: Bool {
        self == .nostalgicNegative || self == .realaAce
    }
}
