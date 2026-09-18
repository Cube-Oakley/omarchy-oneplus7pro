#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL="${KERNEL_TREE:-$ROOT/.work/linux-sm8150-codex-native}"
WORK="$ROOT/.work/charger-trial"
OUT="$ROOT/out/charger-trial"
mkdir -p "$WORK" "$OUT"
cp "$ROOT/devices/oneplus7pro/kernel/power/charger_trial.c" "$WORK/"
printf 'obj-m += charger_trial.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/charger_trial.ko" "$OUT/"
sha256sum "$OUT/charger_trial.ko" > "$OUT/SHA256SUMS"
