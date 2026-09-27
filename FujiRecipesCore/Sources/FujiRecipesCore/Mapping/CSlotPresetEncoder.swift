import Foundation

/// Converts app-level recipe values into X100VI C-slot property payloads.
///
/// `PTPClientPresetData` represents the raw values accepted by `0xD18E...0xD1A4`,
/// rather than active-shooting property values. In particular, tone-family values
/// are signed 16-bit tenths and High ISO NR uses Fuji's non-linear encoding.
public enum CSlotPresetEncoder {
    /// Fuji's C-slot High ISO NR lookup, verified against FilmKit's raw preset
    /// mapping. These are UInt16 bit patterns, including the `0x8000` value.
    public static let highIsoNRRawValues: [Int32: UInt32] = [
        -4: 0x8000, -3: 0x7000, -2: 0x4000, -1: 0x3000,
         0: 0x2000,  1: 0x1000,  2: 0x0000,  3: 0x6000,  4: 0x5000
    ]

    /// Converts a signed raw C-slot tone payload back to its app/UI unit.
    /// `0x8000` is Fuji's unset sentinel and must not be treated as -3276.8.
    ///
    /// Half-stops truncate toward zero (`15` → `1`, `5` → `0`). Camera sync
    /// depends on that: raw `+1.5` must stay distinct from UI `+2`, or an
    /// editor change to `+2` looks unchanged and the stored tenth is kept.
    /// Catalog display rounding lives in `RecipeLoader.catalogTone`. Exact
    /// recipe writes use `Recipe.sourceRawPreset`.
    public static func uiTone(from raw: Int32?) -> Int32? {
        guard let raw else { return nil }
        let signed16 = Int32(Int16(truncatingIfNeeded: raw))
        guard signed16 != Int32(Int16.min) else { return nil }
        return signed16 / 10
    }

    /// Converts Fuji's raw C-slot High ISO NR bit pattern to its UI value.
    public static func uiHighIsoNR(from raw: UInt32?) -> Int32? {
        guard let raw else { return nil }
        return highIsoNRRawValues.first(where: { $0.value == raw })?.key
    }

    public static func encode(recipe: Recipe, slot: Int) throws -> PTPClientPresetData {
        try encode(
            slot: slot,
            name: recipe.name,
            filmSimulation: recipe.filmSimulation,
            dynamicRange: recipe.dynamicRange,
            grainEffect: recipe.grainEffect,
            colorChrome: recipe.colorChrome,
            colorChromeFxBlue: recipe.colorChromeFxBlue,
            smoothSkin: recipe.smoothSkin,
            whiteBalance: recipe.whiteBalanceMode,
            wbShiftRed: recipe.wbShiftRed,
            wbShiftBlue: recipe.wbShiftBlue,
            colorTemp: recipe.colorTempK,
            highlight: recipe.highlight,
            shadow: recipe.shadow,
            color: recipe.color,
            sharpness: recipe.sharpness,
            highIsoNr: recipe.highIsoNr,
            clarity: recipe.clarity,
            imageQuality: nil,
            imageSize: nil,
            monoWarmCool: nil,
            monoMagentaGreen: nil,
            longExpNr: nil,
            colorSpace: nil,
            rawPreset: recipe.sourceRawPreset
        )
    }

    public static func encode(loadout: Loadout, slot: Int) throws -> PTPClientPresetData {
        try encode(
            slot: slot,
            name: loadout.name,
            filmSimulation: loadout.filmSim,
            dynamicRange: loadout.dr,
            grainEffect: loadout.grain,
            colorChrome: loadout.colorChrome,
            colorChromeFxBlue: loadout.colorChromeFxBlue,
            smoothSkin: loadout.smoothSkin,
            whiteBalance: loadout.wb,
            wbShiftRed: loadout.wbShiftRed,
            wbShiftBlue: loadout.wbShiftBlue,
            colorTemp: loadout.colorTempK,
            highlight: loadout.highlight,
            shadow: loadout.shadow,
            color: loadout.color,
            sharpness: loadout.sharpness,
            highIsoNr: loadout.highIsoNr,
            clarity: loadout.clarity,
            imageQuality: loadout.imageQuality,
            imageSize: loadout.imageSize,
            monoWarmCool: loadout.monoWarmCool,
            monoMagentaGreen: loadout.monoMagentaGreen,
            longExpNr: loadout.longExpNr,
            colorSpace: loadout.colorSpace,
            rawPreset: loadout.rawPreset
        )
    }

    private static func encode(
        slot: Int,
        name: String,
        filmSimulation: FilmSimulation?,
        dynamicRange: DynamicRange?,
        grainEffect: GrainEffect?,
        colorChrome: EffectIntensity?,
        colorChromeFxBlue: EffectIntensity?,
        smoothSkin: EffectIntensity?,
        whiteBalance: WhiteBalanceMode?,
        wbShiftRed: Int32?,
        wbShiftBlue: Int32?,
        colorTemp: UInt32?,
        highlight: Int32?,
        shadow: Int32?,
        color: Int32?,
        sharpness: Int32?,
        highIsoNr: Int32?,
        clarity: Int32?,
        imageQuality: UInt32?,
        imageSize: UInt32?,
        monoWarmCool: Int32?,
        monoMagentaGreen: Int32?,
        longExpNr: UInt32?,
        colorSpace: UInt32?,
        rawPreset: LoadoutRawPresetState?
    ) throws -> PTPClientPresetData {
        guard (1...7).contains(slot) else {
            throw CSlotPresetEncodingError.invalidSlot(slot)
        }

        let resolvedFilmSimulation = rawPreset?.filmSimulation ?? filmSimulation?.rawValue
        let isMonochrome = resolvedFilmSimulation
            .flatMap(FilmSimulation.init(rawValue:))
            .map(isMonochrome) ?? false
        let rawWB = rawPreset?.whiteBalance ?? whiteBalance.map { UInt32($0.actualPTPValue) }
        let rawColorTemp: UInt32?
        if rawWB == WhiteBalanceMode.colorTemperature.actualPTPValue {
            let resolvedColorTemp = rawPreset?.colorTemp ?? colorTemp ?? 5_500
            guard (2_500...10_000).contains(resolvedColorTemp) else {
                throw CSlotPresetEncodingError.outOfRange(property: 0xD19C, value: Int64(resolvedColorTemp), valid: "2500...10000 K")
            }
            rawColorTemp = resolvedColorTemp
        } else {
            rawColorTemp = nil
        }

        let rawWBShiftRed = try rawPreset?.wbShiftRed ?? wbShiftRed.map { try rawShift($0, property: 0xD19A) }
        let rawWBShiftBlue = try rawPreset?.wbShiftBlue ?? wbShiftBlue.map { try rawShift($0, property: 0xD19B) }
        let rawHighlight = try rawPreset?.highlight ?? highlight.map { try rawTenths($0, property: 0xD19D, range: -2...4) }
        let rawShadow = try rawPreset?.shadow ?? shadow.map { try rawTenths($0, property: 0xD19E, range: -2...4) }
        let rawColor = try rawPreset?.color ?? color.map { try rawTenths($0, property: 0xD19F, range: -4...4) }
        let rawSharpness = try rawPreset?.sharpness ?? sharpness.map { try rawTenths($0, property: 0xD1A0, range: -4...4) }
        let rawHighIsoNr = try rawPreset?.highIsoNr ?? highIsoNr.map(rawHighIsoNR)
        let rawClarity = try rawPreset?.clarity ?? clarity.map { try rawTenths($0, property: 0xD1A2, range: -5...5) }

        return PTPClientPresetData(
            slot: slot,
            name: CameraPresetName.label(for: name),
            imageQuality: rawPreset?.imageQuality ?? imageQuality,
            imageSize: rawPreset?.imageSize ?? imageSize,
            dynamicRange: rawPreset?.dynamicRange ?? dynamicRange.map(rawDynamicRange),
            filmSimulation: resolvedFilmSimulation,
            monoWarmCool: rawPreset?.monoWarmCool ?? monoWarmCool,
            monoMagentaGreen: rawPreset?.monoMagentaGreen ?? monoMagentaGreen,
            grainEffect: rawPreset?.grainEffect ?? grainEffect.map(rawGrain),
            colorChrome: rawPreset?.colorChrome ?? colorChrome.map(rawEffect),
            colorChromeFxBlue: rawPreset?.colorChromeFxBlue ?? colorChromeFxBlue.map(rawEffect),
            smoothSkin: rawPreset?.smoothSkin ?? smoothSkin.map(rawEffect),
            whiteBalance: rawWB,
            wbShiftRed: rawWBShiftRed,
            wbShiftBlue: rawWBShiftBlue,
            colorTemp: rawColorTemp,
            highlight: rawHighlight,
            shadow: rawShadow,
            color: isMonochrome ? nil : rawColor,
            sharpness: rawSharpness,
            highIsoNr: rawHighIsoNr,
            clarity: rawClarity,
            longExpNr: rawPreset?.longExpNr ?? longExpNr,
            colorSpace: rawPreset?.colorSpace ?? colorSpace
        )
    }

    private static func rawDynamicRange(_ value: DynamicRange) -> UInt32 {
        switch value {
        case .auto: return 0xFFFF
        case .dr100: return 100
        case .dr200: return 200
        case .dr400: return 400
        }
    }

    static func rawGrain(_ value: GrainEffect) -> UInt32 {
        switch value {
        case .off: return 1
        case .weakSmall: return 2
        case .strongSmall: return 3
        case .weakLarge: return 4
        case .strongLarge: return 5
        }
    }

    private static func rawEffect(_ value: EffectIntensity) -> UInt32 {
        switch value {
        case .off: return 1
        case .weak: return 2
        case .strong: return 3
        }
    }

    private static func rawShift(_ value: Int32, property: UInt16) throws -> Int32 {
        guard (-9...9).contains(value) else {
            throw CSlotPresetEncodingError.outOfRange(property: property, value: Int64(value), valid: "-9...9")
        }
        return value
    }

    private static func rawTenths(_ value: Int32, property: UInt16, range: ClosedRange<Int32>) throws -> Int32 {
        guard range.contains(value) else {
            throw CSlotPresetEncodingError.outOfRange(property: property, value: Int64(value), valid: "\(range.lowerBound)...\(range.upperBound)")
        }
        return value * 10
    }

    private static func rawHighIsoNR(_ value: Int32) throws -> UInt32 {
        guard let raw = highIsoNRRawValues[value] else {
            throw CSlotPresetEncodingError.outOfRange(property: 0xD1A1, value: Int64(value), valid: "-4...4")
        }
        return raw
    }

    private static func isMonochrome(_ simulation: FilmSimulation) -> Bool {
        switch simulation {
        case .monochrome, .monochromeY, .monochromeR, .monochromeG,
             .sepia, .acros, .acrosY, .acrosR, .acrosG:
            return true
        default:
            return false
        }
    }
}

public enum CSlotPresetEncodingError: Error, LocalizedError, Sendable, Equatable {
    case invalidSlot(Int)
    case missingColorTemperature
    case outOfRange(property: UInt16, value: Int64, valid: String)

    public var errorDescription: String? {
        switch self {
        case .invalidSlot(let slot):
            return "C-slot \(slot) is outside 1–7"
        case .missingColorTemperature:
            return "Color Temperature white balance requires a color temperature"
        case .outOfRange(let property, let value, let valid):
            return "C-slot property 0x\(String(property, radix: 16)) value \(value) is outside \(valid)"
        }
    }
}
