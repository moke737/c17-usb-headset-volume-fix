#!/system/bin/sh
# ColorOS17 Type-C headset volume fix (v4)
#
# ROOT CAUSE:
#   The ported framework is Android 17 (SDK 37) and maps
#   AUDIO_DEVICE_OUT_USB_HEADSET to the *new* device category
#   DEVICE_CATEGORY_USB_HEADSET (the string is present in
#   /system/lib64/libaudiopolicycomponents.so).
#   The vendor /vendor/etc/audio_policy_volumes.xml comes from Android 16 and
#   only defines EARPIECE / EXT_MEDIA / HEADSET / HEARING_AID / SPEAKER.
#   With no curve for the category in use the lookup falls back to
#   FULL_SCALE_VOLUME_CURVE (0 dB at every index), so the mixer track stays at
#   unity gain and a Type-C headset always plays at full scale - the slider moves
#   but nothing changes.
#
# FIX: mirror every DEVICE_CATEGORY_HEADSET curve as DEVICE_CATEGORY_USB_HEADSET.
#      This touches no routing and no property, so audio output is unaffected.

MODDIR=${0%/*}
SRC="$MODDIR/audio_policy_volumes.xml"
TARGET=/vendor/etc/audio_policy_volumes.xml
LOG=/data/local/tmp/c17_usb_volume_fix.log

log() { echo "[$(date +%H:%M:%S)] $*" >> "$LOG" 2>/dev/null; }

log "=== v4 post-fs-data start ==="
[ -f "$SRC" ]    || { log "ERR: source missing: $SRC"; exit 0; }
[ -f "$TARGET" ] || { log "ERR: target missing: $TARGET"; exit 0; }

chcon --reference="$TARGET" "$SRC" 2>/dev/null && log "chcon: ok" || log "chcon: skipped"

if mount --bind "$SRC" "$TARGET" 2>/dev/null; then
    log "bind mount: OK -> $TARGET"
else
    log "bind mount: FAILED (system/ overlay may still cover it)"
fi

N=$(grep -c 'DEVICE_CATEGORY_USB_HEADSET' "$TARGET" 2>/dev/null)
if [ -n "$N" ] && [ "$N" -gt 0 ]; then
    log "VERIFY OK: $N USB_HEADSET curves present"
else
    log "VERIFY FAIL: no USB_HEADSET curves"
fi
log "=== v4 post-fs-data end ==="