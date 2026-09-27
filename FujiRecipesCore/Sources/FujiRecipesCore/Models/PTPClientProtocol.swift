import Foundation

// MARK: - PTPClient Protocol

/// Protocol abstraction for Fuji PTP communication.
/// Implemented separately for macOS (libgphoto2) and iOS (ImageCaptureCore).
public protocol PTPClientProtocol: Sendable {
    /// Connect to the camera. Must be called before any other operations.
    func connect() async throws

    /// Disconnect from the camera.
    func disconnect()

    /// Whether a connection is currently open.
    var isConnected: Bool { get }

    /// Get device information from the camera.
    var cameraInfo: PTPCameraInfo { get }

    /// Read a device property value.
    func readProperty(_ code: UInt16) async throws -> PTPPropertyResponse

    /// Write a device property value.
    /// Accepts a signed 32-bit value; this covers all Fuji X100VI properties,
    /// including negative tone/shift settings (e.g. highlight/shadow/color).
    func writeProperty(_ code: UInt16, value: Int32) async throws

    /// Read a preset slot (C1–C7) via preset properties.
    func readPresetSlot(_ index: Int) async throws -> PTPClientPresetData

    /// Write a preset slot (C1–C7) via preset properties and report whether
    /// the verified write created a previously never-configured camera slot.
    func writePresetSlot(_ index: Int, data: PTPClientPresetData) async throws -> PTPPresetSlotWriteResult

    /// Read the native conversion profile (0xD185, 632 bytes).
    func readNativeProfile() async throws -> Data
    
    /// Write a Recipe's PTP-mapped settings to the camera.
    func writePTPSettings(from recipe: Recipe) async throws
    
    /// Convert RAF using the camera's built-in converter. The outcome makes
    /// the distinction between a downloaded JPEG and an accepted trigger whose
    /// camera-side output cannot be retrieved by this transport explicit.
    func convertRAF(_ raf: RAFFile, profileModifier: ((inout Data) -> Void)?) async -> RAFConversionOutcome
    
    /// Capture a preview image from the camera.
    func capturePreview() async throws -> JPEGFile?

    /// Register an optional callback invoked when the hardware camera disconnects.
    func setDisconnectHandler(_ handler: (@Sendable () -> Void)?)
}

public extension PTPClientProtocol {
    func setDisconnectHandler(_ handler: (@Sendable () -> Void)?) {}
}

// MARK: - PTP Camera Info

public struct PTPCameraInfo: Sendable {
    public let model: String
    public let firmwareVersion: String?
    public let vendorExtensionId: UInt32
    public let vendorExtensionVersion: UInt32
    public let vendorExtensionDescription: String?

    public init(
        model: String,
        firmwareVersion: String? = nil,
        vendorExtensionId: UInt32 = 0x0000000E,
        vendorExtensionVersion: UInt32 = 0,
        vendorExtensionDescription: String? = nil
    ) {
        self.model = model
        self.firmwareVersion = firmwareVersion
        self.vendorExtensionId = vendorExtensionId
        self.vendorExtensionVersion = vendorExtensionVersion
        self.vendorExtensionDescription = vendorExtensionDescription
    }
    
    public var displayTitle: String {
        if model != "Not connected" { return model }
        return "Fuji Camera"
    }
}

// MARK: - PTP Property Response

public enum PTPPropertyResponse: Sendable {
    case uint32(UInt32)
    case int32(Int32)
    case string(String)
    case data(Data)
    case unsupported
    case error(PTPError)
}

// MARK: - PTP Error

public enum PTPError: Swift.Error, Sendable, LocalizedError {
    case notConnected
    case connectionFailed(String)
    case readFailed(UInt16, String)
    case writeFailed(UInt16, String)
    case invalidResponse(String)
    case commandFailed(UInt16, String)
    case sessionError(String)
    case platformError(String)
    case unknown(UInt16)

    public var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Not connected to a camera"
        case .connectionFailed(let reason):
            return "Connection failed: \(reason)"
        case .readFailed(let code, let reason):
            return "Failed to read property 0x\(String(code, radix: 16)): \(reason)"
        case .writeFailed(let code, let reason):
            return "Failed to write property 0x\(String(code, radix: 16)): \(reason)"
        case .invalidResponse(let msg):
            return "Invalid response: \(msg)"
        case .commandFailed(let code, let reason):
            return "Command 0x\(String(code, radix: 16)) failed: \(reason)"
        case .sessionError(let msg):
            return "Session error: \(msg)"
        case .platformError(let msg):
            return "Platform error: \(msg)"
        case .unknown(let code):
            return "Unknown PTP error: 0x\(String(code, radix: 16))"
        }
    }
}

/// The terminal result of a camera-side RAF conversion.
///
/// A trigger may be accepted even where the macOS transport cannot retrieve
/// the produced JPEG. Callers must not infer a JPEG from trigger acceptance.
public enum RAFConversionOutcome: Sendable {
    case downloadedJPEG(JPEGFile)
    case triggerAcceptedOutputNotRetrievable(reason: String)
    case cancelled
    case failed(message: String)

    public var jpeg: JPEGFile? {
        guard case .downloadedJPEG(let jpeg) = self else { return nil }
        return jpeg
    }
}

// MARK: - PTP Client Preset Data

public struct PTPClientPresetData: Sendable, Equatable {
    public let slot: Int
    public let name: String
    /// True only when the camera explicitly reported its empty/raw-zero
    /// sentinel for a never-configured C slot.
    public let isEmptySlot: Bool
    public let imageQuality: UInt32?
    public let imageSize: UInt32?
    public let dynamicRange: UInt32?
    public let filmSimulation: UInt32?
    public let monoWarmCool: Int32?
    public let monoMagentaGreen: Int32?
    public let grainEffect: UInt32?
    public let colorChrome: UInt32?
    public let colorChromeFxBlue: UInt32?
    public let smoothSkin: UInt32?
    public let whiteBalance: UInt32?
    public let wbShiftRed: Int32?
    public let wbShiftBlue: Int32?
    public let colorTemp: UInt32?
    public let highlight: Int32?
    public let shadow: Int32?
    public let color: Int32?
    public let sharpness: Int32?
    /// C-slot High ISO Noise Reduction (0xD1A1).
    public let highIsoNr: UInt32?
    public let clarity: Int32?
    /// C-slot Long Exposure Noise Reduction (0xD1A3), distinct from High ISO NR.
    public let longExpNr: UInt32?
    public let colorSpace: UInt32?

    public init(
        slot: Int,
        name: String = "",
        isEmptySlot: Bool = false,
        imageQuality: UInt32? = nil,
        imageSize: UInt32? = nil,
        dynamicRange: UInt32? = nil,
        filmSimulation: UInt32? = nil,
        monoWarmCool: Int32? = nil,
        monoMagentaGreen: Int32? = nil,
        grainEffect: UInt32? = nil,
        colorChrome: UInt32? = nil,
        colorChromeFxBlue: UInt32? = nil,
        smoothSkin: UInt32? = nil,
        whiteBalance: UInt32? = nil,
        wbShiftRed: Int32? = nil,
        wbShiftBlue: Int32? = nil,
        colorTemp: UInt32? = nil,
        highlight: Int32? = nil,
        shadow: Int32? = nil,
        color: Int32? = nil,
        sharpness: Int32? = nil,
        highIsoNr: UInt32? = nil,
        clarity: Int32? = nil,
        longExpNr: UInt32? = nil,
        colorSpace: UInt32? = nil
    ) {
        self.slot = slot
        self.name = name
        self.isEmptySlot = isEmptySlot
        self.imageQuality = imageQuality
        self.imageSize = imageSize
        self.dynamicRange = dynamicRange
        self.filmSimulation = filmSimulation
        self.monoWarmCool = monoWarmCool
        self.monoMagentaGreen = monoMagentaGreen
        self.grainEffect = grainEffect
        self.colorChrome = colorChrome
        self.colorChromeFxBlue = colorChromeFxBlue
        self.smoothSkin = smoothSkin
        self.whiteBalance = whiteBalance
        self.wbShiftRed = wbShiftRed
        self.wbShiftBlue = wbShiftBlue
        self.colorTemp = colorTemp
        self.highlight = highlight
        self.shadow = shadow
        self.color = color
        self.sharpness = sharpness
        self.highIsoNr = highIsoNr
        self.clarity = clarity
        self.longExpNr = longExpNr
        self.colorSpace = colorSpace
    }
}

/// Outcome of a C-slot write.  `createdFromEmpty` is true only after the
/// helper has verified every requested write and readback against a
/// never-configured raw-zero sentinel detected before mutation.
public struct PTPPresetSlotWriteResult: Sendable, Equatable {
    public let slot: Int
    public let createdFromEmpty: Bool
    /// Requested properties that the camera reported as inapplicable, rather
    /// than a failed or unverified write.
    public let warnings: [String]
    /// The pre-write state observed by the model. An empty sentinel is not a
    /// writable baseline and is deliberately never used for rollback.
    public let baseline: PTPPresetSlotBaseline?
    /// Recovery attempted after a failed write. Successful writes are
    /// `.notNeeded`.
    public let rollback: PTPPresetSlotRollbackOutcome
    /// The C-slot state read by `CameraManager` after the helper-level write
    /// succeeded. A non-nil value is the observed camera state associated with
    /// this success, rather than an inferred copy of the requested data.
    public let observedSnapshot: PTPClientPresetData?
    /// Requested settings that `observedSnapshot` reads back differently.
    public let differences: [PresetField]
    /// The user changed the slot's draft while this write ran, so the store
    /// kept the newer draft instead of adopting the readback.
    public let draftEditedDuringWrite: Bool

    public init(
        slot: Int,
        createdFromEmpty: Bool = false,
        warnings: [String] = [],
        baseline: PTPPresetSlotBaseline? = nil,
        rollback: PTPPresetSlotRollbackOutcome = .notNeeded,
        observedSnapshot: PTPClientPresetData? = nil,
        differences: [PresetField] = [],
        draftEditedDuringWrite: Bool = false
    ) {
        self.slot = slot
        self.createdFromEmpty = createdFromEmpty
        self.warnings = warnings
        self.baseline = baseline
        self.rollback = rollback
        self.observedSnapshot = observedSnapshot
        self.differences = differences
        self.draftEditedDuringWrite = draftEditedDuringWrite
    }

    public var isVerified: Bool { differences.isEmpty && !draftEditedDuringWrite }

    public var summary: String {
        let verb = createdFromEmpty ? "Created" : "Wrote"
        let outcome: String
        if differences.isEmpty {
            outcome = draftEditedDuringWrite ? "\(verb) C\(slot)." : "\(verb) and verified C\(slot)."
        } else {
            let count = differences.count
            let names = differences.map(\.displayName).joined(separator: ", ")
            outcome = "\(verb) C\(slot) with \(count) difference\(count == 1 ? "" : "s"): \(names)."
        }
        guard draftEditedDuringWrite else { return outcome }
        return "\(outcome) You edited it during the write, so the newer draft is still staged."
    }

    func markingDraftEditedDuringWrite() -> PTPPresetSlotWriteResult {
        PTPPresetSlotWriteResult(
            slot: slot,
            createdFromEmpty: createdFromEmpty,
            warnings: warnings,
            baseline: baseline,
            rollback: rollback,
            observedSnapshot: observedSnapshot,
            differences: differences,
            draftEditedDuringWrite: true
        )
    }
}

public enum PresetField: Sendable {
    case name, imageQuality, imageSize, dynamicRange, filmSimulation
    case monoWarmCool, monoMagentaGreen, grainEffect, colorChrome, colorChromeFxBlue
    case smoothSkin, whiteBalance, wbShiftRed, wbShiftBlue, colorTemp
    case highlight, shadow, color, sharpness, highIsoNr, clarity, longExpNr, colorSpace

    public var displayName: String {
        switch self {
        case .name: return "Name"
        case .imageQuality: return "Image Quality"
        case .imageSize: return "Image Size"
        case .dynamicRange: return "Dynamic Range"
        case .filmSimulation: return "Film Simulation"
        case .monoWarmCool: return "Monochrome Warm/Cool"
        case .monoMagentaGreen: return "Monochrome Magenta/Green"
        case .grainEffect: return "Grain"
        case .colorChrome: return "Color Chrome"
        case .colorChromeFxBlue: return "Color Chrome FX Blue"
        case .smoothSkin: return "Smooth Skin"
        case .whiteBalance: return "White Balance"
        case .wbShiftRed: return "WB Shift Red"
        case .wbShiftBlue: return "WB Shift Blue"
        case .colorTemp: return "Color Temperature"
        case .highlight: return "Highlight"
        case .shadow: return "Shadow"
        case .color: return "Color"
        case .sharpness: return "Sharpness"
        case .highIsoNr: return "High ISO NR"
        case .clarity: return "Clarity"
        case .longExpNr: return "Long Exposure NR"
        case .colorSpace: return "Color Space"
        }
    }
}

extension PTPClientPresetData {
    /// Fields this request sets that `observed` holds differently. Unset
    /// fields keep whatever the camera had. Monochrome tones only apply
    /// under a monochrome film, and the X100VI rejects them otherwise.
    public func differences(from observed: PTPClientPresetData) -> [PresetField] {
        let monochrome = observed.filmSimulation
            .flatMap(FilmSimulation.init(rawValue:))
            .map(CSlotPresetEncoder.isMonochrome) ?? false
        func differs<T: Equatable>(_ requested: T?, _ actual: T?) -> Bool {
            requested != nil && requested != actual
        }
        func grain(_ raw: UInt32?) -> UInt32? {
            raw.map { GrainEffect(cameraValue: $0)?.rawValue ?? $0 }
        }
        let requestedName = name.trimmingCharacters(in: .whitespaces)
        let checks: [(PresetField, Bool)] = [
            (.name, !requestedName.isEmpty && requestedName != observed.name.trimmingCharacters(in: .whitespaces)),
            (.imageQuality, differs(imageQuality, observed.imageQuality)),
            (.imageSize, differs(imageSize, observed.imageSize)),
            (.dynamicRange, differs(dynamicRange, observed.dynamicRange)),
            (.filmSimulation, differs(filmSimulation, observed.filmSimulation)),
            (.monoWarmCool, monochrome && differs(monoWarmCool, observed.monoWarmCool)),
            (.monoMagentaGreen, monochrome && differs(monoMagentaGreen, observed.monoMagentaGreen)),
            (.grainEffect, differs(grain(grainEffect), grain(observed.grainEffect))),
            (.colorChrome, differs(colorChrome, observed.colorChrome)),
            (.colorChromeFxBlue, differs(colorChromeFxBlue, observed.colorChromeFxBlue)),
            (.smoothSkin, differs(smoothSkin, observed.smoothSkin)),
            (.whiteBalance, differs(whiteBalance, observed.whiteBalance)),
            (.wbShiftRed, differs(wbShiftRed, observed.wbShiftRed)),
            (.wbShiftBlue, differs(wbShiftBlue, observed.wbShiftBlue)),
            (.colorTemp, differs(colorTemp, observed.colorTemp)),
            (.highlight, differs(highlight, observed.highlight)),
            (.shadow, differs(shadow, observed.shadow)),
            (.color, differs(color, observed.color)),
            (.sharpness, differs(sharpness, observed.sharpness)),
            (.highIsoNr, differs(highIsoNr, observed.highIsoNr)),
            (.clarity, differs(clarity, observed.clarity)),
            (.longExpNr, differs(longExpNr, observed.longExpNr)),
            (.colorSpace, differs(colorSpace, observed.colorSpace))
        ]
        return checks.filter(\.1).map(\.0)
    }
}

/// A C-slot state captured before mutation.
public enum PTPPresetSlotBaseline: Sendable, Equatable {
    case configured(PTPClientPresetData)
    case emptySentinel
}

/// Independent result of attempting to restore a pre-write configured slot.
public enum PTPPresetSlotRollbackOutcome: Sendable, Equatable {
    case notNeeded
    case restored
    case notAttemptedEmptySentinel
    case failed(String)
}

/// The stage at which a C-slot write workflow stopped. This keeps a
/// successful helper write distinct from a failed manager-side readback.
public enum PTPPresetSlotWriteFailurePhase: Sendable, Equatable {
    case write
    case postWriteVerification
}

/// A C-slot write failed after the model captured a baseline. The rollback
/// result is intentionally separate from the original write error.
public struct PTPPresetSlotWriteRecoveryError: Error, Sendable, LocalizedError {
    public let slot: Int
    public let writeErrorDescription: String
    public let baseline: PTPPresetSlotBaseline
    public let rollback: PTPPresetSlotRollbackOutcome
    public let failurePhase: PTPPresetSlotWriteFailurePhase

    public init(
        slot: Int,
        writeError: Error,
        baseline: PTPPresetSlotBaseline,
        rollback: PTPPresetSlotRollbackOutcome,
        failurePhase: PTPPresetSlotWriteFailurePhase = .write
    ) {
        self.slot = slot
        self.writeErrorDescription = writeError.localizedDescription
        self.baseline = baseline
        self.rollback = rollback
        self.failurePhase = failurePhase
    }

    public var errorDescription: String? {
        let recovery: String
        switch rollback {
        case .restored:
            recovery = "The previous configured C\(slot) values were restored."
        case .notAttemptedEmptySentinel:
            recovery = "The slot was an empty camera sentinel, so no raw-zero rollback was attempted."
        case .failed(let message):
            recovery = "Rollback failed: \(message)"
        case .notNeeded:
            recovery = "No rollback was required."
        }
        let failure: String
        switch failurePhase {
        case .write:
            failure = "C\(slot) write failed"
        case .postWriteVerification:
            failure = "C\(slot) post-write verification failed"
        }
        return "\(failure): \(writeErrorDescription). \(recovery)"
    }
}
