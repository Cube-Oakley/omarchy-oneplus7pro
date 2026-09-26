#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL="${KERNEL_TREE:-$ROOT/.work/linux-sm8150-codex-native}"
WORK="$ROOT/.work/charger-snapshot"
OUT="$ROOT/out/charger-snapshot"
mkdir -p "$WORK" "$OUT"
cp "$ROOT/kernel/power/charger_snapshot.c" "$WORK/"
printf 'obj-m += charger_snapshot.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/charger_snapshot.ko" "$OUT/"
sha256sum "$OUT/charger_snapshot.ko" > "$OUT/SHA256SUMS"
