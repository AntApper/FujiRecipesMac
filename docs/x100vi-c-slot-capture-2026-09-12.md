# X100VI C1 preset persistence capture report — 2026-09-12

> Evidence limitation: this report records the capture operator's observations,
> but the underlying instrumented-transport output is not in the repository.
> It must not be treated as a repository-verifiable raw USB/PTP trace or as
> firmware evidence. The direct-helper regression record is the authoritative
> repository documentation for the C1–C7 hardware results.

## Result

An X100VI persisted a deliberately distinctive C1 preset after a FilmKit WebUSB
write. Persistence was verified by switching away from C1, switching back, then
closing the PTP session, reconnecting the camera, and reading C1 again.

The original C1 preset, `Dreamy Negative`, was restored and verified after the
capture.

## Capture environment

- Camera: Fujifilm X100VI, USB PTP Camera (`04cb:0305`)
- Host: macOS, Microsoft Edge WebUSB
- Capture method: instrumented FilmKit PTP transport
- Why not Wireshark: this macOS installation exposes no USB/XHC capture
  interface to `tshark`, so a passive USB capture would contain no PTP traffic.
- Raw transaction logs were retained outside the repository capture report.

## Reported write sequence

The capture report says each property write used a standard PTP
`SetDevicePropValue` transaction:

1. Send a `COMMAND` container (`type=0x0001`, `code=0x1016`) with the property
   code as its only parameter.
2. Send a separate `DATA` container (`type=0x0002`, `code=0x1016`) with the
   same transaction ID and the raw value payload. The data container has no
   parameters.
3. Require `RESPONSE` (`type=0x0003`, `code=0x2001`) before continuing.

The reported C1 save began:

| Transaction | Property | Payload | Response |
| --- | --- | --- | --- |
| `0xC2` | `0xD18C` preset selector | `01 00` | `0x2001` |
| `0xC3` | `0xD18D` preset name | PTP UCS-2 string | `0x2001` |
| `0xC4…0xDB` | `0xD18E…0xD1A5` preset settings | 16-bit raw values | per-property |

The report describes a 100 ms delay after selecting `D18C` and no additional
vendor operation or separate "commit" command before readback. Because the
raw transaction records are unavailable here, this is not evidence that rules
out a firmware-specific commit behavior or establishes byte-level payload
details beyond the report.

## Reported protocol observations

- The report says `D18C` selected C1 using the **two-byte** little-endian
  payload `01 00`.
- The report says the camera accepted the name as a standard PTP string:
  length byte, UTF-16LE characters, terminating `00 00`.
- The report says the following properties returned `0x201C
  InvalidDevicePropValue` when they
  were inapplicable to the selected recipe: `D193` (mono warm/cool), `D194`
  (mono magenta/green), and `D19C` (color temperature while a fixed WB mode was
  selected). These are expected per-field rejections, not a slot-write failure.
- The reported C1 persistence outcome is consistent with `D18C` +
  `D18D…D1A5` persisting a C1 preset through a PTP reconnect. It is not,
  without the raw capture, proof of the exact on-wire sequence.

## Application implementation requirements

The direct helper now uses the following corresponding implementation choices;
the historical capture report alone is not their byte-level proof:

1. Use `write_prop_u16` for the C-slot selector and all preset field payloads.
2. Encode `D18D` with a PTP string payload.
3. Select the slot, wait 100 ms, write the name, then write every applicable
   field from `PTPClientPresetData`.
4. Treat each `0x2001` response as required; surface `0x201C` for conditional
   fields as a warning rather than declaring the entire operation successful.
5. Re-read the selected slot after the write and compare the requested,
   applicable fields before the Swift UI reports success.

Before enabling physical writes in the UI, repeat the same write/readback/
reconnect check independently for C1 through C7 and record the firmware
version used.
