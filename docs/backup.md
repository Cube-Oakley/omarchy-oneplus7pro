# Backup

Files go to `~/Downloads/oneplus7pro-backup-YYYYMMDD/`. They are **not** in git.

We are **not** keeping a full userdata/app dump. The phone will be wiped. What matters is files on `/sdcard` plus a small firmware set so a bad flash is recoverable.

## What was taken

| Path | Contents |
|---|---|
| `files/` | User files from `/sdcard` (photos, downloads, chat media, …) |
| `luns/sdb.img` … `sdf.img` | Bootloader / vendor / **EFS** (IMEI). ~4.1 GiB. Unbrick only. |
| `partitions/` | Named slices (`boot_a`, `dtbo_a`, `vbmeta_a`, EFS, …) |
| `metadata/` | getprop, partition map |

User-file backup helpers are kept privately and are not distributed. Excluded:

- `Android/` — app private data
- `TWRP/` — old nandroid
- `ROMS/` — Havoc/Magisk zip leftovers

A partial `sda` userdata image was started and deleted.

## Restore files

Copy anything you want out of `~/Downloads/oneplus7pro-backup-YYYYMMDD/files/`.

Firmware checksums:

```bash
python3 scripts/restore_ufs.py --backup-dir ~/Downloads/oneplus7pro-backup-YYYYMMDD
```

Never flash `sdf` (EFS) from another device.
