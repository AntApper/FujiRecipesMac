#!/bin/zsh
set -euo pipefail

slot="${1:-4}"
repeat_count="${2:-20}"

if system_profiler SPUSBDataType 2>/dev/null | grep -qiE 'fuji|x100|04cb'; then
    :
elif ioreg -p IOUSB -l 2>/dev/null | grep -q "USB PTP Camera"; then
    :
else
    print -u2 "X100VI is not currently enumerated over USB."
    exit 2
fi

print "Running ImageCaptureCore USB soak: slot=C${slot}, cycles=${repeat_count}"
swift run --package-path FujiPTPClient ImageCaptureCoreProbe "$slot" "$repeat_count"
