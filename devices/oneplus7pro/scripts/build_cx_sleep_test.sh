#!/usr/bin/env bash
# Sleep-only CX diagnostic from the frozen working native5 source, not MSS trial.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="$ROOT/.work/linux-sm8150-codex-suspend"
SRC="$ROOT/.work/linux-sm8150-cx-sleep"
OUT="$ROOT/out/cx-sleep-test"
FROZEN="$ROOT/out/checkpoints/20260917-native5-test"
mkdir -p "$OUT"
if [[ ! -d "$SRC" ]]; then
    cp -a --reflink=auto "$BASE" "$SRC"
fi
cmp "$BASE/.config" "$FROZEN/config"
cmp "$SRC/.config" "$BASE/.config"
cmp "$SRC/bringup-guacamole.dtb" "$FROZEN/embedded.dtb"
cmp "$SRC/bringup.cpio" "$BASE/bringup.cpio"
cp "$ROOT/kernel/power/rpmhpd-cx-sleep-test.h" "$SRC/drivers/pmdomain/qcom/"
python3 - "$BASE" "$SRC" "$OUT" <<'PY'
from pathlib import Path
import difflib, sys
base, src, out = map(Path, sys.argv[1:])
rel = 'drivers/pmdomain/qcom/rpmhpd.c'
old = (base / rel).read_text()
new = old
for before, after in (
 ('static int rpmhpd_aggregate_corner(struct rpmhpd *pd, unsigned int corner)\n{',
  '#include "rpmhpd-cx-sleep-test.h"\n\nstatic int rpmhpd_aggregate_corner(struct rpmhpd *pd, unsigned int corner)\n{'),
 ('\n\tif (peer && peer->enabled) {',
  '\n\tif (cx_sleep_test_release && !pd->state_synced && cx_sleep_test_domain(pd))\n\t\tthis_sleep_corner = pd->active_only ? 0 : corner;\n\n\tif (peer && peer->enabled) {'),
 ('return of_genpd_add_provider_onecell(pdev->dev.of_node, data);',
  'ret = of_genpd_add_provider_onecell(pdev->dev.of_node, data);\n\tif (!ret)\n\t\tcx_sleep_test_init(dev);\n\treturn ret;')):
    assert new.count(before) == 1, before
    new = new.replace(before, after)
assert 'mss_test_release' not in new
(src / rel).write_text(new)
(out / 'rpmhpd.patch').write_text(''.join(difflib.unified_diff(old.splitlines(True), new.splitlines(True), fromfile='a/'+rel, tofile='b/'+rel)))
PY
make -C "$SRC" ARCH=arm64 LLVM=1 KBUILD_BUILD_VERSION=186 -j"${JOBS:-8}" Image
cmp "$SRC/include/generated/utsrelease.h" "$BASE/include/generated/utsrelease.h"
cmp "$SRC/vmlinux.symvers" "$BASE/vmlinux.symvers"
cmp "$SRC/bringup.cpio" "$BASE/bringup.cpio"
cmp "$SRC/bringup-guacamole.dtb" "$FROZEN/embedded.dtb"
BOOT_CMDLINE=$(fdtget -ts "$FROZEN/embedded.dtb" /chosen bootargs) \
    bash "$ROOT/scripts/pack_hdr2_boot.sh" "$SRC/arch/arm64/boot/Image" \
    "$ROOT/out/cpu-test/restore-ramdisk.gz" "$FROZEN/embedded.dtb" "$OUT/boot.img"
cp "$ROOT/kernel/power/rpmhpd-cx-sleep-test.h" "$OUT/"
cp "$SRC/.config" "$OUT/config"
cp "$SRC/include/generated/utsrelease.h" "$OUT/"
(cd "$OUT" && sha256sum boot.img config rpmhpd.patch rpmhpd-cx-sleep-test.h utsrelease.h > SHA256SUMS)
