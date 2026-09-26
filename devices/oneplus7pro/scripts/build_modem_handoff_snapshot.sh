#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-codex-suspend"
WORK="$ROOT/.work/modem-handoff-snapshot"
OUT="$ROOT/out/modem-handoff"
mkdir -p "$WORK" "$OUT"
cp "$ROOT/kernel/power/modem_handoff_snapshot.c" "$WORK/"
cp "$KERNEL/drivers/remoteproc/"{qcom_common.h,qcom_q6v5.h,remoteproc_internal.h} "$WORK/"
python3 - "$KERNEL/drivers/remoteproc/qcom_q6v5_pas.c" "$WORK/pas-layout.h" <<'PY'
import re,sys
from pathlib import Path
source=Path(sys.argv[1]).read_text()
layout=re.findall(r'struct qcom_pas \{.*?\n\};',source,re.S)
assert len(layout)==1
assert '#define MAX_ASSIGN_COUNT 3' in source
Path(sys.argv[2]).write_text('#define MAX_ASSIGN_COUNT 3\n'+layout[0]+'\n')
PY
printf 'obj-m += modem_handoff_snapshot.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" \
    KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/modem_handoff_snapshot.ko" "$OUT/"
modinfo -F vermagic "$OUT/modem_handoff_snapshot.ko"
(cd "$OUT" && sha256sum modem_handoff_snapshot.ko > SHA256SUMS)
