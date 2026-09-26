#!/busybox sh
# Flash 39: flash-37 set, dump A, block PHY/USB + extra HSI2C, child
# insmod i2c-exynos5 for 10d60000.hsi2c (bus 13 / TCPC) only, dump B, idle.
# Flash 38 hung in I2C/PHY probe and tore ramoops (invalid +114).
BB=/busybox
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
LOG=/persist/omarchy-ramdisk.log
TMPLOG=/tmp/omarchy-ramdisk.log

$BB mkdir -p /proc /sys /dev /dev/block /tmp /bin /sbin /persist /sys/fs/pstore /sys/fs/selinux /sys/kernel/config
$BB mount -t proc proc /proc
$BB mount -t sysfs sysfs /sys
$BB mount -t tmpfs tmpfs /dev 2>/dev/null || true
$BB mkdir -p /dev/block
$BB mknod /dev/null c 1 3 2>/dev/null || true
$BB mknod /dev/kmsg c 1 11 2>/dev/null || true
$BB mknod /dev/sda1 b 8 1 2>/dev/null || true
$BB mknod /dev/block/sda1 b 8 1 2>/dev/null || true
$BB --install -s /bin 2>/dev/null || true

$BB mount -t selinuxfs selinuxfs /sys/fs/selinux 2>/dev/null || true
$BB echo 0 > /sys/fs/selinux/enforce 2>/dev/null || true
$BB mount -t pstore pstore /sys/fs/pstore 2>/dev/null || true

log() {
  $BB echo "OMARCHY: $*" > /dev/kmsg 2>/dev/null
  $BB echo "OMARCHY: $*" >> "$TMPLOG" 2>/dev/null
}

: > "$TMPLOG" 2>/dev/null
: > "$LOG" 2>/dev/null
log "flash=39 cap=100 i2c-bus13-only idle"
log "init pid=$$"
log "selinux enforce=$($BB cat /sys/fs/selinux/enforce 2>/dev/null)"
log "lib/modules exists=$($BB test -d /lib/modules && echo y || echo n)"
log "ko count=$($BB ls /lib/modules/*.ko 2>/dev/null | $BB wc -l)"

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
      *usb*|*dwc3*|*phy-exynos-usb*|*tcpci*|*i2c-exynos*|*i2c-acpm*)
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

wait_s() {
  start=$($BB awk '{printf "%d",$1}' /proc/uptime)
  while [ $($BB awk '{printf "%d",$1}' /proc/uptime) -lt $((start + $1)) ]; do
    :
  done
}

wfile() {
  $BB echo "$2" > "$1" 2>/tmp/wfile.err && log "w $1=$2" || log "w FAIL $1=$2 $($BB cat /tmp/wfile.err)"
}

dump_usb() {
  tag="$1"
  log "$tag udc=$($BB ls /sys/class/udc 2>/dev/null | $BB tr '\n' ' ')"
  log "$tag waiting=$($BB cat /sys/devices/platform/11210000.usb/waiting_for_supplier 2>/dev/null)"
  log "$tag phywait=$($BB cat /sys/devices/platform/11200000.phy/waiting_for_supplier 2>/dev/null)"
  log "$tag i2c_mod=$(test -d /sys/module/i2c_exynos5 && echo y || echo n) tcpci_mod=$(test -d /sys/module/tcpci_max77759 && echo y || echo n)"
  log "$tag hsi2c=$($BB ls -d /sys/devices/platform/*.hsi2c 2>/dev/null | $BB tr '\n' ' ')"
  log "$tag i2cdev=$($BB ls /sys/bus/i2c/devices 2>/dev/null | $BB tr '\n' ' ')"
  log "$tag i2cadr=$($BB ls /sys/class/i2c-adapter 2>/dev/null | $BB tr '\n' ' ')"
  log "$tag physup=$($BB ls -d /sys/devices/platform/11200000.phy/supplier:* 2>/dev/null | $BB tr '\n' ' ')"
  log "$tag usblist=$($BB ls /sys/devices/platform/11210000.usb 2>/dev/null | $BB tr '\n' ' ')"
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
log "loaded ok=$ok fail=$fail n=$n"

wait_s 2
dump_usb A

# Stop PHY/USB from probing when I2C 13-0025 appears (flash 38 hang).
wfile /sys/devices/platform/11200000.phy/driver_override none
wfile /sys/devices/platform/11210000.usb/driver_override none
# Only bus 13 (TCPC): 10d60000.hsi2c. Block the other HSI2C blocks.
for d in /sys/devices/platform/*.hsi2c; do
  [ -d "$d" ] || continue
  case "$d" in
    *10d60000.hsi2c*) log "keep $d" ;;
    *) wfile "$d/driver_override" none ;;
  esac
done
# Do not auto-probe I2C clients (max77759tcpc) if the bus comes up.
if [ -f /sys/bus/i2c/drivers_autoprobe ]; then
  wfile /sys/bus/i2c/drivers_autoprobe 0
else
  log "no i2c drivers_autoprobe yet"
fi

log "fork child i2c-exynos5"
(
  log "child i2c start"
  insmod_one i2c-exynos5.ko
  log "child i2c done"
) &
log "child pid=$!"
wait_s 8
dump_usb B
log "DUMP DONE — idle hold Power+VolDown through logo"
while :; do
  wait_s 30
  log "idle udc=$($BB ls /sys/class/udc 2>/dev/null | $BB tr '\n' ' ') i2c=$(test -d /sys/module/i2c_exynos5 && echo y || echo n) dev=$($BB ls /sys/bus/i2c/devices 2>/dev/null | $BB tr '\n' ' ')"
done
