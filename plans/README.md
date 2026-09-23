# plans/

Human-readable plan for the Omarchy Mobile · OnePlus 7 Pro project.

Plain static HTML/CSS/JS: no build step, no bundler, no CDN, no web server. Open
`index.html` directly and it works from `file://`.

```bash
xdg-open plans/index.html          # or: chromium plans/index.html
```

## Layout

| File | Role |
|---|---|
| `index.html` | Overview: totals for the whole project, links to the three pages |
| `hardware.html` | Components physically in guacamole, plus boot chain / power / storage |
| `software.html` | Shell surfaces, settings, apps, advanced features, AI & agents |
| `integration.html` | Phone ↔ desktop: development link today, shared experience after |
| `assets/plan.css` | All styling, including the dark/light themes and print rules |
| `assets/plan.js` | Renderer, filters, theme switch. No content lives here |
| `assets/data/site.js` | Shared copy: header, status key, open decisions |
| `assets/data/hardware.js` | `PAGE_HARDWARE` |
| `assets/data/software.js` | `PAGE_SOFTWARE` |
| `assets/data/integration.js` | `PAGE_INTEGRATION` |

Every page loads every data file, so the top-bar counts and the "working, whole
project" figure are always current. Each page shares the same top tab bar.

## Status key

| Mark | Value | Meaning |
|---|---|---|
| green check | `ok` | **Working** — verified on the handset, not merely "the driver probed" |
| yellow check | `partial` | **Partial** — plumbing is up, but the user-visible result is unproven, capped, or only one of several paths works |
| red cross | `no` | **Not working** — nothing usable yet, including "not attempted so far" |
| grey dash | `absent` | **Not present** — this handset has no such hardware; tracked so it stays off the wish list |

## Updating a status

Content lives only in `assets/data/*.js`. Nothing is generated, so editing those
objects is the whole workflow:

```js
{ n: "Primary microphone", s: "no",
  note: "Capture path untested; no recording has ever been produced.",
  ref: "docs/audio-bringup-20260918.md" },
```

* `s` — `"ok"` | `"partial"` | `"no"` | `"absent"`; counts, bars and chips recompute on load
* `n` — component or feature name; use the part/marketing name, not a codename
* `note` — one or two lines of **evidence**, including what is still unproven
* `ref` — the file backing the claim (`docs/…`, `scripts/…`, `README.md`), or omit it

A section takes either `items: []` or `groups: [{ title, note?, items: [] }]`. Groups
become separate cards and get sidebar links (slug generated from the title). Only add
an explicit `id` if you need a stable anchor.

## Rules for these pages

1. `ok` requires the physical, user-visible result — not a successful probe. Cellular
   is the standing example: the modem answers QMI and the data interface appears, and
   it is still `partial` because nothing has registered, called or moved data.
2. Rows are either a component that exists in the handset, or work already written up
   in `docs/mobile-roadmap.md` / `docs/pathway.md`. Aspirational rows are allowed
   (touch apps, the app framework, the agent layer) but they are `no` or `partial`
   and their `note` says what is undecided rather than inventing detail.
3. A hardware row is a component, not a feature idea. Features belong on **Software**
   or **Integration**.
4. Keep it in `plans/`. It describes the firmware/OS work; it must never be part of a
   boot image, overlay or rootfs. Nothing here ships to the phone.
5. `docs/status.md` and the dated work notes stay the source of truth; this is the
   view, not the record.

Printing (`Ctrl+P`) drops the sidebar and toolbars and avoids splitting cards. Reset
the filter chips first, or hidden rows stay hidden on paper.
