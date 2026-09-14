import Foundation

/// PTP property codes for Fuji X100VI.
/// Source: libgphoto2 X-T5 dump, FilmKit, Fuji CLI.
public enum PTPProperty {
    // MARK: - Active Shooting Properties

    /// Film Simulation (0xD001) — UINT32, 1–20
    public static let filmSimulation: UInt16 = 0xD001

    /// Film Simulation Tune / Color (0xD002) — INT32, -40 to +40, step 10
    public static let color: UInt16 = 0xD002

    /// Dynamic Range Mode (0xD007) — UINT32, 0xFFFF/100/200/400
    public static let dynamicRange: UInt16 = 0xD007

    /// White Balance (0x5005) — UINT32, WBMode enum
    public static let whiteBalance: UInt16 = 0x5005

    /// Whitebalance Tune 1 — Red shift (0xD00B) — INT32, -9 to +9
    public static let wbShiftRed: UInt16 = 0xD00B

    /// Whitebalance Tune 2 — Blue shift (0xD00C) — INT32, -9 to +9
    public static let wbShiftBlue: UInt16 = 0xD00C

    /// Color Temperature (0xD017) — UINT32, K value
    public static let colorTemp: UInt16 = 0xD017

    /// Noise Reduction / High ISO NR (0xD01C) — UINT32, 0 to 32768, step 4096
    public static let highIsoNr: UInt16 = 0xD01C

    /// Grain Effect (0xD023) — UINT32, 1–5
    public static let grainEffect: UInt16 = 0xD023

    /// Wide Dynamic Range / DR-P (0xD02E) — UINT32, speculative
    public static let dRangePriority: UInt16 = 0xD02E

    /// Highlight Tone (0xD320) — INT32, -20 to +40, step 5
    public static let highlight: UInt16 = 0xD320

    /// Shadow Tone (0xD321) — INT32, -20 to +40, step 5
    public static let shadow: UInt16 = 0xD321

    /// Exposure Index / ISO (0x500F) — INT32, 64–51200 + auto
    public static let iso: UInt16 = 0x500F

    /// Sharpness (0x5015) — INT32, -40 to +40, step 10
    public static let sharpness: UInt16 = 0x5015

    /// Exposure Bias Compensation (0x5010) — INT32, -5000 to +5000, step 333
    public static let exposureCompensation: UInt16 = 0x5010

    // MARK: - Preset Slot Properties (C1–C7)

    /// Preset Slot selector (0xD18C) — 1–7
    public static let presetSlot: UInt16 = 0xD18C

    /// Preset Name (0xD18D) — PTP string
    public static let presetName: UInt16 = 0xD18D

    /// Image Size (0xD18E) — index
    public static let imageSize: UInt16 = 0xD18E

    /// Image Quality (0xD18F) — index
    public static let imageQuality: UInt16 = 0xD18F

    /// Dynamic Range (0xD190) — raw percentage
    public static let presetDynamicRange: UInt16 = 0xD190

    /// Film Simulation (0xD192) — 1–20
    public static let presetFilmSimulation: UInt16 = 0xD192

    /// Mono Warm/Cool ×10 (0xD193) — signed 16-bit raw payload, B&W only.
    public static let presetMonoWarmCool: UInt16 = 0xD193

    /// Mono Magenta/Green ×10 (0xD194) — signed 16-bit raw payload, B&W only.
    public static let presetMonoMagentaGreen: UInt16 = 0xD194

    /// Grain Effect (0xD195) — 1=Off, 2=Weak, 3=Strong
    public static let presetGrainEffect: UInt16 = 0xD195

    /// Color Chrome (0xD196) — 1=Off, 2=Weak, 3=Strong
    public static let presetColorChrome: UInt16 = 0xD196

    /// Color Chrome FX Blue (0xD197) — 1=Off, 2=Weak, 3=Strong
    public static let presetColorChromeFxBlue: UInt16 = 0xD197

    /// Smooth Skin (0xD198) — 1=Off, 2=Weak, 3=Strong
    public static let presetSmoothSkin: UInt16 = 0xD198

    /// White Balance Mode (0xD199) — uint16 WBMode
    public static let presetWhiteBalance: UInt16 = 0xD199

    /// WB Shift R (0xD19A) — signed 16-bit payload, valid -9...+9.
    public static let presetWbShiftR: UInt16 = 0xD19A

    /// WB Shift B (0xD19B) — signed 16-bit payload, valid -9...+9.
    public static let presetWbShiftB: UInt16 = 0xD19B

    /// Color Temp K (0xD19C) — uint16 K, only with Color Temperature WB.
    public static let presetColorTemp: UInt16 = 0xD19C

    /// Highlight Tone ×10 (0xD19D) — signed 16-bit payload, UI -2...+4.
    public static let presetHighlight: UInt16 = 0xD19D

    /// Shadow Tone ×10 (0xD19E) — signed 16-bit payload, UI -2...+4.
    public static let presetShadow: UInt16 = 0xD19E

    /// Color ×10 (0xD19F) — signed 16-bit payload, UI -4...+4, color sims only.
    public static let presetColor: UInt16 = 0xD19F

    /// Sharpness ×10 (0xD1A0) — signed 16-bit payload, UI -4...+4.
    public static let presetSharpness: UInt16 = 0xD1A0

    /// High ISO NR (0xD1A1) — Fuji proprietary uint16 lookup, not linear.
    public static let presetHighIsoNr: UInt16 = 0xD1A1

    /// Clarity ×10 (0xD1A2) — signed 16-bit payload, UI -5...+5.
    public static let presetClarity: UInt16 = 0xD1A2

    /// Long Exp NR (0xD1A3) — 0=Off, 1=On
    public static let presetLongExpNr: UInt16 = 0xD1A3

    /// Color Space (0xD1A4) — 1=sRGB, 2=AdobeRGB
    public static let presetColorSpace: UInt16 = 0xD1A4

    /// Unknown (0xD1A5) — always 7
    public static let presetUnknownD1A5: UInt16 = 0xD1A5

    // MARK: - RAW Conversion

    /// Native Conversion Profile (0xD185) — rawji-standard 632-byte binary
    public static let nativeProfile: UInt16 = 0xD185

    // MARK: - Camera USB Identifiers

    /// Fuji vendor ID
    public static let fujiVendorId: UInt16 = 0x04CB

    /// X100VI product ID
    public static let x100viProductId: UInt16 = 0x0305

    /// PTP vendor extension ID for Fuji
    public static let fujiVendorExtensionId: UInt32 = 0x0000000E
}
