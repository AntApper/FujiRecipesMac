import Foundation

/// The slot editor's visible fields. Tones are in C-slot tenths.
public struct SlotEditorForm: Equatable, Sendable {
    public var name: String
    public var filmSim: FilmSimulation?
    public var dynamicRange: DynamicRange?
    public var grain: GrainEffect?
    public var whiteBalance: WhiteBalanceMode?
    public var colorTemperature: Int
    public var highlight: Int32
    public var shadow: Int32
    public var color: Int32
    public var sharpness: Int32
    public var includesHighlight: Bool
    public var includesShadow: Bool
    public var includesColor: Bool
    public var includesSharpness: Bool

    public init(_ loadout: Loadout) {
        name = loadout.name
        filmSim = loadout.filmSim
        dynamicRange = loadout.dr
        grain = loadout.grain
        whiteBalance = loadout.wb
        colorTemperature = Int(loadout.colorTempK ?? 5600)
        let tones = loadout.toneTenths
        highlight = tones.highlight ?? 0
        shadow = tones.shadow ?? 0
        color = tones.color ?? 0
        sharpness = tones.sharpness ?? 0
        includesHighlight = tones.highlight != nil
        includesShadow = tones.shadow != nil
        includesColor = tones.color != nil
        includesSharpness = tones.sharpness != nil
    }

    public func draft(updating loadout: Loadout) -> Loadout {
        var loadout = loadout
        loadout.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "C\(loadout.slot)" : name
        loadout.filmSim = filmSim
        loadout.dr = dynamicRange
        loadout.grain = grain
        loadout.wb = whiteBalance
        loadout.colorTempK = whiteBalance == .colorTemperature ? UInt32(colorTemperature) : nil
        var raw = loadout.rawPreset ?? LoadoutRawPresetState()
        raw.highlight = includesHighlight ? highlight : nil
        raw.shadow = includesShadow ? shadow : nil
        raw.color = includesColor ? color : nil
        raw.sharpness = includesSharpness ? sharpness : nil
        loadout.rawPreset = raw.hasAnyValue ? raw : nil
        loadout.highlight = raw.highlight.map { $0 / 10 }
        loadout.shadow = raw.shadow.map { $0 / 10 }
        loadout.color = raw.color.map { $0 / 10 }
        loadout.sharpness = raw.sharpness.map { $0 / 10 }
        return loadout
    }
}

extension LoadoutStore {
    /// Saves `form` over the slot's current draft, unless the form shows
    /// exactly that draft.
    public func saveEditorForm(_ form: SlotEditorForm, slot: Int) {
        guard let current = loadout(for: slot), form != SlotEditorForm(current) else { return }
        saveLocalDraft(form.draft(updating: current))
    }
}
