import Foundation

/// Protocol-based camera manager that works with any PTPClientProtocol implementation.
/// macOS uses MacOSSession, iOS uses IOSSession.
@MainActor
public final class CameraManager: ObservableObject {
    public init() {}

    @Published public private(set) var status: CameraStatus = .disconnected
    @Published public private(set) var cameraInfo: PTPCameraInfo?
    /// Explicitly describes whether this backend can read live active settings.
    /// USB RAW mode exposes C-slot properties, but not the active-property
    /// telemetry range; an empty dictionary would incorrectly suggest a valid
    /// successful read with zero settings.
    @Published public private(set) var activeSettingsState: ActiveSettingsState = .notRead
    /// Compatibility projection for existing views. It is nil unless live
    /// settings were actually available; callers needing the reason should use
    /// `activeSettingsState`.
    public var activeSettings: [String: AnyHashable]? {
        activeSettingsState.settings
    }
    @Published public var lastError: String?
    @Published public private(set) var operation: CameraOperation = .idle
    @Published public private(set) var lastSlotRefresh: SlotRefreshResult?

    private var client: PTPClientProtocol?

    // MARK: - Connection

    public func connect(using session: PTPClientProtocol, loadouts: LoadoutStore? = nil) async {
        guard status != .connecting, status != .connected else { return }

        DebugLogger.info("CameraManager.connect() called", category: .camera)
        status = .connecting
        operation = .connecting
        lastError = nil
        client = session

        do {
            try await withTimeout(timeout: 15.0) {
                try await session.connect()
            }

            let info = session.cameraInfo
            self.cameraInfo = PTPCameraInfo(
                model: info.model,
                vendorExtensionId: info.vendorExtensionId
            )
            status = .connected
            operation = .idle

            // Active settings can fail for properties not supported in the current
            // USB mode; don't let that fail the whole connection.
            await readActiveSettings()

            // C-slot reads select and inspect seven camera slots, so run that
            // best-effort sync after reporting the verified PTP connection.
            // The Hub stays interactive even if a camera-side slot read stalls.
            Task { [weak self, weak loadouts] in
                guard let self, self.status == .connected else { return }
                _ = await self.refreshCameraSlots(into: loadouts)
            }
        } catch {
            status = .error
            operation = .failed("Connection failed")
            lastError = "Connection failed. Check the USB connection and camera mode, then retry. \(error.localizedDescription)"
            session.disconnect()
            client = nil
        }
    }

    public func disconnect() {
        client?.disconnect()
        client = nil
        status = .disconnected
        cameraInfo = nil
        activeSettingsState = .notRead
        lastError = nil
        operation = .idle
        lastSlotRefresh = nil
    }

    // MARK: - Active Settings

    public func readActiveSettings() async {
        guard let client = client, client.isConnected else { return }
        activeSettingsState = await readAllActiveSettings()
    }

    // MARK: - Read C-States

    public func readCStates() async -> [PTPClientPresetData] {
        await readCStatesWithStatus().presets
    }

    public func refreshCameraSlots(into loadouts: LoadoutStore?, overwriteDirtyDrafts: Bool = false) async -> SlotRefreshResult {
        operation = .readingSlots
        let result = await readCStatesWithStatus()
        lastSlotRefresh = result
        if !result.presets.isEmpty {
            loadouts?.syncFromCameraPresetData(result.presets, overwriteDirtyDrafts: overwriteDirtyDrafts)
        }
        operation = result.failures.isEmpty ? .idle : .failed("Some camera slots could not be read")
        if !result.failures.isEmpty {
            let failureDetails = result.failures.map(\.description).joined(separator: "; ")
            let recoveryHint = result.failures.contains { $0.message.contains("slot_selection failed") }
                ? " Slot selection could not acquire the camera PTP session. Close other camera apps, reconnect the USB cable, then retry."
                : ""
            lastError = "Camera slot refresh was partial: \(failureDetails)\(recoveryHint)"
        }
        return result
    }

    public func readCStatesWithStatus() async -> SlotRefreshResult {
        guard let client = client, client.isConnected else {
            return SlotRefreshResult(
                presets: [],
                failures: (1...7).map { SlotRefreshFailure(slot: $0, message: CameraError.notConnected.localizedDescription) }
            )
        }

        var presetData: [PTPClientPresetData] = []
        var failures: [SlotRefreshFailure] = []

        for slot in 1...7 {
            do {
                let data = try await client.readPresetSlot(slot)
                presetData.append(data)
            } catch {
                DebugLogger.warning("Failed to read preset slot \(slot): \(error.localizedDescription)", category: .camera)
                failures.append(SlotRefreshFailure(slot: slot, message: error.localizedDescription))
            }
        }

        return SlotRefreshResult(presets: presetData, failures: failures)
    }

    // MARK: - Import Recipe to C-State

    public func importRecipeToCState(_ recipe: Recipe, slot: Int) async throws -> PTPPresetSlotWriteResult {
        guard let client = client, client.isConnected else {
            throw CameraError.notConnected
        }
        guard (1...7).contains(slot) else {
            throw PTPError.invalidResponse("Preset slot must be 1–7")
        }

        operation = .writingSlot(slot)
        defer { if case .writingSlot = operation { operation = .idle } }
        do {
            return try await writePresetSlotRecoverably(
                CSlotPresetEncoder.encode(recipe: recipe, slot: slot),
                to: slot,
                using: client
            )
        } catch {
            operation = .failed("C\(slot) write failed")
            lastError = "C\(slot) was not verified on camera: \(error.localizedDescription)"
            throw error
        }
    }

    // MARK: - Write Loadout

    public func writeLoadout(_ loadout: Loadout, to slot: Int) async throws -> PTPPresetSlotWriteResult {
        guard let client = client, client.isConnected else {
            throw CameraError.notConnected
        }
        guard (1...7).contains(slot) else {
            throw PTPError.invalidResponse("Preset slot must be 1–7")
        }

        operation = .writingSlot(slot)
        defer { if case .writingSlot = operation { operation = .idle } }
        do {
            return try await writePresetSlotRecoverably(
                CSlotPresetEncoder.encode(loadout: loadout, slot: slot),
                to: slot,
                using: client
            )
        } catch {
            operation = .failed("C\(slot) write failed")
            lastError = "C\(slot) was not verified on camera: \(error.localizedDescription)"
            throw error
        }
    }

    // MARK: - RAF Conversion

    public func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)? = nil) async -> RAFConversionOutcome {
        guard let client = client, client.isConnected else {
            return .failed(message: CameraError.notConnected.localizedDescription)
        }
        // Profile modification is intentionally unsupported for the X100VI pipeline.
        _ = profileModifier
        operation = .convertingRAF
        defer { if case .convertingRAF = operation { operation = .idle } }
        let outcome = await client.convertRAF(raf, profileModifier: nil)
        if case .failed(let message) = outcome {
            operation = .failed("RAW conversion failed")
            lastError = "RAW conversion failed: \(message)"
        }
        return outcome
    }

    public func capturePreview() async throws -> JPEGFile? {
        guard let client = client, client.isConnected else {
            throw CameraError.notConnected
        }
        return try await client.capturePreview()
    }

    // MARK: - Helpers

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

        do {
            let result = try await client.writePresetSlot(slot, data: data)
            return PTPPresetSlotWriteResult(
                slot: result.slot,
                createdFromEmpty: result.createdFromEmpty,
                warnings: result.warnings,
                baseline: baseline,
                rollback: .notNeeded
            )
        } catch {
            let rollback: PTPPresetSlotRollbackOutcome
            switch baseline {
            case .emptySentinel:
                rollback = .notAttemptedEmptySentinel
            case .configured(let saved):
                do {
                    _ = try await client.writePresetSlot(slot, data: saved)
                    rollback = .restored
                } catch {
                    rollback = .failed(error.localizedDescription)
                }
            }
            throw PTPPresetSlotWriteRecoveryError(
                slot: slot,
                writeError: error,
                baseline: baseline,
                rollback: rollback
            )
        }
    }

    private func readAllActiveSettings() async -> ActiveSettingsState {
        guard let client = client else { return .notRead }

        var settings: [String: AnyHashable] = [:]

        let propertyCodes: [String: UInt16] = [
            "FilmSim": 0xD001, "Color": 0xD002, "DR": 0xD007,
            "WB": 0x5005, "WBRed": 0xD00B, "WBBlue": 0xD00C,
            "ColorTemp": 0xD017, "HighIsoNr": 0xD01C,
            "Grain": 0xD023, "Highlight": 0xD320, "Shadow": 0xD321,
            "ISO": 0x500F, "Sharpness": 0x5015, "ExpoComp": 0x5010
        ]

        for (name, code) in propertyCodes {
            do {
                let response = try await client.readProperty(code)
                switch response {
                case .uint32(let value):
                    settings[name] = value as AnyHashable
                case .int32(let value):
                    settings[name] = value as AnyHashable
                case .string(let value):
                    settings[name] = value as AnyHashable
                case .data(let data):
                    settings[name] = data as AnyHashable
                case .unsupported, .error:
                    DebugLogger.debug("Property 0x\(String(code, radix: 16)) unsupported or errored", category: .camera)
                }
            } catch {
                DebugLogger.debug("Property 0x\(String(code, radix: 16)) read failed: \(error.localizedDescription)", category: .camera)
            }
        }

        // The X100VI in USB RAW CONV mode rejects the active-property range
        // (for example D001/D007). Treat an all-unavailable pass as a
        // capability result, not as an apparently successful empty payload.
        return settings.isEmpty
            ? .unavailable(.unsupportedInUSBRAWMode)
            : .available(settings)
    }
}

/// Outcome of attempting to read the current, live camera settings.
///
/// This is deliberately separate from C-slot reads: the camera can support
/// preset-slot inspection while declining active-property telemetry.
public enum ActiveSettingsState: Equatable {
    case notRead
    case available([String: AnyHashable])
    case unavailable(ActiveSettingsUnavailableReason)

    public var settings: [String: AnyHashable]? {
        guard case .available(let settings) = self else { return nil }
        return settings
    }
}

public enum ActiveSettingsUnavailableReason: String, Sendable, Equatable {
    case unsupportedInUSBRAWMode

    public var userFacingDescription: String {
        switch self {
        case .unsupportedInUSBRAWMode:
            return "Live active settings are unavailable while the X100VI is in USB RAW mode."
        }
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
