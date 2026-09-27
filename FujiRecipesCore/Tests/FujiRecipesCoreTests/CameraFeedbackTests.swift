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
        XCTAssertNotNil(manager.lastError)

        camera.failingWrites = []
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
        XCTAssertNotNil(manager.lastError)

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
        XCTAssertNotNil(manager.lastError)

        camera.failingReads = []
        _ = await manager.refreshCameraSlots(into: store)

        XCTAssertNil(manager.lastError, "a complete refresh left the partial-refresh banner up")
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
    private var _unplugAfterWrites: Int?

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
    /// Unplugs the camera after this many successful slot writes.
    var unplugAfterWrites: Int? {
        get { lock.withLock { _unplugAfterWrites } }
        set { lock.withLock { _unplugAfterWrites = newValue } }
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
        let (result, unplug): (PTPPresetSlotWriteResult, (@Sendable () -> Void)?) = try lock.withLock {
            guard connected else { throw PTPError.notConnected }
            guard !_failingWrites.contains(index) else { throw PTPError.writeFailed(0xD192, "0x2019 device busy") }
            let old = slots[index]!
            var warnings: [String] = []
            var grain = data.grainEffect ?? old.grainEffect
            if let requested = data.grainEffect, _rejectedGrain.contains(requested) {
                grain = old.grainEffect
                warnings.append("0xD195: 0x201C")
            }
            slots[index] = PTPClientPresetData(
                slot: index,
                name: data.name.isEmpty ? old.name : data.name,
                imageQuality: data.imageQuality ?? old.imageQuality,
                imageSize: data.imageSize ?? old.imageSize,
                dynamicRange: data.dynamicRange ?? old.dynamicRange,
                filmSimulation: data.filmSimulation ?? old.filmSimulation,
                monoWarmCool: data.monoWarmCool ?? old.monoWarmCool,
                monoMagentaGreen: data.monoMagentaGreen ?? old.monoMagentaGreen,
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
            var unplug: (@Sendable () -> Void)?
            if let remaining = _unplugAfterWrites {
                _unplugAfterWrites = remaining - 1
                if remaining - 1 == 0 {
                    connected = false
                    unplug = handler
                }
            }
            return (PTPPresetSlotWriteResult(slot: index, warnings: warnings, observedSnapshot: slots[index]), unplug)
        }
        unplug?()
        return result
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
