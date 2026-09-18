#!/usr/bin/env bash
set -euo pipefail
url=${1:?Usage: omarchy-launch-webapp https://example.com [browser arguments]}
case $url in http://*|https://*) ;; *) echo 'Webapps require an HTTP or HTTPS URL.' >&2; exit 2 ;; esac
shift
exec "${HOME}/.local/bin/omarchy-mobile-browser" --app="$url" "$@"
