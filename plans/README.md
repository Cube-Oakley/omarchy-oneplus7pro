# plans/

Human-readable plan for Omarchy Mobile across every supported device.

Plain static HTML/CSS/JS: no build step, no bundler, no CDN, no web server. Open
`index.html` directly and it works from `file://`.

```bash
xdg-open plans/index.html          # or: chromium plans/index.html
```

## Layout

| File | Role |
|---|---|
| `index.html` | Overview: device cards, the shared layers, and the key capabilities at a glance |
| `compare.html` | Every capability side by side on every device, plus shared-software coverage per device |
| `device.html?d=<id>` | One handset's hardware: every component with its evidence |
| `software.html` | Shared shell surfaces, settings, apps, advanced features, AI & agents |
| `integration.html` | Phone ↔ desktop: development link today, shared experience after |
| `hardware.html` | Redirect to the OnePlus 7 Pro device page, for old links |
| `assets/plan.css` | All styling, including the dark/light themes and print rules |
| `assets/plan.js` | Renderer, filters, device switcher, theme switch. No content lives here |
| `assets/data/site.js` | Shared copy: header, status key, open decisions, GitHub source URL |
| `assets/data/devices.js` | `DEVICES`: one entry per handset (name, SoC, stage, summary, links) |
| `assets/data/capabilities.js` | `CAPS`: the capability list the Compare page is built from |
| `assets/data/device-<id>.js` | `HW.<id>`: that handset's hardware sections |
| `assets/data/software.js` | `PAGE_SOFTWARE` |
| `assets/data/integration.js` | `PAGE_INTEGRATION` |

Every page loads every data file (`plan.js` loads the device files listed in
`DEVICES`), so the top-bar counts and the comparison are always current.

## Status key

| Mark | Value | Meaning |
|---|---|---|
| green check | `ok` | **Working** — verified on the handset, not merely "the driver probed" |
| yellow check | `partial` | **Partial** — plumbing is up, but the user-visible result is unproven, capped, or only one of several paths works |
| red cross | `no` | **Not working** — nothing usable yet, including "not attempted so far" |
| grey dash | `absent` | **Not present** — this handset has no such hardware; tracked so it stays off the wish list |
| dashed circle | *(derived)* | **Not tried yet** — shared rows only: nobody has checked this on that device |

## Updating a status

Content lives only in `assets/data/*.js`. Nothing is generated, so editing those
objects is the whole workflow.

A hardware row, in `device-<id>.js`:

```js
{ n: "Primary microphone", s: "partial", cap: "mic",
  note: "AMIC4, the stock handset mic, records through PipeWire … "
      + "Not yet tested across suspend; gain is a fixed conservative default.",
  ref: "devices/oneplus7pro/docs/microphone-20260922.md" },
```

* `s` — `"ok"` | `"partial"` | `"no"` | `"absent"`; counts, bars and chips recompute on load
* `n` — component or feature name; use the part/marketing name, not a codename
* `note` — one or two lines of **evidence**, including what is still unproven
* `ref` — the file backing the claim, **relative to the repository root**; opens the
  local file from a checkout and the GitHub copy from Pages. Omit if there is none
* `cap` — optional capability id from `capabilities.js`. Tag the rows that answer
  that capability for a phone owner (the microphone, not the codec). The Compare
  page rolls a device's tagged rows up: all working → working, none → not working,
  anything between → partial. Untagged capabilities show "not tracked".

A shared row, in `software.js` or `integration.js`, keeps its shared status in `s`
and adds per-device evidence in `on`:

```js
{ n: "App launcher / drawer", s: "ok",
  on: { pixel7pro: { s: "partial", note: "The Applications page renders and launches apps through "
                       + "the shell's IPC; launching by touch is not verified yet.",
                     ref: "devices/pixel7pro/docs/hyprland-mobile-20260925.md" } },
  note: "Touch launcher on desktop entries; launching through the drawer verified for both installed apps.",
  ref: "devices/oneplus7pro/docs/keyboard-browser-20260918.md" },
```

Without an `on` entry, the reference device (`reference: true` in `devices.js`,
currently the OnePlus 7 Pro) inherits `s`, and every other device shows **Not tried
yet**. `on.<id>` can also be a bare status string.

A section takes either `items: []` or `groups: [{ title, note?, items: [] }]`. Groups
become separate cards and get sidebar links (slug generated from the title). Only add
an explicit `id` if you need a stable anchor.

## Adding a device

1. Add an entry to `DEVICES` in `assets/data/devices.js`.
2. Create `assets/data/device-<id>.js` setting `HW.<id> = { blurb, sections }`, with
   `cap` on the rows that answer each capability and a "Not present" section.
3. Add `on: { <id>: … }` to shared rows as they are verified on the new phone.

No HTML changes: the top bar, overview, Compare page and device switcher pick it up.

## Rules for these pages

1. `ok` requires the physical, user-visible result — not a successful probe. Cellular
   is the standing example: the modem answers QMI and the data interface appears, and
   it is still `partial` because nothing has registered, called or moved data.
2. Rows are either a component that exists in the handset, or work already written up
   in `docs/mobile-roadmap.md` or a device's docs. Aspirational rows are allowed
   (touch apps, the app framework, the agent layer) but they are `no` or `partial`
   and their `note` says what is undecided rather than inventing detail.
3. A hardware row is a component, not a feature idea. Features belong on **Software**
   or **Integration**.
4. Keep it in `plans/`. It describes the firmware/OS work; it must never be part of a
   boot image, overlay or rootfs. Nothing here ships to a phone.
5. Each device's `docs/status.md` and dated work notes stay the source of truth; this
   is the view, not the record.

Printing (`Ctrl+P`) drops the sidebar and toolbars and avoids splitting cards. Reset
the filter chips first, or hidden rows stay hidden on paper.
