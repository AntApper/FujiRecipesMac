import Foundation

// MARK: - JSON Data Model

/// Top-level structure of `recipes-data.json`.
public struct RecipesData: Codable, Sendable {
    public let version: String
    public let exportDate: String
    public let camera: CameraInfo
    public let filmSimulationEnum: [String: Int]
    public let wbModeEnum: [String: Int]
    public let dynamicRangeEnum: [String: Int]
    public let grainEffectEnum: [String: Int]
    public let activeProperties: [String: PropertyInfo]
    public let recipes: [RecipeJSON]
}

public struct CameraInfo: Codable, Sendable {
    public let model: String
    public let sensorGeneration: String
}

public struct PropertyInfo: Codable, Sendable {
    public let property: String
    public let type: String
    public let description: String
}

public struct RecipeJSON: Codable, Sendable {
    public let id: String
    public let name: String
    /// Attribution carried through from the scraped source when available.
    public let source: String?
    public let sensorGeneration: String
    public let filmSimulation: String?
    public let filmSimEnum: Int?
    public let settings: [String: String]
    public let ptpSettings: [String: Double]
    public let presetSettings: [String: Double]
    public let sourceUrl: String?
    public let previewImageUrl: String?
    public let imageUrls: [String]?
    public let date: String?
    public let compatibleCameras: [String]?
    /// Source-provided keywords. They are not inferred by the app.
    public let tags: [String]?

    public init(
        id: String,
        name: String,
        source: String? = nil,
        sensorGeneration: String,
        filmSimulation: String?,
        filmSimEnum: Int?,
        settings: [String: String],
        ptpSettings: [String: Double],
        presetSettings: [String: Double],
        sourceUrl: String?,
        previewImageUrl: String?,
        imageUrls: [String]?,
        date: String?,
        compatibleCameras: [String]?,
        tags: [String]? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.sensorGeneration = sensorGeneration
        self.filmSimulation = filmSimulation
        self.filmSimEnum = filmSimEnum
        self.settings = settings
        self.ptpSettings = ptpSettings
        self.presetSettings = presetSettings
        self.sourceUrl = sourceUrl
        self.previewImageUrl = previewImageUrl
        self.imageUrls = imageUrls
        self.date = date
        self.compatibleCameras = compatibleCameras
        self.tags = tags
    }
}

// MARK: - Recipe Loader

/// Shared recipe loading logic.  Both the macOS and iOS app targets parse
/// the same `recipes-data.json` schema, so the parsing code lives here.
public enum RecipeLoader {
    /// Load recipes from `recipes-data.json` in the given bundle.
    /// - Returns: Recipes sorted by film-simulation display name, then recipe name.
    public static func loadRecipes(from bundle: Bundle) throws -> [Recipe] {
        guard let url = bundle.url(forResource: "recipes-data", withExtension: "json") else {
            throw RecipeLoaderError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        let json = try JSONDecoder().decode(RecipesData.self, from: data)

        let parsed = json.recipes
            .filter(shouldIncludeInX100VICatalog)
            .map(recipe(from:))

        return parsed.sorted { lhs, rhs in
            let lhsName = lhs.filmSimulation?.displayName.lowercased() ?? ""
            let rhsName = rhs.filmSimulation?.displayName.lowercased() ?? ""
            if lhsName != rhsName { return lhsName < rhsName }
            return lhs.name.lowercased() < rhs.name.lowercased()
        }
    }

    /// Converts one normalized source record into the app's UI-level recipe.
    /// `presetSettings` are raw C-slot values, so decode them before passing
    /// the result to `CSlotPresetEncoder` for a future write.
    static func recipe(from jsonRecipe: RecipeJSON) -> Recipe {
        let filmSim = jsonRecipe.filmSimEnum.flatMap { FilmSimulation(rawValue: UInt32($0)) }
        let dr = jsonRecipe.presetSettings["dynamicRange"].flatMap { DynamicRange(rawValue: UInt32($0)) }
        let grain = jsonRecipe.presetSettings["grainEffect"].flatMap { GrainEffect(rawValue: UInt32($0)) }
        let wb = (jsonRecipe.ptpSettings["whiteBalance"] ?? jsonRecipe.presetSettings["whiteBalance"])
            .flatMap { WhiteBalanceMode(rawValue: UInt32($0)) }
        let colorTemp = resolveColorTemperature(from: jsonRecipe, wb: wb)

        return Recipe(
            id: jsonRecipe.id,
            name: jsonRecipe.name,
            source: jsonRecipe.source?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Fuji X Weekly",
            sourceUrl: jsonRecipe.sourceUrl,
            previewImageUrl: jsonRecipe.previewImageUrl,
            imageUrls: jsonRecipe.imageUrls,
            date: date(from: jsonRecipe.date),
            dateString: jsonRecipe.date,
            filmSimulation: filmSim,
            dynamicRange: dr,
            grainEffect: grain,
            colorChrome: jsonRecipe.presetSettings["colorChromeEffect"].flatMap { EffectIntensity(rawValue: UInt32($0)) },
            colorChromeFxBlue: jsonRecipe.presetSettings["colorChromeFxBlue"].flatMap { EffectIntensity(rawValue: UInt32($0)) },
            smoothSkin: jsonRecipe.presetSettings["smoothSkin"].flatMap { EffectIntensity(rawValue: UInt32($0)) },
            whiteBalanceMode: wb,
            wbShiftRed: jsonRecipe.presetSettings["wbShiftRed"]?.int32Value,
            wbShiftBlue: jsonRecipe.presetSettings["wbShiftBlue"]?.int32Value,
            colorTempK: colorTemp,
            highlight: CSlotPresetEncoder.uiTone(from: jsonRecipe.presetSettings["highlightTone"]?.int32Value),
            shadow: CSlotPresetEncoder.uiTone(from: jsonRecipe.presetSettings["shadowTone"]?.int32Value),
            color: CSlotPresetEncoder.uiTone(from: jsonRecipe.presetSettings["color"]?.int32Value),
            sharpness: CSlotPresetEncoder.uiTone(from: jsonRecipe.presetSettings["sharpness"]?.int32Value),
            highIsoNr: CSlotPresetEncoder.uiHighIsoNR(
                from: jsonRecipe.presetSettings["highIsoNr"].flatMap { UInt32(exactly: $0) }
            ),
            clarity: CSlotPresetEncoder.uiTone(from: jsonRecipe.presetSettings["clarity"]?.int32Value),
            iso: jsonRecipe.settings["iso"],
            exposureCompensation: jsonRecipe.settings["exposureCompensation"],
            settings: jsonRecipe.settings,
            sensorGeneration: jsonRecipe.sensorGeneration,
            compatibleCameras: jsonRecipe.compatibleCameras,
            tags: jsonRecipe.tags,
            parseStatus: .ok,
            sourceRawPreset: halfStepRawPreset(from: jsonRecipe.presetSettings)
        )
    }

    /// Whole UI steps round-trip through `uiTone` and `rawTenths`. Half steps
    /// such as `+0.5` (raw `5`) and `-1.5` (raw `-15`) do not, so keep the
    /// original tenths for the encoder's raw-preset path.
    static func halfStepRawPreset(from preset: [String: Double]) -> LoadoutRawPresetState? {
        func fractionalTenths(_ key: String) -> Int32? {
            guard let value = preset[key] else { return nil }
            let raw = Int32(value.rounded(.towardZero))
            guard raw % 10 != 0 else { return nil }
            return raw
        }

        let highlight = fractionalTenths("highlightTone")
        let shadow = fractionalTenths("shadowTone")
        let color = fractionalTenths("color")
        let sharpness = fractionalTenths("sharpness")
        let clarity = fractionalTenths("clarity")
        guard highlight != nil || shadow != nil || color != nil || sharpness != nil || clarity != nil else {
            return nil
        }
        return LoadoutRawPresetState(
            highlight: highlight,
            shadow: shadow,
            color: color,
            sharpness: sharpness,
            clarity: clarity
        )
    }

    /// X-Trans V recipes without compatibility metadata predate the normalized
    /// camera list and are assumed to support the X100VI. A populated list is
    /// authoritative and must explicitly include the target camera.
    static func shouldIncludeInX100VICatalog(_ recipe: RecipeJSON) -> Bool {
        guard recipe.sensorGeneration == "X-Trans V" else { return false }
        guard let compatibleCameras = recipe.compatibleCameras, !compatibleCameras.isEmpty else {
            return true
        }
        return compatibleCameras.contains("X100VI")
    }

    private static func date(from string: String?) -> Date? {
        guard let string else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.date(from: string)
    }

    /// Resolves the color temperature in Kelvin for a recipe:
    /// 1. Checks `presetSettings["colorTemp"]`
    /// 2. Checks `ptpSettings["colorTemp"]`
    /// 3. Extracts Kelvin from `settings["whiteBalance"]` matching `(\d{4,5})\s*K`
    /// 4. Defaults to 5500 if white balance is `.colorTemperature`
    static func resolveColorTemperature(from jsonRecipe: RecipeJSON, wb: WhiteBalanceMode?) -> UInt32? {
        if let temp = jsonRecipe.presetSettings["colorTemp"].flatMap({ UInt32(exactly: $0) ?? ($0 >= 0 ? UInt32($0) : nil) }) {
            return temp
        }
        if let temp = jsonRecipe.ptpSettings["colorTemp"].flatMap({ UInt32(exactly: $0) ?? ($0 >= 0 ? UInt32($0) : nil) }) {
            return temp
        }
        if let wbSetting = jsonRecipe.settings["whiteBalance"],
           let parsed = extractKelvin(from: wbSetting) {
            return parsed
        }
        if wb == .colorTemperature {
            return 5500
        }
        return nil
    }

    /// Parses a 4-5 digit Kelvin value from a white balance description string (e.g. "10000K, +9 Red", "5600 K").
    static func extractKelvin(from string: String) -> UInt32? {
        let pattern = #"(\d{4,5})\s*K"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(string.startIndex..<string.endIndex, in: string)
        guard let match = regex.firstMatch(in: string, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return UInt32(String(string[captureRange]))
    }
}

// MARK: - Errors

public enum RecipeLoaderError: Error, LocalizedError {
    case fileNotFound

    public var errorDescription: String? {
        switch self {
        case .fileNotFound:
            return "recipes-data.json was not found in the app bundle."
        }
    }
}

// MARK: - Numeric Helpers

extension Double {
    public var intValue: Int { Int(self) }
    public var int32Value: Int32 { Int32(self) }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
