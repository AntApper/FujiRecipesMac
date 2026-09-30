import XCTest
@testable import FujiRecipesCore

final class CameraWorkflowRefinementTests: XCTestCase {
    @MainActor
    func testMismatchedWriteKeepsTheRequestedDraftAndItsExactToneValues() async throws {
        let (store, defaults) = makeStore()
        let recipe = requestedRecipe()
        store.applyRecipe(recipe, to: 3)
        let requested = try CSlotPresetEncoder.encode(recipe: recipe, slot: 3)
        let camera = RefinementCamera()
        camera.firstWriteSnapshots[3] = camera.slots[3]
        let manager = CameraManager()
        await manager.connect(using: camera)
        defer { manager.disconnect() }

        let result = try await manager.writeSlot(3, from: store)

        XCTAssertFalse(result.isVerified)
        XCTAssertTrue(result.differences.contains(.filmSimulation))
        XCTAssertEqual(result.observedSnapshot, camera.slots[3])
        XCTAssertNil(result.draftChange)
        XCTAssertEqual(try CSlotPresetEncoder.encode(loadout: XCTUnwrap(store.loadout(for: 3)), slot: 3), requested)
        XCTAssertEqual(store.loadout(for: 3)?.provenance, .localDraft)
        XCTAssertTrue(store.isDirty(3))
        XCTAssertEqual(store.stagedSlots, [3])

        let reloaded = LoadoutStore(defaults: defaults)
        XCTAssertEqual(reloaded.stagedSlots, [3])
        XCTAssertEqual(try CSlotPresetEncoder.encode(loadout: XCTUnwrap(reloaded.loadout(for: 3)), slot: 3), requested)
    }

    @MainActor
    func testMismatchedWriteRestagesAPreviouslySyncedDraft() async throws {
        let store = makeStore().store
        let camera = RefinementCamera()
        let baseline = try XCTUnwrap(camera.slots[3])
        store.syncFromCameraPresetData([baseline])
        camera.firstWriteSnapshots[3] = PTPClientPresetData(slot: 3, name: "Different", filmSimulation: FilmSimulation.velvia.rawValue)
        let requested = try CSlotPresetEncoder.encode(loadout: XCTUnwrap(store.loadout(for: 3)), slot: 3)
        let manager = CameraManager()
        await manager.connect(using: camera)
        defer { manager.disconnect() }

        let result = try await manager.writeSlot(3, from: store)

        XCTAssertFalse(result.isVerified)
        XCTAssertTrue(store.isDirty(3))
        XCTAssertEqual(store.loadout(for: 3)?.provenance, .localDraft)
        XCTAssertEqual(store.stagedSlots, [3])
        XCTAssertEqual(try CSlotPresetEncoder.encode(loadout: XCTUnwrap(store.loadout(for: 3)), slot: 3), requested)
    }

    @MainActor
    func testMismatchedImportStagesTheRequestEvenIfItWasNeverStaged() async throws {
        for hadSyncedSlot in [false, true] {
            let (store, defaults) = makeStore()
            let camera = RefinementCamera()
            if hadSyncedSlot { store.syncFromCameraPresetData([try XCTUnwrap(camera.slots[3])]) }
            XCTAssertEqual(store.stagedSlots, [])
            camera.firstWriteSnapshots[3] = camera.slots[3]
            let recipe = requestedRecipe()
            let manager = CameraManager()
            await manager.connect(using: camera)
            defer { manager.disconnect() }

            let result = try await manager.importRecipeToCState(recipe, slot: 3, updating: store)

            XCTAssertFalse(result.isVerified)
            XCTAssertEqual(store.loadout(for: 3)?.recipeID, recipe.id)
            XCTAssertEqual(store.loadout(for: 3)?.provenance, .localDraft)
            XCTAssertTrue(store.isDirty(3))
            XCTAssertEqual(store.stagedSlots, [3])
            XCTAssertEqual(
                try CSlotPresetEncoder.encode(loadout: XCTUnwrap(store.loadout(for: 3)), slot: 3),
                try CSlotPresetEncoder.encode(recipe: recipe, slot: 3)
            )
            XCTAssertEqual(LoadoutStore(defaults: defaults).stagedSlots, [3])
        }
    }

    @MainActor
    func testMismatchedNameOnlyImportRemainsStagedAcrossRelaunchAndCanBeRetried() async throws {
        let (store, defaults) = makeStore()
        let recipe = Recipe(id: "name-only", name: "Name Only", source: "test", sourceUrl: nil)
        let requested = try CSlotPresetEncoder.encode(recipe: recipe, slot: 3)
        let camera = RefinementCamera()
        camera.firstWriteSnapshots[3] = camera.slots[3]
        let manager = CameraManager()
        await manager.connect(using: camera)
        defer { manager.disconnect() }

        let result = try await manager.importRecipeToCState(recipe, slot: 3, updating: store)

        XCTAssertEqual(result.differences, [.name])
        XCTAssertFalse(result.isVerified)
        XCTAssertEqual(store.loadout(for: 3)?.name, recipe.name)
        XCTAssertEqual(store.loadout(for: 3)?.recipeID, recipe.id)
        XCTAssertEqual(store.loadout(for: 3)?.hasAnySettings, false)
        XCTAssertEqual(store.loadout(for: 3)?.provenance, .localDraft)
        XCTAssertTrue(store.isDirty(3))
        XCTAssertEqual(store.stagedSlots, [3], "a name-only mismatch must be available for retry")
        XCTAssertEqual(try CSlotPresetEncoder.encode(loadout: XCTUnwrap(store.loadout(for: 3)), slot: 3), requested)

        let reloaded = LoadoutStore(defaults: defaults)
        XCTAssertTrue(reloaded.isDirty(3))
        XCTAssertEqual(reloaded.stagedSlots, [3])
        let outcomes = await manager.writeAllStagedSlots(from: reloaded)

        XCTAssertEqual(outcomes.map(\.slot), [3])
        let retry = try XCTUnwrap(outcomes.first).result.get()
        XCTAssertTrue(retry.isVerified)
        XCTAssertEqual(camera.writes, [requested, requested])
        XCTAssertEqual(reloaded.stagedSlots, [])
        XCTAssertFalse(reloaded.isDirty(3))
        XCTAssertEqual(reloaded.loadout(for: 3)?.provenance, .cameraSynced)
    }

    @MainActor
    func testMismatchedImportReportsANewerNameOnlyDraftAsEdited() async throws {
        let store = makeStore().store
        let requested = Recipe(id: "requested-name", name: "Requested Name", source: "test", sourceUrl: nil)
        let newer = Recipe(id: "newer-name", name: "Newer Name", source: "test", sourceUrl: nil)
        let camera = RefinementCamera()
        camera.firstWriteSnapshots[3] = camera.slots[3]
        camera.duringFirstWrite = { @MainActor in store.applyRecipe(newer, to: 3) }
        let manager = CameraManager()
        await manager.connect(using: camera)
        defer { manager.disconnect() }

        let result = try await manager.importRecipeToCState(requested, slot: 3, updating: store)

        XCTAssertEqual(result.differences, [.name])
        XCTAssertEqual(result.draftChange, .edited)
        XCTAssertEqual(store.loadout(for: 3)?.recipeID, newer.id)
        XCTAssertEqual(store.loadout(for: 3)?.name, newer.name)
        XCTAssertEqual(store.loadout(for: 3)?.hasAnySettings, false)
        XCTAssertTrue(store.isDirty(3))
        XCTAssertEqual(store.stagedSlots, [3])
    }

    @MainActor
    func testBatchMismatchKeepsOnlyTheUnverifiedSlotStaged() async throws {
        let store = makeStore().store
        let recipe = requestedRecipe()
        store.applyRecipe(recipe, to: 2)
        store.applyRecipe(recipe, to: 4)
        let camera = RefinementCamera()
        camera.firstWriteSnapshots[2] = camera.slots[2]
        let manager = CameraManager()
        await manager.connect(using: camera)
        defer { manager.disconnect() }

        let outcomes = await manager.writeAllStagedSlots(from: store)

        XCTAssertEqual(outcomes.map(\.slot), [2, 4])
        XCTAssertFalse(try outcomes[0].result.get().isVerified)
        XCTAssertTrue(try outcomes[1].result.get().isVerified)
        XCTAssertEqual(store.stagedSlots, [2])
        XCTAssertEqual(store.loadout(for: 2)?.name, recipe.name)
        XCTAssertEqual(store.loadout(for: 2)?.provenance, .localDraft)
        XCTAssertEqual(store.loadout(for: 4)?.provenance, .cameraSynced)
    }

    @MainActor
    func testMismatchedWritePreservesANewerEdit() async throws {
        let store = makeStore().store
        store.applyRecipe(requestedRecipe(), to: 3)
        let camera = RefinementCamera()
        camera.firstWriteSnapshots[3] = camera.slots[3]
        camera.duringFirstWrite = { @MainActor in store.setHighlight(for: 3, highlight: 4) }
        let manager = CameraManager()
        await manager.connect(using: camera)
        defer { manager.disconnect() }

        let result = try await manager.writeSlot(3, from: store)

        XCTAssertFalse(result.differences.isEmpty)
        XCTAssertEqual(result.draftChange, .edited)
        XCTAssertEqual(store.loadout(for: 3)?.highlight, 4)
        XCTAssertTrue(store.isDirty(3))
        XCTAssertEqual(store.stagedSlots, [3])
    }

    @MainActor
    func testMismatchedWriteDoesNotRestageAClearedDraft() async throws {
        let store = makeStore().store
        store.applyRecipe(requestedRecipe(), to: 3)
        let camera = RefinementCamera()
        camera.firstWriteSnapshots[3] = camera.slots[3]
        camera.duringFirstWrite = { @MainActor in store.clearLoadout(for: 3) }
        let manager = CameraManager()
        await manager.connect(using: camera)
        defer { manager.disconnect() }

        let result = try await manager.writeSlot(3, from: store)

        XCTAssertFalse(result.differences.isEmpty)
        XCTAssertEqual(result.draftChange, .cleared)
        XCTAssertEqual(store.loadout(for: 3)?.hasAnySettings, false)
        XCTAssertEqual(store.stagedSlots, [])
    }

    @MainActor
    func testMismatchedImportPreservesANewerRecipe() async throws {
        let store = makeStore().store
        let camera = RefinementCamera()
        camera.firstWriteSnapshots[3] = camera.slots[3]
        let newer = Recipe(id: "newer", name: "Newer", source: "test", sourceUrl: nil, filmSimulation: .acros)
        camera.duringFirstWrite = { @MainActor in store.applyRecipe(newer, to: 3) }
        let manager = CameraManager()
        await manager.connect(using: camera)
        defer { manager.disconnect() }

        let result = try await manager.importRecipeToCState(requestedRecipe(), slot: 3, updating: store)

        XCTAssertEqual(result.draftChange, .edited)
        XCTAssertEqual(store.loadout(for: 3)?.recipeID, newer.id)
        XCTAssertEqual(store.loadout(for: 3)?.filmSim, .acros)
        XCTAssertEqual(store.stagedSlots, [3])
    }

    @MainActor
    func testMismatchedImportDoesNotRecreateAClearedDraft() async throws {
        let store = makeStore().store
        let camera = RefinementCamera()
        camera.firstWriteSnapshots[3] = camera.slots[3]
        camera.duringFirstWrite = { @MainActor in store.clearLoadout(for: 3) }
        let manager = CameraManager()
        await manager.connect(using: camera)
        defer { manager.disconnect() }

        let result = try await manager.importRecipeToCState(requestedRecipe(), slot: 3, updating: store)

        XCTAssertEqual(result.draftChange, .cleared)
        XCTAssertNil(store.loadout(for: 3)?.recipeID)
        XCTAssertEqual(store.loadout(for: 3)?.hasAnySettings, false)
        XCTAssertEqual(store.stagedSlots, [])
    }

    @MainActor
    func testUnverifiedRollbackWriteResultIsNeverReportedAsRestored() async throws {
        let camera = RefinementCamera()
        camera.initialWriteError = PTPError.writeFailed(PTPProperty.presetFilmSimulation, "partial write")
        camera.rollbackWriteResult = PTPPresetSlotWriteResult(slot: 3, differences: [.filmSimulation])

        let error = try await recoverAfterFailure(using: camera)

        guard case .failed(let reason) = error.rollback else { return XCTFail("Unverified rollback was reported as restored") }
        XCTAssertTrue(reason.contains("Film Simulation"))
        XCTAssertTrue(error.writeErrorDescription.contains("partial write"))
        XCTAssertFalse(error.localizedDescription.contains("settings were restored"))
    }

    @MainActor
    func testRollbackRequiresReadbackThatMatchesTheSavedBaseline() async throws {
        let camera = RefinementCamera()
        camera.initialWriteError = PTPError.writeFailed(PTPProperty.presetFilmSimulation, "partial write")
        camera.rollbackSnapshot = PTPClientPresetData(slot: 3, name: "Camera 3", filmSimulation: FilmSimulation.velvia.rawValue)

        let error = try await recoverAfterFailure(using: camera)

        guard case .failed(let reason) = error.rollback else { return XCTFail("Mismatched readback was reported as restored") }
        XCTAssertTrue(reason.contains("saved baseline"))
        XCTAssertTrue(reason.contains("Film Simulation"))
        XCTAssertEqual(camera.readSlots, [3, 3])
    }

    @MainActor
    func testRollbackWithUnavailableReadbackIsNeverReportedAsRestored() async throws {
        let camera = RefinementCamera()
        camera.initialWriteError = PTPError.writeFailed(PTPProperty.presetFilmSimulation, "partial write")
        camera.rollbackReadError = PTPError.readFailed(PTPProperty.presetFilmSimulation, "readback unavailable")

        let error = try await recoverAfterFailure(using: camera)

        guard case .failed(let reason) = error.rollback else { return XCTFail("Unavailable readback was reported as restored") }
        XCTAssertTrue(reason.contains("readback unavailable"))
        XCTAssertEqual(camera.readSlots, [3, 3])
    }

    @MainActor
    func testRollbackCannotVerifyAnEmptyOrDifferentSlotReadback() async throws {
        for snapshot in [PTPClientPresetData(slot: 3, isEmptySlot: true), PTPClientPresetData(slot: 4, name: "Camera 3")] {
            let camera = RefinementCamera()
            camera.initialWriteError = PTPError.writeFailed(PTPProperty.presetFilmSimulation, "partial write")
            camera.rollbackSnapshot = snapshot

            let error = try await recoverAfterFailure(using: camera)

            guard case .failed(let reason) = error.rollback else { return XCTFail("Invalid rollback readback was reported as restored") }
            XCTAssertTrue(reason.contains("configured C3"))
        }
    }

    @MainActor
    func testRollbackMustAlsoRestoreAnOriginallyBlankName() async throws {
        let camera = RefinementCamera()
        camera.slots[3] = PTPClientPresetData(slot: 3, name: "", filmSimulation: FilmSimulation.classicChrome.rawValue)
        camera.initialWriteError = PTPError.writeFailed(PTPProperty.presetFilmSimulation, "partial write")
        camera.rollbackSnapshot = PTPClientPresetData(slot: 3, name: "Leftover", filmSimulation: FilmSimulation.classicChrome.rawValue)

        let error = try await recoverAfterFailure(using: camera)

        guard case .failed(let reason) = error.rollback else { return XCTFail("A changed blank name was reported as restored") }
        XCTAssertTrue(reason.contains("Name"))
    }

    @MainActor
    func testRollbackMustMatchRawBaselineEvenWhenUIValuesAreEquivalent() async throws {
        let camera = RefinementCamera()
        camera.slots[3] = PTPClientPresetData(slot: 3, name: "Camera 3", filmSimulation: FilmSimulation.classicChrome.rawValue, grainEffect: 7)
        camera.initialWriteError = PTPError.writeFailed(PTPProperty.presetFilmSimulation, "partial write")
        camera.rollbackSnapshot = PTPClientPresetData(slot: 3, name: "Camera 3", filmSimulation: FilmSimulation.classicChrome.rawValue, grainEffect: 6)

        let error = try await recoverAfterFailure(using: camera)

        guard case .failed(let reason) = error.rollback else { return XCTFail("A different retained grain size was reported as restored") }
        XCTAssertTrue(reason.contains("raw preset state"))
    }

    @MainActor
    func testFailedSelectorReadDoesNotSelectAnyCameraSlotOrReplaceDrafts() async {
        let store = makeStore().store
        store.applyRecipe(requestedRecipe(), to: 2)
        let camera = RefinementCamera()
        camera.selectorError = PTPError.readFailed(PTPProperty.presetSlot, "camera busy")
        let manager = CameraManager()
        await manager.connect(using: camera)
        defer { manager.disconnect() }

        let result = await manager.refreshCameraSlots(into: store, overwriteDirtyDrafts: true)

        XCTAssertFalse(result.isComplete)
        XCTAssertEqual(result.presets, [])
        XCTAssertEqual(result.failures.map(\.slot), Array(1...7))
        XCTAssertTrue(result.failures.allSatisfy { $0.message.contains("camera busy") && $0.message.contains("No slots were read") })
        XCTAssertEqual(camera.readSlots, [])
        XCTAssertEqual(camera.selectedSlot, 3)
        XCTAssertEqual(manager.lastError?.kind, .slotRead)
        XCTAssertEqual(store.loadout(for: 2)?.recipeID, requestedRecipe().id)
        XCTAssertEqual(store.stagedSlots, [2])
    }

    @MainActor
    func testUnsupportedInvalidAndErrorSelectorsNeverCycleSlots() async {
        let responses: [PTPPropertyResponse] = [
            .unsupported, .uint32(0), .uint32(8), .uint32(UInt32.max),
            .int32(-1), .string("3"), .data(Data()),
            .error(.readFailed(PTPProperty.presetSlot, "selector unavailable"))
        ]
        for response in responses {
            let camera = RefinementCamera()
            camera.selectorResponse = response
            let manager = CameraManager()
            await manager.connect(using: camera)
            defer { manager.disconnect() }

            let result = await manager.readCStatesWithStatus()

            XCTAssertFalse(result.isComplete)
            XCTAssertEqual(result.presets, [])
            XCTAssertEqual(result.failures.count, 7)
            XCTAssertTrue(result.failures.allSatisfy { $0.message.contains("active camera slot") })
            XCTAssertEqual(camera.readSlots, [])
            XCTAssertEqual(camera.selectedSlot, 3)
        }
    }

    @MainActor
    func testValidSelectorPreservesEverySelectedSlotAndRecoversFromSelectorFailure() async {
        for selected in 1...7 {
            let camera = RefinementCamera()
            camera.selectedSlot = selected
            camera.selectorResponse = .unsupported
            let store = makeStore().store
            let manager = CameraManager()
            await manager.connect(using: camera, loadouts: store)
            defer { manager.disconnect() }
            XCTAssertEqual(manager.status, .connected)
            XCTAssertEqual(camera.readSlots, [])
            XCTAssertEqual(manager.lastError?.kind, .slotRead)
            camera.selectorResponse = nil

            let result = await manager.refreshCameraSlots(into: store)

            XCTAssertTrue(result.isComplete)
            XCTAssertEqual(result.presets.map(\.slot), Array(1...7))
            XCTAssertEqual(camera.readSlots, (1...7).filter { $0 != selected } + [selected])
            XCTAssertEqual(camera.selectedSlot, selected)
            XCTAssertNil(manager.lastError)
        }
    }

    private func requestedRecipe() -> Recipe {
        Recipe(
            id: "requested", name: "Requested", source: "test", sourceUrl: nil,
            filmSimulation: .velvia, whiteBalanceMode: .colorTemperature,
            colorTempK: 6_500, highlight: 1, shadow: 2,
            sourceRawPreset: LoadoutRawPresetState(highlight: 15, shadow: 25)
        )
    }

    @MainActor
    private func makeStore() -> (store: LoadoutStore, defaults: UserDefaults) {
        let domain = "com.ant.fuji-recipes.camera-refinements-tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: domain)!
        addTeardownBlock { UserDefaults(suiteName: domain)?.removePersistentDomain(forName: domain) }
        return (LoadoutStore(defaults: defaults), defaults)
    }

    @MainActor
    private func recoverAfterFailure(using camera: RefinementCamera) async throws -> PTPPresetSlotWriteRecoveryError {
        let manager = CameraManager()
        await manager.connect(using: camera)
        defer { manager.disconnect() }
        do {
            _ = try await manager.importRecipeToCState(requestedRecipe(), slot: 3)
        } catch let error as PTPPresetSlotWriteRecoveryError {
            return error
        }
        throw PTPError.invalidResponse("Expected a recoverable write failure")
    }
}

/// Calls are serialized by CameraManager. The hook changes the local draft
/// after camera mutation and before manager-side verification, deterministically.
private final class RefinementCamera: PTPClientProtocol, @unchecked Sendable {
    var isConnected = false
    let cameraInfo = PTPCameraInfo(model: "Test Camera")
    var selectedSlot = 3
    var selectorResponse: PTPPropertyResponse?
    var selectorError: Error?
    var slots = Dictionary(uniqueKeysWithValues: (1...7).map {
        ($0, PTPClientPresetData(slot: $0, name: "Camera \($0)", filmSimulation: FilmSimulation.classicChrome.rawValue, highlight: 10))
    })
    var firstWriteSnapshots: [Int: PTPClientPresetData] = [:]
    var initialWriteError: Error?
    var rollbackWriteResult: PTPPresetSlotWriteResult?
    var rollbackSnapshot: PTPClientPresetData?
    var rollbackReadError: Error?
    var duringFirstWrite: (@Sendable () async -> Void)?
    private var writeCounts: [Int: Int] = [:]
    private(set) var readSlots: [Int] = []
    private(set) var writes: [PTPClientPresetData] = []

    func connect() async throws { isConnected = true }
    func disconnect() { isConnected = false }
    func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse {
        guard code == PTPProperty.presetSlot else { return .unsupported }
        if let selectorError { throw selectorError }
        return selectorResponse ?? .uint32(UInt32(selectedSlot))
    }
    func writeProperty(_ code: UInt16, value: Int32) async throws {}
    func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        readSlots.append(index)
        selectedSlot = index
        if writeCounts[index, default: 0] > 1, let rollbackReadError { throw rollbackReadError }
        return slots[index]!
    }
    func writePresetSlot(_ index: Int, data: PTPClientPresetData) async throws -> PTPPresetSlotWriteResult {
        writes.append(data)
        writeCounts[index, default: 0] += 1
        let count = writeCounts[index]!
        selectedSlot = index
        slots[index] = count == 1 ? firstWriteSnapshots[index] ?? data : rollbackSnapshot ?? data
        if count == 1 {
            await duringFirstWrite?()
            if let initialWriteError { throw initialWriteError }
        } else if let rollbackWriteResult {
            return rollbackWriteResult
        }
        return PTPPresetSlotWriteResult(slot: index)
    }
    func readNativeProfile() async throws -> Data { Data() }
    func writePTPSettings(from recipe: Recipe) async throws {}
    func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)?) async -> RAFConversionOutcome { .cancelled }
    func capturePreview() async throws -> JPEGFile? { nil }
}
