#!/usr/bin/env bash
# Build-only: kernel #193 = #192 (scripts/build_kernel192.sh) with the boot
# DTB's firmware carve-outs moved to guacamole's OEM map (18821
# sm8150-oem.dtsi), which the sensor DSP needs (docs/sensors-20260924.md):
#   video 0x97c00000 (5 MiB), SLPI 0x98100000 (20 MiB), GPU zap 0x99515000,
#   SPSS 0x99600000, CDSP 0x99700000 (20 MiB); the modem, ADSP and IPA
#   regions already match. The staged fillers that covered the old
#   locations go, and 0x99517000-0x99600000, reserved until now, stays so.
# It also adds the FastRPC pool the sensor DSP's buffers come from: 16 MiB,
# reusable, below 4 GB (as the stock tree and the OnePlus 7T Pro port).
# Nothing else changes: same code, config and release string as #192.
# Output: out/checkpoints/20260924-kernel193/.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
BASE="$ROOT/.work/linux-sm8150-192"
TREE="$ROOT/.work/linux-sm8150-193"
OUT="$ROOT/out/checkpoints/20260924-kernel193"
DTB="$TREE/bringup-guacamole.dtb"
RM=/reserved-memory
[[ -d $BASE ]] || bash "$ROOT/scripts/build_kernel192.sh"
rm -rf "$TREE" "$OUT"
mkdir -p "$OUT"
cp -a --reflink=auto "$BASE" "$TREE"

# region NODE BASE SIZE: move a reservation, keeping its phandle and users.
region() {
    fdtput -t x "$DTB" "$RM/$1" reg 0 "$2" 0 "$3"
    fdtput -t s "$DTB" "$RM/$1" status okay
}
region memory@96e00000 97c00000 500000     # video
region memory@97300000 98100000 1400000    # SLPI (remoteproc@2400000)
region memory@98715000 99515000 2000       # GPU zap shader
region memory@98800000 99600000 100000     # SPSS
region memory@98900000 99700000 1400000    # CDSP (remoteproc@8300000)
for node in radio-unused-tail@97c00000 ipa-legacy-hole@98b00000 cdsp-legacy-tail@99515000; do
    fdtput -r "$DTB" "$RM/$node"
done
fdtput -c "$DTB" "$RM/oem-gap@99517000"
fdtput -t x "$DTB" "$RM/oem-gap@99517000" reg 0 99517000 0 e9000
fdtput -t x "$DTB" "$RM/oem-gap@99517000" no-map

pool="$RM/fastrpc-shared-pool"
phandle=$(dtc -I dtb -O dts -q "$DTB" | grep -o 'phandle = <0x[0-9a-f]*>' |
          grep -o '0x[0-9a-f]*' | sort -u | python3 -c 'import sys; print("%x" % (max(int(x, 16) for x in sys.stdin) + 1))')
fdtput -c "$DTB" "$pool"
fdtput -t s "$DTB" "$pool" compatible shared-dma-pool
fdtput -t x "$DTB" "$pool" alloc-ranges 0 0 0 ffffffff
fdtput -t x "$DTB" "$pool" size 0 1000000
fdtput -t x "$DTB" "$pool" reusable
fdtput -t x "$DTB" "$pool" phandle "$phandle"
fdtput -t s "$DTB" /__symbols__ fastrpc_mem "$pool"

# No two enabled static reservations may overlap.
python3 - "$DTB" <<'PY'
import subprocess, sys
dtb = sys.argv[1]
def fdt(*args):
    r = subprocess.run(['fdtget', *args], capture_output=True, text=True)
    return r.stdout.split() if r.returncode == 0 else None
spans = []
for node in fdt('-l', dtb, '/reserved-memory'):
    path = '/reserved-memory/' + node
    status = subprocess.run(['fdtget', '-ts', dtb, path, 'status'], capture_output=True, text=True).stdout.strip()
    reg = fdt('-t', 'x', dtb, path, 'reg')
    if status in ('', 'okay') and reg:
        base = int(reg[0], 16) << 32 | int(reg[1], 16)
        spans.append((base, base + (int(reg[2], 16) << 32 | int(reg[3], 16)), node))
spans.sort()
for a, b in zip(spans, spans[1:]):
    if b[0] < a[1]:
        sys.exit(f'overlap: {a[2]} {a[0]:#x}-{a[1]:#x} and {b[2]} {b[0]:#x}-{b[1]:#x}')
print(f'{len(spans)} reservations, no overlaps')
PY

make -C "$TREE" ARCH=arm64 LLVM=1 KBUILD_BUILD_VERSION=193 -j"${JOBS:-8}" Image > "$OUT/build.log" 2>&1
BOOT_CMDLINE=$(fdtget -ts "$DTB" /chosen bootargs) \
    bash "$ROOT/scripts/pack_hdr2_boot.sh" "$TREE/arch/arm64/boot/Image" \
    "$ROOT/out/cpu-test/restore-ramdisk.gz" "$DTB" "$OUT/boot.img"
cp "$DTB" "$TREE/.config" "$TREE/include/generated/utsrelease.h" \
    "$TREE/include/generated/utsversion.h" "$OUT/"
(cd "$OUT" && sha256sum boot.img bringup-guacamole.dtb .config utsrelease.h utsversion.h build.log > SHA256SUMS)
