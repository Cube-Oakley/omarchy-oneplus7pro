# USB internet and SSH — 2026-09-17

**Current update:** native2 #179 starts USB SSH automatically after reboot and
has verified Landlock ABI 7. Normal pacman sync passed again without a sandbox
bypass. The host helper corrects the clock and checks DNS. The touch1 service and
pacman limitations below describe the rollback image.

The original setup used touch1 #175 with all eight cores and automatic GPU/touch
startup. Host NetworkManager sharing provides internet over the existing NCM
link. Public-key SSH enters the persistent Arch filesystem directly.

## Everyday use

From this project on the laptop:

```bash
# After a phone reboot, wait for the desktop (~110 seconds), then:
bash scripts/phone-usb-up.sh

# Interactive Arch shell, or append a command:
bash scripts/phone-ssh.sh
bash scripts/phone-ssh.sh 'uname -r; cat /sys/devices/system/cpu/online'
```

`phone-usb-up.sh` starts the persistent service helper through the existing
raw USB shell if SSH is unavailable. It then verifies the pinned SSH host key,
sets the phone clock from the laptop and checks DNS. The clock resets to 1970
on reboot until RTC/NTP integration is done. The installed touch1 image does
**not** autostart these new services; running this command avoids another flash.
Future initramfs work can call `start-usb-services.sh` after mounting Arch's
runtime filesystems, independently of the GPU startup.

## Configuration

- Phone: `172.16.42.1/24` on `usb0`; gateway/DNS `172.16.42.2`.
- Host: `172.16.42.2/24` on `enp198s0f0u2`, NetworkManager profile UUID
  `bc716806-f2dc-3260-a6a1-157c0b1ceae6` (Wired connection 3).
- Profile uses `ipv4.method shared`, explicit address and `never-default yes`.
  DHCP range `.10`–`.100` excludes the static phone/host addresses.
- Host upstream remains `enp198s0f4u1u1`. UFW rules allow DNS from only the
  phone address to the host USB address and forwarding from the phone's USB
  interface through that upstream. NAT/DNS are managed by NetworkManager.
- `scripts/setup-usb-host-firewall.sh` reproduces these three rules. Pass USB
  interface, upstream interface, then `disable` to remove just these rules.
  Interface names may change if the physical USB port or upstream changes.
- SSH listens only on `172.16.42.1:22`, allows root public-key authentication,
  and disables passwords, keyboard-interactive login and forwarding. Root is
  the existing bring-up account; a regular desktop user is future work.
- Phone config: `/etc/ssh/sshd_config.usb`; service helper:
  `/usr/local/sbin/guacamole-usb-services`; log: `/root/sshd-usb.log`.
- The laptop's existing `~/.ssh/id_ed25519.pub` was added to phone
  `/root/.ssh/authorized_keys`. No private client key was copied to the phone.
- A persistent Ed25519 host key was generated on the phone. Its public key
  was read over the direct USB shell and pinned in
  `out/network-test/known_hosts`; the SSH wrapper requires this file.
  Set `PHONE_SSH_IDENTITY` to use another already-authorized identity.
- The old unauthenticated bring-up shell on port 23 remains in touch1 for
  recovery/bootstrap. Retire or gate it when SSH is integrated into boot,
  before adding wireless connectivity.

## Package management

DNS, HTTPS certificate validation and an actual repository database download
have passed. Pacman downloaded `acl-2.4.0-1-aarch64` (143,708 bytes) and its
signature, and successfully checked the keyring and package integrity. No
package was installed by this test. The system package database was left
unchanged; the test uses temporary database/cache directories under `/tmp`.

The custom kernel has `CONFIG_SECURITY_LANDLOCK` disabled. Pacman therefore
needs `--disable-sandbox-filesystem` on this image. This preserves its
unprivileged downloader, syscall filtering and package signature checks;
the main pacman configuration was not changed. Enable Landlock in a future
kernel and remove this workaround. See the
[pacman option documentation](https://man.archlinux.org/man/pacman.8).

The previously uninitialized package signing keyring is initialized using
`pacman-key --init` and the installed `archlinuxarm` keyring. Do not disable
package signature verification. The service helper also creates the standard
`/dev/fd`, `/dev/stdin`, `/dev/stdout` and `/dev/stderr` symlinks missing from
the minimal initramfs; these are required for Bash process substitution used
by `pacman-key`.

The download-only verification command (inside the phone's SSH shell) was:

```bash
mkdir -p /tmp/usb-pacman-db /tmp/usb-pacman-cache
pacman --disable-sandbox-filesystem \
  --dbpath /tmp/usb-pacman-db --cachedir /tmp/usb-pacman-cache \
  -Sywdd --noconfirm acl
```

The double `d` is specific to this isolated download-only test, avoiding
unneeded dependency downloads into the empty test database. Normal package
installations must resolve dependencies; do not copy it into install commands.

## Host rollback

```bash
sudo bash scripts/setup-usb-host-firewall.sh enp198s0f0u2 enp198s0f4u1u1 disable
nmcli connection modify bc716806-f2dc-3260-a6a1-157c0b1ceae6 \
  ipv4.method manual ipv4.shared-dhcp-range ''
nmcli connection up bc716806-f2dc-3260-a6a1-157c0b1ceae6
```

Original profile output and firewall changes are saved in `out/network-test/`.
Evidence includes `ssh-internet-verified.log`, `reconnect-from-stopped.log`,
`pacman-final.log` and `final-state.log`. Reconnect was tested after stopping
the SSH listener and removing runtime DNS/default routing; all were restored.
The frozen touch1 boot image remains unchanged.

NetworkManager's behavior is documented in its
[IPv4 settings reference](https://www.networkmanager.dev/docs/api/latest/settings-ipv4.html).
SSH options follow the [OpenSSH manual](https://man.openbsd.org/sshd_config).
