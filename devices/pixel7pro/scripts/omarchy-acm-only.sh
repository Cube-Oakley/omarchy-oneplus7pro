#!/system/bin/sh
# Proof: ACM gadget without the USB gadget HAL (ramdisk-like).
# A 15s watchdog restores ADB even if this script dies.
trap "" HUP
LOG=/mnt/vendor/persist/omarchy-acm.log
G=/config/usb_gadget/g1
UDC=11210000.dwc3
echo "=== acm-only $(date) ===" >> "$LOG"
setenforce 0

# watchdog restore
(
  sleep 15
  start vendor.usb-gadget-hal
  sleep 1
  svc usb setFunctions
  echo "watchdog restore $(date) functions=$(svc usb getFunctions)" >> "$LOG"
) &
echo "watchdog pid=$!" >> "$LOG"

stop vendor.usb-gadget-hal
sleep 1
echo none > "$G/UDC" 2>>"$LOG" || echo "" > "$G/UDC"
sleep 1
rm -f "$G/configs/b.1/function0" "$G/configs/b.1/function1" "$G/configs/b.1/function2" \
      "$G/configs/b.1/f1" "$G/configs/b.1/f2" "$G/configs/b.1/f3"
ln -s "$G/functions/acm.gs6" "$G/configs/b.1/function0"
echo 0x18d1 > "$G/idVendor"
echo 0x4ee7 > "$G/idProduct"
echo ACM > "$G/configs/b.1/strings/0x409/configuration" 2>/dev/null
echo "$UDC" > "$G/UDC" 2>>"$LOG"
sleep 1
echo "UDC=$(cat $G/UDC)" >> "$LOG"
ls -l "$G/configs/b.1/" >> "$LOG"
ls -l /dev/ttyGS0 >> "$LOG" 2>&1
echo "gadget_state=$(cat /sys/devices/platform/11210000.usb/dwc3_exynos_gadget_state)" >> "$LOG"
echo "otg=$(cat /sys/devices/platform/11210000.usb/dwc3_exynos_otg_state)" >> "$LOG"

if [ -c /dev/ttyGS0 ]; then
  chmod 666 /dev/ttyGS0
  echo "OMARCHY ACM READY $(date)" > /dev/ttyGS0
fi
# Wait for watchdog restore (keeps this process from exiting before bind settles).
sleep 14
echo "script end $(date)" >> "$LOG"
