# X100VI C-slot creation behavior

## Evidence

Hardware regression testing established that an unconfigured C slot is readable
as an empty name plus successful raw-zero property values. Those values are a
camera sentinel, not a lossless writable preset: attempting to restore that
baseline is rejected for several properties with `0x201C
InvalidDevicePropValue`.

The same testing established the intended creation path: C4 began in this
raw-zero state, accepted a valid complete fixture, and retained that fixture
across slot switches and reconnect. The only failed operation was attempting
to return C4 to the non-writable raw-zero sentinel.

## Product contract

- A successful read reports `is_empty_slot: true` only when the helper reads
  an empty preset name and zero for every numeric C-slot property.
- Before writing, the helper reads the selected slot using that same rule.
  Failed baseline detection stops the operation before a profile mutation.
- A valid profile can be written to an empty slot. Success still requires
  strict readback verification of every requested field and name.
- A verified write from that baseline reports `created_from_empty: true`;
  otherwise it is an update (`false`).
- The raw-zero state is not a profile backup and must not be offered as a
  rollback target. A later request to write its invalid zeros is correctly a
  rejected write, without invalidating the earlier successful creation.

## Code-path status and UI boundary

`PTPClientPresetData.isEmptySlot` carries the explicit read result into the
loadout store, so synced C-slots can be shown as **New profile** rather than
an ambiguous empty local draft. `PTPPresetSlotWriteResult.createdFromEmpty`
is returned from `CameraManager.importRecipeToCState` and `writeLoadout`,
allowing a caller that performs the physical write to say **Created** versus
**Updated**. These are code-level behaviors, not UI-path hardware evidence.

The macOS **Send to Dial** control uses an explicit in-app sheet with seven
choices, C1 through C7. This avoids the native macOS confirmation-dialog
presentation that exposed only C1–C3 in production. While connected, a choice
calls `CameraManager.importRecipeToCState`; the local loadout changes only
after that write returns successfully. While disconnected, the same choice is
explicitly labeled as a local save and updates only `UserDefaults`.

The connected app action is routed to the verified write implementation but
still requires its own hardware acceptance evidence. Direct helper testing
shows that a valid profile can create C4 and persist it, but it does not prove
the UI action's connection, request, readback, or reconnect behavior. A
physical-write UI must await the returned result, report success only after
verification, and should not expose a “restore empty baseline” action. It
should also make clear that a create cannot clear the slot back to the
raw-zero sentinel; that requires a camera-supported reset flow.

### macOS UI acceptance (no write required for sheet coverage)

1. Launch the macOS app with no camera connected.
2. In **Recipes**, open **Send to Dial** for any recipe.
3. Confirm the sheet visibly contains seven selectable controls, C1–C7,
   including C4–C7; each must say **Save locally**.
4. Select C4 and confirm the result says it was saved locally and the
   camera was not changed.
5. Reopen the sheet and confirm C4 displays the local recipe label.

Run a physical-write acceptance only under the separate hardware regression
checklist, including immediate, slot-switch, and reconnect readback evidence.
