#!/usr/bin/env bash
# Isolated native5 diagnostic; same module ABI, frozen DT/initramfs and defaults.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="$ROOT/.work/linux-sm8150-codex-suspend"
SRC="$ROOT/.work/linux-sm8150-mss-handoff"
OUT="$ROOT/out/mss-handoff-test"
FROZEN="$ROOT/out/checkpoints/20260917-native5-test"
mkdir -p "$OUT"
if [[ ! -d "$SRC" ]]; then
    cp -a --reflink=auto "$BASE" "$SRC"
fi
cmp "$BASE/.config" "$FROZEN/config"
cmp "$SRC/.config" "$BASE/.config"
cmp "$SRC/bringup-guacamole.dtb" "$FROZEN/embedded.dtb"
cmp "$SRC/bringup.cpio" "$BASE/bringup.cpio"
cp "$ROOT/kernel/power/rpmhpd-mss-test.h" "$SRC/drivers/pmdomain/qcom/"
python3 - "$BASE" "$SRC" "$OUT" <<'PY'
from pathlib import Path
import difflib, sys
base, src, out = map(Path, sys.argv[1:])
rel = 'drivers/pmdomain/qcom/rpmhpd.c'
old = (base / rel).read_text()
new = old
for before, after in (
 ('static int rpmhpd_aggregate_corner(struct rpmhpd *pd, unsigned int corner)\n{',
  '#include "rpmhpd-mss-test.h"\n\nstatic int rpmhpd_aggregate_corner(struct rpmhpd *pd, unsigned int corner)\n{'),
 ('if (pd->state_synced) {', 'if (pd->state_synced || (pd == &mss && mss_test_release)) {'),
 ('return of_genpd_add_provider_onecell(pdev->dev.of_node, data);',
  'ret = of_genpd_add_provider_onecell(pdev->dev.of_node, data);\n\tif (!ret)\n\t\tmss_test_init(dev);\n\treturn ret;')):
    assert new.count(before) == 1, before
    new = new.replace(before, after)
(src / rel).write_text(new)
(out / 'rpmhpd.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True), new.splitlines(True), fromfile='a/'+rel, tofile='b/'+rel)))
PY
make -C "$SRC" ARCH=arm64 LLVM=1 -j"${JOBS:-8}" Image
cmp "$SRC/include/generated/utsrelease.h" "$BASE/include/generated/utsrelease.h"
cmp "$SRC/vmlinux.symvers" "$BASE/vmlinux.symvers"
cmp "$SRC/bringup.cpio" "$BASE/bringup.cpio"
cmp "$SRC/bringup-guacamole.dtb" "$FROZEN/embedded.dtb"
BOOT_CMDLINE=$(fdtget -ts "$FROZEN/embedded.dtb" /chosen bootargs) \
    bash "$ROOT/scripts/pack_hdr2_boot.sh" "$SRC/arch/arm64/boot/Image" \
    "$ROOT/out/cpu-test/restore-ramdisk.gz" "$FROZEN/embedded.dtb" "$OUT/boot.img"
cp "$ROOT/kernel/power/rpmhpd-mss-test.h" "$OUT/"
cp "$SRC/.config" "$OUT/config"
cp "$SRC/include/generated/utsrelease.h" "$OUT/"
(cd "$OUT" && sha256sum boot.img config rpmhpd.patch rpmhpd-mss-test.h utsrelease.h > SHA256SUMS)
