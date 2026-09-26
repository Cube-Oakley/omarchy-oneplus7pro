# Network settings and speed test — September 19

Userspace only. Same NetworkManager helper as the shade; no second Wi-Fi stack.

## Settings

Settings → Network → Wi-Fi: radio, current addresses, DNS (automatic or up to
four static servers), forget, scan/connect/disconnect, and a speed test. Shade
Wi-Fi keeps the quick picker and gains **Speed test** plus **Advanced** (opens
Settings on the Wi-Fi page).

DNS writes `ipv4.dns` / `ipv4.ignore-auto-dns` on the active Wi-Fi UUID, then
brings the connection up. Forget deletes only 802-11-wireless UUIDs.

## Speed test

`omarchy-mobile-speedtest` prints JSON lines. It measures HTTP latency and
throughput to Cloudflare (`speed.cloudflare.com`). That is not ICMP ping and
not an ISP plan number. The themed gauge view is shared (`SpeedTestView`) so
the shade overlay and Settings are the same client.

## Recovery

Installer backup under `~/.local/state/omarchy-mobile/backups/`. Restore
Quickshell + `omarchy-mobile-wifi` / `omarchy-mobile-speedtest` and restart
only Quickshell. Do not flash.
