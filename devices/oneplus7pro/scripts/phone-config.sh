#!/usr/bin/env bash
# Target identity is private local state, never a checked-in handset serial.
# Callers set ROOT to the checkout and retain their existing fastboot/slot guards.
phone_serial() {
    local serial=${PHONE_SERIAL:-}
    if [[ -z $serial && -r "$ROOT/out/device.serial" ]]; then
        IFS= read -r serial < "$ROOT/out/device.serial" || true
    fi
    if [[ ! $serial =~ ^[[:alnum:]_-]+$ ]]; then
        echo 'Set PHONE_SERIAL or put the target serial in ignored out/device.serial.' >&2
        return 1
    fi
    printf '%s\n' "$serial"
}
