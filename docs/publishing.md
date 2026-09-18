# Review and publication

The September 18 review branch is a clean source snapshot, with no parent commits
from the private bring-up history. This prevents old versions of removed files
and identifiers from accompanying a later public push.

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
