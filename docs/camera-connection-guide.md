# Camera Connection Guide for macOS

## Platform scope

This guide covers the macOS helper path for the X100VI: the bundled
`x100vi_helper` uses libusb raw PTP and verifies requested C-slot writes by
readback before the app reports a physical save. The iOS transport remains a
stub; it does not currently provide verified C1–C7 read or write support.

USB PTP-service ownership is a current operational limitation, not a public
release reliability claim. macOS or another camera application can own the
same interface, and a failed connection must be treated as unavailable rather
than as a condition the app can safely override.

## Camera Hub connect regression — 2026-09-12

The production Camera Hub could remain in its connecting state even with an
enumerated X100VI. Three independent defects combined:

1. `withTimeout` waited for its losing sleep task before returning a successful
   result. A successful helper reply therefore remained blocked until the
   timeout elapsed; the outer 15-second connection timeout then surfaced.
2. The Swift client only sent `ping`, which checks the helper protocol but does
   not claim the USB interface or open a PTP session. It now sends `connect`
   after the ping and fails the handshake if the camera cannot be opened.
3. The app bundle copied `FujiRecipesMac/macos/Resources/x100vi_helper`, an
   older 53 KB binary, rather than the current 70 KB helper built from
   `poc-x100vi-reader/x100vi_helper.c`. The stale binary emitted an incomplete
   `read_preset_slot` JSON response. The bundled resource has been rebuilt
   from the current source.

Verification performed with the connected X100VI, using read-only operations:
the rebuilt bundled helper returned `connect` success, read C4 with 26
properties and `slot_select_rc: 0`, then disconnected cleanly. The macOS app
also rebuilt successfully. No recipe or C-slot write was performed as part of
this regression check. C-slot auto-sync now starts only after the Camera Hub
has published its connected state, so a slow slot read cannot keep the initial
connected UI or its write action unavailable.

## How to Connect Your Fuji X100VI

### Prerequisites
- Fujifilm X100VI
- USB-C data cable (not charge-only)
- macOS 14+ with FujiRecipesMac app installed

### Step-by-Step Connection

#### 1. Prepare Your Camera
1. Turn on the camera
2. Go to **Menu → Setup → USB Connection → PTP** (not Mass Storage)
3. Set **USB Mass Storage** to **OFF** (if present)

#### 2. Resolve competing camera ownership
macOS's PTP service (`ptpcamerad`) or another camera application may own the
USB interface. FujiRecipes does not terminate that service and cannot promise
that it can reclaim the interface.

Use only non-destructive recovery steps:

1. Quit Photos, Image Capture, Preview, Adobe Bridge, and other camera apps.
2. Disconnect the USB-C cable, wait a few seconds, and reconnect it.
3. Retry the connection from FujiRecipes.
4. If the camera remains unavailable, power-cycle the camera, reconnect it,
   and retry once.

If ownership continues to prevent a connection, stop there and keep the
camera unchanged. This is a known limitation of the current helper path.

#### 3. Connect USB Cable
1. Plug USB-C cable into camera and Mac
2. Wait ~3 seconds for connection

#### 3. Launch FujiRecipesMac
1. Open the FujiRecipesMac app
2. Go to the **Camera** tab (📷)
3. Click **"Connect Camera"**
4. Wait for connection (should take 1-3 seconds)

### What You'll See

#### If Connected Successfully:
- Green "Connected" status
- Camera model name displayed
- Live settings preview (Film Sim, DR, Highlight, Shadow)
- "Disconnect Camera" button

#### If Connection Fails:
- Red "Error" status with detailed error message
- The error will tell you exactly what went wrong and how to fix it

### Reading C1-C7 Preset Slots

Once connected, the app can read preset slots C1-C7 from the camera. This uses raw PTP commands:

1. Go to the **C1-C7** tab (🎛️)
2. The app displays current slot configurations
3. Click **"Load to Slot"** on any recipe to write it to a C1-C7 slot

### Troubleshooting

#### "No Fuji camera found"
- Ensure camera is powered ON
- Use a USB-C **data** cable (not charge-only)
- Camera USB mode must be set to PTP
- Quit Photos, Image Capture, Preview
- Disconnect and reconnect USB cable
- If it still does not appear, power-cycle the camera before retrying

#### "Camera connecting forever" or "Connection timed out"
- A stale app build may contain an outdated helper; rebuild the app so its
  bundled `x100vi_helper` is refreshed from the repository resource.
- `ptpcamerad` or another camera app may own the USB interface.
- Quit all camera-related apps (Photos, Image Capture, Preview, Adobe Bridge)
- Disconnect and reconnect the USB cable, then retry.
- If ownership persists, power-cycle the camera and retry once. Do not force
  terminate macOS PTP services.

#### "Failed to communicate with camera"
- `ptpcamerad` may still be blocking the interface.
- Quit competing camera apps, reconnect the camera, and retry.
- If the helper still cannot open a session, power-cycle the camera and retry
  once. The current transport does not guarantee recovery from service
  ownership.
- Run a read-only helper check before attempting any C-slot write.

#### Camera not showing in system_profiler
```bash
system_profiler SPUSBDataType | grep -i "fuji\|ptp\|x100"
```
If nothing shows, the USB connection isn't working. Try:
- Different USB-C cable
- Different USB port on Mac
- Different USB hub (if using one)

### Tested camera scope

The C1–C7 workflow is hardware-validated only for the Fujifilm X100VI
(`0x04CB:0x0305`). It is not a support or release-reliability claim for other
Fujifilm bodies. See [RELEASE.md](RELEASE.md) for the supported scope and
release boundary.

### Native ImageCaptureCore transport validation

The repository includes a macOS transport that lets
ImageCaptureCore/`ptpcamerad` own the USB session instead of the raw-libusb
helper. This is now the application default and is the intended path for
eliminating direct USB interface competition. Set
`FUJI_RECIPES_TRANSPORT=helper` only when deliberately falling back to the
legacy raw-libusb helper.

The native setting is already the default. It may also be selected explicitly
in the Xcode scheme environment:

```bash
FUJI_RECIPES_TRANSPORT=image-capture-core
```

Then build/run the `FujiRecipesMac` macOS target from Xcode. The normal app
bundle launch path should be used so ImageCaptureCore receives the app's
normal macOS process and permission context.

For a focused read-only probe, use the diagnostic executable:

```bash
swift run --package-path FujiPTPClient ImageCaptureCoreProbe 4
```

The probe opens a managed ImageCaptureCore session, reads C4, prints the
decoded values, and closes the session. It does not write camera state.
For a reconnect soak test, pass a repeat count:

```bash
swift run --package-path FujiPTPClient ImageCaptureCoreProbe 4 20
```

The guarded repository command is equivalent and first verifies that the
camera is actually enumerated:

```bash
scripts/validate-image-capture-core.sh 4 20
```

With the X100VI connected, validate in this order:

1. Connect and disconnect repeatedly without stopping `ptpcamerad`.
2. Read C4 and confirm all available properties are populated.
3. Capture the C4 baseline before any mutation.
4. Write one distinctive recipe to C4 and require complete readback.
5. Switch to another camera slot, return to C4, disconnect, reconnect, and
   read C4 again.
6. Restore the documented baseline and verify it after another reconnect.

Do not consider this transport fully validated based on a successful build
alone. Promote it for release confidence only after the physical C1–C7
regression passes.

### Technical Details

The macOS connection flow:
1. Ask the user to close competing camera applications and retry after a
   reconnect when the interface is unavailable.
2. Launch the bundled `x100vi_helper` without terminating macOS PTP services.
3. Verify its line-delimited JSON protocol with `ping`.
4. Send the helper's `connect` command, which claims the USB interface and
   opens the PTP session.
5. Publish the connected UI state.
6. Start the C1–C7 read-only sync in the background.

If step 4 cannot claim the interface, the flow reports the failure. It does
not establish dependable public-release access to the USB PTP service.

For raw PTP communication, we use:
- `GetDevicePropValue` (0x1015) — read property values
- `SetDevicePropValue` (0x1016) — write property values
- Properties 0xD18C-0xD1A5 for preset slots C1-C7
