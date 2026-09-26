#!/busybox sh
# Mainline first-boot init: log, try ACM if any UDC appears, reboot to
# bootloader so a hang is not required. No vendor modules.
BB=/busybox
export PATH=/bin:/sbin:/usr/bin:/usr/sbin

$BB mkdir -p /proc /sys /dev /tmp /bin /sys/kernel/config /sys/fs/pstore
$BB mount -t proc proc /proc
$BB mount -t sysfs sysfs /sys
$BB mount -t tmpfs tmpfs /dev
$BB mkdir -p /dev/block
$BB mknod /dev/null c 1 3 2>/dev/null || true
$BB mknod /dev/kmsg c 1 11 2>/dev/null || true
$BB --install -s /bin 2>/dev/null || true
$BB mount -t pstore pstore /sys/fs/pstore 2>/dev/null || true
$BB mount -t configfs configfs /sys/kernel/config 2>/dev/null || true

log() { $BB echo "MAINLINE: $*" > /dev/kmsg 2>/dev/null; }

log "gs201 cheetah init pid=$$"
log "version=$($BB cat /proc/version)"
log "cmdline=$($BB cat /proc/cmdline)"
log "compat=$($BB cat /proc/device-tree/compatible 2>/dev/null | $BB tr '\0' ' ')"
log "udc=$($BB ls /sys/class/udc 2>/dev/null | $BB tr '\n' ' ')"

# If a real UDC showed up, bind ACM and stay. Otherwise timed rebootbl.
G=/sys/kernel/config/usb_gadget/g1
if [ -d /sys/class/udc/11210000.dwc3 ] || [ -d /sys/class/udc/11110000.dwc3 ]; then
  U=$($BB ls -d /sys/class/udc/*.dwc3 2>/dev/null | $BB sed 's,.*/,,' | $BB head -1)
  $BB mkdir -p "$G/strings/0x409" "$G/functions/acm.gs0" "$G/configs/c.1/strings/0x409"
  $BB echo 0x18d1 > "$G/idVendor"
  $BB echo 0x4ee3 > "$G/idProduct"
  $BB echo mainline > "$G/strings/0x409/serialnumber"
  $BB ln -s "$G/functions/acm.gs0" "$G/configs/c.1/" 2>/dev/null || true
  $BB echo "$U" > "$G/UDC" 2>/dev/null && log "ACM on $U"
  while :; do
    log "idle acm udc=$($BB ls /sys/class/udc 2>/dev/null | $BB tr '\n' ' ')"
    start=$($BB awk '{printf "%d",$1}' /proc/uptime)
    while [ $($BB awk '{printf "%d",$1}' /proc/uptime) -lt $((start + 30)) ]; do :; done
  done
fi

# Magisk busybox sleep can hang as PID 1. Spin on uptime.
wait_s() {
  start=$($BB awk '{printf "%d",$1}' /proc/uptime)
  while [ $($BB awk '{printf "%d",$1}' /proc/uptime) -lt $((start + $1)) ]; do
    :
  done
}

# 45s wait: if init runs, fastboot should be ~100s+ not ~63–80s.
log "no dwc3 UDC — rebootbl in 45s"
wait_s 45
log "rebootbl"
exec /rebootbl
while :; do wait_s 30; done
