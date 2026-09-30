import Foundation
import FujiRecipesCore

/// The operations used by the preset-read and temporary-write diagnostics.
/// Recovery can be exercised against a fake without a camera.
public protocol ImageCaptureCoreWriteProbeClient: Sendable {
    var isConnected: Bool { get }
    var cameraInfo: PTPCameraInfo { get }
    func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse
    func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData
    func writeProperty(_ code: UInt16, value: Int32) async throws
}

extension ImageCaptureCorePTPClient: ImageCaptureCoreWriteProbeClient {}

/// Sharpness and the original selector are retained before a temporary write.
/// Older records decode a missing originalSelector as nil, never a guessed slot.
public struct ImageCaptureCoreProbeBaseline: Codable, Sendable, Equatable {
    public let slot: Int
    public let sharpness: Int32
    public let cameraModel: String
    public let capturedAt: Date
    public let originalSelector: Int?

    public init(slot: Int, sharpness: Int32, cameraModel: String, capturedAt: Date = Date(), originalSelector: Int? = nil) {
        self.slot = slot
        self.sharpness = sharpness
        self.cameraModel = cameraModel
        self.capturedAt = capturedAt
        self.originalSelector = originalSelector
    }
}

public enum ImageCaptureCoreProbeCheck: Sendable, Equatable {
    case verified
    case failed(String)
    case unavailable(String)
    case notAttempted(String)

    public var description: String {
        switch self {
        case .verified: "verified"
        case .failed(let reason): "failed: \(reason)"
        case .unavailable(let reason): "unavailable: \(reason)"
        case .notAttempted(let reason): "not attempted: \(reason)"
        }
    }
}

public struct ImageCaptureCoreReadProbeResult: Sendable {
    public let preset: PTPClientPresetData?
    public let originalSelector: Int?
    public let selectionAttempted: Bool
    public let verification: ImageCaptureCoreProbeCheck
    public let selectorRestoration: ImageCaptureCoreProbeCheck

    public var succeeded: Bool { verification == .verified && selectorRestoration == .verified }
    public var recoveryRequired: Bool { selectionAttempted && selectorRestoration != .verified }
}

/// Reads preset contents while restoring the selector changed by readPresetSlot.
public enum ImageCaptureCoreReadProbe {
    public static func readSlot(
        using client: any ImageCaptureCoreWriteProbeClient,
        slot: Int = 4,
        report: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> ImageCaptureCoreReadProbeResult {
        var originalSelector: Int?
        var selectionAttempted = false
        var preset: PTPClientPresetData?
        let verification: ImageCaptureCoreProbeCheck
        do {
            try ProbeSelection.validate(slot)
            let original = try await ProbeSelection.read(using: client)
            originalSelector = original
            report("original_selector=C\(original)")
            try Task.checkCancellation()
            // Slot selection may have reached the camera before a read throws.
            selectionAttempted = true
            let observed = try await client.readPresetSlot(slot)
            guard observed.slot == slot else {
                throw PTPError.invalidResponse("Requested C\(slot), but the snapshot reports C\(observed.slot).")
            }
            try await ProbeSelection.require(slot, using: client)
            try Task.checkCancellation()
            preset = observed
            verification = .verified
        } catch {
            verification = .failed(error.localizedDescription)
        }
        let original = originalSelector
        let attempted = selectionAttempted
        let selectorRestoration = await Task {
            await ProbeSelection.restore(original, attempted: attempted, using: client, report: report)
        }.value
        return ImageCaptureCoreReadProbeResult(
            preset: preset, originalSelector: originalSelector, selectionAttempted: selectionAttempted,
            verification: verification, selectorRestoration: selectorRestoration
        )
    }
}

public struct ImageCaptureCoreWriteProbeResult: Sendable {
    public let baseline: ImageCaptureCoreProbeBaseline?
    public let originalSelector: Int?
    public let selectionAttempted: Bool
    public let mutationAttempted: Bool
    public let verification: ImageCaptureCoreProbeCheck
    public let sharpnessRestoration: ImageCaptureCoreProbeCheck
    public let selectorRestoration: ImageCaptureCoreProbeCheck

    /// Kept for callers of the original sharpness-only probe API.
    public var restoration: ImageCaptureCoreProbeCheck { sharpnessRestoration }
    public var succeeded: Bool {
        verification == .verified && sharpnessRestoration == .verified && selectorRestoration == .verified
    }
    public var recoveryRequired: Bool {
        (mutationAttempted && sharpnessRestoration != .verified) ||
            (selectionAttempted && selectorRestoration != .verified)
    }
}

public enum ImageCaptureCoreWriteProbe {
    /// The baseline must be saved before a sharpness write. Target selection
    /// still occurs while reading it, so selection recovery covers those reads
    /// and every later guard, save failure, error, and recoverable cancellation.
    public static func verifyWrite(
        using client: any ImageCaptureCoreWriteProbeClient,
        slot: Int = 4,
        saveBaseline: @Sendable (ImageCaptureCoreProbeBaseline) throws -> Void,
        report: @escaping @Sendable (String) -> Void = { _ in }
    ) async -> ImageCaptureCoreWriteProbeResult {
        var baseline: ImageCaptureCoreProbeBaseline?
        var originalSelector: Int?
        var selectionAttempted = false
        var mutationAttempted = false
        let verification: ImageCaptureCoreProbeCheck

        do {
            try ProbeSelection.validate(slot)
            let original = try await ProbeSelection.read(using: client)
            originalSelector = original
            report("original_selector=C\(original)")
            try Task.checkCancellation()
            selectionAttempted = true
            let initial = try await client.readPresetSlot(slot)
            guard initial.slot == slot, !initial.isEmptySlot else {
                throw PTPError.invalidResponse("A configured, nonempty C\(slot) is required before a probe sharpness write.")
            }
            guard let sharpness = initial.sharpness, isWritableSharpness(sharpness) else {
                throw PTPError.invalidResponse("C\(slot) must provide a known raw sharpness from -40 through 40 in steps of 10.")
            }
            let known = ImageCaptureCoreProbeBaseline(slot: slot, sharpness: sharpness, cameraModel: client.cameraInfo.model, originalSelector: original)
            try saveBaseline(known)
            baseline = known
            report("baseline_slot=C\(slot) baseline_sharpness=\(sharpness) original_selector=C\(original)")
            try Task.checkCancellation()

            // The saved value must still describe the selected target. Do not
            // overwrite a value changed since the baseline was captured.
            try await ProbeSelection.require(slot, using: client)
            let currentSharpness = try await readSharpness(using: client)
            guard currentSharpness == sharpness else {
                throw PTPError.invalidResponse("C\(slot) sharpness changed after baseline capture: saved \(sharpness), observed \(currentSharpness). No probe sharpness write was attempted.")
            }
            let target: Int32 = sharpness == 20 ? 0 : 20
            report("writing C\(slot) sharpness=\(target)")
            // This separate selector read is immediately before the write;
            // returned snapshot.slot alone does not prove camera selection.
            try await ProbeSelection.require(slot, using: client)
            try Task.checkCancellation()
            mutationAttempted = true
            try await client.writeProperty(0xD1A0, value: target)
            try Task.checkCancellation()
            let updated = try await client.readPresetSlot(slot)
            try await ProbeSelection.require(slot, using: client)
            try Task.checkCancellation()
            report("observed_updated_sharpness=\(updated.sharpness.map(String.init) ?? "nil")")
            guard updated.slot == slot, updated.sharpness == target else {
                throw PTPError.invalidResponse("Write verification for C\(slot) expected \(target), got \(updated.sharpness.map(String.init) ?? "nil") in C\(updated.slot).")
            }
            verification = .verified
        } catch {
            verification = .failed(error.localizedDescription)
        }

        let saved = baseline
        let original = originalSelector
        let selected = selectionAttempted
        let wroteSharpness = mutationAttempted
        // This task is independent of caller cancellation. Selector recovery
        // runs even when sharpness recovery fails or was never needed.
        let outcomes = await Task {
            let sharpness: ImageCaptureCoreProbeCheck
            if wroteSharpness, let saved {
                sharpness = await restoreSharpness(saved, using: client, report: report)
            } else {
                sharpness = .notAttempted("No probe sharpness write was attempted.")
            }
            let selector = await ProbeSelection.restore(original, attempted: selected, using: client, report: report)
            return (sharpness, selector)
        }.value
        return ImageCaptureCoreWriteProbeResult(
            baseline: baseline, originalSelector: originalSelector, selectionAttempted: selectionAttempted,
            mutationAttempted: mutationAttempted, verification: verification,
            sharpnessRestoration: outcomes.0, selectorRestoration: outcomes.1
        )
    }

    private static func isWritableSharpness(_ value: Int32) -> Bool {
        (-40...40).contains(value) && value.isMultiple(of: 10)
    }

    private static func readSharpness(using client: any ImageCaptureCoreWriteProbeClient) async throws -> Int32 {
        let value: Int32
        switch try await client.readProperty(0xD1A0) {
        case .int32(let raw): value = raw
        case .uint32(let raw):
            value = raw > 0x7FFF && raw <= 0xFFFF
                ? Int32(Int16(bitPattern: UInt16(raw)))
                : Int32(bitPattern: raw)
        case .error(let error): throw error
        default: throw PTPError.invalidResponse("The selected slot did not provide numeric raw sharpness.")
        }
        guard isWritableSharpness(value) else {
            throw PTPError.invalidResponse("The selected slot returned invalid writable raw sharpness \(value).")
        }
        return value
    }

    private static func restoreSharpness(
        _ baseline: ImageCaptureCoreProbeBaseline,
        using client: any ImageCaptureCoreWriteProbeClient,
        report: @Sendable (String) -> Void
    ) async -> ImageCaptureCoreProbeCheck {
        guard client.isConnected else {
            return .unavailable("Camera disconnected. Recover C\(baseline.slot) sharpness=\(baseline.sharpness) from the preserved baseline.")
        }
        do {
            report("restoring C\(baseline.slot) sharpness=\(baseline.sharpness)")
            do {
                try await client.writeProperty(0xD18C, value: Int32(baseline.slot))
            } catch {
                guard client.isConnected else { throw error }
                report("sharpness_restore_selection_ack=\(error.localizedDescription); verifying target selector")
            }
            try await Task.sleep(for: .milliseconds(120))
            try await ProbeSelection.require(baseline.slot, using: client)
            do {
                try await client.writeProperty(0xD1A0, value: baseline.sharpness)
            } catch {
                guard client.isConnected else { throw error }
                report("sharpness_restore_write_ack=\(error.localizedDescription); verifying preserved baseline")
            }
            let restored = try await client.readPresetSlot(baseline.slot)
            try await ProbeSelection.require(baseline.slot, using: client)
            report("observed_restored_sharpness=\(restored.sharpness.map(String.init) ?? "nil")")
            guard restored.slot == baseline.slot, restored.sharpness == baseline.sharpness else {
                return .failed("Restore verification expected C\(baseline.slot) sharpness=\(baseline.sharpness), got C\(restored.slot) sharpness=\(restored.sharpness.map(String.init) ?? "nil"). Retain the saved baseline.")
            }
            return .verified
        } catch {
            return ProbeSelection.failure(error, using: client, recovery: "Recover C\(baseline.slot) sharpness=\(baseline.sharpness) from the preserved baseline.")
        }
    }
}

private enum ProbeSelection {
    static func validate(_ slot: Int) throws {
        guard (1...7).contains(slot) else { throw PTPError.invalidResponse("Preset slot must be 1–7") }
    }

    static func read(using client: any ImageCaptureCoreWriteProbeClient) async throws -> Int {
        switch try await client.readProperty(0xD18C) {
        case .uint32(let raw) where (1...7).contains(raw): return Int(raw)
        case .int32(let raw) where (1...7).contains(raw): return Int(raw)
        case .error(let error): throw error
        default:
            throw PTPError.invalidResponse("A known selector from 1 through 7 is required.")
        }
    }

    static func require(_ slot: Int, using client: any ImageCaptureCoreWriteProbeClient) async throws {
        let selected = try await read(using: client)
        guard selected == slot else {
            throw PTPError.invalidResponse("Target selector must be C\(slot), but the camera reports C\(selected).")
        }
    }

    static func restore(
        _ original: Int?,
        attempted: Bool,
        using client: any ImageCaptureCoreWriteProbeClient,
        report: @Sendable (String) -> Void
    ) async -> ImageCaptureCoreProbeCheck {
        guard attempted, let original else { return .notAttempted("No target selection was attempted.") }
        guard client.isConnected else {
            let result = ImageCaptureCoreProbeCheck.unavailable("Camera disconnected. Restore the original selector C\(original) after reconnecting.")
            report("selector_restoration=\(result.description)")
            return result
        }
        do {
            // A failed selector read can be recoverable. Its known original
            // value is still safe to restore, followed by independent readback.
            if (try? await read(using: client)) != original {
                report("restoring original_selector=C\(original)")
                do {
                    try await client.writeProperty(0xD18C, value: Int32(original))
                } catch {
                    guard client.isConnected else { throw error }
                    report("selector_restore_write_ack=\(error.localizedDescription); verifying original selector")
                }
                try await Task.sleep(for: .milliseconds(120))
            }
            let observed = try await read(using: client)
            guard observed == original else {
                let result = ImageCaptureCoreProbeCheck.failed("Original selector C\(original) was not restored; observed C\(observed).")
                report("selector_restoration=\(result.description)")
                return result
            }
            report("selector_restoration=verified original_selector=C\(original)")
            return .verified
        } catch {
            let result = failure(error, using: client, recovery: "Restore the original selector C\(original) after reconnecting.")
            report("selector_restoration=\(result.description)")
            return result
        }
    }

    static func failure(_ error: Error, using client: any ImageCaptureCoreWriteProbeClient, recovery: String) -> ImageCaptureCoreProbeCheck {
        if !client.isConnected { return .unavailable("\(error.localizedDescription) \(recovery)") }
        return .failed("\(error.localizedDescription) \(recovery)")
    }
}
