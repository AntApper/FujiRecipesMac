# Fuji Setting-to-PTP Property Mapping

Maps Fuji X Weekly recipe setting names to Fuji PTP device properties.
Sources: libgphoto2 X-T5 dump (issue #899), FilmKit (eggricesoy/filmkit), Fuji CLI (karaolidis/fujicli).

## Active Shooting Properties (live camera settings)

| Recipe Setting Key       | PTP Property | Name                   | Data Type   | Range / Values              |
|--------------------------|-------------|------------------------|-------------|-----------------------------|
| `filmSimulation`         | `0xD001`    | Film Simulation        | UINT32      | 1–20 (see table below)      |
| `color`                  | `0xD002`    | Film Simulation Tune   | INT32       | -40 to +40, step 10         |
| `dynamicRange`           | `0xD007`    | DRangeMode             | UINT32      | 0xFFFF=Auto, 100, 200, 400  |
| `dRangePriority`         | `0xD02E`    | WideDynamicRange       | UINT32      | 0=Off, 1/2/3=levels, 0x8000=Auto (DR-P values speculative) |
| `whiteBalance`           | `0x5005`    | White Balance          | UINT32      | WBMode enum (see below)     |
| `whiteBalance` (shift R) | `0xD00B`    | WhitebalanceTune1      | INT32       | -9 to +9, step 1            |
| `whiteBalance` (shift B) | `0xD00C`    | WhitebalanceTune2      | INT32       | -9 to +9, step 1            |
| `whiteBalance` (kelvin)  | `0xD017`    | Color Temperature      | UINT32      | Custom K value              |
| `highlight`              | `0xD320`    | HighLightTone          | INT32       | -20 to +40, step 5          |
| `shadow`                 | `0xD321`    | ShadowTone             | INT32       | -20 to +40, step 5          |
| `sharpness`              | `0x5015`    | Sharpness              | INT32       | -40 to +40, step 10         |
| `highIsoNr`              | `0xD01C`    | NoiseReduction         | UINT32      | 0, 4096, 8192, ..., 32768 (see encoding) |
| `grainEffect`            | `0xD023`    | GrainEffect            | UINT32      | 1–5 (see table below)       |
| `colorChromeEffect`      | `0xD008`    | ColorMode              | INT32       | -40 to +40, step 10         |
| `colorChromeFxBlue`      | *(active property TBD)* | —            | —           | See preset property `0xD197` |
| `clarity`                | *(active property TBD)* | —            | —           | See preset property `0xD1A2` |
| `iso`                    | `0x500F`    | Exposure Index (ISO)   | INT32       | 64–51200 + auto (-1/-2/-3)  |
| `exposureCompensation`   | `0x5010`    | Exposure Bias Comp.    | INT32       | -5000 to +5000, step 333    |

> **Note on 0xD008**: libgphoto2 labels this `ColorMode` with range -40 to +40 (step 10).
> This appears to be the same as Film Simulation Tune (0xD002). Color Chrome Effect
> may be stored in the preset properties at `0xD196` instead.

> **Note on 0xD029**: libgphoto2 labels this `Shadowing` with enum [1,2,3]. This may
> map to Sharpness in the recipe context. Needs probe confirmation.

## Custom Preset Properties (C1–C7 slot read/write)

**These use standard PTP `GetDevicePropValue` / `SetDevicePropValue` — no vendor ops needed.**

Confirmed via FilmKit cross-referencing 7 camera presets on X100VI (2026-03).

| PTP Property | Name               | Description                                    | Encoding                                  |
|-------------|-------------------|------------------------------------------------|-------------------------------------------|
| `0xD18C`    | PresetSlot         | Active preset slot selector                    | 1–7                                       |
| `0xD18D`    | PresetName         | Preset display name                            | PTP string                                |
| `0xD18E`    | P:ImageSize        | Image size for preset                          | Index into size enum                      |
| `0xD18F`    | P:ImageQuality     | Image quality for preset                       | Index into quality enum                   |
| `0xD190`    | P:DynamicRange%    | Dynamic range                                  | Raw percentage: 100, 200, 400             |
| `0xD191`    | P:?D191            | Unknown                                        | Always 0                                  |
| `0xD192`    | P:FilmSimulation   | Film simulation                                | FilmSim enum (0x01–0x14)                  |
| `0xD193`    | P:MonoWC×10        | Mono Warm/Cool tone (B&W only)                 | ×10 encoding                              |
| `0xD194`    | P:MonoMG×10        | Mono Magenta/Green tone (B&W only)             | ×10 encoding                              |
| `0xD195`    | P:GrainEffect      | Grain effect                                   | 1=Off, 2=Weak Small, 3=Strong Small, 4=Weak Large, 5=Strong Large |
| `0xD196`    | P:ColorChrome      | Color Chrome Effect                            | 1=Off, 2=Weak, 3=Strong                   |
| `0xD197`    | P:ColorChromeFxBlue| Color Chrome FX Blue                           | 1=Off, 2=Weak, 3=Strong                   |
| `0xD198`    | P:SmoothSkin       | Smooth Skin Effect                             | 1=Off, 2=Weak, 3=Strong                   |
| `0xD199`    | P:WhiteBalance     | White balance mode                             | WBMode uint16 enum                        |
| `0xD19A`    | P:WBShiftR         | WB shift red                                   | INT8, -9 to +9                            |
| `0xD19B`    | P:WBShiftB         | WB shift blue                                  | INT8, -9 to +9                            |
| `0xD19C`    | P:ColorTemp(K)     | Color temperature                              | Kelvin (UINT32), 0 if not custom          |
| `0xD19D`    | P:HighlightTone×10 | Highlight tone                                 | ×10 encoding (e.g. +1.5 → 15)             |
| `0xD19E`    | P:ShadowTone×10    | Shadow tone                                    | ×10 encoding                               |
| `0xD19F`    | P:Color×10         | Color (Film Sim Tune)                          | ×10 encoding                               |
| `0xD1A0`    | P:Sharpness×10     | Sharpness                                      | ×10 encoding                               |
| `0xD1A1`    | P:HighIsoNR         | High ISO NR                                    | Fuji proprietary 16-bit lookup; see below |
| `0xD1A2`    | P:Clarity×10       | Clarity                                        | ×10 encoding                               |
| `0xD1A3`    | P:LongExpNR        | Long exposure NR                               | 0=Off, 1=On                               |
| `0xD1A4`    | P:ColorSpace       | Color space                                    | 1=sRGB, 2=AdobeRGB                        |
| `0xD1A5`    | P:?D1A5            | Unknown                                        | Always 7                                    |

### Verified C-slot raw encoding

C-slot writes use 16-bit raw preset payloads, not the app's display values or
active-shooting property encodings. `CSlotPresetEncoder` is the authoritative
app-side translation, aligned with FilmKit's `translateUIToPresetProps` and
the 2026-09-12 C-slot capture/regression records.

- DR: `Auto=0xFFFF`, `DR100=100`, `DR200=200`, `DR400=400`.
- Grain: `Off=1`, `Weak Small=2`, `Strong Small=3`, `Weak Large=4`,
  `Strong Large=5`; Color Chrome, FX Blue, and Smooth Skin are `1/2/3`
  for Off/Weak/Strong.
- WB shifts are signed `-9...+9`. `D19C` is emitted only for Color Temperature
  WB (`0x8007`) and only for `2500...10000 K`.
- Highlight and shadow accept UI `-2...+4`, while color and sharpness accept
  `-4...+4`, and clarity `-5...+5`; each is sent as signed raw tenths
  (for example, shadow `-1` becomes `0xFFF6`, sharpness `+4` becomes
  `0x0028`). Color is omitted for monochrome/ACROS/sepia simulations.
- High ISO NR is not linear: `-4=0x8000`, `-3=0x7000`, `-2=0x4000`,
  `-1=0x3000`, `0=0x2000`, `+1=0x1000`, `+2=0x0000`, `+3=0x6000`,
  `+4=0x5000`.

### Preset Write Sequence

To write a recipe to a C slot:

1. `SetDevicePropValue(0xD18C, slot)` — select slot 1–7
2. Write each property via `SetDevicePropValue(property, value)`
3. Properties are committed per-write (no separate commit needed)

### Encoding Differences: Preset Properties vs. Active Properties

Preset properties (D18E–D1A5) use **different encodings** than active shooting properties:

| Setting          | Active Property Encoding    | Preset Property Encoding     |
|-----------------|-----------------------------|------------------------------|
| Effects         | 0=Off, 2=Weak, 3=Strong     | 1=Off, 2=Weak, 3=Strong      |
| Grain           | 1=Off, 2=WeakS, 3=StrongS, 4=WeakL, 5=StrongL | Same (flat enum 1-5) |
| Dynamic Range   | 0xFFFF, 100, 200, 400       | Raw percentage: 100, 200, 400 |
| Color Chrome    | -40 to +40 (step 10)        | 1=Off, 2=Weak, 3=Strong      |
| Tone values     | -20 to +40 (step 5)         | ×10 encoding (e.g. +1.5 → 15)|
| WB mode         | UINT32 enum (libgphoto2)    | uint16 WBMode enum            |

## Film Simulation Values (`0xD001` / `0xD192`)

From FilmKit enums (confirmed on X100VI via preset scan) and libgphoto2:

| PTP Value | Name                     | Notes                              |
|-----------|--------------------------|------------------------------------|
| 0x01 (1)  | PROVIA/Standard          |                                    |
| 0x02 (2)  | Velvia/Vivid             |                                    |
| 0x03 (3)  | ASTIA/Soft               |                                    |
| 0x04 (4)  | PRO Neg.Hi               |                                    |
| 0x05 (5)  | PRO Neg.Std              |                                    |
| 0x06 (6)  | Monochrome (B&W)         |                                    |
| 0x07 (7)  | Monochrome + Yellow      |                                    |
| 0x08 (8)  | Monochrome + Red         |                                    |
| 0x09 (9)  | Monochrome + Green       |                                    |
| 0x0A (10) | Sepia                    |                                    |
| 0x0B (11) | Classic Chrome           |                                    |
| 0x0C (12) | ACROS                    |                                    |
| 0x0D (13) | ACROS + Yellow           |                                    |
| 0x0E (14) | ACROS + Red              |                                    |
| 0x0F (15) | ACROS + Green            |                                    |
| 0x10 (16) | ETERNA/Cinema            |                                    |
| 0x11 (17) | Classic Negative         |                                    |
| 0x12 (18) | ETERNA Bleach Bypass     |                                    |
| 0x13 (19) | **Nostalgic Negative**   | X-Trans V only                    |
| 0x14 (20) | **Reala Ace**            | X-Trans V only                    |

## White Balance Mode Values

From FilmKit d185 profile + libgphoto2 `0x5005`:

| PTP Value | Name                   | Notes                              |
|-----------|------------------------|------------------------------------|
| 0x0000    | As Shot                |                                    |
| 0x0002    | Auto (AWB)             | Standard auto white balance        |
| 0x0004    | Daylight               | ~5500K                             |
| 0x0006    | Incandescent/Tungsten  | ~3000K                             |
| 0x0008    | Underwater             |                                    |
| 0x8001    | Fluorescent 1          | ~4500K                             |
| 0x8002    | Fluorescent 2          | ~4700K                             |
| 0x8003    | Fluorescent 3          | ~3600K                             |
| 0x8006    | Shade                  | ~7000K                             |
| 0x8007    | Color Temperature      | Custom Kelvin mode                 |
| 0x8021    | Ambience Priority      | Auto ambience priority (X-Trans V) |

## Dynamic Range Values (`0xD007`)

| PTP Value  | Name    | Notes                              |
|------------|---------|------------------------------------|
| 0xFFFF (65535) | Auto  | Camera auto-selects                |
| 100        | DR100   | Dynamic Range 100%                 |
| 200        | DR200   | Dynamic Range 200%                 |
| 400        | DR400   | Dynamic Range 400%                 |

### D-Range Priority (DR-P)

DR-P may use `0xD02E` (WideDynamicRange) with values:
- 0 = Off
- 1, 2, 3 = Weak/Medium/Strong (speculative)
- 0x8000 = Auto

**Needs probe confirmation.**

## Grain Effect Values

### Active Property (`0xD023`)

| PTP Value | Name           |
|-----------|---------------|
| 1         | Off           |
| 2         | Weak Small    |
| 3         | Strong Small  |
| 4         | Weak Large    |
| 5         | Strong Large  |

### Preset Property (`0xD195`)

Same flat enum 1–5. Confirmed from preset cross-reference.

### d185 Profile Format

Byte-packed: low byte = strength (0=Off, 2=Weak, 3=Strong), high byte = size (0=Small, 1=Large).
e.g. 0x0103 = Strong Large.

## Noise Reduction (`0xD01C`)

Encoded as UINT32 with 4096-step values:

| Recipe Value | PTP Value  | Notes                    |
|-------------|-----------|--------------------------|
| -4          | 0         | Minimum                  |
| -3          | 4096      |                          |
| -2          | 8192      | Default                  |
| -1          | 12288     |                          |
| 0           | 16384     | Neutral                  |
| +1          | 20480     |                          |
| +2          | 24576     |                          |
| +3          | 28672     |                          |
| +4          | 32768     | Maximum                  |

Formula: `ptpValue = (recipeValue + 4) * 4096`

## Tone Value Encoding

Highlight, Shadow, Color, Sharpness, Clarity use different encodings:

### Active Properties
- Highlight (`0xD320`): INT32, range -20 to +40, step 5 → 12 values (-4.0 to +8.0 in 0.5 steps)
- Shadow (`0xD321`): Same as Highlight
- Color/Film Sim Tune (`0xD002`): INT32, range -40 to +40, step 10 → 9 values (-4 to +4)
- Sharpness (`0x5015`): INT32, range -40 to +40, step 10 → 9 values

### Preset Properties (D19D–D1A2)
All use **×10 encoding**: recipe value multiplied by 10.
- +1.5 → 15
- -2.0 → -20
- +3 → 30

### Exposure Compensation (`0x5010`)

INT32, range -5000 to +5000, step 333 (1/3 EV).
- -5.0 EV → -5000
- 0 EV → 0
- +1.3 EV → 1333 (approximately)

31 discrete values from -5 to +5 in 1/3 EV steps.

## ISO Values (`0x500F`)

| PTP Value | ISO   | Notes                    |
|-----------|-------|--------------------------|
| 64–51200  | as listed | Manual ISO values     |
| -1        | Auto  | Auto ISO (range 1)       |
| -2        | Auto  | Auto ISO (range 2)       |
| -3        | Auto  | Auto ISO (range 3)       |

Auto ranges vary by camera model. For X-T5: -3 = Auto up to ISO 6400.

## D185 Profile Format (RAW Conversion)

The camera returns a **625-byte native profile** via property `0xD185`.
Field offsets (confirmed on X100VI):

```
[4]  ExposureBias     [8]  FilmSimulation   [9]  GrainEffect
[6]  DynamicRange%    [10] ColorChrome      [11] SmoothSkin
[13] WBShiftR         [14] WBShiftB         [15] WBColorTemp(K)
[16] HighlightTone*10 [17] ShadowTone*10    [18] Color*10
[19] Sharpness*10     [20] NoiseReduction   [25] CCFxBlue
[27] Clarity*10
```

Tone parameters use ×10 encoding. Noise Reduction uses proprietary non-linear encoding.

## RAW Conversion Workflow

1. `OpenSession` (0x1002)
2. `SendObjectInfo` (0x900C) + `SendObject2` (0x900D) — upload RAF file
3. `GetDevicePropValue` (0x1015, prop=0xD185) — read base conversion profile
4. `SetDevicePropValue` (0x1016, prop=0xD185) — send modified profile
5. `SetDevicePropValue` (0x1016, prop=0xD183, value=0) — trigger conversion
6. Poll `GetObjectHandles` (0x1007) until result appears
7. `GetObject` (0x1009) — download JPEG
8. `DeleteObject` (0x100B) — clean up
9. `CloseSession` (0x1003)

## USB Identifiers

| Camera   | Vendor | Product |
|----------|--------|---------|
| X-T30    | 0x04CB | 0x02E3  |
| X100V    | 0x04CB | 0x02E5  |
| X-T4     | 0x04CB | 0x02E7  |
| **X100VI** | 0x04CB | **0x0305** |

## Sources

- libgphoto2 X-T5 dump: <https://github.com/gphoto/libgphoto2/issues/899>
- FilmKit (WebUSB PTP preset manager): <https://github.com/eggricesoy/filmkit>
- FilmKit QUICK_REFERENCE.md: <https://github.com/eggricesoy/filmkit/blob/master/QUICK_REFERENCE.md>
- Fuji CLI: <https://github.com/karaolidis/fujicli>
- rawji: <https://github.com/pinpox/rawji>
- ISO 15740 — PTP specification

## Remaining Unknowns

- Active property for Color Chrome FX Blue (known in presets at `0xD197`)
- Active property for Clarity (known in presets at `0xD1A2`)
- D-Range Priority exact property and values (likely `0xD02E` or `0xD207`)
- `0xD191` and `0xD1A5` preset properties (always 0 and 7 respectively)
- ISO auto-limit PTP property (recipes specify "Auto up to ISO N")
