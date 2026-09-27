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

    /// Creates a customized copy of this recipe ready to be customized and saved into My Recipes.
    public func duplicated(name customName: String? = nil, source customSource: String? = nil) -> Recipe {
        let baseName = name.isEmpty ? "Recipe" : name
        let targetName = customName ?? "\(baseName) (Custom)"
        let targetSource = customSource ?? "Customized from \(baseName)"
        var copiedSettings = settings ?? [:]
        copiedSettings["source"] = targetSource

        return Recipe(
            id: "custom-\(UUID().uuidString.lowercased())",
            name: targetName,
            source: targetSource,
            sourceUrl: sourceUrl,
            previewImageUrl: previewImageUrl,
            imageUrls: imageUrls,
            date: Date(),
            dateString: nil,
            filmSimulation: filmSimulation ?? .provia,
            dynamicRange: dynamicRange ?? .dr100,
            grainEffect: grainEffect ?? .off,
            colorChrome: colorChrome,
            colorChromeFxBlue: colorChromeFxBlue,
            smoothSkin: smoothSkin,
            whiteBalanceMode: whiteBalanceMode ?? .auto,
            wbShiftRed: wbShiftRed ?? 0,
            wbShiftBlue: wbShiftBlue ?? 0,
            colorTempK: colorTempK ?? (whiteBalanceMode == .colorTemperature ? 5_600 : nil),
            highlight: highlight ?? 0,
            shadow: shadow ?? 0,
            color: color ?? 0,
            sharpness: sharpness ?? 0,
            highIsoNr: highIsoNr ?? 0,
            clarity: clarity ?? 0,
            iso: iso,
            exposureCompensation: exposureCompensation,
            settings: copiedSettings,
            sensorGeneration: sensorGeneration ?? "X-Trans V",
            compatibleCameras: compatibleCameras ?? ["X100VI"],
            tags: ["My Recipes"],
            parseStatus: .ok
        )
    }

    /// Returns a new Recipe instance with the specified settings updated.
    public func mutating(
        name: String? = nil,
        source: String? = nil,
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
        clarity: Int32? = nil
    ) -> Recipe {
        var newSettings = settings ?? [:]
        if let sim = filmSimulation ?? self.filmSimulation { newSettings["filmSimulation"] = sim.displayName }
        if let dr = dynamicRange ?? self.dynamicRange { newSettings["dynamicRange"] = dr.displayName }
        if let grain = grainEffect ?? self.grainEffect { newSettings["grainEffect"] = grain.displayName }
        if let wb = whiteBalanceMode ?? self.whiteBalanceMode { newSettings["whiteBalance"] = wb.displayName }
        if let h = highlight ?? self.highlight { newSettings["highlight"] = h > 0 ? "+\(h)" : "\(h)" }
        if let s = shadow ?? self.shadow { newSettings["shadow"] = s > 0 ? "+\(s)" : "\(s)" }
        if let c = color ?? self.color { newSettings["color"] = c > 0 ? "+\(c)" : "\(c)" }
        if let sh = sharpness ?? self.sharpness { newSettings["sharpness"] = sh > 0 ? "+\(sh)" : "\(sh)" }
        if let nr = highIsoNr ?? self.highIsoNr { newSettings["highIsoNr"] = nr > 0 ? "+\(nr)" : "\(nr)" }
        if let cl = clarity ?? self.clarity { newSettings["clarity"] = cl > 0 ? "+\(cl)" : "\(cl)" }

        let resolvedWB = whiteBalanceMode ?? self.whiteBalanceMode
        let resolvedKelvin = colorTempK ?? self.colorTempK

        return Recipe(
            id: id,
            name: name ?? self.name,
            source: source ?? self.source,
            sourceUrl: sourceUrl,
            previewImageUrl: previewImageUrl,
            imageUrls: imageUrls,
            date: date,
            dateString: dateString,
            filmSimulation: filmSimulation ?? self.filmSimulation,
            dynamicRange: dynamicRange ?? self.dynamicRange,
            grainEffect: grainEffect ?? self.grainEffect,
            colorChrome: colorChrome ?? self.colorChrome,
            colorChromeFxBlue: colorChromeFxBlue ?? self.colorChromeFxBlue,
            smoothSkin: smoothSkin ?? self.smoothSkin,
            whiteBalanceMode: resolvedWB,
            wbShiftRed: wbShiftRed ?? self.wbShiftRed,
            wbShiftBlue: wbShiftBlue ?? self.wbShiftBlue,
            colorTempK: resolvedWB == .colorTemperature ? (resolvedKelvin ?? 5_600) : resolvedKelvin,
            highlight: highlight ?? self.highlight,
            shadow: shadow ?? self.shadow,
            color: color ?? self.color,
            sharpness: sharpness ?? self.sharpness,
            highIsoNr: highIsoNr ?? self.highIsoNr,
            clarity: clarity ?? self.clarity,
            iso: iso,
            exposureCompensation: exposureCompensation,
            settings: newSettings,
            sensorGeneration: sensorGeneration,
            compatibleCameras: compatibleCameras,
            tags: tags,
            parseStatus: parseStatus
        )
    }
}

#if canImport(CoreTransferable) && canImport(UniformTypeIdentifiers)
import CoreTransferable
import UniformTypeIdentifiers

@available(macOS 13.0, iOS 16.0, *)
public extension UTType {
    static var fujiRecipe: UTType {
        UTType(exportedAs: "com.ant.fuji-recipes.recipe", conformingTo: .json)
    }
}

@available(macOS 13.0, iOS 16.0, *)
extension Recipe: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .fujiRecipe)
        CodableRepresentation(contentType: .json)
        ProxyRepresentation(exporting: \.id)
    }
}
#endif

