#!/usr/bin/env bash
# Structural check of the shipped ramdisk Hyprland pin + Lua config.
# Fails if Aquamarine can still pick the GPU-only DRM node, or if we ship .conf.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fail() { echo "FAIL: $*" >&2; exit 1; }

INIT="$ROOT/.work/initramfs-root/init"
RUN="$ROOT/.work/initramfs-root/hypr/run-hypr.sh"
LUA="$ROOT/.work/initramfs-root/hypr/hyprland.lua"
SCRIPTS_INIT="$ROOT/scripts/initramfs/init"

[ -f "$INIT" ] || fail "missing $INIT"
[ -f "$RUN" ] || fail "missing $RUN"
[ -f "$LUA" ] || fail "missing $LUA"

grep -q 'AQ_DRM_DEVICES=/dev/dri/card0' "$RUN" \
	|| fail "run-hypr.sh must pin AQ_DRM_DEVICES to simpledrm card0"
grep -q 'hyprland.lua' "$RUN" \
	|| fail "run-hypr.sh must launch a Lua config"
grep -q 'GALLIUM_DRIVER=llvmpipe' "$RUN" \
	|| fail "run-hypr.sh must use llvmpipe on simpledrm"
if grep -q 'GALLIUM_DRIVER=freedreno' "$RUN"; then
	fail "run-hypr.sh must not select freedreno while msm DRM has no CRTC"
fi

grep -q 'hl.config' "$LUA" || fail "hyprland.lua is not a Hyprland 0.56 Lua config"
grep -q 'disable_hyprland_logo' "$LUA" || fail "hyprland.lua must disable the logo"
grep -q 'hl.bind' "$LUA" || fail "hyprland.lua must register binds (0.56 errors if none load)"
if grep -q 'hl.on(' "$LUA"; then
	fail "hyprland.lua must not use hl.on at file top (aborts before binds on 0.56)"
fi
if grep -E '^[A-Za-z0-9_]+ *=' "$LUA" | grep -vq '^--'; then
	# hyprlang assignments belong in .conf, not lua
	:
fi
if grep -q 'disable_hyprland_logo *= *false' "$LUA"; then
	fail "logo must stay disabled"
fi

grep -q 'cp /hypr/run-hypr.sh' "$INIT" || fail "init must install /hypr/run-hypr.sh onto the rootfs"
grep -q 'hyprland.lua' "$INIT" || fail "init must install hyprland.lua onto the rootfs"
grep -q '/root/run-hypr.sh' "$INIT" || fail "init must still launch /root/run-hypr.sh"
grep -q 'swaybg' "$INIT" || fail "init must start swaybg (hyprpaper GBM/PRIME fails on simpledrm)"
grep -q 'tmpfs tmpfs /dev/shm' "$INIT" || fail "init must mount /dev/shm for swaybg buffers"

USB="$ROOT/.work/linux-sm8150/arch/arm64/kernel/bringup_usb.c"
DTS="$ROOT/.work/linux-sm8150/arch/arm64/boot/dts/qcom/sm8150-oneplus-guacamole.dts"
[ -f "$USB" ] || fail "missing $USB"
grep -q 'bringup_dpu_dwork' "$USB" || fail "bringup_usb.c must delay-enable DPU"
grep -q '120 \* HZ' "$USB" || fail "DPU enable must wait until USB+Hyprland+GPU are up"
grep -q 'qcom,sm8150-dispcc' "$USB" || fail "DPU work must enable dispcc"
grep -q 'bringup_status_okay' "$USB" || fail "DSI/phy must be marked okay before MDSS populate"
MSM="$ROOT/.work/linux-sm8150/drivers/gpu/drm/msm/msm_drv.c"
grep -q 'return -EPROBE_DEFER' "$MSM" || fail "msm_drv_probe must defer on NULL component match"
if grep -A20 '&dispcc {' "$DTS" | grep -q 'usb_1_qmpphy'; then
	fail "dispcc must not depend on disabled USB QMP PHY (fw_devlink parks probe)"
fi
grep -q 'oneplus,guacamole-panel' "$DTS" || fail "DTS must include a DSI panel so msm_dsi can attach"
grep -q 'oneplus,guacamole-panel' "$ROOT/.work/linux-sm8150/drivers/gpu/drm/panel/panel-simple.c" \
	|| fail "panel-simple must know oneplus,guacamole-panel"
grep -q '^CONFIG_DRM_PANEL_SIMPLE=y' "$ROOT/.work/linux-sm8150/.config" \
	|| fail "panel-simple must be built-in (not a module)"
if grep -q 'wait for a real render node' "$INIT"; then
	fail "init must not wait for GPU renderD128 before starting Hyprland"
fi
if grep -A2 'while .*renderD128' "$INIT" | grep -q 'sleep'; then
	fail "init still waits on renderD128 before Hyprland"
fi

# Keep the documented copy in sync with the baked ramdisk.
diff -u "$SCRIPTS_INIT" "$INIT" >/dev/null \
	|| fail "scripts/initramfs/init drifted from .work/initramfs-root/init"
diff -u "$ROOT/scripts/initramfs/run-hypr.sh" "$RUN" >/dev/null \
	|| fail "scripts/initramfs/run-hypr.sh drifted from ramdisk"
diff -u "$ROOT/scripts/initramfs/hyprland.lua" "$LUA" >/dev/null \
	|| fail "scripts/initramfs/hyprland.lua drifted from ramdisk"

echo "PASS: simpledrm KMS pin + Lua Hyprland config"
