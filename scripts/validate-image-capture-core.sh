#!/bin/zsh
set -euo pipefail

slot="${1:-4}"
repeat_count="${2:-20}"

if ! system_profiler SPUSBDataType | rg -qi 'fuji|x100|04cb'; then
    print -u2 "X100VI is not currently enumerated over USB."
    exit 2
fi

print "Running ImageCaptureCore USB soak: slot=C${slot}, cycles=${repeat_count}"
swift run --package-path FujiPTPClient ImageCaptureCoreProbe "$slot" "$repeat_count"
