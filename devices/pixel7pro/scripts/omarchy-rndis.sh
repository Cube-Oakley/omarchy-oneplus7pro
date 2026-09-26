#!/system/bin/sh
trap "" HUP
LOG=/mnt/vendor/persist/omarchy-rndis.log
echo "=== rndis $(date) ===" >> "$LOG"
setenforce 0
# Android USB HAL requires none -> new config, not a direct jump.
setprop sys.usb.config none
sleep 2
echo "after none state=$(getprop sys.usb.state) udc=$(cat /config/usb_gadget/g1/UDC)" >> "$LOG"
setprop sys.usb.config rndis,adb
sleep 3
echo "config=$(getprop sys.usb.config) state=$(getprop sys.usb.state)" >> "$LOG"
echo "UDC=$(cat /config/usb_gadget/g1/UDC)" >> "$LOG"
ls -l /config/usb_gadget/g1/configs/b.1/ >> "$LOG"
# If ADB did not come back, restore after a few seconds.
i=0
while [ $i -lt 12 ]; do
  if [ "$(getprop sys.usb.state)" = "rndis,adb" ] || [ "$(getprop init.svc.adbd)" = "running" ]; then
    echo "ok i=$i state=$(getprop sys.usb.state) adbd=$(getprop init.svc.adbd)" >> "$LOG"
    exit 0
  fi
  sleep 1
  i=$((i + 1))
done
echo "RESTORE adb" >> "$LOG"
setprop sys.usb.config none
sleep 1
setprop sys.usb.config adb
sleep 2
echo "restored state=$(getprop sys.usb.state) adbd=$(getprop init.svc.adbd)" >> "$LOG"
