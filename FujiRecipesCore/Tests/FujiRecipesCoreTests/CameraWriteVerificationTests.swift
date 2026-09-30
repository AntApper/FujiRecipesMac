import XCTest
@testable import FujiRecipesCore

final class CameraWriteVerificationTests: XCTestCase {
    @MainActor
    func testSuccessfulWriteReturnsObservedPostWriteSnapshot() async throws {
        let baseline = PTPClientPresetData(slot: 2, name: "Before", filmSimulation: 3)
        let observed = PTPClientPresetData(slot: 2, name: "Camera Truth", filmSimulation: 7)
        let client = WriteVerificationPTPClient(
            slot: 2,
            baseline: baseline,
            postWriteSnapshot: observed
        )
        let manager = CameraManager()
        await manager.connect(using: client)

        let recipe = Recipe(id: "truth", name: "Requested", source: "test", sourceUrl: nil)
        let result = try await manager.importRecipeToCState(recipe, slot: 2)

        XCTAssertEqual(result.baseline, .configured(baseline))
        XCTAssertEqual(result.observedSnapshot, observed)
        XCTAssertEqual(result.rollback, .notNeeded)
        XCTAssertEqual(client.writes.count, 1)
        XCTAssertEqual(client.postWriteReadCount, 1)
    }

    @MainActor
    func testPostWriteReadFailureRestoresConfiguredBaselineAndReportsVerificationPhase() async {
        let baseline = PTPClientPresetData(slot: 5, name: "Before", filmSimulation: 3)
        let client = WriteVerificationPTPClient(
            slot: 5,
            baseline: baseline,
            postWriteSnapshot: nil,
            postWriteReadError: PTPError.readFailed(0xD18C, "camera stopped responding")
        )
        let manager = CameraManager()
        await manager.connect(using: client)

        let recipe = Recipe(id: "verify-failure", name: "Requested", source: "test", sourceUrl: nil)

        do {
            _ = try await manager.importRecipeToCState(recipe, slot: 5)
            XCTFail("Expected post-write verification failure")
        } catch let error as PTPPresetSlotWriteRecoveryError {
            XCTAssertEqual(error.failurePhase, .postWriteVerification)
            XCTAssertEqual(error.baseline, .configured(baseline))
            XCTAssertEqual(error.rollback, .restored)
            XCTAssertTrue(error.localizedDescription.contains("post-write verification failed"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(client.writes.count, 2)
        XCTAssertEqual(client.writes.last, baseline)
        XCTAssertEqual(client.postWriteReadCount, 2, "rollback must read the restored baseline back")
    }
}

private final class WriteVerificationPTPClient: PTPClientProtocol, @unchecked Sendable {
    var isConnected = false
    var cameraInfo = PTPCameraInfo(model: "Test Camera")
    private let slot: Int
    private let baseline: PTPClientPresetData
    private let postWriteSnapshot: PTPClientPresetData?
    private let postWriteReadError: Error?

    private(set) var writes: [PTPClientPresetData] = []
    private(set) var postWriteReadCount = 0

    init(
        slot: Int,
        baseline: PTPClientPresetData,
        postWriteSnapshot: PTPClientPresetData?,
        postWriteReadError: Error? = nil
    ) {
        self.slot = slot
        self.baseline = baseline
        self.postWriteSnapshot = postWriteSnapshot
        self.postWriteReadError = postWriteReadError
    }

    func connect() async throws {
        isConnected = true
    }

    func disconnect() {
        isConnected = false
    }

    func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse {
        code == PTPProperty.presetSlot ? .uint32(UInt32(slot)) : .unsupported
    }

    func writeProperty(_ code: UInt16, value: Int32) async throws {}

    func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        guard index == slot else {
            return PTPClientPresetData(slot: index)
        }

        if !writes.isEmpty {
            postWriteReadCount += 1
            if writes.count > 1 { return baseline }
            if let postWriteReadError {
                throw postWriteReadError
            }
            return postWriteSnapshot ?? baseline
        }

        return baseline
    }

    func writePresetSlot(_ index: Int, data: PTPClientPresetData) async throws -> PTPPresetSlotWriteResult {
        XCTAssertEqual(index, slot)
        writes.append(data)
        return PTPPresetSlotWriteResult(slot: index)
    }

    func readNativeProfile() async throws -> Data {
        Data()
    }

    func writePTPSettings(from recipe: Recipe) async throws {}

    func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)?) async -> RAFConversionOutcome {
        .failed(message: "not implemented")
    }

    func capturePreview() async throws -> JPEGFile? {
        nil
    }
}
