#!/system/bin/sh
LOG=/data/local/tmp/c17_usb_volume_fix.log
sleep 25
{
    echo "=== v4 service.sh @ $(date) ==="
    echo "USB_HEADSET curves in effect: $(grep -c 'DEVICE_CATEGORY_USB_HEADSET' /vendor/etc/audio_policy_volumes.xml 2>/dev/null)"
    echo "--- STREAM_MUSIC ---"
    dumpsys audio 2>/dev/null | sed -n '/- STREAM_MUSIC:/,/Volume Group/p'
} >> "$LOG" 2>&1