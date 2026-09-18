#!/usr/bin/env bash
# Add an isolated, default-off MMCX SLEEP control to verified #187.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="$ROOT/.work/linux-sm8150-dsi-phy-pm"
SRC="$ROOT/.work/linux-sm8150-mmcx-sleep"
OUT="$ROOT/out/mmcx-sleep-test"
FROZEN="$ROOT/out/checkpoints/20260917-dsi-phy-pm-test"
mkdir -p "$OUT"
if [[ ! -d "$SRC" ]]; then
    cp -a --reflink=auto "$BASE" "$SRC"
fi
cmp "$BASE/.config" "$FROZEN/config"
cmp "$SRC/.config" "$BASE/.config"
cp "$ROOT/devices/oneplus7pro/kernel/power/rpmhpd-mmcx-sleep-test.h" "$SRC/drivers/pmdomain/qcom/"
python3 - "$BASE" "$SRC" "$OUT" <<'PY'
from pathlib import Path
import difflib,sys
base,src,out=map(Path,sys.argv[1:])
rel='drivers/pmdomain/qcom/rpmhpd.c'
old=(base/rel).read_text(); new=old
for before,after in (
 ('#include "rpmhpd-cx-sleep-test.h"', '#include "rpmhpd-cx-sleep-test.h"\n#include "rpmhpd-mmcx-sleep-test.h"'),
 ('\n\tif (peer && peer->enabled) {', '\n\tif (mmcx_sleep_test_release && !pd->state_synced && mmcx_sleep_test_domain(pd))\n\t\tthis_sleep_corner = pd->active_only ? 0 : corner;\n\n\tif (peer && peer->enabled) {'),
 ('\tif (!ret)\n\t\tcx_sleep_test_init(dev);', '\tif (!ret) {\n\t\tcx_sleep_test_init(dev);\n\t\tmmcx_sleep_test_init(dev);\n\t}')):
 assert new.count(before)==1, before
 new=new.replace(before,after)
(src/rel).write_text(new)
(out/'rpmhpd.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/'+rel,tofile='b/'+rel)))
PY
make -C "$SRC" ARCH=arm64 LLVM=1 KBUILD_BUILD_VERSION=188 -j"${JOBS:-8}" Image
for rel in include/generated/utsrelease.h vmlinux.symvers bringup.cpio bringup-guacamole.dtb; do
    cmp "$SRC/$rel" "$BASE/$rel"
done
BOOT_CMDLINE=$(fdtget -ts "$SRC/bringup-guacamole.dtb" /chosen bootargs) \
    bash "$ROOT/scripts/pack_hdr2_boot.sh" "$SRC/arch/arm64/boot/Image" \
    "$ROOT/out/cpu-test/restore-ramdisk.gz" "$SRC/bringup-guacamole.dtb" "$OUT/boot.img"
cp "$SRC/.config" "$OUT/config"
cp "$SRC/include/generated/utsrelease.h" "$SRC/include/generated/utsversion.h" "$OUT/"
cp "$ROOT/devices/oneplus7pro/kernel/power/rpmhpd-mmcx-sleep-test.h" "$OUT/"
(cd "$OUT" && sha256sum boot.img config rpmhpd.patch rpmhpd-mmcx-sleep-test.h utsrelease.h utsversion.h > SHA256SUMS)
