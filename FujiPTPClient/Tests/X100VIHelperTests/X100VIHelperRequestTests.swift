import Foundation
import XCTest
@testable import X100VIHelper
@testable import FujiRecipesCore

final class X100VIHelperRequestTests: XCTestCase {
    func testUniversalNegativeEncoderObjectSerializesToVerifiedHelperRequest() throws {
        // Use the exact production source record selected during C4 validation,
        // not an independently derived request vector.
        let testFile = URL(fileURLWithPath: #filePath)
        let repository = testFile
            .deletingLastPathComponent() // X100VIHelperTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // FujiPTPClient
            .deletingLastPathComponent() // repository root
        let resource = repository
            .appendingPathComponent("macos/Resources/recipes-data.json")
        let database = try JSONDecoder().decode(RecipesData.self, from: Data(contentsOf: resource))
        let source = try XCTUnwrap(database.recipes.first {
            $0.id == "universal-negative-14-fujifilm-x100vi-x-trans-v-film-simulation-recipes-yes-14"
        })
        let recipe = RecipeLoader.recipe(from: source)
        let preset = try CSlotPresetEncoder.encode(recipe: recipe, slot: 4)

        let params = X100VIHelperClient.presetWriteParameters(index: 4, data: preset)
        let data = try X100VIHelperClient.helperRequestData(
            id: "c4-regression",
            command: "write_preset_slot",
            params: params
        )
        let request = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )

        XCTAssertEqual(request["id"] as? String, "c4-regression")
        XCTAssertEqual(request["command"] as? String, "write_preset_slot")
        XCTAssertEqual(request["index"] as? Int, 4)
        XCTAssertEqual(request["color_chrome_fx_blue"] as? Int, 2, "D197")
        XCTAssertEqual(request["high_iso_nr"] as? Int, 32_768, "D1A1")
    }

    func testBusySlotSelectionIsEligibleForOneSafeReconnectRetry() {
        let response: [String: Any] = [
            "success": false,
            "result": [
                "failure_stage": "slot_selection",
                "slot_select_rc": 0x2019,
                "error": "slot_select_failed"
            ]
        ]

        XCTAssertEqual(transientSlotSelectionCode(in: response), 0x2019)
    }

    func testBaselineReadFailureIsNotRetriedAsSlotSelection() {
        let response: [String: Any] = [
            "success": false,
            "result": [
                "failure_stage": "baseline_read",
                "slot_select_rc": 0,
                "baseline_read_rc": -11,
                "error": "baseline_read_failed"
            ]
        ]

        XCTAssertNil(transientSlotSelectionCode(in: response))
    }

    func testInterfaceClaimFailureProducesActionableRecovery() {
        let response: [String: Any] = [
            "success": false,
            "error": "interface_claim_failed",
            "code": -2,
            "transport_code": 0
        ]

        let failure = helperConnectionFailure(in: response)

        XCTAssertEqual(failure, .interfaceUnavailable(transportCode: -2))
        XCTAssertTrue(failure.userActionableDescription.contains("could not claim"))
        XCTAssertTrue(failure.userActionableDescription.contains("Close camera-accessing apps"))
        XCTAssertFalse(failure.userActionableDescription.contains("killall"))
    }

    func testReconnectConnectionFailureRetainsTypedCameraRecovery() {
        let response: [String: Any] = [
            "success": false,
            "error": "reconnect_camera_not_found",
            "code": -1,
            "transport_code": 0
        ]

        let failure = helperConnectionFailure(in: response)

        XCTAssertEqual(failure, .cameraNotFound)
        XCTAssertTrue(failure.userActionableDescription.contains("USB RAW CONVERSION mode"))
    }

    func testSessionOpenFailurePrefersNonzeroTransportDiagnostic() {
        let response: [String: Any] = [
            "success": false,
            "error": "session_open_failed",
            "code": -3,
            "transport_code": -7
        ]

        XCTAssertEqual(
            helperConnectionFailure(in: response),
            .sessionOpenFailed(code: -7)
        )
    }

    func testSlotSelectionFailureIncludesStageAndNumericCode() {
        let response: [String: Any] = [
            "success": false,
            "result": [
                "failure_stage": "slot_selection",
                "slot_select_rc": 0x2019,
                "error": "slot_select_failed"
            ]
        ]

        XCTAssertEqual(
            presetSlotFailureDetails(response),
            "slot_selection failed (PTP 0x2019 (8217)): slot_select_failed"
        )
    }

    func testPropertyReadFailureRejectsIncompleteSlotData() {
        let response: [String: Any] = [
            "success": true,
            "result": [
                "properties": [
                    "0xD18D_Preset Name": ["rc": -2],
                    "0xD192_Film Simulation": ["rc": 0]
                ]
            ]
        ]

        XCTAssertEqual(
            presetPropertyReadFailure(in: response),
            "0xD18D_Preset Name read failed (transport -2)"
        )
    }

    func testConversionEvidenceAcceptsZeroHandleBaselineWhenNoObjectDeltaExists() {
        let response: [String: Any] = [
            "success": false,
            "result": [
                "status": "no_new_object",
                "diagnostics": [
                    "baseline_handle_count": 0,
                    "post_handle_count": 0,
                    "new_handle_count": 0,
                    "inspected_object_count": 0,
                    "auto_deleted": false,
                    "delivery_verified": false
                ]
            ]
        ]

        let evidence = conversionDeliveryEvidence(from: response)
        XCTAssertNotNil(evidence)
        XCTAssertTrue(evidence!.contains("no new PTP object"))
        XCTAssertTrue(evidence!.contains("unverified"))
    }

    func testConversionEvidencePreservesAmbiguousCandidates() {
        let response: [String: Any] = [
            "success": false,
            "result": [
                "status": "indeterminate_multiple_jpeg_candidates",
                "diagnostics": [
                    "new_handle_count": 2,
                    "inspected_object_count": 2,
                    "auto_deleted": false,
                    "delivery_verified": false
                ]
            ]
        ]

        XCTAssertEqual(
            conversionDeliveryEvidence(from: response),
            "The trigger was accepted, but 2 new object(s) produced multiple JPEG-like candidates. Nothing was downloaded automatically."
        )
    }
}
