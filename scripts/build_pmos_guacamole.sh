#!/usr/bin/env bash
# Build a real postmarketOS guacamole boot.img via pmbootstrap.
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
export PMB_SUDO="${PMB_SUDO:-pkexec}"
WORK="${PMB_WORK:-$HOME/.local/var/pmbootstrap}"
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT="${1:-$ROOT/out/pmos}"
PMB="$(command -v pmbootstrap)"

mkdir -p "$WORK" "$OUT" "$HOME/.config"
CFG="$HOME/.config/pmbootstrap_v3.cfg"
cat >"$CFG" <<EOF
[pmbootstrap]
work = $WORK
device = oneplus-guacamole
ui = console
user = pmos
hostname = guacamole
extra_packages = none
jobs = $(nproc)
sudo_timer = True
[providers]
[mirrors]
EOF

# Empty answers -> defaults (device/ui/user already in config).
# `yes` exits 141 (SIGPIPE) when init finishes; don't fail the script.
set +o pipefail
yes '' | pmbootstrap -y init --shallow-initial-clone
set -o pipefail

# Confirm device
pmbootstrap config device
pmbootstrap status || true

# Rootfs + boot.img (console UI, USB gadget, ssh)
# No hardcoded device password here. pmbootstrap's --password is a *dummy*
# password (it is handled in plain text and may hit pmbootstrap's logfile), so
# set PMOS_PASSWORD out of band or just answer the prompt below.
if [ -z "${PMOS_PASSWORD:-}" ]; then
  read -rs -p "postmarketOS dummy password (input hidden): " PMOS_PASSWORD && echo
fi
pmbootstrap install --password "$PMOS_PASSWORD"
unset PMOS_PASSWORD

mkdir -p "$OUT"
pmbootstrap export "$OUT"
ls -lh "$OUT"
echo DONE_PMOS
