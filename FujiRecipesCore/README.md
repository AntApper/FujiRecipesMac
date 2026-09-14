# FujiRecipesCore

Shared Swift package containing all domain models, enums, and PTP mapping constants for the Fuji X100VI recipe manager.

## Package

- **Swift Tools Version:** 6.0
- **Platforms:** iOS 17+, macOS 14+
- **Dependencies:** None

## Structure

```
FujiRecipesCore/
├── Package.swift
└── Sources/FujiRecipesCore/
    ├── Enums/
    │   ├── FilmSimulation.swift     # 1–20 PTP enum (X-Trans V only flags)
    │   ├── WhiteBalanceMode.swift   # 0x5005 WB mode enum
    │   ├── DynamicRange.swift       # 0xD007 DR modes
    │   ├── GrainEffect.swift        # 0xD023 grain enum (1–5)
    │   └── EffectIntensity.swift    # Generic 1=Off, 2=Weak, 3=Strong
    ├── Models/
    │   ├── Recipe.swift             # Recipe with all parsed settings
    │   └── PresetSlot.swift         # C1–C7 slot model
    └── Mapping/
        └── PTPConstants.swift       # All 0xDxxx property codes + USB IDs
```

## Usage

```swift
import FujiRecipesCore

// Film simulation
let sim = FilmSimulation.realaAce  // value: 20

// PTP property code
let code = PTPProperty.filmSimulation  // 0xD001

// Create a recipe
let recipe = Recipe(
    id: "pro-negative-160c",
    name: "PRO Negative 160C",
    source: "Fuji X Weekly",
    filmSimulation: .proNegativeStd,
    dynamicRange: .dr200,
    grainEffect: .weakSmall,
    color: 20,
    highlight: -5,
    shadow: -5,
    // ...
)
```

## Data Sources

- Film simulation values: FilmKit + libgphoto2 X-T5 dump, confirmed on X100VI
- PTP property codes: libgphoto2 issue #899, Fuji CLI, FilmKit
- ISO/auto: X-T5 range mapping (X100VI may differ — needs probe)
