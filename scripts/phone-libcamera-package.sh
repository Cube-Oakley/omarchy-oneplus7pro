#!/usr/bin/env bash
# Runs on the host: builds the libcamera-guacamole pacman package on the
# phone (as nobody; makepkg refuses root) from
# devices/oneplus7pro/camera/libcamera, and with "install" replaces Arch's
# libcamera, libcamera-ipa and libcamera-tools with it.
# Rollback on the phone: pacman -Rdd libcamera-guacamole, then pacman -U the
# cached /var/cache/pacman/pkg/libcamera{,-ipa,-tools}-0.7.2-4 packages.
# Twice the phone crashed into 05c6:900e while a build kept every core busy
# with the camera stack loaded (once streaming, once idle under PipeWire), so
# this refuses to build with the stack loaded and builds with four jobs at
# lower priority. See docs/camera-20260922.md.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
SRC="$ROOT/devices/oneplus7pro/camera/libcamera"
TARBALL="$ROOT/.work/libcamera/libcamera-v0.7.2.tar.gz"
PHONE="$ROOT/scripts/phone-ssh.sh"
# nobody cannot enter /root, so the package builds under /var/tmp.
DIR=/var/tmp/libcamera-pkg
[[ -s $TARBALL ]] || { echo "fetch the tarball first (scripts/build_libcamera_on_phone.sh does)" >&2; exit 1; }
if bash "$PHONE" '[[ -d /sys/module/camcc_sm8150 || -d /sys/module/qcom_camss ]]'; then
    echo "The camera stack is loaded; reboot the phone before building." >&2
    exit 1
fi
# Straight after boot the phone's clock reads 1970 until the network sets it,
# and meson fails on sources dated in the future.
for attempt in $(seq 1 60); do
    [[ $(bash "$PHONE" 'date +%Y') -ge 2026 ]] && break
    sleep 5
done
tar czf - -C "$SRC" PKGBUILD imx586.yaml $(cd "$SRC" && ls 00*.patch) -C "$(dirname "$TARBALL")" "$(basename "$TARBALL")" |
    bash "$PHONE" "set -e; rm -rf $DIR; mkdir -p $DIR; tar xzf - -C $DIR; chown -R nobody: $DIR
        cd $DIR && nice -n 10 runuser -u nobody -- env HOME=$DIR BUILD_JOBS=4 makepkg -f --noconfirm 2>&1 | tail -5
        ls $DIR/*.pkg.tar.* && sync"
if [[ ${1:-} == install ]]; then
    bash "$PHONE" "set -e; pacman -Q libcamera-guacamole 2>/dev/null ||
            pacman -Rdd --noconfirm libcamera libcamera-ipa libcamera-tools
        pacman -U --noconfirm $DIR/libcamera-guacamole-*.pkg.tar.*; sync"
fi
