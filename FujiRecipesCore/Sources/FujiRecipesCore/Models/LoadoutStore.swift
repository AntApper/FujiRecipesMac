import Foundation

/// Manages C1-C7 preset slots locally with UserDefaults persistence.
/// This is the offline/local version — camera sync is handled separately.
@MainActor
public final class LoadoutStore: ObservableObject {
    @Published public private(set) var loadouts: [Loadout] = []
    /// Slots the connected camera explicitly identified as never configured.
    /// This is session state, not a local draft's configuration state.
    @Published public private(set) var cameraEmptySlots: Set<Int> = []
    /// Slots changed locally since their last verified camera read/write.
    @Published public private(set) var dirtySlots: Set<Int> = []
    
    private let loadoutsKey = "com.ant.fuji-recipes.loadouts"
    
    public init() {
        loadLoadouts()
    }
    
    // MARK: - Persistence
    
    private func loadLoadouts() {
        if let data = UserDefaults.standard.data(forKey: loadoutsKey),
           let loadouts = try? JSONDecoder().decode([Loadout].self, from: data) {
            self.loadouts = loadouts.sorted { $0.slot < $1.slot }
            print("✅ LOADED \(loadouts.count) loadouts from UserDefaults")
        } else {
            self.loadouts = (1...7).map { Loadout(slot: $0, name: "C\($0)", filmSim: nil, dr: nil) }
            print("✅ DEFAULT 7 empty loadouts")
        }
    }
    
    private func saveLoadouts() {
        if let data = try? JSONEncoder().encode(loadouts) {
            UserDefaults.standard.set(data, forKey: loadoutsKey)
        }
    }
    
    // MARK: - Operations
    
    public func loadout(for slot: Int) -> Loadout? {
        loadouts.first { $0.slot == slot }
    }

    public func isCameraSlotEmpty(_ slot: Int) -> Bool {
        cameraEmptySlots.contains(slot)
    }

    public func isDirty(_ slot: Int) -> Bool {
        dirtySlots.contains(slot)
    }

    private func update(_ slot: Int, _ mutate: (inout Loadout) -> Void) {
        guard let index = loadouts.firstIndex(where: { $0.slot == slot }) else { return }
        var loadout = loadouts[index]
        mutate(&loadout)
        loadout.provenance = .localDraft
        loadouts[index] = loadout
        dirtySlots.insert(slot)
        saveLoadouts()
    }
    
    public func updateName(for slot: Int, name: String) {
        update(slot) { $0.name = name }
    }
    
    public func setFilmSim(for slot: Int, filmSim: FilmSimulation) {
        update(slot) {
            $0.filmSim = filmSim
            $0.rawPreset?.filmSimulation = nil
        }
    }
    
    public func setDynamicRange(for slot: Int, dr: DynamicRange) {
        update(slot) {
            $0.dr = dr
            $0.rawPreset?.dynamicRange = nil
        }
    }
    
    public func setGrainEffect(for slot: Int, grain: GrainEffect?) {
        update(slot) {
            $0.grain = grain
            $0.rawPreset?.grainEffect = nil
        }
    }
    
    public func setWhiteBalance(for slot: Int, wb: WhiteBalanceMode) {
        update(slot) {
            $0.wb = wb
            $0.rawPreset?.whiteBalance = nil
        }
    }
    
    public func setHighlight(for slot: Int, highlight: Int32) {
        update(slot) {
            $0.highlight = highlight
            $0.rawPreset?.highlight = nil
        }
    }
    
    public func setShadow(for slot: Int, shadow: Int32) {
        update(slot) {
            $0.shadow = shadow
            $0.rawPreset?.shadow = nil
        }
    }
    
    public func setColor(for slot: Int, color: Int32) {
        update(slot) {
            $0.color = color
            $0.rawPreset?.color = nil
        }
    }
    
    public func setSharpness(for slot: Int, sharpness: Int32) {
        update(slot) {
            $0.sharpness = sharpness
            $0.rawPreset?.sharpness = nil
        }
    }
    
    public func clearLoadout(for slot: Int) {
        if let index = loadouts.firstIndex(where: { $0.slot == slot }) {
            var cleared = Loadout(slot: slot, name: "C\(slot)", filmSim: nil, dr: nil)
            cleared.provenance = .localDraft
            loadouts[index] = cleared
            dirtySlots.insert(slot)
            saveLoadouts()
        }
    }
    
    public func applyRecipe(_ recipe: Recipe, to slot: Int) {
        update(slot) { loadout in
            loadout.name = recipe.name
            loadout.recipeName = recipe.name
            loadout.recipeID = recipe.id
            loadout.filmSim = recipe.filmSimulation
            loadout.dr = recipe.dynamicRange
            loadout.grain = recipe.grainEffect
            loadout.colorChrome = recipe.colorChrome
            loadout.colorChromeFxBlue = recipe.colorChromeFxBlue
            loadout.smoothSkin = recipe.smoothSkin
            loadout.wb = recipe.whiteBalanceMode
            loadout.wbShiftRed = recipe.wbShiftRed
            loadout.wbShiftBlue = recipe.wbShiftBlue
            loadout.colorTempK = recipe.colorTempK
            loadout.highlight = recipe.highlight
            loadout.shadow = recipe.shadow
            loadout.color = recipe.color
            loadout.sharpness = recipe.sharpness
            loadout.highIsoNr = recipe.highIsoNr
            loadout.clarity = recipe.clarity
            // A recipe is an explicit desired state, not a camera observation.
            // Dropping the snapshot prevents unrelated old camera values from
            // being written alongside a recipe that does not specify them.
            loadout.imageQuality = nil
            loadout.imageSize = nil
            loadout.monoWarmCool = nil
            loadout.monoMagentaGreen = nil
            loadout.longExpNr = nil
            loadout.colorSpace = nil
            loadout.rawPreset = nil
        }
    }

    /// Takes up to 7 recipes and stages them sequentially into C1...C7.
    public func stageAll(recipes: [Recipe]) {
        for (index, recipe) in recipes.prefix(7).enumerated() {
            let slot = index + 1
            applyRecipe(recipe, to: slot)
        }
    }

    /// Clears local drafts for all 7 slots.
    public func clearAllStaged() {
        for slot in 1...7 {
            clearLoadout(for: slot)
        }
    }
    
    public func loadoutCountWithSettings() -> Int {
        loadouts.filter { $0.hasAnySettings }.count
    }
    
    // MARK: - Sync from Camera
    
    /// Update all loadouts from camera preset data (auto-sync on connect).
    /// Imports only successfully-read slots. Dirty local drafts remain untouched
    /// unless the caller explicitly chooses to replace them.
    public func syncFromCameraPresetData(_ presetData: [PTPClientPresetData], overwriteDirtyDrafts: Bool = false) {
        for data in presetData {
            guard overwriteDirtyDrafts || !dirtySlots.contains(data.slot) else { continue }
            guard let index = loadouts.firstIndex(where: { $0.slot == data.slot }) else { continue }

            if data.isEmptySlot {
                cameraEmptySlots.insert(data.slot)
                loadouts[index] = Loadout(slot: data.slot, name: "C\(data.slot)", filmSim: nil, dr: nil)
                dirtySlots.remove(data.slot)
                continue
            } else {
                cameraEmptySlots.remove(data.slot)
            }

            var loadout = loadouts[index]
            let cameraName = data.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let slotLabel = cameraName.isEmpty ? "C\(data.slot)" : cameraName
            loadout.name = slotLabel
            loadout.recipeName = slotLabel
            loadout.recipeID = nil
            loadout.imageQuality = data.imageQuality
            loadout.imageSize = data.imageSize
            loadout.filmSim = data.filmSimulation.flatMap(FilmSimulation.init(rawValue:))
            loadout.dr = data.dynamicRange.flatMap(DynamicRange.init(rawValue:))
            loadout.monoWarmCool = data.monoWarmCool
            loadout.monoMagentaGreen = data.monoMagentaGreen
            loadout.grain = data.grainEffect.flatMap(GrainEffect.init(rawValue:))
            loadout.colorChrome = data.colorChrome.flatMap(EffectIntensity.init(rawValue:))
            loadout.colorChromeFxBlue = data.colorChromeFxBlue.flatMap(EffectIntensity.init(rawValue:))
            loadout.smoothSkin = data.smoothSkin.flatMap(EffectIntensity.init(rawValue:))
            loadout.wb = data.whiteBalance.flatMap(WhiteBalanceMode.init(rawValue:))
            loadout.wbShiftRed = data.wbShiftRed
            loadout.wbShiftBlue = data.wbShiftBlue
            loadout.colorTempK = data.colorTemp
            // C-slot tone fields are signed raw tenths; Loadout stores
            // app/UI units so a subsequent write does not scale twice.
            loadout.highlight = CSlotPresetEncoder.uiTone(from: data.highlight)
            loadout.shadow = CSlotPresetEncoder.uiTone(from: data.shadow)
            loadout.color = CSlotPresetEncoder.uiTone(from: data.color)
            loadout.sharpness = CSlotPresetEncoder.uiTone(from: data.sharpness)
            loadout.highIsoNr = CSlotPresetEncoder.uiHighIsoNR(from: data.highIsoNr)
            loadout.clarity = CSlotPresetEncoder.uiTone(from: data.clarity)
            loadout.longExpNr = data.longExpNr
            loadout.colorSpace = data.colorSpace
            // Keep every raw value, including values newer than this
            // app's enums or values whose camera representation is not a
            // UI unit (such as High ISO NR and tone tenths).
            loadout.rawPreset = LoadoutRawPresetState(data)
            loadout.provenance = .cameraSynced

            loadouts[index] = loadout
            dirtySlots.remove(data.slot)
        }
        saveLoadouts()
        print("✅ Synced \(presetData.count) loadouts from camera")
    }

    /// Marks a completed PTP write as verified without pretending it refreshed
    /// every camera-side setting.
    public func markCameraWriteVerified(slot: Int) {
        guard let index = loadouts.firstIndex(where: { $0.slot == slot }) else { return }
        loadouts[index].provenance = .cameraSynced
        dirtySlots.remove(slot)
        saveLoadouts()
    }

    /// Saves the editor's complete visible state, including cleared optionals.
    public func saveLocalDraft(_ loadout: Loadout) {
        guard let index = loadouts.firstIndex(where: { $0.slot == loadout.slot }) else { return }
        var draft = loadout
        discardRawValuesOverridden(in: &draft, comparedTo: loadouts[index])
        draft.provenance = .localDraft
        loadouts[index] = draft
        dirtySlots.insert(loadout.slot)
        saveLoadouts()
    }

    /// The SlotEditor passes a value type back after directly mutating its UI
    /// fields. Clear a matching raw snapshot field whenever that editable
    /// value changed, including a transition to nil. Raw fields with no UI
    /// representation stay intact, so a read→edit→write cycle remains
    /// lossless for newer camera values.
    private func discardRawValuesOverridden(in draft: inout Loadout, comparedTo previous: Loadout) {
        guard var raw = draft.rawPreset else { return }

        if draft.filmSim != previous.filmSim { raw.filmSimulation = nil }
        if draft.dr != previous.dr { raw.dynamicRange = nil }
        if draft.grain != previous.grain { raw.grainEffect = nil }
        if draft.colorChrome != previous.colorChrome { raw.colorChrome = nil }
        if draft.colorChromeFxBlue != previous.colorChromeFxBlue { raw.colorChromeFxBlue = nil }
        if draft.smoothSkin != previous.smoothSkin { raw.smoothSkin = nil }
        if draft.wb != previous.wb { raw.whiteBalance = nil }
        if draft.wbShiftRed != previous.wbShiftRed { raw.wbShiftRed = nil }
        if draft.wbShiftBlue != previous.wbShiftBlue { raw.wbShiftBlue = nil }
        if draft.colorTempK != previous.colorTempK { raw.colorTemp = nil }
        if draft.highlight != previous.highlight { raw.highlight = nil }
        if draft.shadow != previous.shadow { raw.shadow = nil }
        if draft.color != previous.color { raw.color = nil }
        if draft.sharpness != previous.sharpness { raw.sharpness = nil }
        if draft.highIsoNr != previous.highIsoNr { raw.highIsoNr = nil }
        if draft.clarity != previous.clarity { raw.clarity = nil }
        if draft.imageQuality != previous.imageQuality { raw.imageQuality = nil }
        if draft.imageSize != previous.imageSize { raw.imageSize = nil }
        if draft.monoWarmCool != previous.monoWarmCool { raw.monoWarmCool = nil }
        if draft.monoMagentaGreen != previous.monoMagentaGreen { raw.monoMagentaGreen = nil }
        if draft.longExpNr != previous.longExpNr { raw.longExpNr = nil }
        if draft.colorSpace != previous.colorSpace { raw.colorSpace = nil }

        draft.rawPreset = raw
    }
}

// MARK: - Loadout Model

public struct Loadout: Identifiable, Codable, Sendable {
    public var id: String { "slot-\(slot)" }
    public var slot: Int
    public var name: String
    public var filmSim: FilmSimulation?
    public var dr: DynamicRange?
    public var grain: GrainEffect?
    public var wb: WhiteBalanceMode?
    public var highlight: Int32?
    public var shadow: Int32?
    public var color: Int32?
    public var sharpness: Int32?
    // Full recipe-mapped C-slot settings.
    public var colorChrome: EffectIntensity?
    public var colorChromeFxBlue: EffectIntensity?
    public var smoothSkin: EffectIntensity?
    public var wbShiftRed: Int32?
    public var wbShiftBlue: Int32?
    public var colorTempK: UInt32?
    public var highIsoNr: Int32?
    public var clarity: Int32?
    // C-slot-only settings not represented by Recipe.
    public var imageQuality: UInt32?
    public var imageSize: UInt32?
    public var monoWarmCool: Int32?
    public var monoMagentaGreen: Int32?
    public var longExpNr: UInt32?
    public var colorSpace: UInt32?
    /// Exact values from the most recent successful camera read. This keeps
    /// unrecognized enum values and raw C-slot encodings round-trippable.
    public var rawPreset: LoadoutRawPresetState?
    /// Name of the recipe that was loaded into this slot, if any (kept separate
    /// from `name` so we can always show provenance even if `name` is edited).
    public var recipeName: String?
    /// ID of the recipe that was loaded into this slot, if any.
    public var recipeID: String?
    /// Optional for backwards-compatible decoding of drafts persisted before
    /// provenance was tracked; `nil` is treated as a local draft.
    public var provenance: LoadoutProvenance?
    
    // Convenience: whether this loadout has at least one setting configured
    public var hasAnySettings: Bool {
        filmSim != nil || dr != nil || grain != nil || wb != nil ||
        highlight != nil || shadow != nil || color != nil || sharpness != nil ||
        colorChrome != nil || colorChromeFxBlue != nil || smoothSkin != nil ||
        wbShiftRed != nil || wbShiftBlue != nil || colorTempK != nil ||
        highIsoNr != nil || clarity != nil || imageQuality != nil ||
        imageSize != nil || monoWarmCool != nil || monoMagentaGreen != nil ||
        longExpNr != nil || colorSpace != nil || rawPreset?.hasAnyValue == true
    }
    
    public init(
        slot: Int,
        name: String,
        filmSim: FilmSimulation? = nil,
        dr: DynamicRange? = nil,
        grain: GrainEffect? = nil,
        wb: WhiteBalanceMode? = nil,
        highlight: Int32? = nil,
        shadow: Int32? = nil,
        color: Int32? = nil,
        sharpness: Int32? = nil,
        colorChrome: EffectIntensity? = nil,
        colorChromeFxBlue: EffectIntensity? = nil,
        smoothSkin: EffectIntensity? = nil,
        wbShiftRed: Int32? = nil,
        wbShiftBlue: Int32? = nil,
        colorTempK: UInt32? = nil,
        highIsoNr: Int32? = nil,
        clarity: Int32? = nil,
        imageQuality: UInt32? = nil,
        imageSize: UInt32? = nil,
        monoWarmCool: Int32? = nil,
        monoMagentaGreen: Int32? = nil,
        longExpNr: UInt32? = nil,
        colorSpace: UInt32? = nil,
        rawPreset: LoadoutRawPresetState? = nil,
        recipeName: String? = nil,
        recipeID: String? = nil,
        provenance: LoadoutProvenance? = .localDraft
    ) {
        self.slot = slot
        self.name = name
        self.filmSim = filmSim
        self.dr = dr
        self.grain = grain
        self.wb = wb
        self.highlight = highlight
        self.shadow = shadow
        self.color = color
        self.sharpness = sharpness
        self.colorChrome = colorChrome
        self.colorChromeFxBlue = colorChromeFxBlue
        self.smoothSkin = smoothSkin
        self.wbShiftRed = wbShiftRed
        self.wbShiftBlue = wbShiftBlue
        self.colorTempK = colorTempK
        self.highIsoNr = highIsoNr
        self.clarity = clarity
        self.imageQuality = imageQuality
        self.imageSize = imageSize
        self.monoWarmCool = monoWarmCool
        self.monoMagentaGreen = monoMagentaGreen
        self.longExpNr = longExpNr
        self.colorSpace = colorSpace
        self.rawPreset = rawPreset
        self.recipeName = recipeName
        self.recipeID = recipeID
        self.provenance = provenance
    }
    
    // Convenience: count of configured settings.
    // NOTE: built as individual Bool checks (not a heterogeneous array literal +
    // compactMap) because mixing different Optional<T> types in an array literal
    // boxes them as `Any`, which makes `compactMap { $0 }` a no-op (nil optionals
    // boxed in `Any` are not `nil` themselves) and always reports the max count.
    public var settingCount: Int {
        var count = 0
        if filmSim != nil { count += 1 }
        if dr != nil { count += 1 }
        if grain != nil { count += 1 }
        if wb != nil { count += 1 }
        if highlight != nil { count += 1 }
        if shadow != nil { count += 1 }
        if color != nil { count += 1 }
        if sharpness != nil { count += 1 }
        if colorChrome != nil { count += 1 }
        if colorChromeFxBlue != nil { count += 1 }
        if smoothSkin != nil { count += 1 }
        if wbShiftRed != nil { count += 1 }
        if wbShiftBlue != nil { count += 1 }
        if colorTempK != nil { count += 1 }
        if highIsoNr != nil { count += 1 }
        if clarity != nil { count += 1 }
        if imageQuality != nil { count += 1 }
        if imageSize != nil { count += 1 }
        if monoWarmCool != nil { count += 1 }
        if monoMagentaGreen != nil { count += 1 }
        if longExpNr != nil { count += 1 }
        if colorSpace != nil { count += 1 }
        return count
    }
}

/// Codable, lossless equivalent of PTPClientPresetData's setting fields.
/// PTPClientPresetData itself deliberately is not persisted, so locally saved
/// loadouts retain the complete camera observation without coupling storage to
/// the transport model.
public struct LoadoutRawPresetState: Codable, Sendable, Equatable {
    public var imageQuality: UInt32?
    public var imageSize: UInt32?
    public var dynamicRange: UInt32?
    public var filmSimulation: UInt32?
    public var monoWarmCool: Int32?
    public var monoMagentaGreen: Int32?
    public var grainEffect: UInt32?
    public var colorChrome: UInt32?
    public var colorChromeFxBlue: UInt32?
    public var smoothSkin: UInt32?
    public var whiteBalance: UInt32?
    public var wbShiftRed: Int32?
    public var wbShiftBlue: Int32?
    public var colorTemp: UInt32?
    public var highlight: Int32?
    public var shadow: Int32?
    public var color: Int32?
    public var sharpness: Int32?
    public var highIsoNr: UInt32?
    public var clarity: Int32?
    public var longExpNr: UInt32?
    public var colorSpace: UInt32?

    public init(_ data: PTPClientPresetData) {
        imageQuality = data.imageQuality
        imageSize = data.imageSize
        dynamicRange = data.dynamicRange
        filmSimulation = data.filmSimulation
        monoWarmCool = data.monoWarmCool
        monoMagentaGreen = data.monoMagentaGreen
        grainEffect = data.grainEffect
        colorChrome = data.colorChrome
        colorChromeFxBlue = data.colorChromeFxBlue
        smoothSkin = data.smoothSkin
        whiteBalance = data.whiteBalance
        wbShiftRed = data.wbShiftRed
        wbShiftBlue = data.wbShiftBlue
        colorTemp = data.colorTemp
        highlight = data.highlight
        shadow = data.shadow
        color = data.color
        sharpness = data.sharpness
        highIsoNr = data.highIsoNr
        clarity = data.clarity
        longExpNr = data.longExpNr
        colorSpace = data.colorSpace
    }

    public var hasAnyValue: Bool {
        imageQuality != nil || imageSize != nil || dynamicRange != nil ||
        filmSimulation != nil || monoWarmCool != nil || monoMagentaGreen != nil ||
        grainEffect != nil || colorChrome != nil || colorChromeFxBlue != nil ||
        smoothSkin != nil || whiteBalance != nil || wbShiftRed != nil ||
        wbShiftBlue != nil || colorTemp != nil || highlight != nil ||
        shadow != nil || color != nil || sharpness != nil || highIsoNr != nil ||
        clarity != nil || longExpNr != nil || colorSpace != nil
    }
}

public enum LoadoutProvenance: String, Codable, Sendable {
    case localDraft
    case cameraSynced
}

// MARK: - Loadout Extensions

extension Loadout {
    /// Short display string for the loadout name
    public var displayLabel: String {
        if hasAnySettings {
            return name
        }
        return "C\(slot)"
    }
}
