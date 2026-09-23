#!/usr/bin/env bash
# Stock missing CAMCC consumer driver; temporary native5 power-handoff trial.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="${KERNEL_TREE:-$ROOT/.work/linux-sm8150-codex-suspend}"
WORK="$ROOT/.work/camcc-sleep-test"
OUT="${OUT_DIR:-$ROOT/out/sleep-stats}"
mkdir -p "$WORK" "$OUT"
cp "$KERNEL/drivers/clk/qcom/camcc-sm8150.c" "$WORK/"
cp "$KERNEL/drivers/clk/qcom/"*.h "$WORK/"
printf 'obj-m += camcc-sm8150.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/camcc-sm8150.ko" "$OUT/"
modinfo -F vermagic "$OUT/camcc-sm8150.ko"
(cd "$OUT" && sha256sum camcc-sm8150.ko > camcc.sha256)
