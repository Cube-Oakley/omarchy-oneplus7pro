#!/usr/bin/env bash
# Isolated native5 module experiment; never overwrites installed radio modules.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-codex-suspend"
WORK="$ROOT/.work/wifi-key-ack"
OUT="$ROOT/out/wifi-key-ack"
mkdir -p "$WORK" "$OUT"
cp -a "$KERNEL/drivers/net/wireless/ath/." "$WORK/"
patch -d "$WORK" -p1 < "$ROOT/devices/oneplus7pro/kernel/radio/ath10k-snoc-key-ack.patch"
symbols="$KERNEL/vmlinux.symvers $ROOT/.work/native5-radio-modules/wireless/Module.symvers $ROOT/.work/native5-radio-modules/mac80211/Module.symvers $ROOT/.work/native5-radio-modules/remoteproc/Module.symvers"
make -C "$KERNEL" ARCH=arm64 LLVM=1 -j"${JOBS:-8}" M="$WORK" \
    KBUILD_EXTRA_SYMBOLS="$symbols" CONFIG_ATH5K=n CONFIG_ATH9K_HW=n \
    CONFIG_CARL9170=n CONFIG_ATH6KL=n CONFIG_AR5523=n CONFIG_WIL6210=n \
    CONFIG_WCN36XX=n CONFIG_ATH11K=n CONFIG_ATH12K=n \
    CONFIG_ATH10K_SDIO=n CONFIG_ATH10K_PCI=n modules
cp "$WORK/ath10k/ath10k_core.ko" "$WORK/ath10k/ath10k_snoc.ko" "$OUT/"
cp "$ROOT/devices/oneplus7pro/kernel/radio/ath10k-snoc-key-ack.patch" "$OUT/"
for module in "$OUT"/*.ko; do modinfo -F vermagic "$module"; done
(cd "$OUT" && sha256sum ./*.ko ath10k-snoc-key-ack.patch > SHA256SUMS)
