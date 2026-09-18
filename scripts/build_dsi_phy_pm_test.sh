#!/usr/bin/env bash
# Balance the DSI PHY iface clock's prepare reference across runtime suspend.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="$ROOT/.work/linux-sm8150-cx-sleep"
SRC="$ROOT/.work/linux-sm8150-dsi-phy-pm"
OUT="$ROOT/out/dsi-phy-pm-test"
FROZEN="$ROOT/out/checkpoints/20260917-native5-test"
mkdir -p "$OUT"
if [[ ! -d "$SRC" ]]; then
    cp -a --reflink=auto "$BASE" "$SRC"
fi
cmp "$BASE/.config" "$ROOT/out/checkpoints/20260917-cx-sleep-test/config"
cmp "$SRC/.config" "$BASE/.config"
python3 - "$BASE" "$SRC" "$OUT" "$ROOT" <<'PY'
from pathlib import Path
import difflib,sys
base,src,out,root=map(Path,sys.argv[1:])
patch=[]
for rel in ('drivers/gpu/drm/msm/dsi/phy/dsi_phy.c','drivers/gpu/drm/msm/dsi/phy/dsi_phy.h'):
 old=(base/rel).read_text();new=old
 if rel.endswith('.h'):
  before='\tbool state_saved;\n};'
  assert new.count(before)==1
  new=new.replace(before,'\tbool state_saved;\n\tstruct clk *iface_clk;\n};')
 else:
  new=new.replace('#include <linux/pm_clock.h>','#include <linux/clk.h>')
  before='''	ret = devm_pm_runtime_enable(dev);
	if (ret)
		return ret;

	ret = devm_pm_clk_create(dev);
	if (ret)
		return ret;

	ret = pm_clk_add(dev, "iface");
	if (ret < 0)
		return dev_err_probe(dev, ret, "Unable to get iface clk\\n");'''
  after='''	phy->iface_clk = devm_clk_get(dev, "iface");
	if (IS_ERR(phy->iface_clk))
		return dev_err_probe(dev, PTR_ERR(phy->iface_clk),
				     "Unable to get iface clk\\n");

	ret = devm_pm_runtime_enable(dev);
	if (ret)
		return ret;'''
  assert new.count(before)==1
  new=new.replace(before,after)
  before='''static const struct dev_pm_ops dsi_phy_pm_ops = {
	SET_RUNTIME_PM_OPS(pm_clk_suspend, pm_clk_resume, NULL)
};'''
  after='''static int __maybe_unused dsi_phy_runtime_suspend(struct device *dev)
{
	struct msm_dsi_phy *phy = dev_get_drvdata(dev);

	/* Dropping enable alone leaves RPMh parents prepared and voting for XO. */
	clk_disable_unprepare(phy->iface_clk);
	return 0;
}

static int __maybe_unused dsi_phy_runtime_resume(struct device *dev)
{
	struct msm_dsi_phy *phy = dev_get_drvdata(dev);

	return clk_prepare_enable(phy->iface_clk);
}

static const struct dev_pm_ops dsi_phy_pm_ops = {
	SET_RUNTIME_PM_OPS(dsi_phy_runtime_suspend, dsi_phy_runtime_resume, NULL)
};'''
  assert new.count(before)==1
  new=new.replace(before,after)
 (src/rel).write_text(new)
 patch.extend(difflib.unified_diff(old.splitlines(True),new.splitlines(True),fromfile='a/'+rel,tofile='b/'+rel))
(out/'dsi-phy-pm.patch').write_text(''.join(patch))
(root/'devices/oneplus7pro/kernel/power/dsi-phy-pm.patch').write_text(''.join(patch))
PY
make -C "$SRC" ARCH=arm64 LLVM=1 KBUILD_BUILD_VERSION=187 -j"${JOBS:-8}" Image
cmp "$SRC/include/generated/utsrelease.h" "$BASE/include/generated/utsrelease.h"
cmp "$SRC/vmlinux.symvers" "$BASE/vmlinux.symvers"
cmp "$SRC/bringup.cpio" "$BASE/bringup.cpio"
cmp "$SRC/bringup-guacamole.dtb" "$FROZEN/embedded.dtb"
cmp "$SRC/drivers/pmdomain/qcom/rpmhpd.c" "$BASE/drivers/pmdomain/qcom/rpmhpd.c"
cmp "$SRC/drivers/pmdomain/qcom/rpmhpd-cx-sleep-test.h" "$BASE/drivers/pmdomain/qcom/rpmhpd-cx-sleep-test.h"
BOOT_CMDLINE=$(fdtget -ts "$FROZEN/embedded.dtb" /chosen bootargs) \
    bash "$ROOT/scripts/pack_hdr2_boot.sh" "$SRC/arch/arm64/boot/Image" \
    "$ROOT/out/cpu-test/restore-ramdisk.gz" "$FROZEN/embedded.dtb" "$OUT/boot.img"
cp "$SRC/.config" "$OUT/config"
cp "$SRC/include/generated/utsrelease.h" "$SRC/include/generated/utsversion.h" "$OUT/"
(cd "$OUT" && sha256sum boot.img config dsi-phy-pm.patch utsrelease.h utsversion.h > SHA256SUMS)
