#!/bin/bash
# Test script for Fuji vendor commands (RAF loading)
# Usage: ./test_vendor.sh [path_to_raf_file]
#
# Camera must be in USB RAW CONVERSION / USB TETHER SHOOTING mode
# (Menu → Setup → USB Connection → USB RAW Conversion or USB Tether Shooting)

HELPER="./x100vi_helper"
RAF_FILE="${1:-}"

if [ ! -f "$HELPER" ]; then
    echo "Building x100vi_helper..."
    gcc -O2 -o $HELPER x100vi_helper.c -I/opt/homebrew/include -L/opt/homebrew/lib -lusb-1.0
fi

run_cmd() {
    local id=$1
    shift
    echo "{\"id\":\"$id\",\"$*\"}" | $HELPER
    sleep 0.2
}

echo "=== Fuji X100VI Vendor Command Test ==="
echo ""

# Test 1: Ping
echo "[1] Ping..."
run_cmd 1 command=ping

# Test 2: Connect
echo ""
echo "[2] Connect..."
result=$(run_cmd 2 command=connect)
echo "$result"
if echo "$result" | grep -q '"success":false'; then
    echo "FAILED: Could not connect. Is the camera connected and in RAW mode?"
    exit 1
fi

# Test 3: Read Film Simulation (verify standard PTP still works)
echo ""
echo "[3] Read Film Simulation (0xD001)..."
run_cmd 3 command=read_property,code=0xD001

# Test 4: Read Preset Slot 0
echo ""
echo "[4] Read Preset Slot 0..."
run_cmd 4 command=read_preset_slot,index=0

# Test 5: Load RAF (if file provided)
if [ -n "$RAF_FILE" ] && [ -f "$RAF_FILE" ]; then
    echo ""
    echo "[5] Load RAF: $RAF_FILE ($(stat -f %z "$RAF_FILE" 2>/dev/null || stat -c %s "$RAF_FILE") bytes)..."
    result=$(run_cmd 5 command=load_raf,path=$RAF_FILE)
    echo "$result"
    
    # Test 5b: Reconnect after RAF upload (macOS workaround)
    echo ""
    echo "[5b] Reconnect after RAF upload..."
    run_cmd 5b command=reconnect
    
    # Test 5c: Verify PTP still works after reconnect
    echo ""
    echo "[5c] Verify PTP after reconnect (0xD001)..."
    run_cmd 5c command=read_property,code=0xD001
    
    # Test 5d: Full conversion pipeline (optional, takes 10-30s)
    echo ""
    read -p "[6] Run full conversion pipeline? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        # Create output path
        RAF_BASENAME=$(basename "$RAF_FILE" .RAF)
        JPEG_OUTPUT="/tmp/${RAF_BASENAME}_converted.jpg"
        echo "Full pipeline: $RAF_FILE → $JPEG_OUTPUT"
        echo "(This will upload RAF, reconnect, get/set profile, trigger conversion, download JPEG)"
        echo ""
        
        # Use individual commands for better progress tracking
        echo "[6a] Load RAF..."
        run_cmd 6a command=load_raf,path=$RAF_FILE
        
        echo "[6b] Reconnect..."
        run_cmd 6b command=reconnect
        
        echo "[6c] Get profile (0xD185)..."
        PROFILE_OUTPUT="/tmp/${RAF_BASENAME}_profile.dat"
        run_cmd 6c command=get_profile,output=$PROFILE_OUTPUT
        
        echo "[6d] Trigger conversion..."
        run_cmd 6d command=trigger_conversion,full_resolution=1
        
        echo "[6e] Wait for result (up to 30s)..."
        run_cmd 6e command=wait_result,output=$JPEG_OUTPUT,timeout_ms=30000
        
        if [ -f "$JPEG_OUTPUT" ]; then
            echo ""
            echo "✅ JPEG saved: $JPEG_OUTPUT ($(stat -f %z "$JPEG_OUTPUT" 2>/dev/null || stat -c %s "$JPEG_OUTPUT") bytes)"
        else
            echo ""
            echo "❌ JPEG not found at $JPEG_OUTPUT"
        fi
        
        # Clean up
        rm -f "$PROFILE_OUTPUT"
    fi
else
    echo ""
    echo "[5] No RAF file provided — skipping load test"
    echo "    Usage: $0 /path/to/photo.RAF"
fi

# Cleanup
echo ""
echo "Disconnecting..."
run_cmd 99 command=disconnect

echo ""
echo "=== Test Complete ==="
echo ""
echo "NOTE: If a vendor command causes the camera to stall (rc=-100), the camera"
echo "may need to be reset (battery removal 10+ seconds) if it enters an"
echo "unrecoverable state. This is expected behavior while debugging."
