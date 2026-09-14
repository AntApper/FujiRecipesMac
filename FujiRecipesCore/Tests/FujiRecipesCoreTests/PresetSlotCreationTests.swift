import XCTest
@testable import FujiRecipesCore

final class PresetSlotCreationTests: XCTestCase {
    func testCameraPresetNameMatchesVerifiedFifteenCharacterLimit() {
        XCTAssertEqual(CameraPresetName.label(for: "C4 PTP VERIFY B"), "C4 PTP VERIFY B")
        XCTAssertEqual(CameraPresetName.label(for: "PRO Negative 160C"), "PRO Negative 16")
        XCTAssertEqual(CameraPresetName.label(for: "Fujicolor 100 Industrial"), "Fujicolor 100 I")
    }

    func testCameraPresetNameNormalizesToSafeASCII() {
        XCTAssertEqual(
            CameraPresetName.label(for: "Ciné—Film\u{00A0}’86"),
            "Cin -Film '86"
        )
    }

    func testCameraPresetNamePayloadMatchesFilmKitPTPEncoding() {
        let label = CameraPresetName.label(for: "PRO Negative 160C")

        XCTAssertEqual(
            Array(CameraPresetName.ptpPayload(forCameraLabel: label)),
            [
                0x10,
                0x50, 0x00, 0x52, 0x00, 0x4F, 0x00, 0x20, 0x00,
                0x4E, 0x00, 0x65, 0x00, 0x67, 0x00, 0x61, 0x00,
                0x74, 0x00, 0x69, 0x00, 0x76, 0x00, 0x65, 0x00,
                0x20, 0x00, 0x31, 0x00, 0x36, 0x00, 0x00, 0x00
            ]
        )
    }

    func testEmptySlotMetadataIsExplicitRatherThanInferredFromName() {
        let unnamedConfiguredSlot = PTPClientPresetData(
            slot: 4,
            name: "",
            filmSimulation: 11
        )
        let neverConfiguredSlot = PTPClientPresetData(
            slot: 4,
            name: "",
            isEmptySlot: true
        )

        XCTAssertFalse(unnamedConfiguredSlot.isEmptySlot)
        XCTAssertTrue(neverConfiguredSlot.isEmptySlot)
    }

    func testCreationResultIsSeparateFromSlotReadState() {
        let creation = PTPPresetSlotWriteResult(slot: 4, createdFromEmpty: true)
        let update = PTPPresetSlotWriteResult(slot: 4)

        XCTAssertTrue(creation.createdFromEmpty)
        XCTAssertFalse(update.createdFromEmpty)
    }

    func testHighISONoiseReductionAndLongExposureNoiseReductionRemainDistinct() {
        let preset = PTPClientPresetData(
            slot: 2,
            highIsoNr: 3,
            longExpNr: 1
        )

        XCTAssertEqual(preset.highIsoNr, 3)
        XCTAssertEqual(preset.longExpNr, 1)
    }

    func testWriteResultRetainsNonFatalWarnings() {
        let result = PTPPresetSlotWriteResult(
            slot: 6,
            warnings: ["0xD19C: 0x201C"]
        )

        XCTAssertEqual(result.warnings, ["0xD19C: 0x201C"])
    }

    func testRAFConversionOutcomeDoesNotTreatAcceptedTriggerAsJPEG() {
        let accepted = RAFConversionOutcome.triggerAcceptedOutputNotRetrievable(reason: "timeout")
        let failed = RAFConversionOutcome.failed(message: "upload rejected")
        let jpeg = JPEGFile(name: "result.jpg", data: Data([0xFF]), size: 1, storageID: 0, objectHandle: 0)

        XCTAssertNil(accepted.jpeg)
        XCTAssertNil(failed.jpeg)
        XCTAssertEqual(RAFConversionOutcome.downloadedJPEG(jpeg).jpeg?.data, Data([0xFF]))
    }

    @MainActor
    func testCameraManagerRollsBackConfiguredSlotAfterPartialWriteFailure() async {
        let baseline = PTPClientPresetData(slot: 3, name: "Previous", filmSimulation: 7)
        let client = RecordingPTPClient(
            preset: baseline,
            writeErrors: [PTPError.writeFailed(0xD192, "readback mismatch"), nil]
        )
        let manager = CameraManager()
        await manager.connect(using: client)
        let recipe = Recipe(id: "replace", name: "Replacement", source: "test", sourceUrl: nil)

        do {
            _ = try await manager.importRecipeToCState(recipe, slot: 3)
            XCTFail("Expected write failure")
        } catch let error as PTPPresetSlotWriteRecoveryError {
            XCTAssertEqual(error.baseline, .configured(baseline))
            XCTAssertEqual(error.rollback, .restored)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(client.writtenPresets.count, 2)
        XCTAssertEqual(client.writtenPresets.last, baseline)
    }

    @MainActor
    func testCameraManagerNeverWritesRawZeroEmptySentinelAsRollback() async {
        let client = RecordingPTPClient(
            preset: PTPClientPresetData(slot: 3, isEmptySlot: true),
            writeErrors: [PTPError.writeFailed(0xD192, "readback mismatch")]
        )
        let manager = CameraManager()
        await manager.connect(using: client)
        let recipe = Recipe(id: "replace", name: "Replacement", source: "test", sourceUrl: nil)

        do {
            _ = try await manager.importRecipeToCState(recipe, slot: 3)
            XCTFail("Expected write failure")
        } catch let error as PTPPresetSlotWriteRecoveryError {
            XCTAssertEqual(error.baseline, .emptySentinel)
            XCTAssertEqual(error.rollback, .notAttemptedEmptySentinel)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(client.writtenPresets.count, 1)
    }

    @MainActor
    func testCameraManagerMapsHighISONoiseReductionToD1A1Field() async throws {
        let client = RecordingPTPClient()
        let manager = CameraManager()
        await manager.connect(using: client)
        let recipe = Recipe(
            id: "high-iso-nr",
            name: "High ISO NR",
            source: "test",
            sourceUrl: nil,
            highIsoNr: 3
        )

        _ = try await manager.importRecipeToCState(recipe, slot: 1)

        XCTAssertEqual(client.writtenPreset?.highIsoNr, 0x6000)
        XCTAssertNil(client.writtenPreset?.longExpNr)
    }

    @MainActor
    func testCameraManagerRoutesC7ThroughPresetWrite() async throws {
        let client = RecordingPTPClient()
        let manager = CameraManager()
        await manager.connect(using: client)
        let recipe = Recipe(
            id: "c7",
            name: "C7 Recipe",
            source: "test",
            sourceUrl: nil
        )

        _ = try await manager.importRecipeToCState(recipe, slot: 7)

        XCTAssertEqual(client.writtenSlot, 7)
        XCTAssertEqual(client.writtenPreset?.slot, 7)
        XCTAssertEqual(client.writtenPreset?.name, "C7 Recipe")
    }

    @MainActor
    func testCameraManagerUsesCameraSafePresetLabel() async throws {
        let client = RecordingPTPClient()
        let manager = CameraManager()
        await manager.connect(using: client)
        let recipe = Recipe(
            id: "long-name",
            name: "PRO Negative 160C",
            source: "test",
            sourceUrl: nil
        )

        _ = try await manager.importRecipeToCState(recipe, slot: 4)

        XCTAssertEqual(client.writtenPreset?.name, "PRO Negative 16")
    }

    @MainActor
    func testCameraManagerRejectsSlotsOutsideC1ThroughC7() async {
        let client = RecordingPTPClient()
        let manager = CameraManager()
        await manager.connect(using: client)
        let recipe = Recipe(
            id: "invalid-slot",
            name: "Invalid",
            source: "test",
            sourceUrl: nil
        )

        do {
            _ = try await manager.importRecipeToCState(recipe, slot: 8)
            XCTFail("Expected an invalid C-slot error")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Invalid response: Preset slot must be 1–7")
        }

        XCTAssertNil(client.writtenPreset)
    }

    @MainActor
    func testCameraManagerCanRetryAfterConnectionFailure() async {
        let manager = CameraManager()
        let failing = RecordingPTPClient(connectError: PTPError.connectionFailed("USB busy"))
        await manager.connect(using: failing)

        XCTAssertEqual(manager.status, .error)
        XCTAssertNotNil(manager.lastError)
        XCTAssertFalse(failing.isConnected)

        let succeeding = RecordingPTPClient()
        await manager.connect(using: succeeding)

        XCTAssertEqual(manager.status, .connected)
        XCTAssertNil(manager.lastError)
    }

    @MainActor
    func testCameraManagerReportsUnsupportedActiveTelemetryExplicitly() async {
        let client = RecordingPTPClient()
        let manager = CameraManager()

        await manager.connect(using: client)

        XCTAssertEqual(
            manager.activeSettingsState,
            .unavailable(.unsupportedInUSBRAWMode)
        )
        XCTAssertNil(manager.activeSettingsState.settings)
    }

    @MainActor
    func testCameraManagerRetainsAvailableActiveTelemetry() async {
        let client = RecordingPTPClient(propertyResponses: [
            0xD001: .uint32(7),
            0x500F: .uint32(400)
        ])
        let manager = CameraManager()

        await manager.connect(using: client)

        XCTAssertEqual(
            manager.activeSettingsState,
            .available(["FilmSim": UInt32(7), "ISO": UInt32(400)])
        )
        XCTAssertEqual(manager.activeSettingsState.settings?["FilmSim"], UInt32(7))
    }

    @MainActor
    func testSlotRefreshReportsPartialFailuresWithoutFabricatingSlots() async {
        let client = RecordingPTPClient(readFailures: [2, 6])
        let manager = CameraManager()
        await manager.connect(using: client)

        let result = await manager.readCStatesWithStatus()

        XCTAssertEqual(result.presets.map(\.slot), [1, 3, 4, 5, 7])
        XCTAssertEqual(result.failures.map(\.slot), [2, 6])
    }
}

private final class RecordingPTPClient: PTPClientProtocol, @unchecked Sendable {
    var isConnected = false
    var cameraInfo = PTPCameraInfo(model: "Test Camera")
    var writtenPreset: PTPClientPresetData?
    var writtenSlot: Int?
    var writtenPresets: [PTPClientPresetData] = []
    let connectError: Error?
    let readFailures: Set<Int>
    let preset: PTPClientPresetData?
    let propertyResponses: [UInt16: PTPPropertyResponse]
    private var writeErrors: [Error?]

    init(
        connectError: Error? = nil,
        readFailures: Set<Int> = [],
        preset: PTPClientPresetData? = nil,
        propertyResponses: [UInt16: PTPPropertyResponse] = [:],
        writeErrors: [Error?] = []
    ) {
        self.connectError = connectError
        self.readFailures = readFailures
        self.preset = preset
        self.propertyResponses = propertyResponses
        self.writeErrors = writeErrors
    }

    func connect() async throws {
        if let connectError { throw connectError }
        isConnected = true
    }
    func disconnect() { isConnected = false }
    func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse {
        propertyResponses[code] ?? .unsupported
    }
    func writeProperty(_ code: UInt16, value: Int32) async throws {}
    func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        if readFailures.contains(index) {
            throw PTPError.readFailed(0xD18C, "slot unavailable")
        }
        return preset ?? PTPClientPresetData(slot: index)
    }
    func writePresetSlot(_ index: Int, data: PTPClientPresetData) async throws -> PTPPresetSlotWriteResult {
        writtenSlot = index
        writtenPreset = data
        writtenPresets.append(data)
        if !writeErrors.isEmpty {
            if let error = writeErrors.removeFirst() {
                throw error
            }
        }
        return PTPPresetSlotWriteResult(slot: index)
    }
    func readNativeProfile() async throws -> Data { Data() }
    func writePTPSettings(from recipe: Recipe) async throws {}
    func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)?) async -> RAFConversionOutcome {
        .failed(message: "not implemented")
    }
    func capturePreview() async throws -> JPEGFile? { nil }
}
