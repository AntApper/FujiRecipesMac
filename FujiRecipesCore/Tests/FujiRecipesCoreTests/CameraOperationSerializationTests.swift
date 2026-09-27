import XCTest
@testable import FujiRecipesCore

final class CameraOperationSerializationTests: XCTestCase {
    private let loadoutsKey = "com.ant.fuji-recipes.loadouts"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: loadoutsKey)
        super.tearDown()
    }

    // MARK: - One camera operation at a time

    @MainActor
    func testWriteDuringWriteAllNeverLandsInAnotherSlot() async throws {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        store.applyRecipe(Recipe(id: "two", name: "Two", source: "test", sourceUrl: nil, filmSimulation: .velvia), to: 2)
        var five = try XCTUnwrap(store.loadout(for: 5))
        five.name = "Five"
        five.filmSim = .acros
        five.rawPreset?.filmSimulation = nil

        let writeAll = Task { await manager.writeAllStagedSlots(from: store) }
        await camera.waitUntilBusy()
        let writeFive = Task { try? await manager.writeLoadout(five, to: 5) }
        _ = await writeAll.value
        _ = await writeFive.value

        XCTAssertEqual(camera.maxConcurrentOperations, 1, "two camera operations ran at the same time")
        XCTAssertEqual(camera.crossSlotAccesses, [], "a property access hit a slot other than the one its operation selected")
        XCTAssertEqual(camera.slot(2).name, "Two")
        XCTAssertEqual(camera.slot(2).filmSimulation, FilmSimulation.velvia.rawValue)
        XCTAssertEqual(camera.slot(5).name, "Five")
        XCTAssertEqual(camera.slot(5).filmSimulation, FilmSimulation.acros.rawValue)
    }

    @MainActor
    func testRefreshDuringWriteReadsEachSlotFromItsOwnRegister() async throws {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        var three = try XCTUnwrap(store.loadout(for: 3))
        three.name = "Three"
        three.filmSim = .eterna

        let write = Task { try? await manager.writeLoadout(three, to: 3) }
        await camera.waitUntilBusy()
        let refresh = Task { await manager.refreshCameraSlots(into: store) }
        _ = await write.value
        let result = await refresh.value

        XCTAssertEqual(camera.maxConcurrentOperations, 1, "two camera operations ran at the same time")
        XCTAssertEqual(camera.crossSlotAccesses, [])
        XCTAssertEqual(result.presets.map(\.name), ["Camera 1", "Camera 2", "Three", "Camera 4", "Camera 5", "Camera 6", "Camera 7"])
    }

    @MainActor
    func testWriteQueuedBehindWriteAllRunsAfterItAndIsBusyTracksTheGate() async throws {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        XCTAssertFalse(manager.isBusy)
        store.applyRecipe(Recipe(id: "two", name: "Two", source: "test", sourceUrl: nil, filmSimulation: .velvia), to: 2)
        store.applyRecipe(Recipe(id: "three", name: "Three", source: "test", sourceUrl: nil, filmSimulation: .eterna), to: 3)
        var five = try XCTUnwrap(store.loadout(for: 5))
        five.name = "Five"
        five.filmSim = .acros

        let writeAll = Task { await manager.writeAllStagedSlots(from: store) }
        await camera.waitUntilBusy()
        XCTAssertTrue(manager.isBusy)
        let writeFive = Task { try await manager.writeLoadout(five, to: 5) }
        _ = await writeAll.value
        _ = try await writeFive.value

        XCTAssertFalse(manager.isBusy)
        XCTAssertEqual(camera.writeOrder, [2, 3, 5])
        XCTAssertEqual(camera.maxConcurrentOperations, 1)
    }

    // MARK: - Edits made during a write survive it

    @MainActor
    func testEditMadeWhileSlotIsWritingStaysDirty() async throws {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        store.applyRecipe(Recipe(id: "three", name: "Three", source: "test", sourceUrl: nil, filmSimulation: .eterna), to: 3)

        let writeAll = Task { await manager.writeAllStagedSlots(from: store) }
        await camera.waitUntilBusy()
        store.setHighlight(for: 3, highlight: 2)
        _ = await writeAll.value

        XCTAssertEqual(store.loadout(for: 3)?.highlight, 2, "the post-write sync discarded an edit made during the write")
        XCTAssertTrue(store.isDirty(3), "a slot edited during its write was marked verified")
        XCTAssertEqual(store.stagedSlots, [3])
    }

    @MainActor
    func testWriteAllReportsASlotEditedDuringItsWrite() async throws {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        store.applyRecipe(Recipe(id: "three", name: "Three", source: "test", sourceUrl: nil, filmSimulation: .eterna), to: 3)

        let writeAll = Task { await manager.writeAllStagedSlots(from: store) }
        await camera.waitUntilBusy()
        store.setHighlight(for: 3, highlight: 2)
        let outcomes = await writeAll.value

        let result = try XCTUnwrap(outcomes.first { $0.slot == 3 }).result.get()
        XCTAssertTrue(result.draftEditedDuringWrite)
        XCTAssertFalse(result.isVerified)
        XCTAssertEqual(
            WriteAllSummary.text(for: outcomes),
            "Wrote 1 of 1 slot. Wrote C3. You edited it during the write, so the newer draft is still staged."
        )
    }

    @MainActor
    func testSingleWriteReportsASlotEditedDuringItsWrite() async throws {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        store.applyRecipe(Recipe(id: "three", name: "Three", source: "test", sourceUrl: nil, filmSimulation: .eterna), to: 3)

        let write = Task { try await manager.writeSlot(3, from: store) }
        await camera.waitUntilBusy()
        store.setHighlight(for: 3, highlight: 2)
        let result = try await write.value

        XCTAssertTrue(result.draftEditedDuringWrite)
        XCTAssertEqual(result.summary, "Wrote C3. You edited it during the write, so the newer draft is still staged.")
    }

    @MainActor
    func testWriteSlotAdoptsReadbackForUntouchedSlot() async throws {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        store.applyRecipe(Recipe(id: "six", name: "Six", source: "test", sourceUrl: nil, filmSimulation: .velvia), to: 6)
        XCTAssertTrue(store.isDirty(6))

        let result = try await manager.writeSlot(6, from: store)

        XCTAssertFalse(result.draftEditedDuringWrite)
        XCTAssertEqual(result.summary, "Wrote and verified C6.")
        XCTAssertEqual(result.observedSnapshot?.name, "Six")
        XCTAssertFalse(store.isDirty(6))
        XCTAssertEqual(store.loadout(for: 6)?.provenance, .cameraSynced)
        XCTAssertEqual(store.loadout(for: 6)?.filmSim, .velvia)
        XCTAssertEqual(store.stagedSlots, [])
    }

    @MainActor
    func testImportLinksTheSlotToTheWrittenRecipe() async throws {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        let recipe = Recipe(id: "tmax-hard", name: "Kodak T-Max 100 Hard Tone - A Film Simulation Recipe", source: "test", sourceUrl: nil, filmSimulation: .acros)

        _ = try await manager.importRecipeToCState(recipe, slot: 3, updating: store)

        let slot = try XCTUnwrap(store.loadout(for: 3))
        XCTAssertEqual(slot.name, "Kodak T-Max 100 Hard Tone")
        XCTAssertEqual(slot.recipeName, "Kodak T-Max 100 Hard Tone - A Film Simulation Recipe")
        XCTAssertEqual(slot.recipeID, "tmax-hard")
    }

    @MainActor
    func testImportKeepsEditMadeWhileItWasWriting() async throws {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        let recipe = Recipe(id: "four", name: "Four", source: "test", sourceUrl: nil, filmSimulation: .eterna)

        let importTask = Task { try await manager.importRecipeToCState(recipe, slot: 4, updating: store) }
        await camera.waitUntilBusy()
        store.setFilmSim(for: 4, filmSim: .acros)
        let result = try await importTask.value

        XCTAssertEqual(result.observedSnapshot?.name, "Four")
        XCTAssertEqual(camera.slot(4).filmSimulation, FilmSimulation.eterna.rawValue)
        XCTAssertEqual(store.loadout(for: 4)?.filmSim, .acros, "the import readback replaced an edit made during the write")
        XCTAssertTrue(store.isDirty(4))
        XCTAssertEqual(store.stagedSlots, [4])
    }

    @MainActor
    func testImportQueuedBehindRefreshAdoptsItsReadback() async throws {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        let recipe = Recipe(id: "four", name: "Four", source: "test", sourceUrl: nil, filmSimulation: .eterna)

        let refresh = Task { await manager.refreshCameraSlots(into: store) }
        await camera.waitUntilBusy()
        let importTask = Task { try await manager.importRecipeToCState(recipe, slot: 4, updating: store) }
        _ = await refresh.value
        _ = try await importTask.value

        XCTAssertEqual(camera.slot(4).name, "Four")
        XCTAssertEqual(store.loadout(for: 4)?.name, "Four", "the camera holds the recipe but the store kept the pre-import slot")
        XCTAssertEqual(store.loadout(for: 4)?.filmSim, .eterna)
        XCTAssertFalse(store.isDirty(4))
    }

    // MARK: - Connect and disconnect

    @MainActor
    func testConnectReportsSlotReadAsItsOwnStep() async {
        let camera = SlotRegisterCamera()
        let manager = CameraManager()

        let connect = Task { await manager.connect(using: camera, loadouts: LoadoutStore()) }
        await camera.waitUntilBusy()

        XCTAssertEqual(manager.status, .connecting)
        XCTAssertEqual(manager.operation, .readingSlots)
        await connect.value
        XCTAssertEqual(manager.status, .connected)
        XCTAssertEqual(manager.operation, .idle)
    }

    @MainActor
    func testDisconnectDuringConnectSlotReadEndsDisconnected() async {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()

        let connect = Task { await manager.connect(using: camera, loadouts: store) }
        await camera.waitUntilBusy()
        manager.disconnect()
        await connect.value

        XCTAssertEqual(manager.status, .disconnected)
        XCTAssertNil(manager.lastError, "a failure from the abandoned connect reached lastError")
        XCTAssertEqual(manager.operation, .idle)
    }

    @MainActor
    func testUnplugDuringConnectSlotReadEndsDisconnected() async {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()

        let connect = Task { await manager.connect(using: camera, loadouts: store) }
        await camera.waitUntilBusy()
        camera.unplug()
        await connect.value
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(manager.status, .disconnected)
        XCTAssertNil(manager.lastError)
    }

    @MainActor
    func testWriteFailureAfterDisconnectDoesNotSetLastError() async throws {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        var four = try XCTUnwrap(store.loadout(for: 4))
        four.filmSim = .provia

        let write = Task { try await manager.writeLoadout(four, to: 4) }
        await camera.waitUntilBusy()
        manager.disconnect()
        let outcome = await write.result

        XCTAssertThrowsError(try outcome.get())
        XCTAssertEqual(manager.status, .disconnected)
        XCTAssertNil(manager.lastError, "a write that failed because of the user's disconnect reported an error banner")
    }

    @MainActor
    func testDisconnectDuringWriteAllLeavesNoSlotWriting() async {
        let camera = SlotRegisterCamera()
        let store = LoadoutStore()
        let manager = CameraManager()
        await manager.connect(using: camera, loadouts: store)
        for slot in 2...4 {
            store.applyRecipe(Recipe(id: "r\(slot)", name: "Recipe \(slot)", source: "test", sourceUrl: nil, filmSimulation: .velvia), to: slot)
        }

        let writeAll = Task { await manager.writeAllStagedSlots(from: store) }
        await camera.waitUntilBusy()
        manager.disconnect()
        let results = await writeAll.value

        XCTAssertEqual(manager.operation, .idle, "an abandoned Write All kept marking slots as writing")
        XCTAssertEqual(manager.status, .disconnected)
        XCTAssertEqual(results.map(\.slot), [2, 3, 4], "Write All left unwritten slots out of its report")
        XCTAssertTrue(results.allSatisfy { if case .failure = $0.result { true } else { false } })
        XCTAssertEqual(camera.writeOrder.count, 0, "Write All kept writing after the disconnect")
        XCTAssertEqual(store.stagedSlots, [2, 3, 4])
    }

    @MainActor
    func testStaleDisconnectHandlerDoesNotEndNextConnection() async {
        let first = SlotRegisterCamera()
        let second = SlotRegisterCamera()
        let manager = CameraManager()
        await manager.connect(using: first)

        first.unplug()
        manager.disconnect()
        await manager.connect(using: second)
        try? await Task.sleep(nanoseconds: 50_000_000)

        XCTAssertEqual(manager.status, .connected)
        XCTAssertTrue(second.isConnected, "the first connection's unplug event closed the second connection")
        XCTAssertFalse(manager.isBusy)
    }
}

// MARK: - Slot-register camera

/// Models the X100VI's C-slot protocol: 0xD18C selects a slot, and every
/// later property access applies to whichever slot is selected at that
/// moment. Each property access suspends, like a real PTP round trip.
private final class SlotRegisterCamera: PTPClientProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var slots: [Int: PTPClientPresetData] = [:]
    private var selected = 1
    private var connected = false
    private var operationsInFlight = 0
    private var _maxConcurrentOperations = 0
    private var _crossSlotAccesses: [String] = []
    private var _writeOrder: [Int] = []
    private var handler: (@Sendable () -> Void)?

    let cameraInfo = PTPCameraInfo(model: "X100VI")

    init() {
        for slot in 1...7 {
            slots[slot] = PTPClientPresetData(slot: slot, name: "Camera \(slot)", filmSimulation: FilmSimulation.classicChrome.rawValue)
        }
    }

    var isConnected: Bool { lock.withLock { connected } }
    var maxConcurrentOperations: Int { lock.withLock { _maxConcurrentOperations } }
    var crossSlotAccesses: [String] { lock.withLock { _crossSlotAccesses } }
    var writeOrder: [Int] { lock.withLock { _writeOrder } }
    func slot(_ index: Int) -> PTPClientPresetData { lock.withLock { slots[index]! } }

    func connect() async throws { lock.withLock { connected = true } }
    func disconnect() { lock.withLock { connected = false } }
    func setDisconnectHandler(_ handler: (@Sendable () -> Void)?) { lock.withLock { self.handler = handler } }

    func unplug() {
        let handler = lock.withLock {
            connected = false
            return self.handler
        }
        handler?()
    }

    func waitUntilBusy() async {
        while lock.withLock({ operationsInFlight == 0 }) {
            await Task.yield()
        }
    }

    func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        try begin()
        defer { end() }
        try await select(index)
        let name = try await access(expecting: index) { $0.name }
        let film = try await access(expecting: index) { $0.filmSimulation }
        return PTPClientPresetData(slot: index, name: name, filmSimulation: film)
    }

    func writePresetSlot(_ index: Int, data: PTPClientPresetData) async throws -> PTPPresetSlotWriteResult {
        try begin()
        defer { end() }
        lock.withLock { _writeOrder.append(index) }
        try await select(index)
        if !data.name.isEmpty {
            try await mutate(expecting: index) { $0 = PTPClientPresetData(slot: $0.slot, name: data.name, filmSimulation: $0.filmSimulation) }
        }
        if let film = data.filmSimulation {
            try await mutate(expecting: index) { $0 = PTPClientPresetData(slot: $0.slot, name: $0.name, filmSimulation: film) }
        }
        let observed = try await access(expecting: index) { $0 }
        return PTPPresetSlotWriteResult(slot: index, observedSnapshot: PTPClientPresetData(slot: index, name: observed.name, filmSimulation: observed.filmSimulation))
    }

    private func begin() throws {
        try lock.withLock {
            guard connected else { throw PTPError.notConnected }
            operationsInFlight += 1
            _maxConcurrentOperations = max(_maxConcurrentOperations, operationsInFlight)
        }
    }

    private func end() {
        lock.withLock { operationsInFlight -= 1 }
    }

    private func roundTrip() async throws {
        try await Task.sleep(nanoseconds: 3_000_000)
        try lock.withLock { guard connected else { throw PTPError.notConnected } }
    }

    private func select(_ index: Int) async throws {
        try await roundTrip()
        lock.withLock { selected = index }
    }

    private func access<T>(expecting index: Int, _ read: (PTPClientPresetData) -> T) async throws -> T {
        try await roundTrip()
        return lock.withLock {
            if selected != index { _crossSlotAccesses.append("read C\(index) from C\(selected)") }
            return read(slots[selected]!)
        }
    }

    private func mutate(expecting index: Int, _ write: (inout PTPClientPresetData) -> Void) async throws {
        try await roundTrip()
        lock.withLock {
            if selected != index { _crossSlotAccesses.append("wrote C\(index) into C\(selected)") }
            write(&slots[selected]!)
        }
    }

    func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse { .unsupported }
    func writeProperty(_ code: UInt16, value: Int32) async throws {}
    func readNativeProfile() async throws -> Data { Data() }
    func writePTPSettings(from recipe: Recipe) async throws {}
    func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)?) async -> RAFConversionOutcome { .failed(message: "unsupported") }
    func capturePreview() async throws -> JPEGFile? { nil }
}
