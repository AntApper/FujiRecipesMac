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

public struct SlotEditorSession: Sendable {
    public let slot: Int
    /// The store's values as of the last load or save. Edits and conflicts
    /// are measured against it.
    public private(set) var baseline: SlotEditorForm
    public var form: SlotEditorForm

    public init(_ loadout: Loadout) {
        slot = loadout.slot
        baseline = SlotEditorForm(loadout)
        form = baseline
    }

    public var isEdited: Bool { form != baseline }

    public mutating func reload(from loadout: Loadout) {
        baseline = SlotEditorForm(loadout)
        form = baseline
    }

    /// The store's slot changed. An untouched form shows the new values; an
    /// edited form keeps its edits.
    public mutating func follow(_ loadout: Loadout) {
        guard !isEdited else { return }
        reload(from: loadout)
    }

    /// Saving now would overwrite a change the user never saw.
    public func conflicts(with loadout: Loadout) -> Bool {
        isEdited && SlotEditorForm(loadout) != baseline
    }
}

extension LoadoutStore {
    /// An unedited session saves nothing: `saveLocalDraft` always marks the
    /// slot dirty, which would restage a camera-synced slot the user only viewed.
    public func save(_ session: inout SlotEditorSession) {
        guard session.isEdited, let current = loadout(for: session.slot) else { return }
        saveLocalDraft(session.form.draft(updating: current))
        if let saved = loadout(for: session.slot) {
            session.reload(from: saved)
        }
    }
}
