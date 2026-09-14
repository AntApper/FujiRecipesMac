# RAF conversion retrieval hardware validation

This retrieval path is intentionally conservative. It has compile- and unit-test
coverage, but its PTP object-delivery behavior is not verified on an X100VI.
Run the following only with a camera and SD card whose contents may be safely
inspected. The helper does not issue `DeleteObject`.

## Preconditions

1. Record the camera's current card object count and photograph several known
   card images so accidental selection is obvious.
2. Put the camera in the USB mode required for RAW conversion, connect it by
   USB-C, and make sure no other camera application is connected.
3. Build the helper and use a same-camera RAF known to be accepted by the
   existing upload path.

## Validation sequence

1. Send `trigger_conversion`; verify the JSON says
   `baseline_inventory: "captured"` and save the reported baseline count.
   A baseline-inventory failure must prevent the trigger from being sent.
2. Call `wait_result` after the trigger. Save its full JSON response and the
   helper stderr log. Confirm `diagnostics.auto_deleted` is `false`.
3. If `status` is `no_new_object`, verify manually on the camera LCD and SD
   card whether the camera produced an image elsewhere. This state makes no
   claim that conversion did or did not complete.
4. If `status` is `no_jpeg_candidate`, inspect the reported new objects using
   an independent PTP browser or the camera. Record their object-info format,
   filename, and size.
5. If `status` is `indeterminate_multiple_jpeg_candidates`, verify that no
   output file was written and no camera object was deleted. Determine which
   candidate is actually the conversion output before considering a future
   selection policy.
6. Only for `status: "jpeg_downloaded"`, verify all of:
   - `diagnostics.delivery_verified` is true;
   - a non-zero candidate handle and JPEG-like metadata were reported;
   - the saved file starts with `FF D8`, opens as the expected image, and
     matches the camera's visible/card result;
   - the camera still retains the candidate object after download.
7. Repeat with a card containing existing JPEGs, no card images, and (where
   supported) multiple storage IDs. Capture the baseline/post counts and
   object-info records for each run.

Do not generalize a result from another Fujifilm body to X100VI. Record camera
firmware, USB mode, macOS version, helper build, source RAF, and full helper
diagnostics with every run.

## Observed hardware evidence — 2026-09-13

- Host: macOS 26.6.2 (build 25G83), Darwin 25.6.0 arm64.
- A physical camera enumerated as `USB PTP Camera` at USB address 3. No
  `ptpcamerad` process was present before or after probing, so its documented
  stop/reclaim workaround was not used.
- The repository's legacy development helper could find the camera and reported
  successful `connect`, `reconnect`, and `disconnect` commands. Its log reported
  OpenSession response `0x201D` on connect and `0x2006` during reconnect, so
  those success JSON responses do not establish a clean PTP-session result.
- The newly bundled helper
  (`FujiRecipesMac/macos/Resources/x100vi_helper`,
  SHA-256 `444b12d31897e302f0d07827bb05b1839e7057d8529661c3a75d80fd04b436b7`)
  found the same camera and loaded its adjacent bundled libusb runtime, but
  OpenSession transaction 1 timed out (`rc=-7`). It returned
  `{"success":false,"error":"session_open_failed","code":-3}`; no property,
  inventory, conversion, or object-retrieval command was issued afterward.
- No `.RAF` file was available anywhere in this repository. Therefore no
  baseline/delta conversion run occurred, no JPEG delivery result is claimed,
  and neither the camera LCD nor SD card was inspected through a tool.

### Continuation evidence — 2026-09-13

- Host: macOS 26.6.2 (build 25G83), Darwin 25.6.0 arm64.
- Source search was restricted to `/Users/ant/Desktop` and found no files with
  either `.RAF` or `.raf` extension. No candidate was opened, copied, moved,
  or modified. Consequently, no RAF upload, profile write, conversion trigger,
  baseline inventory, storage-ID query, delta poll, or JPEG retrieval was
  issued in this run.
- Connection ownership check found no running `ptpcamerad`, `x100vi_helper`,
  `gphoto2`, or FujiRecipes process. The bundled helper was therefore the only
  observed client claiming the camera interface.
- The freshly bundled helper and libusb runtime passed
  `scripts/verify-helper-resource.sh`: both are universal (`arm64`, `x86_64`),
  the helper loads `@rpath/libusb-1.0.0.dylib`, and source/resource provenance
  checks passed. Provenance identifies helper SHA-256
  `d553ae986ac04ea7489f2082dede6ec5c74070e3e71f4d8ece629416f6f10dd8`.
- Bundled-helper connection transcript:
  - Camera identity: `USB PTP Camera`, serial
    `59353731303125022027039021ACCC`.
  - Both endpoint-halt clears returned `rc=0`.
  - OpenSession transaction 1 returned PTP response `0x2001`; the helper
    emitted `{"id":"connection","success":true,"result":"connected"}`.
  - CloseSession transaction 2 returned PTP response `0x2001`; the helper
    emitted `{"id":"connection-close","success":true,"result":"disconnected"}`.
- No camera setting, SD-card content, or camera object was altered. In
  particular, no `DeleteObject` command was sent. Storage IDs, baseline/post
  handle counts, candidate metadata, and JPEG delivery state are unavailable
  because the required Desktop RAF candidate was absent.
- User-required physical inspection: none is implied by this blocked run.
  When a same-camera RAF is placed on the Desktop, inspect the camera LCD and
  SD card if `wait_result` returns `no_new_object`, as required above.

### Full conversion attempt — 2026-09-13 (DSCF3904)

- Source RAF: `/Users/ant/Desktop/DSCF3904.RAF`; it was a readable
  87,550,976-byte file (mode `-rwx------`) with SHA-256
  `d96e162bdc3f107f01b0031607ab4e8055c854a7e8fd4c90340caaf7983fdfed`.
  The helper only read this path; it was neither copied nor modified.
- Before conversion, no `ptpcamerad`, `x100vi_helper`, `gphoto2`, or
  FujiRecipes process owned the camera. The bundled helper opened and closed
  a health-check session with `OpenSession` transaction 1 and `CloseSession`
  transaction 2 both acknowledged as `0x2001`.
- A preflight `convert_raf` command issued without a `connect` request returned
  `not_connected` and sent no PTP command. The single connected pipeline below
  was the actual conversion attempt; it was not a protocol retry.
- Pipeline transport evidence:
  - `SendObjectInfo` (`0x900C`, transaction 2, 82-byte data phase) returned
    `0x2001`.
  - `SendObject2` (`0x900D`, transaction 3) transferred 87,550,988 container
    bytes in 167 chunks and returned `0x2001`.
  - The prescribed post-upload reconnect closed transaction 4 with `0x2001`,
    then opened a fresh transaction-1 session with `0x2001`.
  - The required default 632-byte `0xD185` conversion profile was accepted
    (`0x2001`), and the `0xD183` conversion trigger (value 0) was accepted
    (`0x2001`).
- Baseline/delta evidence:
  - The helper sent `GetStorageIDs` (`0x1004`) and two
    `GetObjectHandles` (`0x1007`) requests successfully, then reported
    `Baseline inventory: 0 handles`.
  - The current helper does not emit the returned storage IDs or individual
    baseline handles. It emitted only the zero handle count, so no storage-ID
    values or handle list can be asserted from this run.
  - Retrieval returned
    `status: "indeterminate_no_baseline"`, `rc: -95`, with baseline/post/new
    handle counts all zero, candidate handle/format/size all zero, an empty
    candidate name, and `inspected_object_count: 0`.
  - This is an empty-inventory helper defect: `capture_object_inventory`
    accepted a valid zero-handle baseline, but `wait_for_result` rejects the
    baseline because its empty handle array has a null pointer. It therefore
    performed no post-trigger delta poll, object-info lookup, JPEG signature
    verification, or JPEG download.
- No local JPEG was created at
  `/tmp/fuji-x100vi-DSCF3904-validation.jpg`; `delivery_verified` is false
  and no output, candidate metadata, or PTP object delivery is claimed.
  `auto_deleted` is false, and no `DeleteObject` command was issued.
- After the helper exited, no camera-owning process remained. The necessary
  next observation is user physical inspection of the camera LCD and SD card:
  the camera accepted the upload/profile/trigger, but this run cannot
  determine whether it displayed or saved a conversion result. Do not retry
  this same retrieval flow until the zero-handle baseline defect is fixed or
  a helper that preserves an empty baseline is used.

### Repaired-helper conversion attempt — 2026-09-13 (DSCF3904)

- The repaired bundled helper passed `scripts/verify-helper-resource.sh`.
  Provenance records source SHA-256
  `a5ac77aad34266d282bad49a572abc0fd3b90c3f82f366036fe2b19ed041fa7d`
  and helper SHA-256
  `02c227507ab4cb21de118bcaa56467d4bd9e4b931d08c49fb34dd9eeeb00fdc4`.
  The power-cycled camera passed a separate session health check: OpenSession
  transaction 1 and CloseSession transaction 2 both returned `0x2001`.
- One connected conversion pipeline was run. `SendObjectInfo` (`0x900C`,
  transaction 2, 82-byte data) and `SendObject2` (`0x900D`, transaction 3,
  87,550,988 container bytes in 167 chunks) both returned `0x2001`.
  The mandated reconnect closed transaction 4 with `0x2001`, then reopened
  a fresh session with `0x2001`. The 632-byte default profile and trigger
  (`0xD183`, value 0) each returned `0x2001`.
- Structured baseline/delta retrieval result (helper stdout):

  ```json
  {
    "id": "validation-DSCF3904",
    "success": true,
    "result": {
    "status": "jpeg_downloaded",
    "path": "/tmp/fuji-x100vi-DSCF3904-validation.jpg",
    "size": 2042201,
    "candidate_handle": 2,
    "candidate_format": 14337,
    "candidate_name": "DSCF0001.jpg",
    "diagnostics": {
      "baseline_handle_count": 0,
      "post_handle_count": 1,
      "new_handle_count": 1,
      "inspected_object_count": 1,
      "auto_deleted": false,
      "delivery_verified": true
    },
    "rc": 0
    }
  }
  ```

- Helper stderr confirms the baseline `GetStorageIDs` followed by two
  `GetObjectHandles` requests, then a post-trigger `GetStorageIDs`, two
  `GetObjectHandles`, `GetObjectInfo` (candidate handle 2), and `GetObject`.
  The helper does not expose raw storage-ID values or per-storage handle lists
  in its structured output; only the observed aggregate counts above can be
  recorded. `candidate_format` 14337 is `0x3801` (EXIF/JFIF JPEG).
- Local byte verification passed: the downloaded file begins
  `FF D8 FF E1 … Exif`, SHA-256 is
  `04ef8f41e1d7e4770a348cbe326dcaf20f5d0dbb3e0ce13f29ceff50af243cf5`,
  and macOS identified it as a 3888×2592 JPEG. `auto_deleted` is false; no
  `DeleteObject` command was sent. The final CloseSession transaction 12 also
  returned `0x2001`.
- This verifies PTP JPEG delivery. The helper has no post-download listing
  command, so continued camera retention of handle 2 and a visible/card match
  were not independently re-read. A brief LCD/SD inspection is the minimal
  remaining corroboration; it is not needed to establish that the JPEG was
  delivered over PTP.

### SD-card conversion attempt — 2026-09-13 (DSCF3904)

- After the user installed an SD card and power-cycled the camera, no
  `ptpcamerad`, helper, gphoto2, or FujiRecipes process was present. A clean
  preflight OpenSession/CloseSession exchange returned `0x2001` for
  transactions 1 and 2.
- Exactly one connected conversion was issued. `SendObjectInfo` (`0x900C`),
  `SendObject2` (`0x900D`, 87,550,988 container bytes in 167 chunks), the
  reconnect CloseSession/OpenSession, the 632-byte default profile, and the
  value-0 conversion trigger all returned `0x2001`.
- The helper baseline logged 0 handles. Its post-trigger retrieval logged one
  post handle and one new handle, inspected one object, selected candidate
  handle 2 (`DSCF0001.jpg`, format `0x3801`), then completed `GetObject`.
  Structured stdout reported:

  ```json
  {
    "id": "sd-validation-DSCF3904",
    "success": true,
    "result": {
      "status": "jpeg_downloaded",
      "path": "/tmp/fuji-x100vi-DSCF3904-sd-validation.jpg",
      "size": 2043367,
      "candidate_handle": 2,
      "candidate_format": 14337,
      "candidate_name": "DSCF0001.jpg",
      "diagnostics": {
        "baseline_handle_count": 0,
        "post_handle_count": 1,
        "new_handle_count": 1,
        "inspected_object_count": 1,
        "auto_deleted": false,
        "delivery_verified": true
      },
      "rc": 0
    }
  }
  ```

- The downloaded file starts `FF D8 FF E1 … Exif`, is a valid 3888×2592 JPEG,
  and has SHA-256
  `f0692bbd701f760815328ccf92b6f11023534143adf938e1a6633320e7269288`.
  The helper's final CloseSession (transaction 12) returned `0x2001`; no
  camera-owning process remained afterward. `auto_deleted` is false and no
  `DeleteObject` operation was issued.
- This is PTP-delivery evidence only. It makes no claim that the JPEG is on
  the SD card or visible on the LCD. User inspection of both is required to
  establish those physical observations.
