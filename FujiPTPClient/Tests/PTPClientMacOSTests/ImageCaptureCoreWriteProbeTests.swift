import Foundation
import XCTest
import FujiRecipesCore
@testable import PTPClientMacOS

final class ImageCaptureCoreWriteProbeTests: XCTestCase, @unchecked Sendable {
    func testReadRefusesUnknownOriginalSelectorWithoutSelectingTarget() async {
        for response in unknownSelectors {
            let client = FakeProbeClient(selectorResponses: [1: response])
            let result = await ImageCaptureCoreReadProbe.readSlot(using: client)
            XCTAssertFalse(result.selectionAttempted)
            XCTAssertFalse(result.succeeded)
            XCTAssertFalse(result.recoveryRequired)
            XCTAssertNil(result.originalSelector)
            XCTAssertTrue(client.writes.isEmpty)
            XCTAssertEqual(client.readCount, 0)
        }
    }

    func testWriteRefusesUnknownOriginalSelectorWithoutSelectingOrSaving() async {
        for response in unknownSelectors {
            let client = FakeProbeClient(selectorResponses: [1: response])
            let saved = SavedProbeBaselines()
            let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: saved.save)
            XCTAssertFalse(result.selectionAttempted)
            XCTAssertFalse(result.mutationAttempted)
            XCTAssertFalse(result.succeeded)
            XCTAssertFalse(result.recoveryRequired)
            XCTAssertNil(result.originalSelector)
            XCTAssertNil(result.baseline)
            XCTAssertTrue(client.writes.isEmpty)
            XCTAssertTrue(saved.values.isEmpty)
            XCTAssertEqual(client.readCount, 0)
        }
    }

    func testInvalidTargetDoesNotReadOrSelectInEitherPath() async {
        for slot in [0, 8] {
            let client = FakeProbeClient()
            let read = await ImageCaptureCoreReadProbe.readSlot(using: client, slot: slot)
            let write = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, slot: slot, saveBaseline: { _ in
                XCTFail("An invalid target must not save a baseline")
            })
            XCTAssertFalse(read.succeeded)
            XCTAssertFalse(write.succeeded)
            XCTAssertTrue(client.operations.isEmpty)
        }
    }

    func testReadSuccessRestoresOriginalSelectorWithoutWritingRecipeProperties() async {
        let client = FakeProbeClient()
        let result = await ImageCaptureCoreReadProbe.readSlot(using: client)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.originalSelector, 2)
        XCTAssertEqual(result.preset?.slot, 4)
        XCTAssertEqual(result.verification, .verified)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertFalse(result.recoveryRequired)
        XCTAssertEqual(client.selector, 2)
        XCTAssertEqual(client.writes, [.init(code: 0xD18C, value: 4), .init(code: 0xD18C, value: 2)])
        XCTAssertEqual(client.sharpness(in: 4), 10)
        XCTAssertEqual(client.operations.first, .readProperty(0xD18C))
        XCTAssertEqual(client.operations.last, .readProperty(0xD18C))
    }

    func testReadAlreadySelectedTargetStillVerifiesOriginalSelector() async {
        let client = FakeProbeClient(selector: 4, selectorResponses: [1: .int32(4)])
        let result = await ImageCaptureCoreReadProbe.readSlot(using: client)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.originalSelector, 4)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(client.selector, 4)
        XCTAssertEqual(client.writes, [.init(code: 0xD18C, value: 4)])
        XCTAssertEqual(client.operations.last, .readProperty(0xD18C))
    }

    func testRecoverableReadFailureAfterSelectionRestoresOriginal() async {
        let client = FakeProbeClient(reads: [.failure])
        let result = await ImageCaptureCoreReadProbe.readSlot(using: client)
        XCTAssertNotEqual(result.verification, .verified)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.recoveryRequired)
        XCTAssertNil(result.preset)
        XCTAssertEqual(client.selector, 2)
        XCTAssertTrue(client.sharpnessWrites.isEmpty)
    }

    func testReadCancellationAfterSelectionDoesNotCancelRecovery() async {
        let client = FakeProbeClient(reads: [.cancelCaller])
        let result = await Task {
            await ImageCaptureCoreReadProbe.readSlot(using: client)
        }.value
        XCTAssertNotEqual(result.verification, .verified)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.recoveryRequired)
        XCTAssertEqual(client.selector, 2)
        XCTAssertTrue(client.sharpnessWrites.isEmpty)
    }

    func testReadWrongSnapshotSlotFailsAndRestoresOriginalSelector() async {
        let client = FakeProbeClient(reads: [.snapshot(configuredSnapshot(slot: 5))])
        let result = await ImageCaptureCoreReadProbe.readSlot(using: client)
        XCTAssertNotEqual(result.verification, .verified)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(client.selector, 2)
    }

    func testReadIndependentlyChecksTargetSelector() async {
        let client = FakeProbeClient(selectorResponses: [2: .uint32(5)])
        let result = await ImageCaptureCoreReadProbe.readSlot(using: client)
        XCTAssertNotEqual(result.verification, .verified)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(client.selector, 2)
    }

    func testReadDisconnectRetainsOriginalSelectorAndReportsRecoveryRequired() async {
        let client = FakeProbeClient(reads: [.disconnect])
        let reports = RecordedProbeMessages()
        let result = await ImageCaptureCoreReadProbe.readSlot(using: client, report: reports.record)
        guard case .unavailable(let reason) = result.selectorRestoration else {
            return XCTFail("A disconnected camera cannot be reported as restored")
        }
        XCTAssertTrue(reason.contains("C2"))
        XCTAssertEqual(result.originalSelector, 2)
        XCTAssertTrue(result.recoveryRequired)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(client.writes, [.init(code: 0xD18C, value: 4)])
        XCTAssertTrue(reports.values.contains { $0.contains("original_selector=C2") })
        XCTAssertTrue(reports.values.contains { $0.contains("unavailable") && $0.contains("C2") })
    }

    func testReadSuccessDoesNotMaskSelectorRestoreMismatch() async {
        let client = FakeProbeClient(ignoredSelectorWrites: [2])
        let result = await ImageCaptureCoreReadProbe.readSlot(using: client)
        XCTAssertEqual(result.verification, .verified)
        guard case .failed(let reason) = result.selectorRestoration else {
            return XCTFail("A selector that remains on C4 must fail restoration")
        }
        XCTAssertTrue(reason.contains("C2"))
        XCTAssertTrue(reason.contains("C4"))
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(result.recoveryRequired)
        XCTAssertEqual(client.selector, 4)
    }

    func testReadRecoversFromSelectorReadErrorDuringCleanup() async {
        let client = FakeProbeClient(selectorResponses: [3: .error(.readFailed(0xD18C, "recoverable"))])
        let result = await ImageCaptureCoreReadProbe.readSlot(using: client)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(client.selector, 2)
    }

    func testReadVerifiesOriginalAfterRecoverableRestoreAcknowledgementFailure() async {
        let client = FakeProbeClient(selectorFailures: [2: .afterMutation])
        let reports = RecordedProbeMessages()
        let result = await ImageCaptureCoreReadProbe.readSlot(using: client, report: reports.record)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertFalse(result.recoveryRequired)
        XCTAssertEqual(client.selector, 2)
        XCTAssertTrue(reports.values.contains { $0.contains("selector_restore_write_ack=") })
        XCTAssertEqual(client.operations.last, .readProperty(0xD18C))
    }

    func testMissingSharpnessBaselineRefusesSharpnessMutationAndRecoversSelection() async {
        let client = FakeProbeClient(reads: [.snapshot(configuredSnapshot(sharpness: nil))])
        let saved = SavedProbeBaselines()
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: saved.save)
        XCTAssertFalse(result.mutationAttempted)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.recoveryRequired)
        XCTAssertTrue(client.sharpnessWrites.isEmpty)
        XCTAssertTrue(saved.values.isEmpty)
        XCTAssertNil(result.baseline)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(client.selector, 2)
    }

    func testInvalidRawSharpnessRefusesSharpnessMutation() async {
        for sharpness in [-41, -1, 5, 41, 65_535, Int32.max] {
            let client = FakeProbeClient(reads: [.snapshot(configuredSnapshot(sharpness: sharpness))])
            let saved = SavedProbeBaselines()
            let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: saved.save)
            XCTAssertFalse(result.mutationAttempted, "Invalid raw value \(sharpness)")
            XCTAssertFalse(result.succeeded)
            XCTAssertNil(result.baseline)
            XCTAssertTrue(client.sharpnessWrites.isEmpty)
            XCTAssertTrue(saved.values.isEmpty)
            XCTAssertEqual(result.selectorRestoration, .verified)
            XCTAssertEqual(client.selector, 2)
        }
    }

    func testEmptySlotRefusesWriteEvenWithWritableSharpness() async {
        let empty = PTPClientPresetData(slot: 4, isEmptySlot: true, sharpness: 10)
        let client = FakeProbeClient(reads: [.snapshot(empty)])
        let saved = SavedProbeBaselines()
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: saved.save)
        XCTAssertFalse(result.mutationAttempted)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(client.sharpnessWrites.isEmpty)
        XCTAssertTrue(saved.values.isEmpty)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(client.selector, 2)
    }

    func testNativeRawZeroSentinelIsReadableButCannotBeWriteBaseline() async {
        let empty = rawZeroSnapshot()
        XCTAssertTrue(empty.isEmptySlot)
        XCTAssertEqual(empty.sharpness, 0)

        let readClient = FakeProbeClient(reads: [.snapshot(empty)])
        let read = await ImageCaptureCoreReadProbe.readSlot(using: readClient)
        XCTAssertTrue(read.succeeded)
        XCTAssertEqual(read.preset, empty)
        XCTAssertEqual(readClient.selector, 2)
        XCTAssertTrue(readClient.sharpnessWrites.isEmpty)

        let writeClient = FakeProbeClient(reads: [.snapshot(empty)])
        let saved = SavedProbeBaselines()
        let write = await ImageCaptureCoreWriteProbe.verifyWrite(using: writeClient, saveBaseline: saved.save)
        XCTAssertFalse(write.succeeded)
        XCTAssertFalse(write.mutationAttempted)
        XCTAssertNil(write.baseline)
        XCTAssertTrue(writeClient.sharpnessWrites.isEmpty)
        XCTAssertTrue(saved.values.isEmpty)
        XCTAssertEqual(write.selectorRestoration, .verified)
        XCTAssertEqual(writeClient.selector, 2)
    }

    func testWrongSlotBaselineRefusesSharpnessMutationAndRecoversSelection() async {
        let client = FakeProbeClient(reads: [.snapshot(configuredSnapshot(slot: 5))])
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in })
        XCTAssertFalse(result.mutationAttempted)
        XCTAssertTrue(client.sharpnessWrites.isEmpty)
        XCTAssertNil(result.baseline)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(client.selector, 2)
    }

    func testInitialReadFailureStillRestoresSelectionWithoutBaseline() async {
        let client = FakeProbeClient(reads: [.failure])
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in
            XCTFail("A failed baseline read cannot produce a baseline")
        })
        XCTAssertFalse(result.mutationAttempted)
        XCTAssertFalse(result.succeeded)
        XCTAssertNil(result.baseline)
        XCTAssertTrue(client.sharpnessWrites.isEmpty)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(client.selector, 2)
    }

    func testFailureToSaveBaselineRefusesSharpnessMutationAndRecoversSelection() async {
        let client = FakeProbeClient()
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in
            throw ProbeFixtureError.failure
        })
        XCTAssertFalse(result.mutationAttempted)
        XCTAssertTrue(client.sharpnessWrites.isEmpty)
        XCTAssertNil(result.baseline)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(client.selector, 2)
    }

    func testChangedSharpnessBaselineIsNotOverwritten() async {
        let client = FakeProbeClient()
        let saved = SavedProbeBaselines()
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { baseline in
            saved.save(baseline)
            client.setSharpness(30, in: 4)
        })
        XCTAssertFalse(result.mutationAttempted)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.recoveryRequired)
        XCTAssertTrue(client.sharpnessWrites.isEmpty)
        XCTAssertEqual(saved.values.first?.sharpness, 10)
        XCTAssertEqual(result.baseline?.sharpness, 10)
        XCTAssertEqual(client.sharpness(in: 4), 30)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(client.selector, 2)
        guard case .notAttempted = result.sharpnessRestoration else {
            return XCTFail("A changed baseline must not be overwritten during cleanup")
        }
    }

    func testWrongSelectionBeforeBaselineRecheckRefusesSharpnessReadAndWrite() async {
        let client = FakeProbeClient()
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in
            client.setSelector(5)
        })
        XCTAssertFalse(result.mutationAttempted)
        XCTAssertTrue(client.sharpnessWrites.isEmpty)
        XCTAssertFalse(client.operations.contains(.readProperty(0xD1A0)))
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(client.selector, 2)
    }

    func testTargetSelectorIsCheckedAgainImmediatelyBeforeTestWrite() async {
        let client = FakeProbeClient()
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in }, report: { message in
            if message.hasPrefix("writing C4 sharpness=") { client.setSelector(5) }
        })
        XCTAssertFalse(result.mutationAttempted)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(client.operations.contains(.readProperty(0xD1A0)))
        XCTAssertTrue(client.sharpnessWrites.isEmpty)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(client.selector, 2)
    }

    func testInvalidIndependentSharpnessReadRefusesWrite() async {
        for response in [PTPPropertyResponse.unsupported, .uint32(0xFFFF), .int32(5)] {
            let client = FakeProbeClient(sharpnessResponses: [1: response])
            let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in })
            XCTAssertFalse(result.mutationAttempted)
            XCTAssertFalse(result.succeeded)
            XCTAssertTrue(client.sharpnessWrites.isEmpty)
            XCTAssertEqual(result.baseline?.sharpness, 10)
            XCTAssertEqual(result.selectorRestoration, .verified)
            XCTAssertEqual(client.selector, 2)
        }
    }

    func testRecoverableReadbackExceptionRestoresExactNegativeBaselineAndSelection() async {
        let client = FakeProbeClient(reads: [.snapshot(configuredSnapshot(sharpness: -10)), .failure])
        let saved = SavedProbeBaselines()
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: saved.save)
        XCTAssertEqual(result.sharpnessRestoration, .verified)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertNotEqual(result.verification, .verified)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.recoveryRequired)
        XCTAssertEqual(saved.values.first?.sharpness, -10)
        XCTAssertEqual(saved.values.first?.originalSelector, 2)
        XCTAssertEqual(client.sharpnessWrites.map(\.value), [20, -10])
        XCTAssertEqual(client.sharpness(in: 4), -10)
        XCTAssertEqual(client.selector, 2)
        XCTAssertEqual(client.readCount, 3)
        assertSharpnessWritesAreGuarded(client)
    }

    func testReadbackMismatchRestoresBothStatesButDoesNotReportWriteSuccess() async {
        let client = FakeProbeClient(reads: [.snapshot(configuredSnapshot()), .snapshot(configuredSnapshot(sharpness: 0))])
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in })
        XCTAssertNotEqual(result.verification, .verified)
        XCTAssertEqual(result.sharpnessRestoration, .verified)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.recoveryRequired)
        XCTAssertEqual(client.sharpnessWrites.map(\.value), [20, 10])
        XCTAssertEqual(client.sharpness(in: 4), 10)
        XCTAssertEqual(client.selector, 2)
    }

    func testRecoverableTestWriteAcknowledgementFailureStillRestoresBothStates() async {
        let client = FakeProbeClient(sharpnessFailures: [1: .afterMutation])
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in })
        XCTAssertTrue(result.mutationAttempted)
        XCTAssertEqual(result.sharpnessRestoration, .verified)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertNotEqual(result.verification, .verified)
        XCTAssertFalse(result.succeeded)
        XCTAssertFalse(result.recoveryRequired)
        XCTAssertEqual(client.sharpnessWrites.map(\.value), [20, 10])
        XCTAssertEqual(client.sharpness(in: 4), 10)
        XCTAssertEqual(client.selector, 2)
    }

    func testDisconnectPreservesRecoveryFileAndReportsBothUnavailableOutcomes() async throws {
        let client = FakeProbeClient(reads: [.snapshot(configuredSnapshot(sharpness: -20)), .disconnect])
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("fuji-probe-test-baseline-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { baseline in
            try JSONEncoder().encode(baseline).write(to: file, options: .withoutOverwriting)
        })
        let preserved = try JSONDecoder().decode(ImageCaptureCoreProbeBaseline.self, from: Data(contentsOf: file))
        XCTAssertEqual(preserved.slot, 4)
        XCTAssertEqual(preserved.sharpness, -20)
        XCTAssertEqual(preserved.originalSelector, 2)
        XCTAssertEqual(preserved.cameraModel, "Fake X100VI")
        XCTAssertEqual(result.baseline, preserved)
        guard case .unavailable(let sharpnessReason) = result.sharpnessRestoration,
              case .unavailable(let selectorReason) = result.selectorRestoration else {
            return XCTFail("Neither restoration can be verified after disconnect")
        }
        XCTAssertTrue(sharpnessReason.contains("C4"))
        XCTAssertTrue(sharpnessReason.contains("-20"))
        XCTAssertTrue(selectorReason.contains("C2"))
        XCTAssertTrue(result.recoveryRequired)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(client.sharpnessWrites.map(\.value), [20])
    }

    func testSharpnessRestoreMismatchRequiresRecoveryEvenWithSelectorRestored() async {
        let client = FakeProbeClient(reads: [
            .snapshot(configuredSnapshot()),
            .snapshot(configuredSnapshot(sharpness: 20)),
            .snapshot(configuredSnapshot(sharpness: 0))
        ])
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in })
        XCTAssertEqual(result.verification, .verified)
        guard case .failed = result.sharpnessRestoration else {
            return XCTFail("Mismatched sharpness restoration must fail verification")
        }
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertTrue(result.recoveryRequired)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(result.baseline?.sharpness, 10)
        XCTAssertEqual(result.baseline?.originalSelector, 2)
        XCTAssertEqual(client.selector, 2)
    }

    func testFailedSharpnessRestoreStillRestoresSelectorAndRetainsBaseline() async {
        let client = FakeProbeClient(sharpnessFailures: [2: .beforeMutation])
        let saved = SavedProbeBaselines()
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: saved.save)
        XCTAssertEqual(result.verification, .verified)
        guard case .failed = result.sharpnessRestoration else {
            return XCTFail("An unapplied baseline must remain unverified")
        }
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertTrue(result.recoveryRequired)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(saved.values.first?.sharpness, 10)
        XCTAssertEqual(saved.values.first?.originalSelector, 2)
        XCTAssertEqual(client.sharpness(in: 4), 20)
        XCTAssertEqual(client.selector, 2)
    }

    func testTargetSelectorIsCheckedImmediatelyBeforeSharpnessRestoration() async {
        // Fifth selector read is immediately before the restoration write.
        let client = FakeProbeClient(selectorResponses: [5: .uint32(5)])
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in })
        XCTAssertEqual(result.verification, .verified)
        guard case .failed(let reason) = result.sharpnessRestoration else {
            return XCTFail("A mismatched target must prevent the sharpness restoration write")
        }
        XCTAssertTrue(reason.contains("C5"))
        XCTAssertEqual(client.sharpnessWrites.map(\.value), [20])
        XCTAssertEqual(client.sharpness(in: 4), 20)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(client.selector, 2)
        XCTAssertTrue(result.recoveryRequired)
        XCTAssertFalse(result.succeeded)
    }

    func testSelectorRestoreMismatchCannotBeMaskedBySharpnessRestoreSuccess() async {
        // Fifth selector write restores C2 after target selection and readbacks.
        let client = FakeProbeClient(ignoredSelectorWrites: [5])
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in })
        XCTAssertEqual(result.verification, .verified)
        XCTAssertEqual(result.sharpnessRestoration, .verified)
        guard case .failed = result.selectorRestoration else {
            return XCTFail("Selector restoration is independent of sharpness restoration")
        }
        XCTAssertEqual(client.sharpness(in: 4), 10)
        XCTAssertEqual(client.selector, 4)
        XCTAssertEqual(result.baseline?.originalSelector, 2)
        XCTAssertTrue(result.recoveryRequired)
        XCTAssertFalse(result.succeeded)
    }

    func testCallerCancellationAfterMutationDoesNotCancelEitherRecovery() async {
        let client = FakeProbeClient(reads: [.snapshot(configuredSnapshot()), .cancelCaller])
        let result = await Task {
            await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in })
        }.value
        XCTAssertNotEqual(result.verification, .verified)
        XCTAssertEqual(result.sharpnessRestoration, .verified)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertFalse(result.recoveryRequired)
        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(client.sharpnessWrites.map(\.value), [20, 10])
        XCTAssertEqual(client.sharpness(in: 4), 10)
        XCTAssertEqual(client.selector, 2)
        assertSharpnessWritesAreGuarded(client)
    }

    func testCancellationAfterBaselineCaptureRestoresSelectionWithoutSharpnessWrite() async {
        let client = FakeProbeClient()
        let result = await Task {
            await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            })
        }.value
        XCTAssertFalse(result.mutationAttempted)
        XCTAssertNotEqual(result.verification, .verified)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(result.baseline?.sharpness, 10)
        XCTAssertEqual(result.baseline?.originalSelector, 2)
        XCTAssertFalse(result.recoveryRequired)
        XCTAssertFalse(result.succeeded)
        XCTAssertTrue(client.sharpnessWrites.isEmpty)
        XCTAssertEqual(client.selector, 2)
    }

    func testSuccessRequiresBothRestorationsAndAcceptsConfiguredNamelessZero() async {
        let configured = rawZeroSnapshot(filmSimulation: 1)
        XCTAssertFalse(configured.isEmptySlot)
        XCTAssertTrue(configured.name.isEmpty)
        let client = FakeProbeClient(reads: [.snapshot(configured)])
        let saved = SavedProbeBaselines()
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: saved.save)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.verification, .verified)
        XCTAssertEqual(result.sharpnessRestoration, .verified)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(result.restoration, result.sharpnessRestoration)
        XCTAssertEqual(result.baseline?.sharpness, 0)
        XCTAssertEqual(saved.values.first?.sharpness, 0)
        XCTAssertEqual(saved.values.first?.originalSelector, 2)
        XCTAssertEqual(client.sharpnessWrites.map(\.value), [20, 0])
        XCTAssertEqual(client.sharpness(in: 4), 0)
        XCTAssertEqual(client.sharpness(in: 2), 10)
        XCTAssertEqual(client.selector, 2)
        assertSharpnessWritesAreGuarded(client)
    }

    func testWritableBoundariesAndExistingTestValueRestoreExactRawBaseline() async {
        for sharpness in [-40, -20, 20, 40] as [Int32] {
            let client = FakeProbeClient(reads: [.snapshot(configuredSnapshot(sharpness: sharpness))])
            let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in })
            XCTAssertTrue(result.succeeded, "Writable raw value \(sharpness)")
            XCTAssertEqual(client.sharpnessWrites.map(\.value), [sharpness == 20 ? 0 : 20, sharpness])
            XCTAssertEqual(client.sharpness(in: 4), sharpness)
            XCTAssertEqual(client.selector, 2)
            assertSharpnessWritesAreGuarded(client)
        }
    }

    func testRecoverableRestoreTargetAcknowledgementErrorStillChecksTargetAndRestores() async {
        // Third selector write reselects C4 for sharpness restoration.
        let client = FakeProbeClient(selectorFailures: [3: .afterMutation])
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in })
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.sharpnessRestoration, .verified)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertEqual(client.sharpness(in: 4), 10)
        XCTAssertEqual(client.selector, 2)
        assertSharpnessWritesAreGuarded(client)
    }

    func testRestoreSharpnessAcknowledgementErrorRequiresIndependentReadback() async {
        let client = FakeProbeClient(sharpnessFailures: [2: .afterMutation])
        let reports = RecordedProbeMessages()
        let result = await ImageCaptureCoreWriteProbe.verifyWrite(using: client, saveBaseline: { _ in }, report: reports.record)
        XCTAssertTrue(result.succeeded)
        XCTAssertEqual(result.sharpnessRestoration, .verified)
        XCTAssertEqual(result.selectorRestoration, .verified)
        XCTAssertFalse(result.recoveryRequired)
        XCTAssertEqual(client.sharpness(in: 4), 10)
        XCTAssertEqual(client.selector, 2)
        XCTAssertTrue(reports.values.contains { $0.contains("sharpness_restore_write_ack=") })
        XCTAssertEqual(client.readCount, 3)
    }

    func testLegacyBaselineDecodesWithoutInventingOriginalSelector() throws {
        let legacy = Data(#"{"slot":4,"sharpness":-10,"cameraModel":"Fake X100VI","capturedAt":123}"#.utf8)
        let baseline = try JSONDecoder().decode(ImageCaptureCoreProbeBaseline.self, from: legacy)
        XCTAssertEqual(baseline.slot, 4)
        XCTAssertEqual(baseline.sharpness, -10)
        XCTAssertNil(baseline.originalSelector)
    }

    func testBaselineRoundTripRetainsOriginalSelectorAndExactSharpness() throws {
        let baseline = ImageCaptureCoreProbeBaseline(
            slot: 4, sharpness: -40, cameraModel: "Fake X100VI",
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000), originalSelector: 7
        )
        let data = try JSONEncoder().encode(baseline)
        XCTAssertEqual(try JSONDecoder().decode(ImageCaptureCoreProbeBaseline.self, from: data), baseline)
    }

    private var unknownSelectors: [PTPPropertyResponse] {
        [.uint32(0), .uint32(8), .int32(-1), .unsupported, .data(Data()), .error(.readFailed(0xD18C, "unknown"))]
    }

    private func assertSharpnessWritesAreGuarded(_ client: FakeProbeClient, file: StaticString = #filePath, line: UInt = #line) {
        let operations = client.operations
        for index in operations.indices {
            if case .writeProperty(0xD1A0, _, let selector) = operations[index] {
                XCTAssertEqual(selector, 4, file: file, line: line)
                XCTAssertGreaterThan(index, 0, file: file, line: line)
                if index > 0 {
                    XCTAssertEqual(operations[index - 1], .readProperty(0xD18C), file: file, line: line)
                }
            }
        }
    }
}

private enum ProbeFixtureError: Error { case failure }

private func configuredSnapshot(slot: Int = 4, sharpness: Int32? = 10) -> PTPClientPresetData {
    PTPClientPresetData(slot: slot, name: "Configured C\(slot)", filmSimulation: 1, sharpness: sharpness)
}

private func rawZeroSnapshot(filmSimulation: UInt32 = 0) -> PTPClientPresetData {
    var values: [UInt16: PTPPropertyResponse] = [0xD18D: .data(Data([0]))]
    for code in UInt16(0xD18E)...UInt16(0xD1A4) { values[code] = .uint32(0) }
    values[0xD192] = .uint32(filmSimulation)
    return ImageCaptureCorePTPClient.presetData(slot: 4, values: values)
}

private final class SavedProbeBaselines: @unchecked Sendable {
    private let lock = NSLock()
    private var baselines: [ImageCaptureCoreProbeBaseline] = []
    var values: [ImageCaptureCoreProbeBaseline] { lock.withLock { baselines } }
    func save(_ baseline: ImageCaptureCoreProbeBaseline) { lock.withLock { baselines.append(baseline) } }
}

private final class RecordedProbeMessages: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [String] = []
    var values: [String] { lock.withLock { messages } }
    func record(_ message: String) { lock.withLock { messages.append(message) } }
}

private final class FakeProbeClient: ImageCaptureCoreWriteProbeClient, @unchecked Sendable {
    enum ReadStep: Sendable {
        case snapshot(PTPClientPresetData)
        case failure, disconnect, cancelCaller
    }

    enum WriteFailure: Sendable, Equatable { case beforeMutation, afterMutation }

    struct Write: Equatable {
        let code: UInt16
        let value: Int32
    }

    enum Operation: Equatable {
        case readProperty(UInt16)
        case readSlot(Int)
        case writeProperty(UInt16, Int32, Int)
    }

    let cameraInfo = PTPCameraInfo(model: "Fake X100VI")
    private let lock = NSLock()
    private var reads: [ReadStep]
    private var recordedWrites: [Write] = []
    private var recordedOperations: [Operation] = []
    private var count = 0
    private var selectorReadCount = 0
    private var sharpnessReadCount = 0
    private var selectorWriteCount = 0
    private var sharpnessWriteCount = 0
    private var selected: Int
    private var sharpnessBySlot: [Int: Int32] = [:]
    private var connected = true
    private let selectorResponses: [Int: PTPPropertyResponse]
    private let sharpnessResponses: [Int: PTPPropertyResponse]
    private let selectorFailures: [Int: WriteFailure]
    private let sharpnessFailures: [Int: WriteFailure]
    private let ignoredSelectorWrites: Set<Int>

    var isConnected: Bool { lock.withLock { connected } }
    var selector: Int { lock.withLock { selected } }
    var writes: [Write] { lock.withLock { recordedWrites } }
    var sharpnessWrites: [Write] { writes.filter { $0.code == 0xD1A0 } }
    var operations: [Operation] { lock.withLock { recordedOperations } }
    var readCount: Int { lock.withLock { count } }

    init(
        reads: [ReadStep] = [], selector: Int = 2,
        selectorResponses: [Int: PTPPropertyResponse] = [:],
        sharpnessResponses: [Int: PTPPropertyResponse] = [:],
        selectorFailures: [Int: WriteFailure] = [:],
        sharpnessFailures: [Int: WriteFailure] = [:],
        ignoredSelectorWrites: Set<Int> = []
    ) {
        self.reads = reads
        self.selected = selector
        self.selectorResponses = selectorResponses
        self.sharpnessResponses = sharpnessResponses
        self.selectorFailures = selectorFailures
        self.sharpnessFailures = sharpnessFailures
        self.ignoredSelectorWrites = ignoredSelectorWrites
    }

    func setSharpness(_ value: Int32, in slot: Int) { lock.withLock { sharpnessBySlot[slot] = value } }
    func sharpness(in slot: Int) -> Int32 { lock.withLock { sharpnessBySlot[slot] ?? 10 } }
    func setSelector(_ slot: Int) { lock.withLock { selected = slot } }

    func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse {
        try Task.checkCancellation()
        return try lock.withLock {
            guard connected else { throw PTPError.notConnected }
            recordedOperations.append(.readProperty(code))
            switch code {
            case 0xD18C:
                selectorReadCount += 1
                return selectorResponses[selectorReadCount] ?? .uint32(UInt32(truncatingIfNeeded: selected))
            case 0xD1A0:
                sharpnessReadCount += 1
                // Match the native client's zero-extended signed 16-bit response.
                let raw = UInt32(UInt16(bitPattern: Int16(truncatingIfNeeded: sharpnessBySlot[selected] ?? 10)))
                return sharpnessResponses[sharpnessReadCount] ?? .uint32(raw)
            default: throw PTPError.readFailed(code, "Not used by this fake")
            }
        }
    }

    func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData {
        // Like the native implementation, selection happens before any field
        // read. An injected error/cancellation therefore still needs recovery.
        try await writeProperty(0xD18C, value: Int32(index))
        try Task.checkCancellation()
        let step: ReadStep = lock.withLock {
            recordedOperations.append(.readSlot(index))
            count += 1
            let step = reads.isEmpty
                ? .snapshot(configuredSnapshot(slot: index, sharpness: sharpnessBySlot[selected] ?? 10))
                : reads.removeFirst()
            if count == 1, case .snapshot(let snapshot) = step, snapshot.slot == index, let sharpness = snapshot.sharpness {
                sharpnessBySlot[index] = sharpness
            }
            return step
        }
        switch step {
        case .snapshot(let snapshot): return snapshot
        case .failure: throw ProbeFixtureError.failure
        case .disconnect:
            lock.withLock { connected = false }
            throw PTPError.notConnected
        case .cancelCaller:
            withUnsafeCurrentTask { $0?.cancel() }
            throw CancellationError()
        }
    }

    func writeProperty(_ code: UInt16, value: Int32) async throws {
        try Task.checkCancellation()
        let failure: WriteFailure? = try lock.withLock {
            guard connected else { throw PTPError.notConnected }
            recordedWrites.append(Write(code: code, value: value))
            recordedOperations.append(.writeProperty(code, value, selected))
            if code == 0xD18C {
                selectorWriteCount += 1
                let failure = selectorFailures[selectorWriteCount]
                if failure != .beforeMutation, !ignoredSelectorWrites.contains(selectorWriteCount) { selected = Int(value) }
                return failure
            }
            if code == 0xD1A0 {
                sharpnessWriteCount += 1
                let failure = sharpnessFailures[sharpnessWriteCount]
                if failure != .beforeMutation { sharpnessBySlot[selected] = value }
                return failure
            }
            throw PTPError.writeFailed(code, "Not used by this fake")
        }
        if failure != nil { throw ProbeFixtureError.failure }
    }
}
