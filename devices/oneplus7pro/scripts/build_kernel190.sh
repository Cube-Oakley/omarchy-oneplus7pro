#!/usr/bin/env bash
# Build-only: kernel #190 = #189 (.work/linux-sm8150-ipa-dtb) plus
#   - the hsuart0 = UART13 alias in the embedded boot DTB, which retires the
#     Bluetooth alias shim (docs/bluetooth-20260922.md);
#   - power_support.ko in the built-in initramfs rebuilt with PM8150L's GPIO
#     block enabled, which the IMX586 needs (docs/camera-20260922.md).
# Same source, .config and release string, so every existing module loads.
# Only that one initramfs member changes; the archive is rewritten entry by
# entry, not regenerated. Output: out/checkpoints/20260923-kernel190/.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="$ROOT/.work/linux-sm8150-ipa-dtb"
TREE="$ROOT/.work/linux-sm8150-190"
OUT="$ROOT/out/checkpoints/20260923-kernel190"
rm -rf "$TREE" "$OUT"
mkdir -p "$OUT"
cp -a --reflink=auto "$BASE" "$TREE"
cmp "$TREE/.config" "$ROOT/.work/linux-sm8150-mmcx-sleep/.config"
# The running power_support.ko is the RTC variant of this overlay (checked
# byte for byte against #189's initramfs).
POWER_RTC_SUPPORT=1 KERNEL_TREE="$TREE" POWER_WORK="$ROOT/.work/power-support-190" \
    POWER_OUT="$OUT/power" bash "$ROOT/scripts/build_power_support.sh"
fdtput -t s "$TREE/bringup-guacamole.dtb" /aliases hsuart0 /soc@0/geniqup@cc0000/serial@c8c000
python3 - "$TREE/bringup.cpio" "$OUT/power/power_support.ko" <<'PY'
from pathlib import Path
import sys
archive, module = Path(sys.argv[1]), Path(sys.argv[2]).read_bytes()
data, out, pos, replaced = archive.read_bytes(), bytearray(), 0, 0
pad = lambda n: (4 - n % 4) % 4
while True:
    head = data[pos:pos + 110]
    assert head[:6] == b'070701', pos
    fields = [int(head[6 + 8 * i:14 + 8 * i], 16) for i in range(13)]
    size, namesize = fields[6], fields[11]
    name_end = pos + 110 + namesize
    name = data[pos + 110:name_end - 1].decode()
    body = name_end + pad(110 + namesize)
    if name == 'hypr/power/power_support.ko':
        fields[6] = len(module)
        out += b'070701' + b''.join(b'%08X' % f for f in fields) + data[pos + 110:body]
        out += module + b'\0' * pad(len(module))
        replaced += 1
    else:
        out += data[pos:body + size + pad(size)]
    pos = body + size + pad(size)
    if name == 'TRAILER!!!':
        out += data[pos:]
        break
assert replaced == 1
archive.write_bytes(out)
PY
make -C "$TREE" ARCH=arm64 LLVM=1 KBUILD_BUILD_VERSION=190 -j"${JOBS:-8}" Image > "$OUT/build.log" 2>&1
BOOT_CMDLINE=$(fdtget -ts "$TREE/bringup-guacamole.dtb" /chosen bootargs) \
    bash "$ROOT/scripts/pack_hdr2_boot.sh" "$TREE/arch/arm64/boot/Image" \
    "$ROOT/out/cpu-test/restore-ramdisk.gz" "$TREE/bringup-guacamole.dtb" "$OUT/boot.img"
cp "$TREE/bringup-guacamole.dtb" "$TREE/.config" "$TREE/include/generated/utsrelease.h" \
    "$TREE/include/generated/utsversion.h" "$OUT/"
(cd "$OUT" && sha256sum boot.img bringup-guacamole.dtb .config utsrelease.h utsversion.h \
    power/power_support.ko build.log > SHA256SUMS)
