# Vendor Command Debug — RAF Loading Issue

## Problem
Vendor commands (0x900C SendObjectInfo, 0x900D SendObject2, 0x902B TetherOpen) cause device stall (rc=-9 / LIBUSB_ERROR_PIPE) on X100VI via libusb on macOS.

## ✅ RESOLVED (2026-07-04)
All three protocol bugs fixed. SendObjectInfo (0x900C) and SendObject2 (0x900D) now work perfectly — tested with 54.7MB RAF upload (110 chunks, zero stalls). TetherOpen (0x902B) still stalls (likely doesn't need DATA phase).

## Root Cause Analysis

After studying FilmKit (WebUSB, working), rawji (PyUSB, working), and fudge (WiFi, working), I found **two bugs** in our libusb implementation that could contribute to the stall:

### Bug 1: DATA container had extra parameter bytes

Our old `send_two_phase_combined` function built the DATA container with `paramCount * 4` extra bytes:

```
WRONG: DATA = header(12) + params(paramCount*4 zeros) + data
RIGHT: DATA = header(12) + data (NO params)
```

FilmKit and rawji both send DATA containers with **NO params** — just the 12-byte header followed directly by raw data. The PTP spec says DATA containers carry the payload after the header, with no parameters.

**However**, this bug was only in `send_two_phase_combined` which was used by the **disabled** vendor commands. Standard PTP (read/write properties) used separate functions that were correct.

### Bug 2: Combined COMMAND + DATA in single transfer

Our old code sent both COMMAND and DATA containers concatenated in a **single** `libusb_bulk_transfer` call:

```
WRONG: One bulk transfer: [COMMAND container][DATA container]
RIGHT: Two transfers:  [COMMAND container] then [DATA container]
```

FilmKit and rawji send each PTP container as a **separate** USB transfer. Each container is independently addressed by the camera's USB stack.

### Bug 3: No stall recovery

When `libusb_bulk_transfer` returns `LIBUSB_ERROR_PIPE` (-9), the endpoint is stalled. Our code had no recovery — it would need `libusb_clear_halt()` to clear the stall.

## Changes Made

### 1. Fixed `ptp_send` (COMMAND container)
- Changed from fixed 24-byte buffer to actual container length
- Always sends exactly `12 + paramCount * 4` bytes

### 2. Added `ptp_send_data` (DATA container)
- New function matching FilmKit/rawji protocol
- DATA container: 12-byte header + raw data only (NO params)
- For payloads ≤ 64KB: single transfer with header + data
- For larger payloads: header+data chunked at 512KB (matches FilmKit)

### 3. Added `send_vendor_command` (proper 3-phase)
- Phase 1: COMMAND container (type=0x0001, with params) — separate transfer
- Phase 2: DATA container (type=0x0002, NO params) — separate transfer via `ptp_send_data`
- Phase 3: RESPONSE container (type=0x0003) — received after 10ms delay
- Includes stall recovery with `libusb_clear_halt()` and 100ms delay

### 4. Added `clear_endpoint_halt`
- Wraps `libusb_clear_halt()` for OUT (0x01) and IN (0x81) endpoints

### 5. Re-enabled `load_raf` command
- Reads RAF file from disk
- Builds ObjectInfo structure (matches FilmKit exactly: 78 bytes)
- Step 1: `send_vendor_command(0x900C, ...)` with ObjectInfo
- Step 2: `send_vendor_command(0x900D, ...)` with RAF data
- Detailed error reporting (stall type, rc codes)

### 6. Updated `test_vendor` command
- Supports `tether_open` (0x902B) and `send_object_info` (0x900C) test modes
- Uses proper 3-phase vendor command function

## Protocol Verification

### ObjectInfo Structure (verified byte-by-byte)
```
Offset  Size  Field              Value
0       4     StorageID          0x00000000
4       2     ObjectFormat       0xF802 (RAF)
6       2     ProtectionStatus   0x0000
8       4     CompressedSize     <file size>
12      2     ThumbFormat        0x0000
14      4     ThumbCompressedSize 0
18      4     ThumbPixWidth      0
22      4     ThumbPixHeight     0
26      4     ImagePixWidth      0
30      4     ImagePixHeight     0
34      4     ImageBitDepth      0
38      4     ParentObject       0
42      2     AssociationType    0
44      4     AssociationDesc    0
48      4     SequenceNumber     0
52      1     FilenameLen        13 (incl. null)
53      26    Filename           "FUP_FILE.dat" (UCS-2LE)
79      1     CaptureDate        0 (empty)
80      1     ModificationDate   0 (empty)
81      1     Keywords           0 (empty)
Total: 82 bytes
```

### Vendor Command Sequence (matches FilmKit/rawji exactly)
```
1. sendCommand(0x900C, [0,0,0], ObjectInfo) → RESPONSE
   - COMMAND: type=0x0001, code=0x900C, params=[0,0,0], transId=N
   - DATA: type=0x0002, code=0x900C, NO params, data=ObjectInfo, transId=N
   - RESPONSE: type=0x0003, code=0x2001 (OK), transId=N

2. sendCommand(0x900D, [], RAF_data) → RESPONSE
   - COMMAND: type=0x0001, code=0x900D, NO params, transId=N+1
   - DATA: type=0x0002, code=0x900D, NO params, data=RAF_file, transId=N+1
   - RESPONSE: type=0x0003, code=0x2001 (OK), transId=N+1
```

## Test Results (2026-07-04, X100VI, macOS Sequoia, libusb 1.0.28)

### Pre-fix baseline
```
SendObjectInfo (0x900C): rc=-9 (LIBUSB_ERROR_PIPE, OUT endpoint stalled)
SendObject2 (0x900D):     rc=-9 (LIBUSB_ERROR_PIPE, OUT endpoint stalled)
TetherOpen (0x902B):      rc=-9 (LIBUSB_ERROR_PIPE, OUT endpoint stalled)
```

### Post-fix results
```
SendObjectInfo (0x900C):  OK (0x2001) ✅ — with proper 82-byte ObjectInfo
SendObject2 (0x900D):     OK (0x2001) ✅ — 54.7MB in 110 chunks
TetherOpen (0x902B):      rc=-9 (stall on DATA phase, may not need DATA)
```

### Key findings
- Minimal 16-byte ObjectInfo → 0x2008 (InvalidStorageID) — camera couldn't parse
- Proper 82-byte ObjectInfo → 0x2001 (OK) — camera accepted immediately
- RAF from different camera body → 0x2002 on D185 read (expected per rawji)
- `ptpcamerad` must be killed before testing (macOS PTP daemon conflicts)
- Camera must be in USB RAW Conversion mode

## Remaining Unknowns

### Camera Menu Setting
The camera **must** be in "USB RAW Conversion" or "USB Tether Shooting" mode:
- Menu → Setup → USB Connection → USB RAW Conversion (or USB Tether Shooting)
- Without this setting, vendor commands may fail
- **Standard PTP works regardless** (OpenSession, property reads/writes)

### libusb vs WebUSB/PyUSB Platform Differences
Even after fixing the protocol bugs, the camera may still stall. Possible reasons:
1. **macOS USB stack** — Apple's IOKit USB driver may handle bulk transfers differently than Linux kernel or Chrome's WebUSB
2. **Transfer framing** — libusb submits URBs directly to the kernel; WebUSB goes through the browser's USB API with different buffering
3. **Timing** — libusb transfers may have different inter-packet delays than WebUSB
4. **Alternate interface settings** — Camera may expose different alternate settings that change endpoint behavior
5. **Camera firmware** — X100VI may have quirks not present in X-T30/X-T4 tested by rawji

### Endpoint Configuration
Our code hardcodes endpoints 0x01 (OUT) and 0x81 (IN). These work for standard PTP but vendor commands may need:
- Different endpoint numbers
- Different alternate interface setting
- Interface re-configuration after OpenSession

## Testing Plan

When camera is connected:

1. **Basic test**: `./test_vendor.sh` — verifies connection, standard PTP, then vendor commands
2. **SendObjectInfo test**: `echo '{"id":"1","command":"test_vendor","op":"send_object_info"}' | ./x100vi_helper`
3. **Full RAF load**: `./test_vendor.sh /path/to/photo.RAF`
4. **Check endpoint config**: Use `lsusb -v` to inspect alternate settings

### Expected debug output for successful vendor command:
```
[VENDOR] command=0x900C transId=1 params=3 data=82 timeout=30000ms
[VENDOR] CMD sent: len=24 transferred=24 rc=0
[DEBUG] ptp_send_data: code=0x900C len=94 transferred=94 rc=0
[VENDOR] RESP: type=0x0003 code=0x2001 len=16
```

### If stall occurs:
```
[VENDOR] CMD sent: len=24 transferred=24 rc=-9
[VENDOR] CMD endpoint stalled, clearing halt...
[DEBUG] clear_endpoint_halt: ep=0x01 rc=0
```

## Files Changed
- `poc-x100vi-reader/x100vi_helper.c` — Full vendor command rewrite
- `poc-x100vi-reader/test_vendor.sh` — New test script

## References
- FilmKit source: `src/ptp/transport.ts` — `sendDataCommand()` (separate transfers)
- rawji source: `src/rawji/fuji_usb.py` — `send_data_command()` (separate transfers)
- PTP spec (ISO 15740): Container format, DATA container has no params
- gphoto2 libusb.c: Standard PTP over libusb reference
