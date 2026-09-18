#!/usr/bin/env bash
# Run inside the phone with the staged files, AFTER approval of browser display
# access. This installs the adapter; launching Chromium then grants socket access.
set -euo pipefail
stage=${1:?Usage: install-phone-browser.sh /root/shade-stage}
[[ $(id -u) == 0 ]] || exit 1
backup=/root/.local/state/omarchy-mobile/backups/keyboard-browser-20260918/browser
mkdir -p "$backup" /root/.local/bin /root/.local/share/applications \
    /root/.local/share/icons/hicolor/192x192/apps
for path in /root/.local/bin/{chromium,omarchy-mobile-browser,omarchy-launch-webapp} \
    /root/.config/omarchy-mobile/browser-launch \
    /root/.local/share/applications/{chromium,Grok}.desktop; do
    if [[ -e $path ]]; then cp -an "$path" "$backup/"; fi
done
getent passwd mobile-browser >/dev/null || useradd --create-home --shell /usr/bin/nologin mobile-browser
install -m755 "$stage/browser.sh" /root/.local/bin/omarchy-mobile-browser
ln -sfn omarchy-mobile-browser /root/.local/bin/chromium
install -m755 "$stage/launch-webapp.sh" /root/.local/bin/omarchy-launch-webapp
install -m755 "$stage/browser-launch.sh" /root/.config/omarchy-mobile/browser-launch
install -m644 "$stage/Grok.desktop" /root/.local/share/applications/Grok.desktop
install -m644 "$stage/grok.png" /root/.local/share/icons/hicolor/192x192/apps/omarchy-webapp-grok.png
python3 - <<'PY'
from pathlib import Path
import re
source = Path('/usr/share/applications/chromium.desktop').read_text()
updated, count = re.subn(r'^Exec=(?:/usr/bin/)?chromium(?=\s|$)',
                         'Exec=omarchy-mobile-browser', source, flags=re.M)
if count == 0:
    raise SystemExit('Packaged Chromium Exec format changed; inspect before installing')
Path('/root/.local/share/applications/chromium.desktop').write_text(updated)
PY
update-desktop-database /root/.local/share/applications
