#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL=${CLOCK_KERNEL:-"$ROOT/.work/linux-sm8150-cx-sleep"}
WORK="$ROOT/.work/clock-refs"
OUT=${CLOCK_OUTPUT:-"$ROOT/out/clock-refs"}
mkdir -p "$WORK" "$OUT"
cmp "$KERNEL/.config" "$ROOT/out/checkpoints/20260917-cx-sleep-test/config"
cmp "$KERNEL/include/generated/utsrelease.h" "$ROOT/out/checkpoints/20260917-cx-sleep-test/utsrelease.h"
cp "$ROOT/devices/oneplus7pro/kernel/power/clock_refs.c" "$WORK/"
python3 - "$KERNEL" "$WORK" <<'PY'
from pathlib import Path
import re,sys
kernel,work=map(Path,sys.argv[1:])
source=(kernel/'drivers/clk/clk.c').read_text()
struct=re.findall(r'struct clk_core \{.*?\n\};',source,re.S)
assert len(struct)==1
(work/'clock-layout.h').write_text(struct[0]+'\n')
providers=[
 ('qcom,gcc-sm8150','gcc-sm8150.c','gcc_sm8150_clocks','qcom,gcc-sm8150.h'),
 ('qcom,sm8150-dispcc','dispcc-sm8250.c','disp_cc_sm8250_clocks','qcom,dispcc-sm8150.h'),
 ('qcom,sm8150-gpucc','gpucc-sm8150.c','gpu_cc_sm8150_clocks','qcom,gpucc-sm8150.h'),
 ('qcom,sm8150-rpmh-clk','clk-rpmh.c','sm8150_rpmh_clocks','qcom,rpmh.h')]
parts=[];specs=[]
for i,(compat,file,array,binding) in enumerate(providers):
 source=(kernel/'drivers/clk/qcom'/file).read_text()
 match=re.findall(re.escape(array)+r'\[\] = \{(.*?)\n\};',source,re.S)
 assert len(match)==1,array
 names=re.findall(r'\[(\w+)\]\s*=',match[0])
 if compat == 'qcom,sm8150-dispcc':
  # The shared SM8250 table explicitly removes three divider clocks on SM8150.
  branch=source.split('/* Apply differences for SM8150 and SM8350 */',1)[1].split('} else if',1)[0]
  removed=re.findall(re.escape(array)+r'\[(\w+)\] = NULL;',branch)
  assert set(removed)=={'DISP_CC_MDSS_DP_LINK1_DIV_CLK_SRC',
                        'DISP_CC_MDSS_DP_LINK_DIV_CLK_SRC',
                        'DISP_CC_MDSS_EDP_LINK_DIV_CLK_SRC'}
  names=[n for n in names if n not in removed]
 defines=dict(re.findall(r'^#define\s+(\w+)\s+(\d+)\s*$',(kernel/'include/dt-bindings/clock'/binding).read_text(),re.M))
 ids=sorted({int(defines[n]) for n in names})
 assert len(ids)==len(names)
 parts.append('static const unsigned int ids%d[] = {%s};'%(i,','.join(map(str,ids))))
 specs.append('{"%s", ids%d, ARRAY_SIZE(ids%d)}'%(compat,i,i))
 print(compat,len(ids),'clocks')
parts.append('static const unsigned int dsi_ids[] = {0,1};')
specs.append('{"qcom,dsi-phy-7nm-8150", dsi_ids, ARRAY_SIZE(dsi_ids)}')
parts.append('static const struct provider_spec providers[] = {\n'+',\n'.join(specs)+'\n};')
(work/'clock-providers.h').write_text('\n'.join(parts)+'\n')
PY
printf 'obj-m += clock_refs.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/clock_refs.ko" "$WORK/clock-layout.h" "$WORK/clock-providers.h" "$OUT/"
modinfo -F vermagic "$OUT/clock_refs.ko"
(cd "$OUT" && sha256sum clock_refs.ko clock-layout.h clock-providers.h > SHA256SUMS)
