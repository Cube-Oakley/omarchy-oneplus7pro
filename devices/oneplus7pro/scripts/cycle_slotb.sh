#!/usr/bin/env bash
# Rebuild guacamole DTB, filter overlays, pack boot, flash slot B, report.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KSRC="$ROOT/.work/linux-sm8150"
KOUT="$ROOT/out/kernel-raid6fix"
RAMDISK=/tmp/pmos-boot-unpack/ramdisk
LOG="$ROOT/out/cycle.log"
log() { echo "$(date +%H:%M:%S) $*" | tee -a "$LOG"; }

cd "$KSRC"
log "rebuild dtbs"
make ARCH=arm64 LLVM=1 dtbs DTC_FLAGS="-@" -j"$(nproc)" >/tmp/dtbs-build.log 2>&1
cp arch/arm64/boot/dts/qcom/sm8150-oneplus-guacamole.dtb "$KOUT/sm8150-oneplus-guacamole.dtb"
DTB="$KOUT/sm8150-oneplus-guacamole.dtb"

python3 "$ROOT/scripts/filter_dtbo.py" \
  --base "$DTB" \
  --overlay "$ROOT/out/dtbo-split/entry00-id0-rev0.dtbo" \
  --out-dir /tmp/filtered-ovl | tee -a "$LOG"

fdtoverlay -i "$DTB" -o /tmp/merged.dtb /tmp/filtered-ovl/filtered.dtbo
log "merged dtb $(stat -c%s /tmp/merged.dtb)"

CMDLINE='androidboot.hardware=qcom androidboot.usbcontroller=a600000.dwc3 clk_ignore_unused pd_ignore_unused ignore_loglevel console=ttyMSM0,115200n8'
IMG="$ROOT/out/pmos/boot-cycle.img"
mkbootimg \
  --header_version 2 --os_version 16.0.0 --os_patch_level 2026-08 \
  --kernel "$KOUT/Image.gz" --ramdisk "$RAMDISK" --dtb /tmp/merged.dtb \
  --pagesize 0x00001000 --base 0x00000000 \
  --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --second_offset 0x00000000 --tags_offset 0x00000100 --dtb_offset 0x01f00000 \
  --board '' --cmdline "$CMDLINE" --output "$IMG"

# noop matching dtbo (ABL match only)
python3 - <<'PY'
from pathlib import Path
import subprocess
ids=[(0x4985,0x00,0x37),(0x498F,0x00,0xff),(0x49a9,0x0c,0x37),(0x49b1,0x00,0x37),(0x4d59,0x00,0x37),(0x4d97,0x00,0x37)]
files=[]
for i,(d,lo,hi) in enumerate(ids):
    t=f'''/dts-v1/;
/plugin/;
/ {{
  model = "guacamole";
  compatible = "qcom,sm8150-mtp", "qcom,sm8150";
  qcom,board-id = <0x08 0x00>;
  oplus,dtsi_no = <{d:#x}>;
  oplus,pcb_range = <{lo:#x} {hi:#x}>;
}};
'''
    p=Path(f'/tmp/noop{i}.dts'); p.write_text(t)
    subprocess.check_call(['dtc','-@','-I','dts','-O','dtb','-o',f'/tmp/noop{i}.dtbo',str(p)], stderr=subprocess.DEVNULL)
    files.append(f'/tmp/noop{i}.dtbo')
Path('/tmp/noop-list').write_text(' '.join(files))
PY
mkdtboimg create "$ROOT/out/dtbo-noop.img" --page_size=4096 $(cat /tmp/noop-list)

# ensure fastboot
if timeout 3 adb get-state 2>/dev/null | grep -q device; then
  adb reboot bootloader
fi
ok=0
for i in $(seq 1 40); do
  timeout 3 fastboot devices | grep -q fastboot && { ok=1; break; }
  sleep 1
done
[ "$ok" = 1 ]

log "flash boot_b + noop dtbo"
fastboot flash boot_b "$IMG"
fastboot flash dtbo_b "$ROOT/out/dtbo-noop.img"
fastboot flash vbmeta_b /tmp/vbmeta-disabled.img || true
fastboot set_active b
fastboot reboot

result=unknown
for i in $(seq 1 30); do
  adb_out=$(timeout 2 adb devices | awk 'NR>1 && NF{print}')
  fb_out=$(timeout 2 fastboot devices)
  usb=$(timeout 2 lsusb | grep -E '18d1:d00d|22d9:|1d6b:0104' || true)
  if echo "$usb" | grep -q '1d6b:0104'; then result=gadget; break; fi
  if echo "$fb_out" | grep -q fastboot; then result=fastboot; break; fi
  if echo "$adb_out" | grep -qE '\bdevice\b'; then
    slot=$(timeout 6 adb shell getprop ro.boot.slot_suffix | tr -d '\r')
    krn=$(timeout 6 adb shell uname -r | tr -d '\r')
    result="adb slot=$slot kernel=$krn"
    break
  fi
  sleep 1
done
log "RESULT $result"
echo "$result"
