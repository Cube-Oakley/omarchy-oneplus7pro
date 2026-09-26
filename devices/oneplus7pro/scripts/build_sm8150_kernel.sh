#!/usr/bin/env bash
# Rebuild linux-postmarketos-qcom-sm8150 6.17 with RAID6 benchmark off.
# That initcall is the first known direct-boot hang on SM8150 phones.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.work/linux-sm8150"
PM="$ROOT/.work/pmaports/device/testing/linux-postmarketos-qcom-sm8150"
OUT="$ROOT/out/kernel-raid6fix"
TAG=v6.17.0-sm8150
JOBS="$(nproc)"

mkdir -p "$ROOT/.work" "$OUT"
if [ ! -d "$SRC/.git" ]; then
  git clone --depth=1 --branch "$TAG" https://gitlab.com/sm8150-mainline/linux.git "$SRC" \
    || git clone --depth=1 --branch "$TAG" https://gitlab.postmarketos.org/soc/qualcomm-sm8150/linux.git "$SRC"
fi
cd "$SRC"
git checkout --force "$TAG" 2>/dev/null || true
# device patches that apply to this tree
for p in "$PM"/000*.patch; do
  echo "patch $p"
  git apply --check "$p" 2>/dev/null && git apply "$p" || patch -p1 --forward --reject-file=- < "$p" || true
done
cp "$PM/config-postmarketos-qcom-sm8150.aarch64" .config
./scripts/config --disable RAID6_PQ_BENCHMARK
./scripts/config --enable QCOM_WDT
make ARCH=arm64 LLVM=1 olddefconfig
make ARCH=arm64 LLVM=1 -j"$JOBS" Image.gz dtbs
install -D arch/arm64/boot/Image.gz "$OUT/Image.gz"
install -D arch/arm64/boot/dts/qcom/sm8150-oneplus-guacamole.dtb "$OUT/sm8150-oneplus-guacamole.dtb"
ls -lh "$OUT"
echo DONE_KERNEL
