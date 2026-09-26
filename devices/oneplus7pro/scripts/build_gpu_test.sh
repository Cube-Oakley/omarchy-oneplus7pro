#!/usr/bin/env bash
# Cross-build the offscreen test without an ARM graphics development sysroot.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/out/gpu-test"
mkdir -p "$OUT/include"
cp -r /usr/include/EGL /usr/include/GLES2 /usr/include/KHR "$OUT/include/"
"${CC:-aarch64-linux-gnu-gcc}" -O2 -Wall -Wextra -Werror \
  -I"$OUT/include" "$ROOT/scripts/gpu-render-test.c" -ldl \
  -o "$OUT/gpu-render-test"
file "$OUT/gpu-render-test"
