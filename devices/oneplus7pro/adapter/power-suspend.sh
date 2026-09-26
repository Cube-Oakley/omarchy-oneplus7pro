#!/usr/bin/env bash
# Board adapter; the native5 command owns charger, battery and wake-source guards.
set -euo pipefail
exec /usr/local/sbin/guacamole-suspend "$@"
