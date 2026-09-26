#!/system/bin/sh
# Run on device as: su -c sh /data/local/tmp/root-dump.sh
set -f
OUT=/data/local/tmp/omarchy-dump
rm -rf "$OUT"
mkdir -p "$OUT/gadget" "$OUT/sys" "$OUT/vendor" "$OUT/pstore" "$OUT/persist"

echo "id=$(id)" > "$OUT/meta.txt"
echo "enforce=$(cat /sys/fs/selinux/enforce 2>/dev/null)" >> "$OUT/meta.txt"
getenforce >> "$OUT/meta.txt" 2>&1
date >> "$OUT/meta.txt"
getprop ro.boot.slot_suffix >> "$OUT/meta.txt"
getprop sys.usb.config >> "$OUT/meta.txt"
getprop sys.usb.controller >> "$OUT/meta.txt"

# gadget scalars
G=/config/usb_gadget/g1
for f in UDC idVendor idProduct bcdUSB bcdDevice bDeviceClass bDeviceSubClass \
         bDeviceProtocol bMaxPacketSize0 max_speed; do
  echo -n "$f=" >> "$OUT/gadget/scalars.txt"
  cat "$G/$f" >> "$OUT/gadget/scalars.txt" 2>> "$OUT/gadget/scalars.err"
done
for f in manufacturer product serialnumber; do
  echo -n "$f=" >> "$OUT/gadget/strings.txt"
  cat "$G/strings/0x409/$f" >> "$OUT/gadget/strings.txt" 2>> "$OUT/gadget/scalars.err"
done
ls -l "$G/configs/b.1/" > "$OUT/gadget/config-b1.txt" 2>&1
readlink "$G/configs/b.1/function0" > "$OUT/gadget/function0.txt" 2>&1
ls -l "$G/configs/b.1/" >> "$OUT/gadget/config-b1.txt" 2>&1
# all symlinks in config
find "$G/configs" -type l -exec ls -l {} \; > "$OUT/gadget/config-links.txt" 2>&1
find "$G/functions" -maxdepth 1 -type d > "$OUT/gadget/functions.txt" 2>&1
cat "$G/functions/acm.gs6/port_num" > "$OUT/gadget/acm-port.txt" 2>&1
cat "$G/os_desc/use" > "$OUT/gadget/os_desc.txt" 2>&1

# udc / dwc3
ls -l /sys/class/udc/ > "$OUT/sys/udc.txt" 2>&1
for u in /sys/class/udc/*; do
  echo "== $u ==" >> "$OUT/sys/udc-detail.txt"
  cat "$u/uevent" >> "$OUT/sys/udc-detail.txt" 2>&1
done
cat /sys/devices/platform/11210000.usb/11210000.dwc3/mode > "$OUT/sys/dwc3-mode.txt" 2>&1
ls -l /dev/ttyGS* > "$OUT/sys/ttyGS.txt" 2>&1

# usb rc files
cp /vendor/etc/init/hw/init.gs201.usb.rc "$OUT/vendor/" 2>/dev/null
cp /system/etc/init/hw/init.usb.configfs.rc "$OUT/vendor/" 2>/dev/null
cp /system/etc/init/hw/init.usb.rc "$OUT/vendor/" 2>/dev/null
cp /vendor/etc/init/android.hardware.usb-service.rc "$OUT/vendor/" 2>/dev/null
cp /vendor/etc/init/android.hardware.usb.gadget-service.rc "$OUT/vendor/" 2>/dev/null

# persist
ls -la /mnt/vendor/persist/ > "$OUT/persist/ls.txt" 2>&1
ls -la /mnt/vendor/persist/ | grep -i omarchy >> "$OUT/persist/ls.txt" 2>&1
cat /mnt/vendor/persist/omarchy-ramdisk.log > "$OUT/persist/omarchy-ramdisk.log" 2>&1
find /mnt/vendor/persist -iname '*omarchy*' -o -iname '*ramdisk*' > "$OUT/persist/find.txt" 2>&1

# pstore
ls -la /sys/fs/pstore/ > "$OUT/pstore/ls.txt" 2>&1
for f in /sys/fs/pstore/*; do
  bn=$(basename "$f")
  dd if="$f" of="$OUT/pstore/$bn" bs=4096 count=256 2>/dev/null
done

# selinux / init
ls -lZ /init /system/bin/init > "$OUT/selinux-init.txt" 2>&1
cat /proc/cmdline > "$OUT/cmdline.txt" 2>&1
cat /proc/mounts > "$OUT/mounts.txt" 2>&1
lsmod > "$OUT/lsmod.txt" 2>&1
dmesg | grep -iE 'usb|dwc|gadget|udc|phy-exynos|tcpci|max777|configfs|OMARCHY' > "$OUT/dmesg-usb.txt" 2>&1

# modules on vendor_dlkm / vendor
find /vendor /vendor_dlkm /lib/modules -name '*dwc3*' -o -name '*usbdrd*' -o -name '*tcpci*' \
  -o -name '*xhci-exynos*' -o -name '*usb_f_*' > "$OUT/ko-paths.txt" 2>&1
ls /vendor/lib/modules/ 2>/dev/null | grep -iE 'usb|dwc|phy|xhci|tcpci|max777|rndis|gadget' > "$OUT/vendor-lib-modules-usb.txt"
ls /vendor_dlkm/lib/modules/ 2>/dev/null | grep -iE 'usb|dwc|phy|xhci|tcpci|max777|rndis|gadget' > "$OUT/vendor_dlkm-usb.txt"

# firmware
ls /vendor/firmware/ 2>/dev/null | grep -iE 'usb|dwc|phy|max777' > "$OUT/firmware-usb.txt"

# Magisk
magisk -v > "$OUT/magisk.txt" 2>&1
ls -la /data/adb/modules > "$OUT/magisk-modules.txt" 2>&1
ls -la /data/adb/magisk > "$OUT/magisk-dir.txt" 2>&1

# block devices for persist
ls -l /dev/block/by-name/persist /dev/block/sda1 > "$OUT/persist-block.txt" 2>&1

echo DONE > "$OUT/DONE"
ls -la "$OUT" "$OUT/gadget" "$OUT/vendor" "$OUT/pstore" "$OUT/persist"
