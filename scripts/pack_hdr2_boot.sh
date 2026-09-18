#!/usr/bin/env bash
# Pack an ABL-compatible header-v2 boot.img: uncompressed Image + ramdisk + DTB.
# Pads to the Lineage boot partition size (96 MiB).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL="${1:-$ROOT/.work/linux-sm8150/arch/arm64/boot/Image}"
RAMDISK="${2:-$ROOT/.work/initramfs.cpio.gz}"
DTB="${3:-$ROOT/out/kernel-raid6fix/sm8150-oneplus-guacamole.dtb}"
OUT="${4:-$ROOT/out/pmos/boot-entrylayout.img}"
PART_SIZE=100663296

# Keep under 511 chars: OOS12 ABL ignores extra_cmdline.
CMDLINE="${BOOT_CMDLINE:-console=ttyMSM0,115200n8 clk_ignore_unused pd_ignore_unused ignore_loglevel maxcpus=0 nokaslr androidboot.hardware=qcom androidboot.usbcontroller=a600000.dwc3 androidboot.boot_devices=soc/1d84000.ufshc iommu.passthrough=1 arm-smmu.disable_bypass=0 swiotlb=force}"

[ -s "$KERNEL" ] || { echo "missing kernel $KERNEL" >&2; exit 1; }
[ -s "$RAMDISK" ] || { echo "missing ramdisk $RAMDISK" >&2; exit 1; }
[ -s "$DTB" ] || { echo "missing dtb $DTB" >&2; exit 1; }

python3 - "$KERNEL" <<'PY'
import struct, sys
p=sys.argv[1]
d=open(p,'rb').read(64)
to,sz,flags=struct.unpack_from('<QQQ', d, 8)
magic=d[56:60]
print(f'Image first4={d[:4].hex()} text_offset=0x{to:x} image_size=0x{sz:x} flags=0x{flags:x} magic={magic!r}')
if to != 0x80000:
    print('WARNING: text_offset is not 0x80000', file=sys.stderr)
if d[:2]==b'MZ':
    print('WARNING: Image still starts with MZ EFI stub', file=sys.stderr)
PY

mkdir -p "$(dirname "$OUT")"
RAW="${OUT}.raw"
mkbootimg \
  --header_version 2 --os_version 16.0.0 --os_patch_level 2026-08 \
  --kernel "$KERNEL" --ramdisk "$RAMDISK" --dtb "$DTB" \
  --pagesize 0x00001000 --base 0x00000000 \
  --kernel_offset 0x00008000 --ramdisk_offset 0x01000000 \
  --second_offset 0x00000000 --tags_offset 0x00000100 --dtb_offset 0x01f00000 \
  --board '' --cmdline "$CMDLINE" --output "$RAW"

python3 - "$RAW" "$OUT" "$PART_SIZE" <<'PY'
import sys, os
src, dst, size = sys.argv[1], sys.argv[2], int(sys.argv[3])
data=open(src,'rb').read()
if len(data)>size:
    raise SystemExit(f'boot image {len(data)} exceeds partition {size}')
open(dst,'wb').write(data + b'\x00'*(size-len(data)))
os.remove(src)
print(f'wrote {dst} ({size} bytes, payload {len(data)})')
PY
ls -lh "$OUT"
echo DONE_PACK
