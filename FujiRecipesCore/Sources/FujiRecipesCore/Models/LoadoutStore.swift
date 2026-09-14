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
        update(slot) { $0.filmSim = filmSim }
    }
    
    public func setDynamicRange(for slot: Int, dr: DynamicRange) {
        update(slot) { $0.dr = dr }
    }
    
    public func setGrainEffect(for slot: Int, grain: GrainEffect?) {
        update(slot) { $0.grain = grain }
    }
    
    public func setWhiteBalance(for slot: Int, wb: WhiteBalanceMode) {
        update(slot) { $0.wb = wb }
    }
    
    public func setHighlight(for slot: Int, highlight: Int32) {
        update(slot) { $0.highlight = highlight }
    }
    
    public func setShadow(for slot: Int, shadow: Int32) {
        update(slot) { $0.shadow = shadow }
    }
    
    public func setColor(for slot: Int, color: Int32) {
        update(slot) { $0.color = color }
    }
    
    public func setSharpness(for slot: Int, sharpness: Int32) {
        update(slot) { $0.sharpness = sharpness }
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
            loadout.wb = recipe.whiteBalanceMode
            loadout.highlight = recipe.highlight
            loadout.shadow = recipe.shadow
            loadout.color = recipe.color
            loadout.sharpness = recipe.sharpness
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
            if data.isEmptySlot {
                cameraEmptySlots.insert(data.slot)
            } else {
                cameraEmptySlots.remove(data.slot)
            }
            if let index = loadouts.firstIndex(where: { $0.slot == data.slot }) {
                var loadout = loadouts[index]
                loadout.name = data.name.isEmpty ? "C\(data.slot)" : data.name
                
                if let fsRaw = data.filmSimulation {
                    loadout.filmSim = FilmSimulation(rawValue: fsRaw)
                }
                if let drRaw = data.dynamicRange {
                    loadout.dr = DynamicRange(rawValue: drRaw)
                }
                if let grainRaw = data.grainEffect {
                    loadout.grain = GrainEffect(rawValue: grainRaw)
                }
                if let wbRaw = data.whiteBalance {
                    loadout.wb = WhiteBalanceMode(rawValue: wbRaw)
                }
                // C-slot tone fields are signed raw tenths; Loadout stores
                // app/UI units so a subsequent write does not scale twice.
                loadout.highlight = CSlotPresetEncoder.uiTone(from: data.highlight)
                loadout.shadow = CSlotPresetEncoder.uiTone(from: data.shadow)
                loadout.color = CSlotPresetEncoder.uiTone(from: data.color)
                loadout.sharpness = CSlotPresetEncoder.uiTone(from: data.sharpness)
                loadout.provenance = .cameraSynced
                
                loadouts[index] = loadout
                dirtySlots.remove(data.slot)
            }
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
        draft.provenance = .localDraft
        loadouts[index] = draft
        dirtySlots.insert(loadout.slot)
        saveLoadouts()
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
        highlight != nil || shadow != nil || color != nil || sharpness != nil
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
        return count
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
