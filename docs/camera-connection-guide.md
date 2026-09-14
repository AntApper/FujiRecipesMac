# Camera Connection Guide for macOS

## Platform scope

This guide covers the macOS production path: the bundled `x100vi_helper`
uses libusb raw PTP and verifies requested C-slot writes by readback before
the app reports a physical save. The iOS transport remains a stub; it does
not currently provide verified C1–C7 read or write support.

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
- Fuji X100VI (or X100V, X-T5, X-T30, X-T4)
- USB-C data cable (not charge-only)
- macOS 14+ with FujiRecipesMac app installed

### Step-by-Step Connection

#### 1. Prepare Your Camera
1. Turn on the camera
2. Go to **Menu → Setup → USB Connection → PTP** (not Mass Storage)
3. Set **USB Mass Storage** to **OFF** (if present)

#### 2. Release macOS's PTP daemon
macOS may automatically grab USB cameras through `ptpcamerad`. FujiRecipes
attempts to release it before connecting. If that fails, close Photos, Image
Capture, and Preview, then retry after reconnecting the camera.

```bash
# If diagnostics show the daemon owns the camera:
killall -9 ptpcamerad
```

Then **quit Photos, Image Capture, and Preview** if they're running.

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
- Run: `sudo killall PTPCamera`
- Disconnect and reconnect USB cable

#### "Camera connecting forever" or "Connection timed out"
- A stale app build may contain an outdated helper; rebuild the app so its
  bundled `x100vi_helper` is refreshed from the repository resource.
- `ptpcamerad` or another camera app may own the USB interface.
- Run: `killall -9 ptpcamerad`
- Quit all camera-related apps (Photos, Image Capture, Preview, Adobe Bridge)
- Wait 5 seconds
- Try again

#### "Failed to communicate with camera"
- `ptpcamerad` may still be blocking the interface.
- Check: `pgrep -a ptpcamerad` — if a process shows, quit competing camera
  apps, reconnect the camera, and retry.
- Run a read-only helper check before attempting any C-slot write.

#### Camera not showing in system_profiler
```bash
system_profiler SPUSBDataType | grep -i "fuji\|ptp\|x100"
```
If nothing shows, the USB connection isn't working. Try:
- Different USB-C cable
- Different USB port on Mac
- Different USB hub (if using one)

### Test Script
```bash
# Run the comprehensive camera connection test
bash tools/test-camera-connection.sh
```

This script will:
1. Check if a Fuji camera is connected
2. Kill PTPCamera if running
3. Verify libgphoto2 availability
4. Test gphoto2 CLI
5. Show camera details

### Supported Cameras

| Camera | USB VID:PID | PTP Code |
|--------|------------|----------|
| X100VI | 0x04CB:0x0305 | Supported |
| X100V  | 0x04CB:0x02E5 | Supported |
| X-T5   | 0x04CB:0x02E3 | Supported |
| X-T30  | 0x04CB:0x02E3 | Supported |
| X-T4   | 0x04CB:0x02E7 | Supported |

### Technical Details

The macOS connection flow:
1. Release the competing `ptpcamerad` process when present.
2. Launch the bundled `x100vi_helper`.
3. Verify its line-delimited JSON protocol with `ping`.
4. Send the helper's `connect` command, which claims the USB interface and
   opens the PTP session.
5. Publish the connected UI state.
6. Start the C1–C7 read-only sync in the background.

For raw PTP communication, we use:
- `GetDevicePropValue` (0x1015) — read property values
- `SetDevicePropValue` (0x1016) — write property values
- Properties 0xD18C-0xD1A5 for preset slots C1-C7
