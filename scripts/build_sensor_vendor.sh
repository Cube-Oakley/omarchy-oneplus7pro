#!/usr/bin/env bash
# Build-only: the stock files the sensor DSP reads through hexagonrpcd, taken
# unmodified from the images this phone last ran (docs/sensors-20260924.md):
# vendor.img from the LineageOS 23.2 package (OnePlus's sensor configuration,
# which LineageOS carries), dsp.img from the OxygenOS 12 H.41 firmware:
#   sensors/config/       vendor /etc/sensors/config (the 65 JSON, byte-exact)
#   sensors/sns_reg.conf  vendor /etc/sensors/sns_reg_config
#   dsp/sdsp/             dsp partition /sdsp (the SLPI skeleton libraries)
# The registry and socinfo are added on the phone (phone-sensors-test.sh tree):
# the registry comes from persist, which holds per-device data and stays there.
# Output: out/sensors/vendor-tree/. Deploys nothing.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
IMAGES="$ROOT/.work/firmware/payload-out"
OUT="$ROOT/out/sensors/vendor-tree"
rm -rf "$OUT"
mkdir -p "$OUT/sensors" "$OUT/dsp"
dump() {  # dump IMAGE PATH DEST: debugfs cannot chown as a user; that is harmless.
    debugfs -R "rdump $2 $3" "$1" 2>&1 | grep -v -E '^debugfs|while changing ownership' || true
    [[ -e $3/$(basename "$2") ]]
}
dump "$IMAGES/vendor.img" /etc/sensors/config "$OUT/sensors"
dump "$IMAGES/vendor.img" /etc/sensors/sns_reg_config "$OUT/sensors"
mv "$OUT/sensors/sns_reg_config" "$OUT/sensors/sns_reg.conf"
dump "$IMAGES/dsp.img" /sdsp "$OUT/dsp"
chmod -R u+rwX,go+rX "$OUT"
[[ $(ls "$OUT/sensors/config" | wc -l) == 65 && $(ls "$OUT/dsp/sdsp" | wc -l) == 17 ]]
(cd "$OUT" && find . -type f ! -name SHA256SUMS -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' sha256sum > SHA256SUMS)
wc -l < "$OUT/SHA256SUMS"
