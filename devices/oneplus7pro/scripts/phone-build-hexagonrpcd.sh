#!/usr/bin/env bash
# Build hexagonrpcd 0.4.0 with the 7T Pro port's patches
# (devices/oneplus7pro/adapter/sensors/hexagonrpcd/) on the phone, verbose, so its log
# records every file the sensor DSP opens. Installs only into
# /root/sensors-bringup/{bin,lib}. See docs/sensors-20260924.md.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
WORK="$ROOT/.work/hexagonrpc"
TARBALL="$WORK/v0.4.0.tar.gz"
SHA512=18ebe4beeed97018243bec5043b8395c07c76f1174085e41a32648fd481485076fefffa091700ca1f72163687405456e5537aa538bc4f08fecacb3f83e3a82d8
mkdir -p "$WORK"
[[ -s $TARBALL ]] || curl -sSL -o "$TARBALL" https://github.com/linux-msm/hexagonrpc/archive/refs/tags/v0.4.0.tar.gz
echo "$SHA512  $TARBALL" | sha512sum -c --quiet
tar -C "$WORK" -cf - v0.4.0.tar.gz -C "$ROOT/adapter/sensors/hexagonrpcd" . |
    bash "$ROOT/scripts/phone-ssh.sh" "set -euo pipefail
if [[ -d /sys/module/camcc_sm8150 || -d /sys/module/qcom_camss ]]; then
    echo 'The camera stack is loaded; reboot the phone before building.' >&2; exit 1
fi
B=/root/sensors-bringup
rm -rf \$B/hexagonrpcd/build-src
mkdir -p \$B/hexagonrpcd/build-src \$B/bin \$B/lib
cd \$B/hexagonrpcd/build-src
tar xf -
echo '$SHA512  v0.4.0.tar.gz' | sha512sum -c --quiet
mkdir src
tar xzf v0.4.0.tar.gz -C src --strip-components=1
for p in 000*.patch; do patch -s -p1 -d src < \$p; done
cd src
meson setup ../build -Dc_args=-DHEXAGONRPC_VERBOSE -Dc_link_args=-Wl,-rpath,\$B/lib >/dev/null
nice -n 10 meson compile -C ../build -j4 >/dev/null
cp -a ../build/libhexagonrpc/libhexagonrpc.so* \$B/lib/
install -m 755 ../build/hexagonrpcd/hexagonrpcd \$B/bin/hexagonrpcd
ldd \$B/bin/hexagonrpcd | grep hexagonrpc"
