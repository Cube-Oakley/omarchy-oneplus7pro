#!/usr/bin/env bash
# Connect to persistent Arch, with the host key pinned during USB provisioning.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KNOWN_HOSTS="$ROOT/out/network-test/known_hosts"
IDENTITY=${PHONE_SSH_IDENTITY:-$HOME/.ssh/id_ed25519}
[[ -s $KNOWN_HOSTS ]] || {
    echo 'Missing pinned phone host key; provision SSH over the trusted USB link first.' >&2
    exit 1
}
exec ssh -F /dev/null -i "$IDENTITY" -o IdentitiesOnly=yes \
    -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$KNOWN_HOSTS" \
    -o ConnectTimeout=5 root@172.16.42.1 "$@"
