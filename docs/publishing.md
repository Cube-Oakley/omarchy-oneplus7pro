# Review and publication

The published line starts from the September 18 review snapshot: a clean source
tree with no parent commits from the private bring-up history. It is carried by
the local `public` branch, which is GitHub `main`; the original review branch was
merged into `main` and deleted. This keeps old versions of removed files and
identifiers from accompanying a later public push.

The original development history is preserved privately in the development
checkout and an ignored recovery bundle under `out/private/`. It is not the
publication branch. Do not publish all branches/tags or mirror that repository.

Reviewed distribution content includes source, experiment notes, theme assets
and six real screenshots. The personal file-backup helper is excluded. Handset
serials are local configuration; personal Wi-Fi names, LAN addresses and host
paths have been removed. Screenshot review hides Wi-Fi identity and notification
contents before capture, and avoids browser sessions or personal files.

`out/`, `.work/`, firmware extracts, SSH material and device backups stay local.
Keep upstream source attribution. The audio notes distinguish electrical tests
from user-confirmed sound and list the remaining protection/persistence checks.

The user approved merging the reviewed snapshot into local `main` and publishing
to `Cube-Oakley/omarchy-oneplus7pro` on September 18. Local `main` retains private
development ancestry; GitHub `main` starts from the clean review snapshot. These
branches have the same published file content but intentionally different history.
Future public updates must descend from the clean public branch. Never merge the
private development ancestry into it or mirror the private repository.

## Mechanics

Two branches, deliberately unrelated. `main` carries the private development
ancestry and pushes to the private development remote (`origin`). `public` descends
only from the clean snapshot and is what GitHub serves.

The `github` remote is pinned to one branch so an ordinary or mirrored push cannot
send private history:

```bash
git config remote.github.push '+refs/heads/public:refs/heads/main'
```

Public edits happen in the ignored `.work/public` worktree, never in the
development checkout:

```bash
cd .work/public
git checkout main -- <paths>       # or: git cherry-pick <sha>
git commit
git push github                    # GitHub main
git push origin public:refs/heads/public   # private-side mirror of the public line
```

The two trees stay byte-identical except for the Pages files below, so check that
diff after each public commit.

GitHub branch Pages can publish only `/` or `/docs`, so the site is served from the
public repository root: a root `index.html` redirects to `plans/`, and a root
`.nojekyll` keeps the hand-written HTML, CSS and JavaScript verbatim. Nothing on
the public branch may name or embed the private host — no LAN addresses, no
internal hostnames, no forge/gitea references.

## Checks before each public sync

Scan the lines the sync adds (`git diff public main`, excluding the Pages files):

- IPv4 addresses: only public resolvers such as 1.1.1.1 and 8.8.8.8 may appear.
- MAC-style addresses: only obvious test fixtures.
- Digit runs of 14–20 (IMEI, IMSI, ICCID) and phone-number patterns: none.
- The private host, forge names, home paths and email addresses: none.
- The handset's own values, compared on the phone without printing them: the
  fastboot serial (`out/device.serial`), SoC serial, Wi-Fi connection names and
  SSID, network and Bluetooth controller addresses, paired device addresses.
  A paired device's product name, such as a headphone model, is acceptable.
- Binary files: none unless reviewed; camera frames and recordings stay in `out/`.
- Credentials, keys, tokens and PIN/PUK values: none.

## Publication log

- September 18: the reviewed snapshot became GitHub `main`.
- September 23: `public` synced to development `main` (Settings kit, audio and
  microphones, Bluetooth, camera, IPA, CPU scaling, 90 Hz, switcher smoothness)
  after the checks above found nothing private.
- September 23, later: synced again (Omarchy Camera's burst merge and photo
  renderer, libcamera-guacamole 0.7.2-7, the camera theme) after the same
  checks; the only address added is the USB link's 172.16.42.1.
- September 23, night: synced the brightness, vibration, flashlight and alert
  slider controls after the same checks; the only address added is the
  upstream author's, already public in the 7T Pro patches.
- September 24: synced kernel #192 (crash handling) after the same checks,
  which found nothing to remove.
