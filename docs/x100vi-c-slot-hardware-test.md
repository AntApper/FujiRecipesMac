# X100VI C1–C7 hardware regression checklist

Run this checklist only with a fully charged X100VI in USB RAW CONV. /
BACKUP RESTORE mode. Record the firmware version when it is available and keep
a copy of each writable baseline before overwriting it. An empty C-slot's
raw-zero sentinel is not a writable rollback fixture; establish and document
an intentional replacement baseline before continuing with that slot.

## Per-slot test

Repeat the following for C1 through C7:

1. Connect through the direct raw-PTP helper. Confirm the camera model and that the
   helper owns the USB interface.
2. Read the target slot and save the returned name and raw property values as
   the rollback fixture.
3. Run the app's `CSlotPresetEncoder` in test/log-only mode and retain its
   complete raw payload list. Confirm that tones/clarity are in signed tenths,
   High ISO NR is one of the verified Fuji lookup values, and that conditional
   Color Temperature/monochrome/color fields are absent when inapplicable.
4. Write a unique name, film simulation, white-balance mode and shifts,
   dynamic range, grain, color chrome, highlight, shadow, color, sharpness,
   noise reduction, and clarity values.
5. Require a successful PTP response for `D18C`, `D18D`, and every applicable
   property write. Record `0x201C` only for conditionally invalid settings.
6. Read the selected slot immediately and compare every requested applicable
   setting to the requested value.
7. Select a different slot, return to the target slot, and repeat the
   readback comparison.
8. Close the PTP session, release the USB interface, reconnect, and repeat the
   readback comparison.
9. Restore the saved original fixture and repeat the reconnect readback check.

## Pass criteria

- A unique slot name and all applicable requested values survive a full PTP
  reconnect.
- Changing one slot does not change the saved values in any other slot.
- A failed command is surfaced to the caller; the UI never reports a physical
  save as successful based only on local `UserDefaults`.
- The rollback fixture restores the exact original slot name and applicable
  values, or—when an empty sentinel was intentionally replaced—the documented
  replacement baseline.

## Capture evidence

For any failure, retain the helper JSON request/response log and a PTP trace
with transaction IDs, command/data containers, response codes, and the
post-reconnect readback. The helper error must identify the property, requested
raw 16-bit payload, and PTP response code. Do not overwrite another slot while
investigating.

This checklist validates the helper path only. A macOS UI acceptance run must
also prove that the UI action initiated the helper transaction and must retain
its immediate, slot-switch, and reconnect helper readbacks; do not infer that
evidence from a direct helper pass.
