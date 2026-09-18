#!/usr/bin/env bash
# Run on Arch ARM against the pinned upstream sources staged in radio-bringup.
set -euo pipefail
SRC="${RADIO_SOURCE:-/root/radio-bringup/src}"
OUT="${RADIO_BIN:-/root/radio-bringup/bin}"
mkdir -p "$OUT"
common=(-O2 -Wall -I"$SRC/qrtr/include")
qrtr=("$SRC"/qrtr/lib/*.c)
cc "${common[@]}" "${qrtr[@]}" "$SRC/qrtr/src/lookup.c" -o "$OUT/qrtr-lookup"
cc "${common[@]}" "${qrtr[@]}" "$SRC/qrtr/src/cfg.c" "$SRC/qrtr/src/addr.c" -o "$OUT/qrtr-cfg"
cc "${common[@]}" "${qrtr[@]}" \
    "$SRC/rmtfs/qmi_rmtfs.c" "$SRC/rmtfs/rmtfs.c" "$SRC/rmtfs/rproc.c" \
    "$SRC/rmtfs/sharedmem.c" "$SRC/rmtfs/storage.c" "$SRC/rmtfs/util.c" \
    -ludev -lpthread -o "$OUT/rmtfs"
cc "${common[@]}" -DHAVE_ZSTD "${qrtr[@]}" "$SRC/tqftpserv/tqftpserv.c" \
    "$SRC/tqftpserv/translate.c" "$SRC/tqftpserv/zstd-decompress.c" \
    -lzstd -o "$OUT/tqftpserv"
sha256sum "$OUT"/*
