import Foundation

/// A Fuji film simulation recipe with all settings parsed and PTP-mapped.
public struct Recipe: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let source: String
    public let sourceUrl: String?
    public let previewImageUrl: String?
    public let imageUrls: [String]
    public let date: Date?
    public let dateString: String?

    // Core settings
    public let filmSimulation: FilmSimulation?
    public let dynamicRange: DynamicRange?
    public let grainEffect: GrainEffect?
    public let colorChrome: EffectIntensity?
    public let colorChromeFxBlue: EffectIntensity?
    public let smoothSkin: EffectIntensity?

    // White balance
    public let whiteBalanceMode: WhiteBalanceMode?
    public let wbShiftRed: Int32?
    public let wbShiftBlue: Int32?
    public let colorTempK: UInt32?

    // Tone & sharpening
    public let highlight: Int32?
    public let shadow: Int32?
    public let color: Int32?
    public let sharpness: Int32?

    // Other
    public let highIsoNr: Int32?
    public let clarity: Int32?
    public let iso: String?  // "Auto, up to ISO 6400" etc.
    public let exposureCompensation: String?  // "0 to +2/3" etc.

    /// Raw scraped settings as key/value pairs (e.g. ["filmSimulation": "Reala Ace"]).
    public let settings: [String: String]?

    // Metadata
    public let sensorGeneration: String?
    public let compatibleCameras: [String]?
    public let tags: [String]?
    public let parseStatus: ParseStatus

    public enum ParseStatus: String, Codable, Sendable {
        case ok
        case needsReview
    }

    public init(
        id: String,
        name: String,
        source: String,
        sourceUrl: String?,
        previewImageUrl: String? = nil,
        imageUrls: [String]? = nil,
        date: Date? = nil,
        dateString: String? = nil,
        filmSimulation: FilmSimulation? = nil,
        dynamicRange: DynamicRange? = nil,
        grainEffect: GrainEffect? = nil,
        colorChrome: EffectIntensity? = nil,
        colorChromeFxBlue: EffectIntensity? = nil,
        smoothSkin: EffectIntensity? = nil,
        whiteBalanceMode: WhiteBalanceMode? = nil,
        wbShiftRed: Int32? = nil,
        wbShiftBlue: Int32? = nil,
        colorTempK: UInt32? = nil,
        highlight: Int32? = nil,
        shadow: Int32? = nil,
        color: Int32? = nil,
        sharpness: Int32? = nil,
        highIsoNr: Int32? = nil,
        clarity: Int32? = nil,
        iso: String? = nil,
        exposureCompensation: String? = nil,
        settings: [String: String]? = nil,
        sensorGeneration: String? = nil,
        compatibleCameras: [String]? = nil,
        tags: [String]? = nil,
        parseStatus: ParseStatus = .ok
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.sourceUrl = sourceUrl
        self.previewImageUrl = previewImageUrl
        self.imageUrls = imageUrls ?? []
        self.date = date
        self.dateString = dateString
        self.filmSimulation = filmSimulation
        self.dynamicRange = dynamicRange
        self.grainEffect = grainEffect
        self.colorChrome = colorChrome
        self.colorChromeFxBlue = colorChromeFxBlue
        self.smoothSkin = smoothSkin
        self.whiteBalanceMode = whiteBalanceMode
        self.wbShiftRed = wbShiftRed
        self.wbShiftBlue = wbShiftBlue
        self.colorTempK = colorTempK
        self.highlight = highlight
        self.shadow = shadow
        self.color = color
        self.sharpness = sharpness
        self.highIsoNr = highIsoNr
        self.clarity = clarity
        self.iso = iso
        self.exposureCompensation = exposureCompensation
        self.settings = settings
        self.sensorGeneration = sensorGeneration
        self.compatibleCameras = compatibleCameras
        self.tags = tags
        self.parseStatus = parseStatus
    }

    // Computed: whether this recipe has any unmapped settings
    public var needsProbe: Bool {
        // TODO: implement based on which settings have PTP mapping gaps
        false
    }

    /// Convenience: all settings that are writable to a camera preset slot.
    /// ISO and exposure compensation are stored as display strings only;
    /// clarity is included because it maps to property 0xD1A2.
    public var hasFullPTPMapped: Bool {
        filmSimulation != nil &&
        dynamicRange != nil &&
        grainEffect != nil &&
        whiteBalanceMode != nil &&
        highlight != nil &&
        shadow != nil &&
        color != nil &&
        sharpness != nil &&
        highIsoNr != nil &&
        clarity != nil
    }
}
