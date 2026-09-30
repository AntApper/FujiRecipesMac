<div align="center">

# FujiRecipes for macOS

### The native macOS studio for Fujifilm film simulation recipes, direct USB-C custom dial synchronization, and hardware-accelerated RAW darkroom development.

[![Platform: macOS 14.0+](https://img.shields.io/badge/Platform-macOS%2014.0%2B%20(Sonoma%20%7C%20Sequoia)-000000?style=for-the-badge&logo=apple&logoColor=white)](https://apple.com/macos)
[![Swift: 6.0](https://img.shields.io/badge/Swift-6.0-FA7343?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![Xcode: 16+](https://img.shields.io/badge/Xcode-16%2B-1575F9?style=for-the-badge&logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)
[![Camera: Fujifilm X100VI](https://img.shields.io/badge/Camera-Fujifilm%20X100VI-E60012?style=for-the-badge&logo=fujifilm&logoColor=white)](https://fujifilm-x.com/products/cameras/x100vi/)
[![Sensor: X-Trans V](https://img.shields.io/badge/Sensor-40.2MP%20X--Trans%20V-4B5563?style=for-the-badge)](https://fujifilm-x.com)
[![Protocol: USB PTP Direct](https://img.shields.io/badge/Protocol-USB%20PTP%20Direct-10B981?style=for-the-badge)](docs/camera-connection-guide.md)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg?style=for-the-badge)](LICENSE)
[![Build: Passing](https://img.shields.io/badge/Build-Passing-brightgreen?style=for-the-badge)](#building-from-source)

<br/>

<p align="center">
  <img src="docs/screenshots/recipe-library.png" alt="FujiRecipes Studio Hero" width="920" />
</p>

</div>

---

## Overview

**FujiRecipes for macOS** is a high-performance, native macOS desktop companion engineered specifically for Fujifilm X-series photographers.

Setting up custom film simulation recipes on Fujifilm cameras has historically been a slow, manual chore: navigating nested camera menus with rotary dials to configure over 20 distinct imaging parameters for every custom slot (**C1–C7**). 

**FujiRecipes solves this directly at the hardware layer.** Connect your Fujifilm camera (such as the **X100VI**) to your Mac via USB-C in `USB RAW CONV. / BACKUP RESTORE` mode, and FujiRecipes communicates directly through native Picture Transfer Protocol (PTP). You can browse curated film stocks, fine-tune color formulas, stage C1–C7 dial banks offline, and push verified configurations straight to camera memory in seconds—with automated pre-write backups, safety baselines, and complete post-write readback verification.

---

## Key Features

### 1. Recipe Studio & Curated Library
Browse, filter, and organize over 50 curated film recipes inspired by iconic analog emulsion stocks—from classic color negatives and rich slides to high-contrast street monochromes.

<p align="center">
  <img src="docs/screenshots/recipe-library.png" alt="Recipe Studio & Library" width="880" />
</p>

- **Film Simulation Filtering**: Instantly isolate recipes based on Fujifilm base simulations: *Classic Chrome*, *Reala Ace*, *Classic Negative*, *Velvia*, *Acros / Monochrome*, *Nostalgic Neg*, *Eterna / Cinema*, and *Provia / Astia*.
- **Quick Look Formulas**: Press **Spacebar** on any recipe card to open a full formula breakdown featuring Dynamic Range tags, Kelvin color temperature badges, and tone curve highlights.
- **One-Click Dial Staging**: Quickly assign any recipe directly to custom dial slots (**C1–C7**) with live slot status indicators.
- **Deep Search & Tagging**: Search recipes dynamically by recipe title, creator, tags, Kelvin values, or sensor compatibility.

---

### 2. Camera Hub & High-Speed USB PTP Synchronization
Establish a direct USB-C link to your camera using native Fujifilm PTP protocols, eliminating manual menu entry.

<p align="center">
  <img src="docs/screenshots/camera-hub.png" alt="Camera Hub & Staging" width="880" />
</p>

- **Real-Time Hardware Telemetry**: Live inspection of connected camera state, hardware model detection (e.g. `FUJIFILM X100VI`), sensor capabilities (40.2 MP Back-Illuminated X-Trans CMOS 5 HR), and USB Vendor ID (`0x04CB`) / Product ID (`0x0305`).
- **Interactive Connection Checklist**: Step-by-step guidance ensuring camera connection mode, high-speed data cables, and macOS PTP endpoint permissions are properly configured.
- **Safe Readback Verification**: Every write transaction automatically backs up prior slot settings, writes individual camera properties, and executes a full readback before confirming physical persistence.
- **Dual Transport Architecture**: Modern `ImageCaptureCore` session management by default (coexisting harmoniously with macOS `ptpcamerad`) with an optional bundled universal `libusb` helper fallback.

---

### 3. C1–C7 Custom Dial Matrix
A complete visual command center for staging, comparing, and managing all 7 physical custom dial positions on your camera.

<p align="center">
  <img src="docs/screenshots/dial-matrix.png" alt="Custom Dial Matrix" width="880" />
</p>

- **Offline Staging Rack**: Prepare complete 7-recipe loadouts on your Mac before connecting the camera. Staged drafts remain safely isolated from camera hardware until explicitly written.
- **Side-by-Side Slot Comparison**: Clearly view staged draft values side-by-side with live, camera-verified settings.
- **Batch Push to Camera**: One-click **"Write All Staged Slots to Camera"** pushes and verifies all 7 dial positions in a sequential, transactional pipeline.
- **Granular Slot Management**: Edit, refresh, clear, or push individual slots without disturbing your other dial presets.

---

### 4. In-Camera RAF Darkroom & RAW Processing
Harness the authentic image processing power of your camera's dedicated onboard **X-Processor 5** chip directly from macOS.

<p align="center">
  <img src="docs/screenshots/darkroom-preview.png" alt="RAF In-Camera Darkroom" width="880" />
</p>

- **Hardware-Accelerated In-Camera Development**: Sends native uncompressed or lossless-compressed RAF files to the connected camera over USB for hardware-level demosaicing and rendering.
- **Authentic Fujifilm Color Science**: Because processing runs on the camera's dedicated imaging ASIC, results deliver 100% genuine Fuji color, grain texture, and tonal gradation with zero third-party software approximation.
- **3-Stage Development Pipeline**:
  1. *Source RAF Ingestion*: Drag and drop uncompressed or lossless compressed RAF raw files.
  2. *Recipe Profile Selection*: Choose any curated or custom recipe from your library.
  3. *Hardware Conversion Trigger*: Initiate development on camera hardware and export high-resolution JPEGs.

---

### 5. In-Depth Recipe Editor & Customizer
Craft signature photographic recipes with complete creative control and real-time validation.

<p align="center">
  <img src="docs/screenshots/recipe-editor.png" alt="Custom Recipe Editor" width="880" />
</p>

- **Visual Film Simulation Carousel**: Fast visual picker displaying color chips calibrated to each Fujifilm simulation aesthetic.
- **Dynamic Range & Exposure**: Precise selection across `DR100`, `DR200`, `DR400`, and `DR Auto`.
- **White Balance & Color Shift**: Select standard WB presets or dial in exact color temperatures from **2,500K to 10,000K**, combined with interactive Red and Blue shift offsets (-9 to +9).
- **Tone Curve with Half-Step Precision**: Configure Highlight and Shadow tone curves with 0.5-step granularity (-2.0 to +4.0).
- **Grain, Color Chrome & Clarity**: Fine-tune Grain Effect (Off, Weak/Strong, Small/Large), Color Chrome Effect, Color Chrome FX Blue, Sharpness, Clarity, and High ISO Noise Reduction.
- **Real-Time Validation**: Automatic sanity checks prevent duplicate recipe naming and ensure all parameters fall within valid Fujifilm hardware specifications.

---

### 6. Local Backup & Safe Restore Safeguards
FujiRecipes is built with defensive engineering to protect your camera presets and local collections:

- **Strict State Separation**: Local drafts and camera-synced presets are kept strictly distinct in memory and persistent storage. Clearing a local draft never alters camera hardware.
- **Non-Destructive Baselines**: The app never writes raw-zero empty sentinels to physical slots. When resetting or rolling back, documented camera-accepted baseline fixtures are maintained.
- **Fault Recovery Alerts**: If staged drafts or local libraries encounter serialization anomalies, automatic recovery alerts present options to inspect backup snapshots in Finder.

---

## Hardware & System Requirements

| Requirement | Specification |
|:---|:---|
| **Operating System** | macOS 14.0 Sonoma or later (macOS 15 Sequoia fully supported) |
| **Architecture** | Universal binary (Apple Silicon M1/M2/M3/M4 & Intel x86_64) |
| **Supported Camera** | **Fujifilm X100VI** (Hardware validated for C1–C7 preset persistence; compatible with X-Trans V generation cameras) |
| **Camera Connection Mode** | `SET-UP` > `CONNECTION SETTING` > `CONNECTION MODE` > **`USB RAW CONV. / BACKUP RESTORE`** |
| **USB Cable** | Direct USB-C data cable (480 Mbps USB 2.0 or 5+ Gbps USB 3.x; charge-only cables will not enumerate) |

### Connecting Your Camera

1. Power on your Fujifilm camera.
2. In the camera menu, navigate to:  
   `SET-UP` &rarr; `CONNECTION SETTING` &rarr; `CONNECTION MODE` &rarr; select **`USB RAW CONV. / BACKUP RESTORE`**.
3. Connect the camera directly to your Mac using a USB-C data cable.
4. Launch **FujiRecipes** and open the **Camera & Staging** tab.
5. Click **Connect Camera**. The status indicator will turn green and display **Session Active**.

> **Note**: If another application (such as Apple Photos or Image Capture) is locking the camera PTP endpoint, close it before initiating connection.

---

## Architecture & Technology Stack

FujiRecipes is structured into modular layers separating the native UI, business logic, and low-level camera protocols:

```
┌────────────────────────────────────────────────────────┐
│                   FujiRecipesMac                       │
│      Native macOS App (SwiftUI + AppKit + Glass)       │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│                  FujiRecipesCore                       │
│   Domain Models • Recipe Parser • Preset Encoders      │
│   Loadout Management • Hardware Verification Engine    │
└───────────────────────────┬────────────────────────────┘
                            │
┌───────────────────────────▼────────────────────────────┐
│                   FujiPTPClient                        │
│   Cross-Platform PTP Protocol Abstraction Layer        │
│                                                        │
│   ┌──────────────────────────┐  ┌──────────────────┐  │
│   │ ImageCaptureCore Transport│  │ libusb Helper    │  │
│   │ (Default, macOS native)  │  │ (Fallback PTP)   │  │
│   └──────────────────────────┘  └──────────────────┘  │
└───────────────────────────┬────────────────────────────┘
                            │ USB-C (PTP 0x04CB:0x0305)
┌───────────────────────────▼────────────────────────────┐
│           Fujifilm Camera (e.g. X100VI)                │
│    C1–C7 Custom Slots • X-Processor 5 RAW Engine       │
└────────────────────────────────────────────────────────┘
```

- **`macos/`**: Pure native macOS user interface built with SwiftUI and AppKit. Implements sleek dark-theme styling, glass design system tokens, responsive split navigation, keyboard accelerators, and Quick Look integration.
- **`FujiRecipesCore/`**: Core library with zero UI dependencies. Handles JSON recipe parsing, film simulation models, white balance Kelvin calculations, C-slot binary encoders, snapshot rendering, and write verification logic.
- **`FujiPTPClient/`**: PTP communication layer implementing `PTPClientProtocol`. Defaults to Apple's `ImageCaptureCore` transport for seamless coexistence with system daemon `ptpcamerad`, with a bundled universal C helper (`poc-x100vi-reader`) using `libusb-1.0` available via `FUJI_RECIPES_TRANSPORT=helper`.

---

## Getting Started / Building from Source

### Prerequisites

- macOS 14.0 or later
- Xcode 16.0+ or Command Line Tools with **Swift 6.0+**
- Git

### 1. Clone the Repository

```bash
git clone https://github.com/AntApper/FujiRecipesMac.git
cd FujiRecipesMac
```

### 2. Run Test Suites

Verify core business logic and PTP protocol tests:

```bash
# Run FujiRecipesCore test suite (158 unit & integration tests)
swift test --package-path FujiRecipesCore

# Run FujiPTPClient protocol tests
swift test --package-path FujiPTPClient
```

### 3. Build the macOS App

Build the debug executable using Swift Package Manager:

```bash
swift build --package-path macos
```

Or run the application directly from terminal:

```bash
swift run --package-path macos FujiRecipesMac
```

### 4. Generate High-Resolution Snapshots

FujiRecipes includes an integrated headless snapshot renderer that generates retina screenshots matching your app styling:

```bash
swift run --package-path macos FujiRecipesMac --generate-snapshots --snapshot-output docs/screenshots
```

### 5. Package a Distributable `.app` Bundle

Produce a self-contained, notarization-ready macOS application bundle complete with icons and embedded resources:

```bash
cd macos
./package_app.sh release --version 1.0.0 --build-number 1
```

The resulting `Fuji Recipes.app` will be created in `macos/dist/` containing universal `arm64` and `x86_64` binaries.

---

## Repository Structure

```
FujiRecipesMac/
├── docs/                                # Technical documentation & hardware evidence
│   ├── screenshots/                     # Curated high-res retina UI screenshots
│   │   ├── recipe-library.png           # Recipe Studio & curated library view
│   │   ├── camera-hub.png               # Camera Hub & USB PTP hardware telemetry
│   │   ├── dial-matrix.png              # C1–C7 Custom Dial Matrix staging
│   │   ├── darkroom-preview.png         # In-Camera RAF Darkroom workflow
│   │   └── recipe-editor.png            # Custom Recipe Editor & inspector
│   ├── RELEASE.md                       # Release guide & distribution requirements
│   ├── MACOS_RELEASE_BOUNDARIES.md      # Signing, notarization, and runtime boundaries
│   ├── camera-connection-guide.md       # Detailed camera connection walkthrough
│   ├── architecture-decision.md         # PTP architecture decisions & rationale
│   └── x100vi-c-slot-hardware-regression-2026-09-12.md # Physical hardware verification
├── macos/                               # Native macOS application
│   ├── Package.swift                    # macOS target configuration
│   ├── package_app.sh                   # Application bundle packager & validator
│   ├── Resources/                       # Icons, bundled helper, and recipe catalog
│   └── Source/                          # SwiftUI views, AppShell, and snapshot engine
├── FujiRecipesCore/                     # Core domain package
│   ├── Package.swift                    # Core target configuration
│   ├── Sources/FujiRecipesCore/         # Models, parsers, encoders, and stores
│   └── Tests/FujiRecipesCoreTests/      # Verification, recovery, and serialization tests
├── FujiPTPClient/                       # Hardware PTP protocol package
│   ├── Package.swift                    # PTP client target configuration
│   └── Sources/                         # ImageCaptureCore & libusb PTP implementations
├── scripts/                             # Release verification, linting, and notarization
├── LICENSE                              # MIT License
└── README.md                            # Project documentation
```

---

## Technical Documentation

For deeper architectural details and hardware verification logs, refer to the technical documents in `docs/`:

- [macOS Release Guide](docs/RELEASE.md) — Scope, signing, and verification instructions.
- [macOS Release Boundaries](docs/MACOS_RELEASE_BOUNDARIES.md) — Structural vs. notarization requirements.
- [Camera Connection Guide](docs/camera-connection-guide.md) — Comprehensive USB PTP troubleshooting.
- [C1–C7 Hardware Regression Record](docs/x100vi-c-slot-hardware-regression-2026-09-12.md) — Physical hardware validation logs on Fujifilm X100VI.
- [Recipe Library Schema](docs/recipe-library-schema.md) — JSON recipe format specifications.

---

## Roadmap

- [x] Curated Recipe Library with 50+ analog-inspired film formulations
- [x] High-speed USB PTP connection in `USB RAW CONV. / BACKUP RESTORE` mode
- [x] Complete C1–C7 custom dial matrix staging, comparison, and batch synchronization
- [x] In-Camera RAF Darkroom integration utilizing onboard X-Processor 5 hardware
- [x] Fine-grained Custom Recipe Editor with visual color simulation chips and half-step tone curves
- [x] Automated pre-write backup and verified readback validation
- [ ] Expand validated hardware profiles to additional Fujifilm X-Trans V cameras (X-T5, X-H2, X-T50)
- [ ] Recipe export/import in open JSON and QR code formats for mobile companion scanning
- [ ] Batch RAF conversion queue with automatic JPEG export directory management

---

## Contributing

Contributions, bug reports, and recipe formulations are warmly welcomed!

1. Fork the repository.
2. Create a descriptive feature branch (`git checkout -b feature/recipe-search-enhancement`).
3. Ensure all tests pass cleanly (`swift test --package-path FujiRecipesCore && swift test --package-path FujiPTPClient`).
4. Commit your changes following standard commit conventions.
5. Open a Pull Request with a summary of changes and verification steps.

---

## Legal / Trademark Disclaimer

This project is an independent open-source tool and is not affiliated with, endorsed by, sponsored by, or associated with **FUJIFILM Corporation**, **Fuji X Weekly**, **Eastman Kodak Company**, **CineStill Inc.**, **HARMAN technology Ltd.**, or **Agfa-Gevaert NV**.

*"FUJIFILM"*, *"X100VI"*, *"X-Trans"*, and Fujifilm film simulation names are trademarks or registered trademarks of FUJIFILM Corporation. All other brand names, product names, and trademarks mentioned in this project are the property of their respective owners and are used solely for identification, educational, and compatibility purposes.

---

## License

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for complete details.

<div align="center">
  <sub>Engineered with precision for Fujifilm photographers. Crafted with Swift and SwiftUI on macOS.</sub>
</div>
