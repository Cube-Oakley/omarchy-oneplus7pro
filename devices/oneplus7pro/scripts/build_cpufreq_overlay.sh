#!/usr/bin/env bash
# Build-only: the runtime overlay module that enables CPU frequency scaling
# (qcom-cpufreq-hw) on the running #188-#190 native5 kernel. Deploys nothing.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/cpufreq-overlay"
OUT="$ROOT/out/power/cpufreq"
SRC="$ROOT/kernel/power"
rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"
dtc -@ -I dts -O dtb "$SRC/guacamole-cpufreq.dts" -o "$OUT/cpufreq.dtbo"
fdtoverlay -i "$ROOT/out/checkpoints/20260923-kernel190/bringup-guacamole.dtb" \
    -o "$WORK/merged-check.dtb" "$OUT/cpufreq.dtbo"
cp "$SRC/cpufreq_overlay.c" "$WORK/"
python3 - "$OUT/cpufreq.dtbo" "$WORK/cpufreq_dtbo.h" <<'PY'
from pathlib import Path
import sys
blob = Path(sys.argv[1]).read_bytes()
Path(sys.argv[2]).write_text('static const unsigned char cpufreq_dtbo[] __aligned(8) = {\n'
                             + ','.join(map(str, blob)) + '\n};\n')
PY
printf 'obj-m += guacamole_cpufreq.o\nguacamole_cpufreq-y := cpufreq_overlay.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/guacamole_cpufreq.ko" "$OUT/"
(cd "$OUT" && sha256sum guacamole_cpufreq.ko cpufreq.dtbo > SHA256SUMS)
