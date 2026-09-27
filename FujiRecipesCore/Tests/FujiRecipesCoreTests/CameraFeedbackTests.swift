import XCTest
@testable import FujiRecipesCore

final class CameraFeedbackTests: XCTestCase {
    private let loadoutsKey = "com.ant.fuji-recipes.loadouts"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
        super.tearDown()
    }

    private func draft(_ slot: Int, _ film: FilmSimulation) -> Loadout {
        Loadout(slot: slot, name: "Draft \(slot)", filmSim: film)
    }

    // MARK: - Camera failure banner

    @MainActor
    func testWriteFailureClearsOnTheNextSuccessfulWriteOfThatSlot() async throws {
        let camera = ScriptedCamera()
        let manager = CameraManager()
        await manager.connect(using: camera)
        camera.failingWrites = [3]
        _ = try? await manager.writeLoadout(draft(3, .acros), to: 3)
        XCTAssertEqual(manager.lastError?.kind, .slotWrite(3))

        camera.failingWrites = []
        _ = try await manager.writeLoadout(draft(5, .velvia), to: 5)
        XCTAssertEqual(manager.lastError?.kind, .slotWrite(3), "a C5 write cleared C3's failure")
        _ = try await manager.writeLoadout(draft(3, .acros), to: 3)

        XCTAssertNil(manager.lastError, "a successful C3 write left C3's failure banner up")
    }

    @MainActor
    func testRAWConversionFailureClearsOnTheNextSuccessfulConversion() async throws {
        let camera = ScriptedCamera()
        let manager = CameraManager()
        await manager.connect(using: camera)
        let raf = RAFFile(name: "DSCF0001.RAF", data: Data([0x46]))
        camera.conversionOutcome = .failed(message: "camera busy")
        _ = await manager.convertRAF(raf)
        XCTAssertEqual(manager.lastError, CameraFailure(.rawConversion, "camera busy"))

        camera.conversionOutcome = .triggerAcceptedOutputNotRetrievable(reason: "no download")
        _ = await manager.convertRAF(raf)

        XCTAssertNil(manager.lastError, "a successful conversion left the RAW failure banner up")
    }

    @MainActor
    func testCompleteRefreshClearsAnEarlierPartialRefreshFailure() async throws {
        let camera = ScriptedCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        camera.failingReads = [6]
        _ = await manager.refreshCameraSlots(into: store)
        XCTAssertEqual(manager.lastError, CameraFailure(.slotRead, "C6: Failed to read property 0xd18d: busy"))

        camera.failingReads = []
        _ = try await manager.writeLoadout(draft(2, .velvia), to: 2)
        XCTAssertEqual(manager.lastError?.kind, .slotRead, "a write cleared the refresh failure")
        _ = await manager.refreshCameraSlots(into: store)

        XCTAssertNil(manager.lastError, "a complete refresh left the partial-refresh banner up")
    }

    // MARK: - Write readback comparison

    @MainActor
    func testRewritingASlotThatReadsGrainSixReportsNoDifference() async throws {
        let camera = ScriptedCamera()
        camera.rejectedGrain = [6]
        camera.setSlot(PTPClientPresetData(slot: 5, name: "California Summ", filmSimulation: 19, grainEffect: 6, whiteBalance: 0x8007, colorTemp: 6700))
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        store.updateName(for: 5, name: "California Sun")

        let result = try await manager.writeSlot(5, from: store)

        XCTAssertEqual(result.differences, [])
        XCTAssertEqual(result.summary, "Wrote and verified C5.")
        XCTAssertEqual(camera.slot(5).grainEffect, 6)
    }

    @MainActor
    func testCopyingGrainSixIntoAnotherSlotReportsTheGrainDifference() async throws {
        let camera = ScriptedCamera()
        camera.rejectedGrain = [6]
        let manager = CameraManager()
        await manager.connect(using: camera)
        var raw = LoadoutRawPresetState()
        raw.grainEffect = 6
        let copy = Loadout(slot: 3, name: "California Summ", filmSim: .nostalgicNegative, rawPreset: raw)

        let result = try await manager.writeLoadout(copy, to: 3)

        XCTAssertEqual(result.differences, [.grainEffect])
        XCTAssertEqual(result.summary, "Wrote C3 with 1 difference: Grain.")
    }

    @MainActor
    func testUnsetFieldsAndMonochromeTonesUnderAColorFilmAreNotDifferences() async throws {
        let camera = ScriptedCamera()
        camera.setSlot(PTPClientPresetData(slot: 3, name: "Camera 3", filmSimulation: 12, monoWarmCool: 10, grainEffect: 5, whiteBalance: 2, colorTemp: 6500, color: 20))
        let manager = CameraManager()
        await manager.connect(using: camera)
        let colorRecipe = Loadout(slot: 3, name: "Chrome", filmSim: .classicChrome, wb: .auto, monoWarmCool: 0)

        let result = try await manager.writeLoadout(colorRecipe, to: 3)

        XCTAssertEqual(camera.slot(3).monoWarmCool, 10)
        XCTAssertEqual(result.differences, [])
    }

    // MARK: - Write All and Refresh summaries

    func testWriteAllSummaryForOneAndSeveralVerifiedSlots() {
        XCTAssertEqual(
            WriteAllSummary.text(for: [(slot: 3, result: .success(PTPPresetSlotWriteResult(slot: 3)))]),
            "Wrote and verified C3."
        )
        XCTAssertEqual(
            WriteAllSummary.text(for: [2, 3, 5].map { (slot: $0, result: .success(PTPPresetSlotWriteResult(slot: $0))) }),
            "Wrote and verified all 3 staged slots."
        )
    }

    func testWriteAllSummaryListsDifferencesAndFailuresWithReasons() {
        let outcomes: [SlotWriteOutcome] = [
            (slot: 2, result: .success(PTPPresetSlotWriteResult(slot: 2))),
            (slot: 3, result: .success(PTPPresetSlotWriteResult(slot: 3, differences: [.grainEffect, .color]))),
            (slot: 5, result: .failure(CameraError.notConnected))
        ]

        XCTAssertEqual(
            WriteAllSummary.text(for: outcomes),
            "Wrote 2 of 3 slots. Wrote C3 with 2 differences: Grain, Color. C5: Camera not connected. Connect via USB-C to continue."
        )
    }

    func testWriteAllSummaryForASingleFailedSlot() {
        XCTAssertEqual(
            WriteAllSummary.text(for: [(slot: 4, result: .failure(PTPError.writeFailed(0xD192, "busy")))]),
            "Wrote 0 of 1 slot. C4: Failed to write property 0xd192: busy"
        )
    }

    @MainActor
    func testWriteAllReturnsEverySlotAfterAMidRunUnplug() async throws {
        let camera = ScriptedCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        for slot in [2, 3, 5] {
            store.applyRecipe(Recipe(id: "r\(slot)", name: "Recipe \(slot)", source: "test", sourceUrl: nil, filmSimulation: .velvia), to: slot)
        }
        camera.unplugOnWrite = 2

        let outcomes = await manager.writeAllStagedSlots(from: store)

        XCTAssertEqual(outcomes.map(\.slot), [2, 3, 5])
        XCTAssertEqual(outcomes.map { (try? $0.result.get()) != nil }, [true, false, false])
        XCTAssertTrue(WriteAllSummary.text(for: outcomes).hasPrefix("Wrote 1 of 3 slots. C3: "))
    }

    func testRefreshSummaryListsEachFailedSlotWithItsReason() {
        let partial = SlotRefreshResult(
            presets: (1...5).map { PTPClientPresetData(slot: $0) },
            failures: [SlotRefreshFailure(slot: 6, message: "busy"), SlotRefreshFailure(slot: 7, message: "timeout")]
        )
        let complete = SlotRefreshResult(presets: (1...7).map { PTPClientPresetData(slot: $0) }, failures: [])

        XCTAssertEqual(partial.summary, "Read 5 of 7 slots. C6: busy; C7: timeout")
        XCTAssertEqual(complete.summary, "Read all 7 camera slots.")
    }
}

/// Stores every C-slot field. A write applies each field it sets unless the
/// field is in `rejectedValues`, which the X100VI answers with 0x201C and
/// leaves unchanged.
final class ScriptedCamera: PTPClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [Int: PTPClientPresetData]
    private var connected = false
    private var handler: (@Sendable () -> Void)?
    private var _failingWrites: Set<Int> = []
    private var _failingReads: Set<Int> = []
    private var _rejectedGrain: Set<UInt32> = []
    private var _conversionOutcome: RAFConversionOutcome = .cancelled
    private var _unplugOnWrite: Int?

    let cameraInfo = PTPCameraInfo(model: "X100VI")

    init() {
        slots = Dictionary(uniqueKeysWithValues: (1...7).map {
            ($0, PTPClientPresetData(slot: $0, name: "Camera \($0)", filmSimulation: FilmSimulation.classicChrome.rawValue, grainEffect: 2, whiteBalance: 2))
        })
    }

    var failingWrites: Set<Int> {
        get { lock.withLock { _failingWrites } }
        set { lock.withLock { _failingWrites = newValue } }
    }
    var failingReads: Set<Int> {
        get { lock.withLock { _failingReads } }
        set { lock.withLock { _failingReads = newValue } }
    }
    var rejectedGrain: Set<UInt32> {
        get { lock.withLock { _rejectedGrain } }
        set { lock.withLock { _rejectedGrain = newValue } }
    }
    var conversionOutcome: RAFConversionOutcome {
        get { lock.withLock { _conversionOutcome } }
        set { lock.withLock { _conversionOutcome = newValue } }
    }
    /// The cable is pulled as this slot write (1-based) starts.
    var unplugOnWrite: Int? {
        get { lock.withLock { _unplugOnWrite } }
        set { lock.withLock { _unplugOnWrite = newValue } }
    }

    func slot(_ index: Int) -> PTPClientPresetData { lock.withLock { slots[index]! } }
    func setSlot(_ data: PTPClientPresetData) { lock.withLock { slots[data.slot] = data } }

    var isConnected: Bool { lock.withLock { connected } }
    func connect() async throws { lock.withLock { connected = true } }
    func disconnect() { lock.withLock { connected = false } }
    func setDisconnectHandler(_ handler: (@Sendable () -> Void)?) { lock.withLock { self.handler = handler } }

    func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        await Task.yield()
        return try lock.withLock {
            guard connected else { throw PTPError.notConnected }
            guard !_failingReads.contains(index) else { throw PTPError.readFailed(0xD18D, "busy") }
            return slots[index]!
        }
    }

    func writePresetSlot(_ index: Int, data: PTPClientPresetData) async throws -> PTPPresetSlotWriteResult {
        await Task.yield()
        let unplug: (@Sendable () -> Void)? = lock.withLock {
            guard let remaining = _unplugOnWrite else { return nil }
            _unplugOnWrite = remaining - 1
            guard remaining == 1 else { return nil }
            connected = false
            return handler
        }
        unplug?()
        return try lock.withLock {
            guard connected else { throw PTPError.notConnected }
            guard !_failingWrites.contains(index) else { throw PTPError.writeFailed(0xD192, "0x2019 device busy") }
            let old = slots[index]!
            var warnings: [String] = []
            var grain = data.grainEffect ?? old.grainEffect
            if let requested = data.grainEffect, _rejectedGrain.contains(requested) {
                grain = old.grainEffect
                warnings.append("0xD195: 0x201C")
            }
            let film = data.filmSimulation ?? old.filmSimulation
            let monochrome = film.flatMap(FilmSimulation.init(rawValue:)).map(CSlotPresetEncoder.isMonochrome) ?? false
            slots[index] = PTPClientPresetData(
                slot: index,
                name: data.name.isEmpty ? old.name : data.name,
                imageQuality: data.imageQuality ?? old.imageQuality,
                imageSize: data.imageSize ?? old.imageSize,
                dynamicRange: data.dynamicRange ?? old.dynamicRange,
                filmSimulation: film,
                monoWarmCool: monochrome ? data.monoWarmCool ?? old.monoWarmCool : old.monoWarmCool,
                monoMagentaGreen: monochrome ? data.monoMagentaGreen ?? old.monoMagentaGreen : old.monoMagentaGreen,
                grainEffect: grain,
                colorChrome: data.colorChrome ?? old.colorChrome,
                colorChromeFxBlue: data.colorChromeFxBlue ?? old.colorChromeFxBlue,
                smoothSkin: data.smoothSkin ?? old.smoothSkin,
                whiteBalance: data.whiteBalance ?? old.whiteBalance,
                wbShiftRed: data.wbShiftRed ?? old.wbShiftRed,
                wbShiftBlue: data.wbShiftBlue ?? old.wbShiftBlue,
                colorTemp: data.colorTemp ?? old.colorTemp,
                highlight: data.highlight ?? old.highlight,
                shadow: data.shadow ?? old.shadow,
                color: data.color ?? old.color,
                sharpness: data.sharpness ?? old.sharpness,
                highIsoNr: data.highIsoNr ?? old.highIsoNr,
                clarity: data.clarity ?? old.clarity,
                longExpNr: data.longExpNr ?? old.longExpNr,
                colorSpace: data.colorSpace ?? old.colorSpace
            )
            return PTPPresetSlotWriteResult(slot: index, warnings: warnings, observedSnapshot: slots[index])
        }
    }

    func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)?) async -> RAFConversionOutcome {
        conversionOutcome
    }

    func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse { .unsupported }
    func writeProperty(_ code: UInt16, value: Int32) async throws {}
    func readNativeProfile() async throws -> Data { Data() }
    func writePTPSettings(from recipe: Recipe) async throws {}
    func capturePreview() async throws -> JPEGFile? { nil }
}
