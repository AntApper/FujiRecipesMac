# Camera Connection Guide for macOS

## Supported workflow and evidence boundary

The documented macOS camera workflow is for the Fujifilm X100VI and its C1–C7
custom slots. Set the camera to **USB RAW CONV./BACKUP RESTORE**, connect with
a data-capable USB-C cable, and use **Connect Camera** in FujiRecipes. The app
defaults to `ImageCaptureCorePTPClient`, which uses the ImageCaptureCore camera
session and PTP passthrough APIs. It does not directly claim the USB interface
with libusb.

The [2026-09-29 native hardware checks](x100vi-imagecapturecore-hardware-checks-2026-09-29.md)
record all-seven-slot reads and comparisons, configured C4 write/readback and
restoration through a real manager diagnostic, and packaged-app connection,
unplug detection, absent-device timeout, and reconnect. This bounded result
applies to the documented uncommitted working tree and arm64 environment;
native GUI camera writes and the other listed limits remain untested.

Earlier C1–C7 persistence and rollback checks used the legacy helper on
2026-09-12. A production macOS UI C4 write
was also recorded for that helper path. See the [evidence manifest](x100vi-c-slot-evidence-manifest-2026-09-12.json)
and its [detailed chronology](x100vi-c-slot-hardware-regression-2026-09-12.md)
for that separate historical scope. The retained helper record
does not identify the tested repository revision or macOS version, and the
camera firmware was unavailable.

## Connect

1. Turn on the X100VI.
2. Set **SET-UP → CONNECTION SETTING → CONNECTION MODE** to **USB RAW
   CONV./BACKUP RESTORE**.
3. Connect the camera directly to the Mac with a USB-C data cable.
4. Open FujiRecipes and choose **Connect Camera** from the Camera & Staging
   view.
5. Confirm the app reports a connected camera before reading or writing a
   slot.

Before replacing a slot, capture its current values and confirm any rollback
values can be written by the camera. An empty raw-zero slot can use sentinel
values that are not valid rollback settings. Write through the C-slot UI and
require a complete readback comparison before treating the requested values as
verified.

## Troubleshooting

### Camera not found

- Check that the camera is powered on and set to **USB RAW CONV./BACKUP
  RESTORE**.
- Try a known data cable and a direct Mac port.
- Disconnect and reconnect the cable, then retry.
- Quit Photos, Image Capture, or other camera applications if they have opened
  the device. Do not force-terminate `ptpcamerad`.

### Connection fails or times out

The default ImageCaptureCore path asks macOS to manage the camera session. If
it cannot open the device, disconnect and reconnect the camera and retry once.
In the bounded native run, the running app detected unplug and an absent-device
retry timed out cleanly after 15 seconds. The first cable replug did not
enumerate at the OS level. After a requested camera off/on, the X100VI
enumerated and the same app reconnected with all seven slots synced, without
relaunch. This establishes recovery after USB re-enumeration; independently
verified power-cycle persistence and unplug during a write remain untested.

For diagnostics only, `FUJI_RECIPES_TRANSPORT=helper` selects the legacy
raw-libusb helper. That helper can compete with macOS's `ptpcamerad` for USB
interface ownership. Close other camera applications and reconnect before
trying it. Do not stop the macOS PTP service as a workaround. The helper is not
the default transport.

## Preset-read ImageCaptureCore probe

With the X100VI connected, the PTP package includes a C4 preset-read probe:

```bash
swift run --package-path FujiPTPClient ImageCaptureCoreProbe 4
```

To repeat the read/close session, pass a count:

```bash
swift run --package-path FujiPTPClient ImageCaptureCoreProbe 4 20
```

The guarded repository script first confirms that the X100VI is enumerated:

```bash
scripts/validate-image-capture-core.sh 4 20
```

These commands leave recipe property values untouched, but reading a slot
writes the camera's C-slot selector. Before selecting the target, the probe
requires and reports a known original selector from C1 through C7. Each
successful iteration requires `read_verification=verified` and
`selector_restoration=verified`: the original selector is restored and read
back before disconnecting. Recovery is also attempted after recoverable
errors or task cancellation. If restoration cannot be verified, the probe
fails and reports `RECOVERY_REQUIRED` with the original selector. Unplugging
the camera or terminating the process can prevent recovery; retain the
reported original selector for recovery after reconnecting.

These checks do not independently confirm native session-close completion.
The dated native record includes three repository-probe reads, a temporary
configured C4 sharpness change and restoration, and exact all-seven-slot
comparison afterward. Wider acceptance still requires the untested cases in
that record. Future evidence should identify the working tree or tested
commit, source hashes, environment, and exact physical operations performed.

## Experimental RAF conversion

RAF/RAW conversion is experimental and unsupported for a release. The active
default transport does not implement conversion. Do not use it as a supported
camera workflow or claim conversion/JPEG retrieval based on the interface.
