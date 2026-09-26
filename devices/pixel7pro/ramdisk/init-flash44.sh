#!/busybox sh
# Flash 44: flash-37 modules, child-bind PHY/DWC3, ACM if real UDC,
# else rebootbl. Host ttyACM0 is the success signal (pstore dies on reboot).
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
$BB mknod /dev/pmsg0 c 252 0 2>/dev/null || true
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
  $BB echo "OMARCHY: $*" > /dev/pmsg0 2>/dev/null
}

: > "$TMPLOG" 2>/dev/null
: > "$LOG" 2>/dev/null
log "flash=44 cap=100 child-bind ACM-or-rebootbl"
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
    if [ "$n" -gt 100 ]; then
      log "cap 100 at $m"
      break
    fi
    insmod_one "$m"
  done < "$LOAD"
else
  log "no modules.load"
fi
# Skip list does not stop PHY/DWC3 coming in as deps of exynos-pd (line 40).
# Dump whether they actually landed, then idle for a hold-through log.
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
log "phy_mod=$(test -d /sys/module/phy_exynos_usbdrd_super && echo y || echo n)"
log "dwc3_mod=$(test -d /sys/module/dwc3_exynos_usb && echo y || echo n)"
log "xhci_mod=$(test -d /sys/module/xhci_exynos && echo y || echo n)"
log "pd_mod=$(test -d /sys/module/exynos_pd && echo y || echo n)"
log "i2c_mod=$(test -d /sys/module/i2c_exynos5 && echo y || echo n)"
log "tcpci_mod=$(test -d /sys/module/tcpci_max77759 && echo y || echo n)"
log "phydev=$($BB ls /sys/devices/platform/11200000.phy 2>/dev/null | $BB tr '\n' ' ')"
log "phywait=$($BB cat /sys/devices/platform/11200000.phy/waiting_for_supplier 2>/dev/null)"
log "DUMP A udc=$($BB ls /sys/class/udc 2>/dev/null | $BB tr '\n' ' ') wait=$($BB cat /sys/devices/platform/11210000.usb/waiting_for_supplier 2>/dev/null)"
# Bind may hang the USB stack (flash 38/39). Child so PID 1 can still rebootbl
# if only the child blocks. Kernel freeze → logo stays; hold after 2 min.
log "fork bind"
(
  log "child bind phy"
  $BB echo 11200000.phy > /sys/bus/platform/drivers/phy_exynos_usbdrd/bind 2>/tmp/bind.err \
    && log "bind phy ok" || log "bind phy $($BB cat /tmp/bind.err)"
  log "child bind dwc3"
  $BB echo 11210000.usb > /sys/bus/platform/drivers/exynos-dwc3/bind 2>/tmp/bind.err \
    && log "bind dwc3 ok" || log "bind dwc3 $($BB cat /tmp/bind.err)"
  log "child bind done udc=$($BB ls /sys/class/udc 2>/dev/null | $BB tr '\n' ' ')"
) &
log "child pid=$!"
wait_s 8
UDC=$($BB ls /sys/class/udc 2>/dev/null | $BB tr '\n' ' ')
log "DUMP B udc=$UDC wait=$($BB cat /sys/devices/platform/11210000.usb/waiting_for_supplier 2>/dev/null)"
case "$UDC" in
  *11210000.dwc3*)
    G=/sys/kernel/config/usb_gadget/g1
    $BB mkdir -p "$G/strings/0x409" "$G/functions/acm.gs0" "$G/configs/c.1/strings/0x409"
    $BB echo 0x18d1 > "$G/idVendor"
    $BB echo 0x4ee3 > "$G/idProduct"
    $BB echo 0x0200 > "$G/bcdUSB"
    $BB echo omarchy > "$G/strings/0x409/serialnumber"
    $BB echo xAI > "$G/strings/0x409/manufacturer"
    $BB echo ramdisk > "$G/strings/0x409/product"
    $BB echo acm > "$G/configs/c.1/strings/0x409/configuration"
    $BB ln -s "$G/functions/acm.gs0" "$G/configs/c.1/acm.gs0" 2>/dev/null || true
    $BB echo 11210000.dwc3 > "$G/UDC" 2>/tmp/udc.err \
      && log "ACM bind 11210000.dwc3" || log "ACM fail $($BB cat /tmp/udc.err)"
    log "ACM idle — host should see ttyACM0"
    while :; do
      wait_s 30
      log "idle acm udc=$($BB ls /sys/class/udc 2>/dev/null | $BB tr '\n' ' ')"
    done
    ;;
esac
if [ -f "$TMPLOG" ]; then
  $BB cat "$TMPLOG" > /dev/pmsg0 2>/dev/null || true
fi
log "no real UDC — rebootbl"
wait_s 2
exec /rebootbl
while :; do wait_s 30; done
