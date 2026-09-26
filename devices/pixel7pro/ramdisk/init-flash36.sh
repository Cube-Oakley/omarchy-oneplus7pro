#!/busybox sh
# Pixel 7 Pro ramdisk: disable SELinux, log to pmsg+persist, load USB PHY.
BB=/busybox
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
LOG=/persist/omarchy-ramdisk.log
TMPLOG=/tmp/omarchy-ramdisk.log

$BB mkdir -p /proc /sys /dev /dev/block /tmp /bin /sbin /persist /sys/fs/pstore /sys/fs/selinux /sys/kernel/config
$BB mount -t proc proc /proc
$BB mount -t sysfs sysfs /sys
# GKI has CONFIG_DEVTMPFS=n. tmpfs + mknod, same as Android ueventd.
$BB mount -t tmpfs tmpfs /dev 2>/dev/null || true
$BB mkdir -p /dev/block
$BB mknod /dev/null c 1 3 2>/dev/null || true
$BB mknod /dev/kmsg c 1 11 2>/dev/null || true
$BB mknod /dev/sda1 b 8 1 2>/dev/null || true
$BB mknod /dev/block/sda1 b 8 1 2>/dev/null || true
$BB --install -s /bin 2>/dev/null || true

# Kernel is enforcing with no Android policy — that would block USB probes.
$BB mount -t selinuxfs selinuxfs /sys/fs/selinux 2>/dev/null || true
$BB echo 0 > /sys/fs/selinux/enforce 2>/dev/null || true

# Do not mount persist in PID 1. Early mount can block on a dead sda1
# node; post-modules mount blocked reboot() on flash 24.
$BB mount -t pstore pstore /sys/fs/pstore 2>/dev/null || true

log() {
  $BB echo "OMARCHY: $*" > /dev/kmsg 2>/dev/null
  $BB echo "OMARCHY: $*" >> "$TMPLOG" 2>/dev/null
}

: > "$TMPLOG" 2>/dev/null
: > "$LOG" 2>/dev/null
log "init pid=$$"
log "selinux enforce=$($BB cat /sys/fs/selinux/enforce 2>/dev/null)"
log "lib/modules exists=$($BB test -d /lib/modules && echo y || echo n)"
log "ko count=$($BB ls /lib/modules/*.ko 2>/dev/null | $BB wc -l)"
log "block=$($BB ls /dev/block 2>/dev/null | $BB tr '\n' ' ')"

MODDIR=/lib/modules
DEP=$MODDIR/modules.dep
LOAD=$MODDIR/modules.load
LD=/tmp/ld
$BB mkdir -p "$LD"
ok=0
fail=0
n=0
mn() { echo "$1" | $BB sed 's/\.ko$//;s/-/_/g'; }
insmod_one() {
  local m="$1"
  local name deps line d b err
  name=$(mn "$m")
  [ -d "/sys/module/$name" ] && return 0
  [ -f "$LD/$m" ] && return 0
  : > "$LD/$m"
  line=$($BB grep "^/lib/modules/${m}:" "$DEP" 2>/dev/null)
  deps=${line#*:}
  for d in $deps; do
    b=${d##*/}
    [ -n "$b" ] && insmod_one "$b"
  done
  if [ -d "/sys/module/$name" ]; then
    ok=$((ok + 1))
    return 0
  fi
  if [ ! -f "$MODDIR/$m" ]; then
    fail=$((fail + 1))
    log "missing $m"
    return 1
  fi
  if $BB insmod "$MODDIR/$m" 2>/tmp/insmod.err; then
    ok=$((ok + 1))
    case "$m" in
      *usb*|*dwc3*|*phy-exynos-usb*|*tcpci*|*s2mpg*|*iommu*|*pd_hsi0*|*exynos-pd.ko|*i2c-exynos*)
        log "ok $m sys=$(test -d /sys/module/$name && echo y || echo n)" ;;
    esac
    return 0
  fi
  err=$($BB cat /tmp/insmod.err)
  case "$err" in
    *"File exists"*)
      ok=$((ok + 1))
      log "exists $m sys=$(test -d /sys/module/$name && echo y || echo n)"
      return 0
      ;;
  esac
  fail=$((fail + 1))
  log "FAIL $m $err"
  return 1
}
if [ -f "$LOAD" ]; then
  log "loading $LOAD via modules.dep"
  while read m; do
    [ -z "$m" ] && continue
    case "$m" in \#*|focal_touch.ko|syna_touch.ko|softdog.ko|ehld.ko|hardlockup-debug.ko|hardlockup-watchdog.ko|ufs-exynos-core.ko|ufs-pixel-fips140.ko|phy-exynos-usbdrd-super.ko|dwc3-exynos-usb.ko|xhci-exynos.ko) continue ;; esac
    n=$((n + 1))
    insmod_one "$m"
  done < "$LOAD"
else
  log "no modules.load"
fi
# Do not insmod PHY/DWC3/xhci — local-m probe appears to block PID 1
# (frozen logo on 25/26/28). Dump without them, then rebootbl.
log "loaded ok=$ok fail=$fail n=$n"
log "blockdev=$($BB ls /sys/block 2>/dev/null | $BB tr '\n' ' ')"

# Magisk busybox sleep appears to hang as PID 1 on this GKI (pstore
# always stops at the last insmod). Spin on /proc/uptime instead.
wait_s() {
  start=$($BB awk '{printf "%d",$1}' /proc/uptime)
  while [ $($BB awk '{printf "%d",$1}' /proc/uptime) -lt $((start + $1)) ]; do
    :
  done
}
wait_s 2
log "udc=$($BB ls /sys/class/udc 2>/dev/null | $BB tr '\n' ' ')"
log "plat_usb=$($BB ls -d /sys/devices/platform/*usb* /sys/devices/platform/*dwc* 2>/dev/null | $BB tr '\n' ' ')"
log "mods=$($BB ls /sys/module 2>/dev/null | $BB grep -iE 'dwc|usb|phy_exynos' | $BB tr '\n' ' ')"
log "pdrv=$($BB ls /sys/bus/platform/drivers 2>/dev/null | $BB grep -iE 'dwc|usb|hsi|phy' | $BB tr '\n' ' ')"
log "usbuev=$($BB cat /sys/devices/platform/11210000.usb/uevent 2>/dev/null | $BB tr '\n' ';')"
log "usbmod=$($BB cat /sys/devices/platform/11210000.usb/modalias 2>/dev/null)"
log "usblist=$($BB ls /sys/devices/platform/11210000.usb 2>/dev/null | $BB tr '\n' ' ')"
log "waiting=$($BB cat /sys/devices/platform/11210000.usb/waiting_for_supplier 2>/dev/null)"
# trybind/gadget can block forever if PHY probes (frozen logo on 25/26).
# Dump then rebootbl so we can cycle unattended.
log "DUMP DONE — rebootbl"
wait_s 1
exec /rebootbl
while :; do wait_s 30; done
