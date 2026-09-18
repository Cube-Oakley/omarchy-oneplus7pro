#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KERNEL="$ROOT/.work/linux-sm8150-mmcx-sleep"
WORK="$ROOT/.work/adsp-test"
OUT="$ROOT/out/audio-test"
mkdir -p "$WORK" "$OUT/firmware"
dtc -@ -I dts -O dtb "$ROOT/devices/oneplus7pro/kernel/power/guacamole-adsp.dts" -o "$OUT/adsp.dtbo"
fdtoverlay -i "$KERNEL/bringup-guacamole.dtb" -o "$OUT/adsp-merged.dtb" "$OUT/adsp.dtbo"
cp "$ROOT/devices/oneplus7pro/kernel/power/adsp_overlay.c" "$WORK/"
python3 - "$ROOT" "$WORK" "$OUT" <<'PY'
from pathlib import Path
import struct,sys,shutil,hashlib,json
root,work,out=map(Path,sys.argv[1:])
blob=(out/'adsp.dtbo').read_bytes()
(work/'adsp_dtbo.h').write_text('static const unsigned char adsp_dtbo[] __aligned(8) = {\n'+','.join(map(str,blob))+'\n};\n')
source=root/'.work/guacamole-radio-firmware/image'
mdt=(source/'adsp.mdt').read_bytes()
assert mdt[:6] == b'\x7fELF\x01\x01', 'Expected ELF32 little endian'
phoff=struct.unpack_from('<I',mdt,28)[0]
phsize,count=struct.unpack_from('<HH',mdt,42)
assert phsize==32
segments=[]
for index in range(count):
    kind,offset,virt,phys,filesz,memsz,flags,align=struct.unpack_from('<8I',mdt,phoff+index*phsize)
    if kind != 1 or not memsz or (flags >> 24) & 7 == 2: continue
    assert 0x8be00000 <= phys < phys+memsz <= 0x8dc00000, (index,hex(phys),hex(memsz))
    if filesz:
        part=source/f'adsp.b{index:02d}'
        assert part.stat().st_size==filesz, (part,filesz)
    segments.append({'index':index,'address':hex(phys),'file_bytes':filesz,'memory_bytes':memsz})
assert segments
for file in [source/'adsp.mdt', *sorted(source.glob('adsp.b*')),source/'adspr.jsn',source/'adspua.jsn']:
    shutil.copy2(file,out/'firmware'/file.name)
(out/'firmware-check.json').write_text(json.dumps({'reserved_start':'0x8be00000','reserved_end':'0x8dc00000','segments':segments},indent=2)+'\n')
PY
printf 'obj-m += guacamole_adsp_test.o\nguacamole_adsp_test-y := adsp_overlay.o\n' > "$WORK/Makefile"
make -C "$KERNEL" ARCH=arm64 LLVM=1 M="$WORK" KBUILD_EXTRA_SYMBOLS="$KERNEL/vmlinux.symvers" modules
cp "$WORK/guacamole_adsp_test.ko" "$OUT/"
(cd "$OUT" && sha256sum guacamole_adsp_test.ko adsp.dtbo firmware/* > SHA256SUMS)
tar -C "$OUT" -czf "$OUT/adsp-test.tar.gz" guacamole_adsp_test.ko adsp.dtbo firmware firmware-check.json SHA256SUMS
