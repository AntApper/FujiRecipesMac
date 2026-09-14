import Foundation

/// Represents a C1–C7 preset slot on the X100VI.
public struct PresetSlot: Codable, Sendable {
    public let slot: Int  // 1–7
    public let name: String
    public let filmSimulation: FilmSimulation
    public let dynamicRange: DynamicRange
    public let grainEffect: GrainEffect?
    public let colorChrome: EffectIntensity?
    public let colorChromeFxBlue: EffectIntensity?
    public let smoothSkin: EffectIntensity?
    public let whiteBalanceMode: WhiteBalanceMode?
    public let wbShiftRed: Int32?
    public let wbShiftBlue: Int32?
    public let colorTempK: UInt32?
    public let highlight: Int32?
    public let shadow: Int32?
    public let color: Int32?
    public let sharpness: Int32?
    public let clarity: Int32?

    public init(
        slot: Int,
        name: String,
        filmSimulation: FilmSimulation,
        dynamicRange: DynamicRange,
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
        clarity: Int32? = nil
    ) {
        self.slot = slot
        self.name = name
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
        self.clarity = clarity
    }
}
