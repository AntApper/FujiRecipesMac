import Foundation

/// Protocol-based camera manager that works with any PTPClientProtocol implementation.
/// macOS uses MacOSSession, iOS uses IOSSession.
@MainActor
public final class CameraManager: ObservableObject {
    public init() {}

    @Published public private(set) var status: CameraStatus = .disconnected
    @Published public private(set) var cameraInfo: PTPCameraInfo?
    @Published public var lastError: CameraFailure?
    @Published public private(set) var operation: CameraOperation = .idle
    @Published public private(set) var lastSlotRefresh: SlotRefreshResult?
    /// True while a camera operation holds the gate or is queued behind it.
    @Published public private(set) var isBusy = false

    private var client: PTPClientProtocol?
    private var connectionMonitorTask: Task<Void, Never>?
    /// Bumped by `connect` and `disconnect()`. Work captured under an older
    /// value belongs to an ended connection and must not touch the gate or
    /// published state.
    private var generation = 0
    private var gateWaiters: [CheckedContinuation<Void, Error>] = []

    // MARK: - Connection

    public func connect(using session: PTPClientProtocol, loadouts: LoadoutStore? = nil) async {
        guard status != .connecting, status != .connected else { return }

        DebugLogger.info("CameraManager.connect() called", category: .camera)
        generation += 1
        let gen = generation
        status = .connecting
        operation = .connecting
        lastError = nil
        client = session
        isBusy = true

        session.setDisconnectHandler { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.generation == gen else { return }
                if self.status == .connected || self.status == .connecting {
                    DebugLogger.info("Camera USB physical disconnection detected", category: .camera)
                    self.disconnect()
                }
            }
        }

        do {
            try await withTimeout(timeout: 15.0) {
                try await session.connect()
            }
            guard gen == generation else { return }

            let info = session.cameraInfo
            self.cameraInfo = PTPCameraInfo(
                model: info.model,
                vendorExtensionId: info.vendorExtensionId
            )

            // Keep dirty drafts: anything staged while offline still needs writing.
            if let loadouts {
                operation = .readingSlots
                _ = await refreshSlots(into: loadouts, overwriteDirtyDrafts: false, using: session, gen: gen)
                guard gen == generation else { return }
            }

            guard session.isConnected else {
                disconnect()
                return
            }
            status = .connected
            operation = .idle
            release(gen)
            startConnectionMonitor(gen)
        } catch {
            guard gen == generation else { return }
            status = .error
            operation = .failed("Connection failed")
            lastError = CameraFailure(.connection, "Check the USB connection and camera mode, then retry. \(error.localizedDescription)")
            session.disconnect()
            client = nil
            release(gen)
        }
    }

    public func disconnect() {
        generation += 1
        let waiters = gateWaiters
        gateWaiters = []
        isBusy = false
        waiters.forEach { $0.resume(throwing: CameraError.notConnected) }
        connectionMonitorTask?.cancel()
        connectionMonitorTask = nil
        client?.setDisconnectHandler(nil)
        client?.disconnect()
        client = nil
        status = .disconnected
        cameraInfo = nil
        lastError = nil
        operation = .idle
        lastSlotRefresh = nil
    }

    private func startConnectionMonitor(_ gen: Int) {
        connectionMonitorTask?.cancel()
        connectionMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { break }
                guard let self = self, self.generation == gen, self.status == .connected else { break }
                guard let client = self.client, client.isConnected else {
                    DebugLogger.info("Camera client reported isConnected == false; setting status to disconnected", category: .camera)
                    self.disconnect()
                    break
                }
            }
        }
    }

    // MARK: - Read C-States

    public func readCStates() async -> [PTPClientPresetData] {
        await readCStatesWithStatus().presets
    }

    public func refreshCameraSlots(into loadouts: LoadoutStore?, overwriteDirtyDrafts: Bool = false) async -> SlotRefreshResult {
        let result = try? await exclusive(.readingSlots) { client, gen in
            await refreshSlots(into: loadouts, overwriteDirtyDrafts: overwriteDirtyDrafts, using: client, gen: gen)
        }
        return result ?? notConnectedRefresh
    }

    public func readCStatesWithStatus() async -> SlotRefreshResult {
        let result = try? await exclusive(nil) { client, _ in
            await readSlots(using: client)
        }
        return result ?? notConnectedRefresh
    }

    private var notConnectedRefresh: SlotRefreshResult {
        SlotRefreshResult(
            presets: [],
            failures: (1...7).map { SlotRefreshFailure(slot: $0, message: CameraError.notConnected.localizedDescription) }
        )
    }

    private func refreshSlots(
        into loadouts: LoadoutStore?,
        overwriteDirtyDrafts: Bool,
        using client: PTPClientProtocol,
        gen: Int
    ) async -> SlotRefreshResult {
        let revisions = loadouts.map { store in
            Dictionary(uniqueKeysWithValues: (1...7).map { ($0, store.revision(of: $0)) })
        }
        let result = await readSlots(using: client)
        guard gen == generation else { return result }
        lastSlotRefresh = result
        if let loadouts, !result.presets.isEmpty {
            let presets = overwriteDirtyDrafts
                ? result.presets.filter { loadouts.revision(of: $0.slot) == revisions?[$0.slot] }
                : result.presets
            loadouts.syncFromCameraPresetData(presets, overwriteDirtyDrafts: overwriteDirtyDrafts)
        }
        if result.failures.isEmpty {
            clearFailure(.slotRead)
        } else {
            operation = .failed("Some camera slots could not be read")
            let failureDetails = result.failures.map(\.description).joined(separator: "; ")
            let recoveryHint = result.failures.contains { $0.message.contains("slot_selection failed") }
                ? " Slot selection could not acquire the camera PTP session. Close other camera apps, reconnect the USB cable, then retry."
                : ""
            lastError = CameraFailure(.slotRead, "\(failureDetails)\(recoveryHint)")
        }
        return result
    }

    private func readSlots(using client: PTPClientProtocol) async -> SlotRefreshResult {
        let selectedSlot: Int
        do {
            switch try await client.readProperty(PTPProperty.presetSlot) {
            case .uint32(let value) where (1...7).contains(value):
                selectedSlot = Int(value)
            case .error(let error):
                throw error
            case .unsupported:
                throw PTPError.invalidResponse("The active-slot selector is unsupported")
            default:
                throw PTPError.invalidResponse("The active-slot selector must report a slot from 1 to 7")
            }
        } catch {
            let message = "Could not determine the active camera slot: \(error.localizedDescription). No slots were read, so the camera's selection was preserved. Retry refreshing after reconnecting."
            return SlotRefreshResult(
                presets: [],
                failures: (1...7).map { SlotRefreshFailure(slot: $0, message: message) }
            )
        }

        var order = Array(1...7)
        // Reading a slot selects it on the camera, so the slot it was on is read last.
        order.append(order.remove(at: selectedSlot - 1))

        var presetData: [Int: PTPClientPresetData] = [:]
        var failures: [Int: SlotRefreshFailure] = [:]

        for slot in order {
            do {
                presetData[slot] = try await client.readPresetSlot(slot)
            } catch {
                DebugLogger.warning("Failed to read preset slot \(slot): \(error.localizedDescription)", category: .camera)
                failures[slot] = SlotRefreshFailure(slot: slot, message: error.localizedDescription)
            }
        }

        return SlotRefreshResult(
            presets: (1...7).compactMap { presetData[$0] },
            failures: (1...7).compactMap { failures[$0] }
        )
    }

    // MARK: - Import Recipe to C-State

    /// When `loadouts` is given, the verified readback replaces the slot only
    /// if the slot has not changed since this call, including while queued.
    /// A differing readback leaves the requested recipe staged for retry.
    public func importRecipeToCState(
        _ recipe: Recipe,
        slot: Int,
        updating loadouts: LoadoutStore? = nil
    ) async throws -> PTPPresetSlotWriteResult {
        guard (1...7).contains(slot) else {
            throw PTPError.invalidResponse("Preset slot must be 1–7")
        }
        let revision = loadouts?.revision(of: slot)
        return try await exclusive(nil) { client, gen in
            let result = try await writePreset(CSlotPresetEncoder.encode(recipe: recipe, slot: slot), to: slot, using: client, gen: gen)
            guard let loadouts, let revision else { return result }
            return adopt(result, for: slot, into: loadouts, ifUnchangedSince: revision, writtenFrom: recipe, gen: gen)
        }
    }

    // MARK: - Write Loadout

    /// Writes the store's current draft for `slot`, captured once the camera
    /// is free. The readback is adopted only if the draft did not change
    /// during the write and matches the request. A differing request stays
    /// staged; the result's `draftChange` says whether a newer edit was kept.
    public func writeSlot(_ slot: Int, from loadouts: LoadoutStore) async throws -> PTPPresetSlotWriteResult {
        guard (1...7).contains(slot) else {
            throw PTPError.invalidResponse("Preset slot must be 1–7")
        }
        return try await exclusive(nil) { client, gen in
            try await writeStoredSlot(slot, from: loadouts, using: client, gen: gen)
        }
    }

    public func writeLoadout(_ loadout: Loadout, to slot: Int) async throws -> PTPPresetSlotWriteResult {
        guard (1...7).contains(slot) else {
            throw PTPError.invalidResponse("Preset slot must be 1–7")
        }
        return try await exclusive(nil) { client, gen in
            try await writePreset(CSlotPresetEncoder.encode(loadout: loadout, slot: slot), to: slot, using: client, gen: gen)
        }
    }

    // MARK: - Batch Write Staged Slots

    public func writeAllStagedSlots(from loadouts: LoadoutStore) async -> [SlotWriteOutcome] {
        do {
            return try await exclusive(nil) { client, gen in
                var results: [SlotWriteOutcome] = []

                for slot in loadouts.stagedSlots {
                    guard loadouts.stagedSlots.contains(slot) else { continue }
                    guard gen == generation else {
                        results.append((slot: slot, result: .failure(CameraError.notConnected)))
                        continue
                    }

                    do {
                        let writeResult = try await writeStoredSlot(slot, from: loadouts, using: client, gen: gen)
                        results.append((slot: slot, result: .success(writeResult)))
                    } catch {
                        results.append((slot: slot, result: .failure(error)))
                    }
                }

                return results
            }
        } catch {
            return loadouts.stagedSlots.map { (slot: $0, result: .failure(error)) }
        }
    }

    // MARK: - RAF Conversion

    public func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)? = nil) async -> RAFConversionOutcome {
        // Profile modification is intentionally unsupported for the X100VI pipeline.
        _ = profileModifier
        do {
            return try await exclusive(.convertingRAF) { client, gen in
                let outcome = await client.convertRAF(raf, profileModifier: nil)
                guard gen == generation else { return outcome }
                switch outcome {
                case .failed(let message):
                    operation = .failed("RAW conversion failed")
                    lastError = CameraFailure(.rawConversion, message)
                case .downloadedJPEG, .triggerAcceptedOutputNotRetrievable:
                    clearFailure(.rawConversion)
                case .cancelled:
                    break
                }
                return outcome
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    public func capturePreview() async throws -> JPEGFile? {
        try await exclusive(nil) { client, _ in
            try await client.capturePreview()
        }
    }

    // MARK: - Camera Gate

    /// Runs `body` as the only camera operation. The camera applies property
    /// reads and writes to whichever C slot was last selected, so no two
    /// operations may interleave. Not reentrant: multi-slot work holds one
    /// acquisition and calls private bodies, never public operations.
    private func exclusive<T>(
        _ op: CameraOperation?,
        _ body: @MainActor (PTPClientProtocol, Int) async throws -> T
    ) async throws -> T {
        guard status == .connected, let client, client.isConnected else {
            throw CameraError.notConnected
        }
        let gen = generation
        try await acquire(gen)
        defer { release(gen) }
        if let op { operation = op }
        defer { if let op, gen == generation, operation == op { operation = .idle } }
        return try await body(client, gen)
    }

    private func acquire(_ gen: Int) async throws {
        guard isBusy else {
            isBusy = true
            return
        }
        // A handoff from `release` resumes this waiter with the gate still held.
        try await withCheckedThrowingContinuation { gateWaiters.append($0) }
        guard gen == generation else { throw CameraError.notConnected }
    }

    private func release(_ gen: Int) {
        guard gen == generation else { return }
        if gateWaiters.isEmpty {
            isBusy = false
        } else {
            gateWaiters.removeFirst().resume()
        }
    }

    // MARK: - Helpers

    private func writeStoredSlot(
        _ slot: Int,
        from loadouts: LoadoutStore,
        using client: PTPClientProtocol,
        gen: Int
    ) async throws -> PTPPresetSlotWriteResult {
        guard let loadout = loadouts.loadout(for: slot) else {
            throw PTPError.invalidResponse("No local draft for C\(slot)")
        }
        let revision = loadouts.revision(of: slot)
        let result = try await writePreset(CSlotPresetEncoder.encode(loadout: loadout, slot: slot), to: slot, using: client, gen: gen)
        return adopt(result, for: slot, into: loadouts, ifUnchangedSince: revision, requestedDraft: loadout, gen: gen)
    }

    private func adopt(
        _ result: PTPPresetSlotWriteResult,
        for slot: Int,
        into loadouts: LoadoutStore,
        ifUnchangedSince revision: Int,
        writtenFrom recipe: Recipe? = nil,
        requestedDraft: Loadout? = nil,
        gen: Int
    ) -> PTPPresetSlotWriteResult {
        guard gen == generation else { return result }
        if !result.differences.isEmpty, loadouts.revision(of: slot) == revision {
            // Preserve the request, including an import that wasn't staged
            // before the write. Newer edits/clears follow the revision guard
            // in adoptCameraWrite below and are never replaced here.
            if let recipe {
                loadouts.applyRecipe(recipe, to: slot)
            } else if let requestedDraft {
                loadouts.saveLocalDraft(requestedDraft)
            }
            return result
        }
        guard let observed = result.observedSnapshot, observed.slot == slot else { return result }
        guard loadouts.adoptCameraWrite(observed, ifUnchangedSince: revision, writtenFrom: recipe) else {
            return result.marking(loadouts.hasContent(for: slot) ? .edited : .cleared)
        }
        return result
    }

    private func writePreset(
        _ data: @autoclosure () throws -> PTPClientPresetData,
        to slot: Int,
        using client: PTPClientProtocol,
        gen: Int
    ) async throws -> PTPPresetSlotWriteResult {
        if gen == generation { operation = .writingSlot(slot) }
        defer { if gen == generation, operation == .writingSlot(slot) { operation = .idle } }
        do {
            let result = try await writePresetSlotRecoverably(data(), to: slot, using: client)
            if gen == generation { clearFailure(.slotWrite(slot)) }
            return result
        } catch {
            if gen == generation {
                operation = .failed("C\(slot) write failed")
                lastError = CameraFailure(.slotWrite(slot), error.localizedDescription)
            }
            throw error
        }
    }

    private func clearFailure(_ kind: CameraFailure.Kind) {
        if lastError?.kind == kind { lastError = nil }
    }

    /// Captures a trustworthy pre-write state and restores it after any
    /// partial/verification failure. Camera raw-zero empty slots are a
    /// read-only sentinel, not a valid write baseline, so they are explicitly
    /// refused as rollback input.
    private func writePresetSlotRecoverably(
        _ data: PTPClientPresetData,
        to slot: Int,
        using client: PTPClientProtocol
    ) async throws -> PTPPresetSlotWriteResult {
        let observed = try await client.readPresetSlot(slot)
        let baseline: PTPPresetSlotBaseline = observed.isEmptySlot
            ? .emptySentinel
            : .configured(observed)

        let helperResult: PTPPresetSlotWriteResult
        do {
            helperResult = try await client.writePresetSlot(slot, data: data)
        } catch {
            throw await recoverPresetSlotWrite(
                after: error,
                phase: .write,
                slot: slot,
                baseline: baseline,
                using: client
            )
        }

        do {
            let observedSnapshot = try await client.readPresetSlot(slot)
            return PTPPresetSlotWriteResult(
                slot: helperResult.slot,
                createdFromEmpty: helperResult.createdFromEmpty,
                warnings: helperResult.warnings,
                baseline: baseline,
                rollback: .notNeeded,
                observedSnapshot: observedSnapshot,
                differences: data.differences(from: observedSnapshot)
            )
        } catch {
            throw await recoverPresetSlotWrite(
                after: error,
                phase: .postWriteVerification,
                slot: slot,
                baseline: baseline,
                using: client
            )
        }
    }

    private func recoverPresetSlotWrite(
        after error: Error,
        phase: PTPPresetSlotWriteFailurePhase,
        slot: Int,
        baseline: PTPPresetSlotBaseline,
        using client: PTPClientProtocol
    ) async -> PTPPresetSlotWriteRecoveryError {
        let rollback: PTPPresetSlotRollbackOutcome
        switch baseline {
        case .emptySentinel:
            rollback = .notAttemptedEmptySentinel
        case .configured(let saved):
            do {
                let writeResult = try await client.writePresetSlot(slot, data: saved)
                guard writeResult.slot == slot, writeResult.isVerified else {
                    let fields = writeResult.differences.map(\.displayName).joined(separator: ", ")
                    throw PTPError.invalidResponse("Rollback write was not verified for C\(slot)\(fields.isEmpty ? "" : ": \(fields)")")
                }
                let readback = try await client.readPresetSlot(slot)
                guard readback.slot == slot, !readback.isEmptySlot else {
                    throw PTPError.invalidResponse("Rollback readback did not report configured C\(slot)")
                }
                var differences = saved.differences(from: readback)
                // A blank request normally means "leave the name alone";
                // rollback must also restore a baseline that had no name.
                if saved.name.trimmingCharacters(in: .whitespaces).isEmpty,
                   !readback.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    differences.insert(.name, at: 0)
                }
                // Restoration must match the raw baseline, including hidden
                // values such as the grain size retained while grain is off.
                guard readback == saved else {
                    let fields = differences.isEmpty ? "raw preset state" : differences.map(\.displayName).joined(separator: ", ")
                    throw PTPError.invalidResponse("Rollback readback differed from the saved baseline: \(fields)")
                }
                rollback = .restored
            } catch {
                rollback = .failed(error.localizedDescription)
            }
        }

        return PTPPresetSlotWriteRecoveryError(
            slot: slot,
            writeError: error,
            baseline: baseline,
            rollback: rollback,
            failurePhase: phase
        )
    }
}

// MARK: - Camera Status

public enum CameraStatus: String, Sendable {
    case disconnected
    case connecting
    case connected
    case error
}

public enum CameraOperation: Equatable, Sendable {
    case idle
    case connecting
    case readingSlots
    case writingSlot(Int)
    case convertingRAF
    case failed(String)
}

/// The most recent camera failure. It stays until the user dismisses it or
/// the next operation of the same kind succeeds.
public struct CameraFailure: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case connection
        case slotRead
        case slotWrite(Int)
        case rawConversion
    }

    public let kind: Kind
    public let message: String

    public init(_ kind: Kind, _ message: String) {
        self.kind = kind
        self.message = message
    }
}

public struct SlotRefreshFailure: Equatable, Sendable {
    public let slot: Int
    public let message: String

    public init(slot: Int, message: String) {
        self.slot = slot
        self.message = message
    }

    public var description: String { "C\(slot): \(message)" }
}

public struct SlotRefreshResult: Sendable {
    public let presets: [PTPClientPresetData]
    public let failures: [SlotRefreshFailure]

    public init(presets: [PTPClientPresetData], failures: [SlotRefreshFailure]) {
        self.presets = presets
        self.failures = failures
    }

    public var isComplete: Bool { failures.isEmpty && presets.count == 7 }

    public var summary: String {
        guard !isComplete else { return "Read all 7 camera slots." }
        return "Read \(presets.count) of 7 slots. \(failures.map(\.description).joined(separator: "; "))"
    }
}

public typealias SlotWriteOutcome = (slot: Int, result: Result<PTPPresetSlotWriteResult, Error>)

public enum WriteAllSummary {
    public static func text(for outcomes: [SlotWriteOutcome]) -> String {
        guard !outcomes.isEmpty else { return "No staged slots were written." }
        if outcomes.count == 1, case .success(let result) = outcomes[0].result {
            return result.summary
        }
        let written = outcomes.compactMap { try? $0.result.get() }
        let failures = outcomes.compactMap { outcome -> String? in
            guard case .failure(let error) = outcome.result else { return nil }
            return "C\(outcome.slot): \(error.localizedDescription)"
        }
        if failures.isEmpty, written.allSatisfy(\.isVerified) {
            let head = "Wrote and verified all \(written.count) staged slots."
            let created = written.filter(\.createdFromEmpty).map { "C\($0.slot)" }
            guard let last = created.last else { return head }
            guard created.count > 1 else { return "\(head) Created \(last) from an empty slot." }
            return "\(head) Created \(created.dropLast().joined(separator: ", ")) and \(last) from empty slots."
        }
        let count = outcomes.count
        let head = "Wrote \(written.count) of \(count) slot\(count == 1 ? "" : "s")."
        let unverified = written.filter { !$0.isVerified }.map(\.summary)
        return ([head] + unverified + failures).joined(separator: " ")
    }
}

// MARK: - Camera Error

public enum CameraError: Error, LocalizedError {
    case notConnected
    case fileAccessDenied

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Camera not connected. Connect via USB-C to continue."
        case .fileAccessDenied:
            return "macOS could not access the selected RAF. Choose the file again and retry."
        }
    }
}
