#!/usr/bin/env bash
# Build the unmodified, read-only Qualcomm sleep statistics driver for native5.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-codex-suspend"
WORK="$ROOT/.work/sleep-stats"
OUT="$ROOT/out/sleep-stats"
mkdir -p "$WORK" "$OUT"
cp "$KERNEL/drivers/soc/qcom/qcom_stats.c" "$WORK/"
printf 'obj-m += qcom_stats.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/qcom_stats.ko" "$OUT/"
modinfo -F vermagic "$OUT/qcom_stats.ko"
(cd "$OUT" && sha256sum qcom_stats.ko > SHA256SUMS)
