#!/system/bin/sh
# Run on device as Magisk root. Adds ACM serial next to ADB.
trap "" HUP
# ADB drops for ~2s while UDC rebinds; it should come back.
LOG=/mnt/vendor/persist/omarchy-acm.log
G=/config/usb_gadget/g1
BB=/data/adb/magisk/busybox
UDC=11210000.dwc3

echo "=== acm $(date) ===" >> "$LOG"
echo "id=$(id)" >> "$LOG"
setenforce 0 2>>"$LOG"
echo "enforce=$(cat /sys/fs/selinux/enforce)" >> "$LOG"

# Keep ADB function0; add ACM as function1 if missing.
echo none > "$G/UDC" 2>>"$LOG" || echo "" > "$G/UDC" 2>>"$LOG"
sleep 1
if [ ! -e "$G/configs/b.1/function1" ] && [ ! -e "$G/configs/b.1/f2" ]; then
  ln -s "$G/functions/acm.gs6" "$G/configs/b.1/function1" 2>>"$LOG"
fi
echo "$UDC" > "$G/UDC" 2>>"$LOG"
sleep 1
echo "UDC=$(cat $G/UDC 2>/dev/null)" >> "$LOG"
ls -l "$G/configs/b.1/" >> "$LOG" 2>&1
ls -l /dev/ttyGS0 >> "$LOG" 2>&1

# Root shell on the ACM port. Magisk busybox has setsid+cttyhack, not getty.
if [ -c /dev/ttyGS0 ]; then
  chmod 666 /dev/ttyGS0 2>>"$LOG"
  if [ ! -f /data/local/tmp/omarchy-getty.pid ] || ! kill -0 "$(cat /data/local/tmp/omarchy-getty.pid)" 2>/dev/null; then
    (
      export PATH=/data/adb/magisk:/system/bin:/system/xbin
      export HOME=/data/local/tmp
      export PS1='omarchy-acm# '
      while true; do
        $BB setsid $BB cttyhack $BB sh -i <>/dev/ttyGS0 >&0 2>&0
        sleep 1
      done
    ) &
    echo $! > /data/local/tmp/omarchy-getty.pid
    echo "getty pid=$!" >> "$LOG"
  fi
else
  echo "no ttyGS0" >> "$LOG"
fi
echo "done $(date)" >> "$LOG"
