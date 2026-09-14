# X100VI C1–C7 regression chronology and final acceptance — 2026-09-12

## Scope and evidence boundary

This document preserves the chronological hardware record for direct
`x100vi_helper` regressions and the later macOS production UI run performed
on 2026-09-12. It contains failed and blocked attempts that were superseded by
later passes; those entries are evidence of the safety process, **not final
acceptance status**.

The concise, machine-readable final result is
[`x100vi-c-slot-evidence-manifest-2026-09-12.json`](x100vi-c-slot-evidence-manifest-2026-09-12.json).
It is the review entry point: it identifies every final C1–C7 outcome, the
production-UI C4 result, baseline policy, commands/tests, helper identity, and
evidence limitations. This document supplies the detailed supporting
chronology.

The helper reports per-property response/readback results and was used for
immediate, slot-switch, and helper-reconnect checks. Raw helper JSON fixtures
and transaction-level logging were retained outside this repository, so neither
this document nor the manifest claims a repository-held USB packet trace,
firmware version, or byte-level transaction transcript.

## Final acceptance at a glance

| Path | Final outcome | Supporting final section |
| --- | --- | --- |
| Direct helper C1–C7 | **PASS** — every slot passed immediate, alternate-slot, reconnect, and post-rollback checks; C3–C7 use the documented replacement-baseline policy. | [Final helper-hardware status](#final-helper-hardware-status) |
| Production macOS UI → C4 | **PASS** — the real **Send to Dial → C4** action wrote the recipe, helper readbacks passed after a C1 switch and reconnect, and the C4 baseline was restored exactly after reconnect. | [Raw-encoding production UI C4 persistence/rollback](#raw-encoding-production-ui-c4-persistencerollback--2026-09-12) |
| iOS C-slot path | **Out of scope / unproven** — transport remains a stub. | [Evidence manifest](x100vi-c-slot-evidence-manifest-2026-09-12.json) |

Read the sections below **“Superseded historical run chronology”** as a dated
debugging record only. A failed or blocked section does not overturn a final
PASS unless a later section explicitly says it does.

## Final helper-hardware status

| Slot | Baseline ultimately retained | Direct-helper persistence checks | Direct-helper restore/replacement result | Status |
| --- | --- | --- | --- | --- |
| C1 | Original `Dreamy Negative` backup | Immediate, C2-switch, reconnect | Original 26 raw fields + PTP name matched after reconnect | **PASS** |
| C2 | Original `Kodachrome` backup | Immediate, C1-switch, reconnect | Original 26 raw fields + PTP name matched after reconnect | **PASS** |
| C3 | Manual-overwrite state accepted as replacement baseline | Immediate, C1-switch, reconnect | Replacement 26 raw fields + name matched after reconnect | **PASS** |
| C4 | `C4 PTP VERIFY` fixture accepted as replacement baseline | Immediate, C1-switch, reconnect | Replacement 26 raw fields + PTP name matched after reconnect | **PASS** |
| C5 | Intentional complete copy of C4 replacement baseline | Immediate, C1-switch, reconnect | C4-baseline applicable raw fields + name matched after reconnect | **PASS** |
| C6 | Intentional complete copy of C4 replacement baseline | Immediate, C1-switch, reconnect | C4-baseline applicable raw fields + name matched after reconnect | **PASS** |
| C7 | Intentional complete copy of C4 replacement baseline | Immediate, C1-switch, reconnect | C4-baseline applicable raw fields + name matched after reconnect | **PASS** |

“Replacement baseline” is deliberate terminology: initially empty C3–C7
reported raw-zero sentinels that the camera rejected when written back. These
slots cannot be described as restored to their original empty state. C3 was
manually overwritten before its accepted baseline was captured; C4 retained
the valid `C4 PTP VERIFY` fixture; C5–C7 were intentionally initialized from
that C4 baseline. No firmware version was collected in this series.

## Superseded historical run chronology

The sections in this chronology predate the final acceptance above. They are
kept to explain why fixture validation and replacement-baseline policy were
needed. In particular, the initial C1 failure and the blocked C3/C4 empty-slot
restores must not be read as the final C1–C7 outcome.

### Initial C1 attempt — superseded

**Failed safely at C1; C1 was restored exactly.** No write was attempted for
C2–C7. The helper and test harness exited after the emergency restore.

## Environment and helper

- Camera: Fujifilm X100VI (`04cb:0305`), USB PTP Camera.
- Helper binary: freshly built `poc-x100vi-reader/x100vi_helper`.
- SHA-256: `e50ae57b5211f29c74fc27fcc7bc31024e64b6784552c072452fefc4598fde31`.
- Firmware version: unavailable; this run did not invoke any non-C-slot
  property to obtain it.
- The macOS PTP daemon was stopped immediately before every helper connection.
  No FilmKit or browser client was running.

Build command:

```sh
cd poc-x100vi-reader
gcc -O2 -o x100vi_helper x100vi_helper.c \
  -I/opt/homebrew/include -L/opt/homebrew/lib -lusb-1.0
shasum -a 256 x100vi_helper
```

The regression used only `connect`, `disconnect`, `read_preset_slot`, and
`write_preset_slot`. It took a complete 26-property raw readback (including
the PTP name) of C1–C7 before the first write; those rollback fixtures and any
transaction trace remain outside the repository under `/tmp`. They are not
repository evidence and are not reproduced here.

## Slot results

| Slot | Backup | Fixture write / verification | Restore |
| --- | --- | --- | --- |
| C1 | Complete (26 properties) | Failed before fixture readback | Write verified; full post-reconnect raw comparison matched backup |
| C2 | Complete (26 properties) | Not attempted | No change made |
| C3 | Complete (26 properties) | Not attempted | No change made |
| C4 | Complete (26 properties) | Not attempted | No change made |
| C5 | Complete (26 properties) | Not attempted | No change made |
| C6 | Complete (26 properties) | Not attempted | No change made |
| C7 | Complete (26 properties) | Not attempted | No change made |

## C1 failure evidence

The unique fixture selected C1 and attempted its required name, film
simulation, daylight white balance with shifts, dynamic range, grain, color
chrome settings, tones, color, sharpness, high-ISO noise reduction, clarity,
long-exposure NR, and color space.

- `D18C` slot selection and `D18D` name write succeeded.
- `D19C` color temperature returned the expected conditional `0x201C` for
  fixed daylight white balance.
- `D195` grain effect returned an immediate readback mismatch (`-300`).
- Subsequent tone, color, sharpness, clarity, and long-exposure-NR writes
  returned `0x201C` (`8220`) and the helper surfaced the failure.

The fail-safe path immediately wrote C1's saved complete fixture. The restore
reported only the expected conditional warnings for `D193`, `D194`, and
`D19C`; a full C1 raw-property and name comparison after disconnect/reconnect
had zero mismatches.

## Implementation correction made before the run

`x100vi_helper.c` now includes `D1A1` (`high_iso_nr`) in its C-slot write
field list, so the production helper can back up and restore the checklist's
noise-reduction setting. Its `read_preset_slot` JSON closing braces were also
corrected; the original malformed response was discovered during the
pre-write backup pass, before any C-slot content write.

## Follow-up

Do not continue with C2–C7 until the valid grain-effect raw values and the
dependent-setting ordering/eligibility that causes the later `0x201C`
responses are established. The helper correctly reports this physical write
failure rather than claiming a saved preset.

## Follow-up correction — 2026-09-12

The root cause was the fixture's `grain_effect: 0`: C-slot `D195` uses raw
values `1...5` (`1=Off`, `2=Weak Small`, `3=Strong Small`, `4=Weak Large`,
`5=Strong Large`), not the UI/profile-style zero-based value. `D195` accepted
the malformed value but read back a different value, after which the later
writes were no longer reliable.

`write_preset_slot` now:

- rejects invalid grain/effect/dynamic-range/WB encodings before selecting or
  mutating a slot;
- writes `D199` WB mode, then conditional `D19C` color temperature, then
  `D19A`/`D19B` WB shifts (FilmKit's confirmed ordering);
- omits inapplicable mono, color-temperature, and monochrome-color fields
  instead of issuing known-invalid writes.

The helper rebuilt successfully (`sha256
4cd4072562c3cf9da154c6af2c1db8f6e0ee89b8f922917f8b643e8af673caa0`);
the Swift package also built successfully. No live retest was performed in
this follow-up because no X100VI was enumerated over USB (`system_profiler
SPUSBDataType` returned no camera). C1 was therefore not touched and C2–C7
remain untouched.

## C1 retest — 2026-09-12

**Overall result: FAIL-SAFE; C1 restoration verification: PASS.** The camera
enumerated as `USB PTP Camera`; the helper was the only client after stopping
`ptpcamerad`. C2 was read only for the required slot-switch check and was
never written. C3–C7 were untouched.

Fixture (`C1 PTP VERIFY`) used valid raw preset values: grain `4` (Weak Large),
non-monochrome film simulation `11`, daylight WB `4`, WB shifts `-2/+3`, and
non-default effects/tones. It passed all fixture checks:

- immediate C1 readback: pass;
- read C2 then return to C1: pass;
- helper disconnect/reconnect then C1 readback: pass.

The first rollback request exposed a separate helper boundary bug: signed
backup fields are read as their unsigned 16-bit raw bits (for example
`0xFFF9`), but `write_preset_slot` initially accepted only signed decimal
JSON. Preflight rejected the rollback before it selected or wrote C1. The
test stopped immediately; no C2–C7 write was attempted.

The original `Dreamy Negative` C1 configuration was then restored with the
correct signed conversion and checked after a fresh reconnect. All 26 raw
properties and the PTP name matched the saved baseline (including the
run-time baseline color-temperature value `5600`); all property reads returned
`rc: 0`.

The helper now accepts either signed decimal or `0...65535` raw-bit JSON for
signed C-slot fields, so a `read_preset_slot` raw backup can be submitted
unchanged to `write_preset_slot`. This source correction is build-verified,
but must receive one clean C1-only end-to-end rerun before any C2–C7 test.

## Clean C1 regression — 2026-09-12

**PASS.** The helper was rebuilt from the signed-raw correction
(`sha256 8eaf475a6fc1fcbb4ba7387886a2fb1781e5aec56379723b6c9d4926fa7f9bef`)
and the X100VI was confirmed as `USB PTP Camera` before use.

- C1 (`Dreamy Negative`) raw backup: complete, 26 properties plus PTP name.
- Valid non-default fixture write: helper response and per-field verification
  passed.
- Immediate C1 readback: no mismatches.
- C2 read only, then return to C1: no C1 mismatches; C2 was not written.
- Full helper disconnect/reconnect, then C1 readback: no mismatches.
- Restore from the unmodified raw backup: helper verification passed.
- Full reconnect after restore: all 26 raw properties and the PTP name
  matched exactly.

C3–C7 were not accessed. The helper exited cleanly and no FilmKit/helper
client remained running. This clears the C1 gate: it is safe to begin the
already-authorized C2–C7 regression, using the same backup/fixture/restore
procedure one slot at a time.

## C2–C7 regression — 2026-09-12

**Stopped at C3; do not continue.** The first multi-slot runner was terminated
while blocked on its unread diagnostic pipe during C2's backup read; a
subsequent read-only check confirmed C2 had not yet been written. The runner
was then corrected to discard helper diagnostics and execute one helper
process per slot.

| Slot | Backup | Fixture persistence | Restore after reconnect | Result |
| --- | --- | --- | --- | --- |
| C2 (`Kodachrome`) | 26 raw properties + name | Immediate, C1-switch, and reconnect checks passed | Exact 26-property + name match | **PASS** |
| C3 (empty name/raw-zero slot) | 26 raw properties + name | Immediate, C1-switch, and reconnect checks passed | **Blocked** | **FAIL** |
| C4–C7 | Not accessed | Not attempted | Not needed | Untouched |

C3's original empty-slot backup contains camera-read raw zero sentinels
(including `D195=0`). The camera accepts those values as readback but rejects
attempts to write them back with `0x201C InvalidDevicePropValue` (observed for
`D18E`, `D18F`, `D190`, `D192`, `D195`–`D199`, `D1A3`, and `D1A4`). The
fixture therefore remains in C3. The temporary change that admitted zero
values at helper preflight was reverted because it cannot produce a physical
restore.

Recovery requires a camera-supported way to clear/reset an empty C slot
(likely the camera UI or an as-yet-unidentified PTP operation). C4–C7 must
not be tested until C3 is manually restored and that recovery method can be
verified. C1 was only read for switch checks and was not written in this run.

## C3 reset verification retry — 2026-09-12

**Not ready; no write performed.** After the user reported a manual reset,
the helper completed a read-only C3 scan (all 26 reads `rc: 0`). C3 still held
the test fixture rather than an empty slot: DR `200`, film simulation `11`,
grain `4`, Color Chrome `2`, FX Blue `3`, Smooth Skin `2`, daylight WB `4`,
and its fixture name/settings. Therefore the manual clear was not observable
over PTP, or was applied to a different camera state. C3 was not modified in
this retry; C4–C7 remain untouched.

## C3–C7 continuation — 2026-09-12

The next manual C3 overwrite was observable: the old C3 fixture was gone and
the current camera state was accepted as the new baseline. The helper also
admitted the newly observed valid WB raw value `0x8020` so that baseline could
be restored losslessly.

| Slot | Backup | Fixture persistence | Restore after reconnect | Result |
| --- | --- | --- | --- | --- |
| C3 | 26 raw properties + current name | Immediate, C1-switch, and reconnect checks passed | Exact 26-property + name match | **PASS** |
| C4 (empty name/raw-zero slot) | 26 raw properties + name | Immediate, C1-switch, and reconnect checks passed | **Blocked** | **FAIL** |
| C5–C7 | Not accessed | Not attempted | Not needed | Untouched |

C4 has the same camera-empty-slot condition previously observed for C3:
`grain_effect=0` in the raw backup is not a writable preset value. Restore
preflight rejected it before selecting or writing C4, leaving the fixture in
C4. C5–C7 were not accessed. Manual overwrite/reset of C4 must be verified
over PTP before continuing; the same manual-baseline procedure can then be
used for each remaining empty slot.

## C4 persisted-baseline regression — 2026-09-12

**PASS.** The previous valid C4 fixture (`C4 PTP VERIFY`) was intentionally
treated as C4's new baseline. Its complete 26-property raw backup and name
were captured before writing a distinct fixture (`C4 PTP VERIFY B`, DR400,
film simulation 20, grain 5, and different effects/tones).

- Fixture write and helper verification: pass.
- Immediate C4 readback: no mismatches.
- Read-only C1 switch, then return to C4: no mismatches.
- Full helper disconnect/reconnect, then C4 readback: no mismatches.
- Restore to `C4 PTP VERIFY`, followed by reconnect: exact 26-property and
  PTP-name match.

C5–C7 were not accessed. The helper exited cleanly and no browser/helper
client remained running.

## C5–C7 permanent C4-baseline policy — 2026-09-12

**PASS.** Per the selected permanent-baseline policy, each previously empty
target was intentionally replaced with a fresh complete read of C4
(`C4 PTP VERIFY`, 26 raw properties plus PTP name). Empty-slot sentinel values
were not retained or restored.

For each target, the C4 baseline copy was verified immediately, after a
read-only C1 switch, and after a full helper reconnect. A distinct valid
fixture was then written and passed the same immediate/switch/reconnect
checks. Finally, the C4 baseline was restored and verified after reconnect
against every applicable raw field and the PTP name.

| Slot | C4 baseline copy | Distinct fixture persistence | Restored C4 baseline | Result |
| --- | --- | --- | --- | --- |
| C5 | Immediate/switch/reconnect pass | Immediate/switch/reconnect pass | Applicable raw fields + name match after reconnect | **PASS** |
| C6 | Immediate/switch/reconnect pass | Immediate/switch/reconnect pass | Applicable raw fields + name match after reconnect | **PASS** |
| C7 | Immediate/switch/reconnect pass | Immediate/switch/reconnect pass | Applicable raw fields + name match after reconnect | **PASS** |

Only C1 was read for the alternate-slot switch checks; C2–C4 were not
modified. Each helper instance exited cleanly, and no helper or browser client
remained running.

## macOS production UI-path C4 validation attempt — 2026-09-12

**Blocked safely; no camera write occurred.** Before launching or interacting
with the app for this run, `system_profiler SPUSBDataType` reported no
enumerated X100VI / USB PTP Camera. Consequently, no C4 baseline capture,
application connection, recipe selection, `Send to Dial` action, helper
readback, reconnect persistence check, or restoration was attempted.

This does not alter the helper-hardware C4 PASS above: it establishes only that
the **pending macOS UI-driven C4 test** made no change. There is no recorded
app-originated selector/name/property transaction, no app-originated helper
readback, and no app-originated reconnect persistence result. C1–C7,
including C4, remain unmodified by this attempt.

### Final acceptance checklist: pending macOS UI-driven C4 test

Run only when the camera is available, using C4's current replacement baseline
(`C4 PTP VERIFY`) as the rollback target:

1. Capture C4's pre-write 26 raw properties and PTP name through the helper;
   retain the UI action time and the helper request/response log.
2. Connect from the macOS app, select a distinct recipe, and use **Send to
   Dial → C4**. Do not substitute a direct helper write.
3. Establish that the UI path issued the expected helper write: successful
   C4 selector, name, and each requested applicable property response; record
   conditional warnings separately from failures.
4. Read C4 with the helper immediately after the UI action and compare the
   requested applicable fields and name to the recipe. The app success message
   alone is insufficient.
5. Read a different slot (C1 is sufficient), return to C4, and repeat the
   helper comparison.
6. Disconnect/reconnect the helper/session, then repeat the C4 comparison.
7. Restore the captured C4 replacement baseline with the helper and require a
   post-reconnect exact comparison of its applicable raw fields and PTP name.

Do not claim UI-path acceptance without all seven artifacts. A raw USB capture
or firmware version may be added if available, but neither is present in the
current evidence set and neither is a substitute for the required readbacks.

## Re-requested macOS production UI-path C4 validation — 2026-09-12

**Blocked safely before launch/write.** A fresh preflight
`system_profiler SPUSBDataType` again contained no X100VI / USB PTP Camera
entry, so the camera was not available to this Mac despite the readiness
report. The current Debug `FujiRecipesMac` target built successfully
(`** BUILD SUCCEEDED **`), but it was not launched because connecting or
driving its Camera Hub UI without an enumerated camera cannot validate the
physical path safely.

No helper was started; therefore no 26-property/name C4 baseline was captured,
no recipe was selected, no `Send to Dial` action occurred, and no C4
readback/reconnect/restore sequence ran. Firmware was unavailable because the
camera never enumerated. The preflight found no app/helper/FilmKit client, and
no client was left running. C1–C7 remain unmodified by this attempt.

## CAMERA_READY macOS UI-path C4 validation — 2026-09-12

**Blocked safely after Camera Hub connection; no fixture write occurred.**
`ioreg` confirmed `USB PTP Camera` before the run. The current Debug
`FujiRecipesMac` app was launched, its Camera Hardware Hub was opened using
the app's Command-3 navigation, and its actual Connect Camera control was
pressed through macOS accessibility. The packaged `x100vi_helper` spawned,
confirming the production app/backend path was entered.

- C4 baseline captured beforehand: 26 raw properties plus PTP name
  `C4 PTP VERIFY` (`/tmp/x100vi-c4-ui-baseline-2026-09-12.json`).
- Firmware: unavailable. The read-only `0xD186` attempt returned helper
  libusb error `-7`; it made no slot change.
- The Camera Hub did not return a connected/error state after more than
  90 seconds; its accessibility query remained blocked. The app and packaged
  helper were stopped rather than attempting an unverified UI write.
- The delayed accessibility query subsequently completed and provides the
  decisive app-side result: **Link Offline** with Connection Diagnostic
  **`Operation timed out after 15s`**. This confirms that the production
  connection failed before the recipe/Send-to-Dial UI could be reached.
- No recipe selection, **Send to Dial → C4**, C4 fixture/readback,
  alternate-slot check, persistence check, or restore was performed.
- After stopping the app, a fresh standalone helper connection read C4 only:
  all 26 properties had `rc: 0` and the exact raw/name comparison against the
  pre-run baseline had zero mismatches.

No slot was written by this attempt. The app's normal connect path may have
started its read-only C-state synchronization before it stalled; no other slot
was explicitly accessed by the validation harness. All app/helper processes
were stopped at the end.

## Final production UI C4 validation — 2026-09-12

**Blocked safely at the platform slot-picker; no C-slot write occurred.**
This run confirmed the Camera Hub connection fix, but the current macOS
confirmation-dialog presentation exposed only C1, C2, C3, and an **OK** button:
C4–C7 had no selectable UI action. No direct-helper fixture write was
substituted.

- USB preflight: `ioreg` reported `USB PTP Camera`.
- App: freshly built Debug `FujiRecipesMac` (`** BUILD SUCCEEDED **`).
- Bundled production helper SHA-256:
  `0a005901c5fe71714addba7ba87280a85c011a72302d2faeacb7f017356caa68`.
- Pre-write C4 baseline: complete 26 raw properties plus PTP name
  `C4 PTP VERIFY` (`/tmp/x100vi-c4-final-ui-baseline-2026-09-12.json`).
- Firmware: unavailable; read-only `0xD186` returned helper/libusb
  `error_code: -7`.
- Production Camera Hub: **Camera Online**, **USB PTP • Ready**, **LINK
  ACTIVE**, and **7 / 7 SYNCHRONIZED**.
- Production recipe UI: expanded the known bundled recipe
  `Universal Negative - 14 Fujifilm X100VI (X-Trans V) Film Simulation Recipes
  (Yes, 14!!)` and pressed its actual **Send to Dial (C1–C7)** action.
  Its sheet explicitly said *Load into Camera Custom Slot*, but exposed only
  `C1 — Dreamy Negative`, `C2 — Kodachrome`, `C3 — C3`, and `OK`; the latter
  was dismissed. C1–C3 were not pressed.
- A fresh helper reconnect then read C4 only: 26 properties, all `rc: 0`,
  zero raw/name mismatches versus the captured baseline.

Because C4 could not be selected through the production UI, no UI success
message, fixture readback, alternate-slot switch, reconnect persistence, or
restore could be performed. The app and helper were stopped; no slot was
written by this attempt.

## Explicit C1–C7 picker production UI retry — 2026-09-12

**Blocked safely: the picker sheet rendered blank.** The X100VI again
enumerated as `USB PTP Camera`. The fresh Debug app build succeeded; its
bundled helper SHA-256 remained
`0a005901c5fe71714addba7ba87280a85c011a72302d2faeacb7f017356caa68`.

- C4 baseline captured before the app session: 26 raw properties plus
  `C4 PTP VERIFY`.
- The real Camera Hub Connect control reached **Camera Online / LINK ACTIVE**.
- A recipe card was expanded and the visible production **Send to Dial
  (C1–C7)** control was activated. The app created an `AXSheet`, but it
  rendered as an empty 100 × 80 sheet with zero accessibility descendants:
  no C1–C7 choices, Cancel button, success prompt, or C4 action was present.
- Escape dismissed the blank sheet; no slot-picker action was invoked.
- A fresh post-app helper connection read C4 only: 26 properties, every
  `rc: 0`, and zero raw/name mismatches versus the captured baseline.

No C-slot write, alternate-slot check, persistence check, or baseline restore
was possible because the physical C4 write never began. The app and helper
were stopped. The focused screenshot evidence was captured locally at
`/tmp/fuji-ui-validation-picker-active.png`.

## `sheet(item:)` picker production UI C4 attempt — 2026-09-12

**UI path reached C4, but the packaged helper exited before a physical write
result.** The X100VI enumerated; a fresh Debug build succeeded; C4's complete
26-property/name baseline (`C4 PTP VERIFY`) was captured before connecting.
The real Camera Hub again reported **Camera Online**.

- The actual expanded **Send to Dial (C1–C7)** control opened the repaired
  picker. Its accessibility tree exposed all seven choices; C4's help text
  explicitly said it would write and verify the selected recipe on physical
  slot C4.
- The C4 picker button was clicked through the production UI. The app's result
  alert was: `Camera slot C4 was not changed: Invalid response: Helper closed
  stdout`.
- The app and packaged helper were stopped immediately. A fresh standalone
  helper connection then read **C4 only**: all 26 properties returned `rc: 0`
  and its complete raw/name comparison to the pre-write baseline had zero
  mismatches.

Thus no physical C4 change occurred, so no alternate-slot/reconnect
persistence check or baseline restore was warranted. No other C-slot was
written and no client remained running.

## Single stderr-diagnostic production UI C4 attempt — 2026-09-12

**Failed safely; exactly one C4 UI write was attempted and C4 is unchanged.**
The X100VI enumerated, C4's 26-property baseline was captured, the Debug app
connected through Camera Hub, and the repaired C1–C7 picker selected C4. No
second write attempt was made.

The app's user-visible diagnostic was captured verbatim:

```text
Camera slot C4 was not changed: Invalid response: Helper closed stdout (signal 5): value=0x00000002 (payloadLen=2)
```

The captured helper stderr in the same alert ends with this verbatim write
boundary (preceded by successful `0x1015` property reads, each with DATA
`len=14` and RESPONSE `0x2001`):

```text
[DEBUG] property value=0x00000007 (payloadLen=2)
[DEBUG] ptp_send: code=0x1016 len=16 transferred=16 rc=0
[DEBUG] write_prop CMD: rc=0
[DEBUG] write_prop DATA: totalLen=14 transId=205
```

After stopping the app/helper, one fresh standalone helper connection read C4
only: 26 properties, all `rc: 0`, with zero raw/name mismatches versus the
baseline. Therefore no restore, alternate-slot switch, or persistence sequence
was warranted. No other slot was written and all clients were stopped.

## Exact-size DATA-send production UI C4 attempt — 2026-09-12

**Failed safely before C4 mutation.** The X100VI enumerated, the current Debug
app built successfully, and C4's full 26-property baseline was captured before
the real Camera Hub session and C4 picker action. The user-visible production
result was:

```text
Camera slot C4 was not changed: Failed to write property 0xd18c: 0xD18D: 8220
```

The app/helper were stopped without retry. A fresh standalone helper read C4
only: all 26 properties returned `rc: 0` and the raw/name comparison had zero
mismatches against the baseline. No restore, alternate-slot switch, or
reconnect persistence check was warranted; no other slot was written.

## Safe-label production UI C4 attempt and rollback — 2026-09-12

**Partial C4 physical write was detected and restored exactly.** The X100VI
enumerated; C4's complete 26-property/name baseline was captured; Camera Hub
connected; and exactly one C4 Send-to-Dial action was issued. The recipe
search field was not exposed to macOS accessibility (`fields=0`), so the
visible bundled recipe `Universal Negative - 14…` was used rather than
`PRO Negative 160C`.

- The failed UI result was:

  ```text
  Camera slot C4 was not changed: Failed to write property 0xd18c: 0xD19E: 8220, 0xD1A0: 8220
  ```

- Contrary to the message, immediate post-failure C4 readback showed a partial
  physical mutation: PTP name `Universal Negat` (15 ASCII characters, safely
  bounded), DR400, Strong Small grain, changed WB shifts, highlight/color,
  and high-ISO NR. This run therefore did not claim write success or run the
  alternate-slot/persistence checks.
- The safe helper rollback wrote the saved C4 baseline, then disconnected and
  reconnected. Its post-reconnect C4 comparison passed: 26 properties, all
  `rc: 0`, and zero raw/name mismatches to baseline.

No other slot was written; app/helper clients were stopped. This establishes
that the safe-label change avoids the former SIGTRAP, but the recipe's
inapplicable `D19E`/`D1A0` writes can still yield a partial C4 update before
the UI reports failure.

## Raw-encoding production UI C4 persistence/rollback — 2026-09-12

**Physical write, persistence, and exact rollback passed.** The X100VI
enumerated, C4's full 26-property baseline was captured, the current Debug
app connected through Camera Hub, and the real Send-to-Dial C4 action reported:

```text
"Universal Negative - 14 Fujifilm X100VI (X-Trans V) Film Simulation Recipes (Yes, 14!!)" was verified on camera slot C4.
```

The immediate helper readback reported the safe 15-character PTP name
`Universal Negat`. A read-only C1 switch followed by C4 readback produced zero
mismatches, and a full helper disconnect/reconnect produced zero C4
mismatches, confirming physical persistence. The saved C4 baseline was then
restored through the helper and verified after another reconnect: all 26
properties returned `rc: 0` with an exact raw/name match.

The validation harness's hand-derived raw expectations differed only at
`D197` (expected `3`, observed `2`) and `D1A1` (expected `0`, observed
`32768`). The hand-derived vector was wrong: the selected normalized recipe's
authoritative `presetSettings` contain `colorChromeFxBlue: 2` and
`highIsoNr: 32768`. `RecipeLoader` decodes those raw values to UI `.weak` and
`-4`; `CSlotPresetEncoder` then correctly re-encodes them as `D197 = 2` and
`D1A1 = 0x8000` (`32768`).

This agrees with FilmKit's verified mapping: C-slot effects are one-indexed
(`Off=1`, `Weak=2`, `Strong=3`), and High ISO NR maps `-4` to `0x8000`.
The source article's display-text fields say `Strong` / `-4`, but this
multi-recipe article's display text is not the C-slot payload; the normalized
`presetSettings` are. The core regression test now round-trips that exact
source record through `RecipeLoader` and `CSlotPresetEncoder`. The helper
regression test serializes the resulting `PTPClientPresetData` through the
same `write_preset_slot` JSON builder used in production and asserts
`color_chrome_fx_blue: 2` and `high_iso_nr: 32768`. This replaces
hand-derived request expectations with the encoder object that the helper
actually receives. No other slot was written; all clients were stopped.

## Packaged-helper termination diagnosis — 2026-09-12

The UI-path failure is confirmed to be a child-process termination, not a
reported PTP write rejection. The original macOS client inherited helper stderr
to the app process and discarded the child termination reason, so the only
available error was `Helper closed stdout`.

- The packaged `Resources/x100vi_helper` and development helper are both
  arm64 Mach-O executables with identical libusb linkage. Their executable
  contents matched; their SHA-256 values differ because of the Mach-O UUID and
  ad-hoc code-signature data.
- A rebuilt helper accepted line-delimited JSON containing the write command,
  signed values, and an escaped name without terminating. The safe no-camera
  path returned structured JSON, so JSON framing alone is not sufficient to
  reproduce the termination.
- The Swift client now drains stderr continuously, retains its final 4 KiB,
  and reports the helper's exit/signal status plus stderr tail when stdout
  closes. This prevents a verbose helper stderr pipe from stalling a write and
  makes the next failure diagnosable without guessing.

No C-slot write was performed for this diagnosis. The physical root cause
(exit status and final libusb/PTP operation) remains unproven until the
instrumented packaged app executes one user-authorized write. The next
hardware step is: capture C4's complete baseline, execute exactly one
user-authorized C4 UI write, and stop at the first result. If it fails, retain
the new termination/stderr diagnostic and read C4 only to confirm whether
rollback is required.
