#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
K="$ROOT/mainline/linux"
export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-
cd "$K"
make defconfig
# Merge extra options. olddefconfig drops unknown keys instead of prompting.
# The fragment names this workspace as @PIXEL_ROOT@; fill it in for this checkout.
FRAGMENT="$(mktemp)"
trap 'rm -f "$FRAGMENT"' EXIT
sed "s#@PIXEL_ROOT@#$ROOT#g" "$ROOT/mainline/kconfig.fragment" > "$FRAGMENT"
scripts/kconfig/merge_config.sh -m .config "$FRAGMENT"
make olddefconfig
make -j"$(nproc)" Image
ls -lh arch/arm64/boot/Image
