#!/usr/bin/env bash
# Build the narrow radio dependency set against the exact prepared kernel.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL="${KERNEL_TREE:-$ROOT/.work/linux-sm8150-codex-wifi}"
WORK="${RADIO_MODULE_WORK:-$ROOT/.work/radio-modules}"
OUT="${RADIO_MODULE_OUT:-$ROOT/out/wifi-desktop-test/modules}"
mkdir -p "$WORK" "$OUT"
symbols="$KERNEL/vmlinux.symvers"
for item in lib/crypto net/rfkill net/wireless net/mac80211 drivers/rpmsg net/qrtr drivers/remoteproc drivers/soc/qcom drivers/net/wireless/ath; do
    name=${item##*/}
    mkdir -p "$WORK/$name"
    cp -a "$KERNEL/$item/." "$WORK/$name/"
    case "$name" in
        crypto)
            printf 'obj-m += libarc4.o\nlibarc4-y := arc4.o\n' > "$WORK/$name/Makefile" ;;
        remoteproc)
            printf 'obj-m += qcom_pil_info.o qcom_common.o qcom_q6v5.o qcom_q6v5_pas.o qcom_sysmon.o\n' > "$WORK/$name/Makefile" ;;
        qcom)
            printf 'obj-m += qcom_pd_mapper.o\n' > "$WORK/$name/Makefile" ;;
        ath)
            if [[ ${RADIO_KEY_ACK:-0} == 1 ]]; then
                patch -d "$WORK/$name" -p1 < \
                    "$ROOT/devices/oneplus7pro/kernel/radio/ath10k-snoc-key-ack.patch"
            fi ;;
    esac
    make -C "$KERNEL" ARCH=arm64 LLVM=1 -j"${JOBS:-8}" M="$WORK/$name" \
        KBUILD_EXTRA_SYMBOLS="$symbols" CONFIG_QRTR_MHI=n CONFIG_RPMSG_MTK_SCP=n \
        CONFIG_ATH5K=n CONFIG_ATH9K_HW=n CONFIG_CARL9170=n CONFIG_ATH6KL=n \
        CONFIG_AR5523=n CONFIG_WIL6210=n CONFIG_WCN36XX=n CONFIG_ATH11K=n \
        CONFIG_ATH12K=n CONFIG_ATH10K_SDIO=n CONFIG_ATH10K_PCI=n modules
    symbols="$symbols $WORK/$name/Module.symvers"
    find "$WORK/$name" -name '*.ko' -exec cp '{}' "$OUT/" \;
done
(cd "$OUT" && sha256sum ./*.ko > SHA256SUMS)
