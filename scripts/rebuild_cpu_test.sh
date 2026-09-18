#!/usr/bin/env bash
# Rebuild the isolated, prepared CPU experiment; never flashes the phone.
# See docs/cpu-gpu-work-20260916.md for the snapshot inputs and rollback pair.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/.work/linux-sm8150-codex-cpu"
RAMROOT="${INITRAMFS_ROOT:-$ROOT/.work/codex-cpu-initramfs}"
OUT="$ROOT/out/cpu-test"
TEST_NAME="${CPU_TEST_NAME:-smp2}"
case "$TEST_NAME" in
  ''|*[!a-zA-Z0-9_-]*) echo "Invalid CPU_TEST_NAME" >&2; exit 1 ;;
esac
for input in "$SRC/bringup-guacamole.dtb" "$SRC/.config" \
             "$RAMROOT/init" "$OUT/restore-ramdisk.gz"; do
  [ -s "$input" ] || { echo "Missing prepared input: $input" >&2; exit 1; }
done

python3 - "$RAMROOT" "$SRC/bringup.cpio" <<'PY'
from pathlib import Path
import subprocess, sys
root, archive = map(Path, sys.argv[1:])
paths = ['.'] + [str(p.relative_to(root)) for p in sorted(root.rglob('*'))]
with archive.open('wb') as dest:
    subprocess.run(['cpio', '--null', '-o', '-H', 'newc', '--owner=0:0'],
                   cwd=root, input=('\0'.join(paths) + '\0').encode(),
                   stdout=dest, check=True)
PY
"$SRC/scripts/config" --file "$SRC/.config" --set-str LOCALVERSION "-sm8150-codex-$TEST_NAME"
make -C "$SRC" ARCH=arm64 LLVM=1 olddefconfig
make -C "$SRC" ARCH=arm64 LLVM=1 -j"${JOBS:-4}" Image
BOOT_CMDLINE="$(fdtget "$SRC/bringup-guacamole.dtb" /chosen bootargs)" \
  bash "$ROOT/scripts/pack_hdr2_boot.sh" \
  "$SRC/arch/arm64/boot/Image" "$OUT/restore-ramdisk.gz" \
  "$SRC/bringup-guacamole.dtb" "$OUT/boot-codex-$TEST_NAME.img"
sha256sum "$OUT/boot-codex-$TEST_NAME.img" "$ROOT/out/dtbo-filtered-gpu-sqe.img" \
  > "$OUT/boot-codex-$TEST_NAME.sha256"
cat "$OUT/boot-codex-$TEST_NAME.sha256"
