#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="${KERNEL_TREE:-$ROOT/.work/linux-sm8150-codex-suspend}"
WORK="$ROOT/.work/rpmh-votes"
OUT="${OUT_DIR:-$ROOT/out/sleep-stats}"
mkdir -p "$WORK" "$OUT"
cp "$ROOT/kernel/power/rpmh_votes.c" "$WORK/"
cp "$KERNEL/drivers/soc/qcom/rpmh-internal.h" "$WORK/"
python3 - "$KERNEL/drivers/soc/qcom/rpmh.c" "$WORK/cache-layout.h" <<'PY'
from pathlib import Path
import re, sys
source = Path(sys.argv[1]).read_text()
structs = []
for name in ('cache_req', 'batch_cache_req'):
    matches = re.findall(r'struct ' + name + r' \{.*?\n\};', source, re.S)
    assert len(matches) == 1, name
    structs.extend(matches)
Path(sys.argv[2]).write_text('\n'.join(structs) + '\n')
PY
printf 'obj-m += rpmh_votes.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/rpmh_votes.ko" "$OUT/"
modinfo -F vermagic "$OUT/rpmh_votes.ko"
(cd "$OUT" && sha256sum rpmh_votes.ko > rpmh-votes.sha256)
