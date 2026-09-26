/* ==========================================================================
   Omarchy Mobile project plan — shared renderer
   No build step, no modules, no network. Plain scripts, works from file://.
   Pages set <html data-page="overview|compare|device|software|integration">.
   Device data files (assets/data/device-<id>.js) are loaded here, one per
   entry in DEVICES, so adding a device never means editing the HTML.
   ========================================================================== */

const SHARED = [
  { id: "software",    href: "software.html",    nav: "Software" },
  { id: "integration", href: "integration.html", nav: "Integration" }
];
const sharedPage = id => ({ software: PAGE_SOFTWARE, integration: PAGE_INTEGRATION })[id];
const deviceById = id => DEVICES.find(d => d.id === id);
const deviceHref = id => `device.html?d=${encodeURIComponent(id)}`;
const REFERENCE = () => (DEVICES.find(d => d.reference) || DEVICES[0]).id;

const ICON = {
  ok:      '<svg class="ico ok" viewBox="0 0 24 24" role="img" aria-label="working"><circle cx="12" cy="12" r="10" fill="currentColor" opacity=".16"/><path d="M7.2 12.6l3.1 3.1 6.5-6.9" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  partial: '<svg class="ico warn" viewBox="0 0 24 24" role="img" aria-label="partially working"><circle cx="12" cy="12" r="10" fill="currentColor" opacity=".16"/><path d="M12 2a10 10 0 0 1 0 20z" fill="currentColor" opacity=".3"/><path d="M7.2 12.6l3.1 3.1 6.5-6.9" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  no:      '<svg class="ico bad" viewBox="0 0 24 24" role="img" aria-label="not working"><circle cx="12" cy="12" r="10" fill="currentColor" opacity=".16"/><path d="M8.6 8.6l6.8 6.8M15.4 8.6l-6.8 6.8" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>',
  absent:  '<svg class="ico na" viewBox="0 0 24 24" role="img" aria-label="not present on this handset"><circle cx="12" cy="12" r="10" fill="currentColor" opacity=".14"/><path d="M8 12h8" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>',
  untested:'<svg class="ico un" viewBox="0 0 24 24" role="img" aria-label="not tried yet"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="1.8" stroke-dasharray="3.2 3"/></svg>'
};

const LABEL = {
  ok: "Working", partial: "Partial", no: "Not working", absent: "Not present", untested: "Not tried yet",
  all: "All"
};
const LEGEND = {
  ok: "Working — verified on the handset",
  partial: "Partial — running, not fully proven",
  no: "Not working — nothing usable yet",
  absent: "Not present on this handset (no hardware to bring up)",
  untested: "Not tried on this device yet"
};
const ORDER = ["ok", "partial", "no", "absent", "untested"];
const TONE = { ok: "ok", partial: "warn", no: "bad", absent: "na", untested: "un" };

const esc = s => String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));
const slug = s => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");
const param = k => new URLSearchParams(location.search).get(k);

/* Refs open the file in a local checkout, or on GitHub when served from Pages. */
function refHref(ref) {
  if (location.protocol === "file:" || !SITE.source) return "../" + ref;
  return SITE.source.replace(/\/blob\/([^/]+)\/$/, ref.endsWith("/") ? "/tree/$1/" : "/blob/$1/") + ref;
}

/* --------------------------------------------------------------- data */
function groupsOf(sec) {
  return sec.groups || [{ title: null, items: sec.items || [] }];
}
function itemsOf(page) {
  return page ? page.sections.flatMap(s => groupsOf(s).flatMap(g => g.items)) : [];
}
const hwItems = id => itemsOf(HW[id]);

function counts(items, stat = i => i.s) {
  const c = { ok: 0, partial: 0, no: 0, absent: 0, untested: 0 };
  items.forEach(i => { const k = stat(i); c[k] = (c[k] || 0) + 1; });
  return c;
}
const tracked = c => c.ok + c.partial + c.no;

/* A shared row's status on one device: explicit `on`, else the shared status on the
   reference device, else not tried yet. */
function onDevice(item, dev) {
  const v = item.on && item.on[dev];
  if (v) return typeof v === "string" ? { s: v } : v;
  return dev === REFERENCE() ? { s: item.s } : { s: "untested" };
}

/* Roll a device's rows for one capability up into a single status. */
function capStatus(dev, cap) {
  const rows = hwItems(dev).filter(i => i.cap === cap);
  if (!rows.length) return { s: "untracked", rows };
  const real = rows.filter(r => r.s !== "absent");
  if (!real.length) return { s: "absent", rows };
  const s = real.every(r => r.s === "ok") ? "ok" : real.every(r => r.s === "no") ? "no" : "partial";
  return { s, rows };
}

/* --------------------------------------------------------------- fragments */
function bar(c, total) {
  const t = total || 1;
  return `<div class="bar" title="${c.ok} working, ${c.partial} partial, ${c.no} not working${c.absent ? `, ${c.absent} not present` : ""}${c.untested ? `, ${c.untested} not tried yet` : ""}">
    ${ORDER.map(k => `<i class="${TONE[k]}" style="width:${(c[k] || 0) / t * 100}%"></i>`).join("")}
  </div>`;
}
function pill(c) {
  return `${c.ok} working · ${c.partial} partial · ${c.no} not working`
    + (c.absent ? ` · ${c.absent} not present` : "") + (c.untested ? ` · ${c.untested} not tried yet` : "");
}
function statHtml(k, n) {
  return `<div class="stat ${TONE[k]}"><div class="big">${n}</div><div class="lbl">${LABEL[k].toLowerCase()}</div></div>`;
}
function legendHtml(keys) {
  return `<div class="legend"><h4>Status key</h4>${keys.map(k => `<div class="l">${ICON[k]} ${esc(LEGEND[k])}</div>`).join("")}</div>`;
}
const refHtml = ref => ref ? `<a class="ref mono" href="${esc(refHref(ref))}">${esc(ref)}</a>` : "";

/* A row. `view` is a device id on shared pages (or null for the shared status);
   hardware rows pass no view. */
function rowHtml(it, view, anchor) {
  const shared = view !== undefined;
  const st = shared && view ? onDevice(it, view) : { s: it.s };
  let devs = "", devnotes = "";
  if (shared && DEVICES.length > 1) {
    devs = `<div class="devs">${DEVICES.map(d => {
      const o = onDevice(it, d.id);
      return `<a class="dv ${TONE[o.s]}${d.id === view ? " cur" : ""}" href="?d=${d.id}" data-dev="${d.id}"
        title="${esc(d.name)}: ${esc(LABEL[o.s].toLowerCase())}${o.note ? " — " + esc(o.note) : ""}">${ICON[o.s]}<span>${esc(d.short || d.name)}</span></a>`;
    }).join("")}</div>`;
    devnotes = DEVICES.filter(d => it.on && it.on[d.id] && it.on[d.id].note && (!view || d.id === view)).map(d => {
      const o = it.on[d.id];
      return `<div class="devnote"><b>${esc(d.name)}:</b> ${esc(o.note)} ${o.ref ? refHtml(o.ref) : ""}</div>`;
    }).join("");
  }
  const text = [it.n, it.note || "", ...(it.on ? Object.values(it.on).map(o => o.note || "") : [])].join(" ").toLowerCase();
  return `<div class="row${devs ? " withdevs" : ""}" data-s="${st.s}" data-text="${esc(text)}"${anchor ? ` id="${anchor}"` : ""}>
    ${ICON[st.s]}
    <div>
      <div class="name">${esc(it.n)}</div>
      ${it.note ? `<div class="note">${esc(it.note)}</div>` : ""}
      ${devnotes}
      ${refHtml(it.ref)}
    </div>
    ${devs}
  </div>`;
}

function sectionHtml(sec, view, stat, anchors) {
  const groups = groupsOf(sec);
  const all = groups.flatMap(g => g.items);
  const c = counts(all, stat);

  let h = `<section class="sec" id="${sec.id}">
    <div class="sechead"><h2>${esc(sec.title)}</h2><span class="secpill">${pill(c)}</span></div>
    ${sec.blurb ? `<p class="secblurb">${esc(sec.blurb)}</p>` : ""}
    ${bar(c, all.length)}`;

  groups.forEach(g => {
    const gid = g.id || (sec.id + "-" + slug(g.title || "items"));
    const gc = counts(g.items, stat);
    h += `<div class="card" id="${gid}">`;
    if (g.title) h += `<h3>${esc(g.title)}<span class="counts">${gc.ok} / ${g.items.length}</span></h3>`;
    if (g.note) h += `<div class="groupnote">${esc(g.note)}</div>`;
    h += g.items.map(it => rowHtml(it, view, anchors && anchors(it))).join("");
    h += `</div>`;
  });

  if (sec.notes && sec.notes.length) {
    h += `<div class="card"><div class="groupnote">${sec.notes.map(n => `<p style="margin:0 0 8px">${esc(n)}</p>`).join("")}</div></div>`;
  }
  return h + `</section>`;
}

function navHtml(sections, legendKeys, extra = "") {
  let h = `<div class="navtitle">On this page</div>`;
  sections.forEach(s => {
    h += `<a href="#${s.id}">${esc(s.title)}</a>`;
    (s.groups || []).forEach(g => {
      if (g.title) h += `<a class="sub" href="#${s.id}-${slug(g.title)}">${esc(g.title)}</a>`;
    });
  });
  return h + extra + legendHtml(legendKeys);
}

function topbarHtml(active) {
  const tab = (href, label, n, on) =>
    `<a href="${href}" class="${on ? "active" : ""}">${label}${n != null ? `<span class="n">${n}</span>` : ""}</a>`;
  const devTabs = DEVICES.map(d => {
    const c = counts(hwItems(d.id));
    return tab(deviceHref(d.id), esc(d.name), `${c.ok}/${tracked(c)}`, active === "device:" + d.id);
  }).join("");
  const shTabs = SHARED.map(p => {
    const c = counts(itemsOf(sharedPage(p.id)));
    return tab(p.href, p.nav, `${c.ok}/${tracked(c)}`, active === p.id);
  }).join("");
  return `<div class="inner">
    <a class="brand" href="index.html"><span class="dot"></span><b>Omarchy Mobile</b></a>
    <nav class="tabs">
      ${tab("index.html", "Overview", null, active === "overview")}
      ${tab("compare.html", "Compare", null, active === "compare")}
      <span class="sep" aria-hidden="true"></span>${devTabs}
      <span class="sep" aria-hidden="true"></span>${shTabs}
    </nav>
    <div class="tools"><button class="chip" id="themeBtn" title="switch light / dark">theme</button></div>
  </div>`;
}

function headerHtml(h) {
  return `<div class="eyebrow">${esc(h.eyebrow)}</div>
    <h1>${esc(h.title)}</h1>
    <p class="sub">${h.html ? h.blurb : esc(h.blurb)}</p>
    <div class="meta">${(h.meta || []).map(m => `<span class="mono">${m.html || esc(m)}</span>`).join("")}</div>`;
}

function toolbarHtml(keys, deviceSwitch) {
  const sw = deviceSwitch ? `<div class="devswitch" role="group" aria-label="Status shown for">
      <span class="lbl">Status on</span>
      <span class="chip" data-view="" aria-pressed="false">Shared</span>
      ${DEVICES.map(d => `<span class="chip" data-view="${d.id}" aria-pressed="false">${esc(d.name)}</span>`).join("")}
    </div>` : "";
  return `${sw}<div class="toolbar">
    ${["all", ...keys].map(k => `<span class="chip" data-filter="${k}" aria-pressed="${k === "all"}">${LABEL[k]}<span class="n" data-count="${k}"></span></span>`).join("")}
    <input type="search" id="q" placeholder="filter by name…" autocomplete="off">
  </div>`;
}

const footnoteHtml = () => `<div class="footnote">
  <h3>How to read these pages</h3>
  <ul>${SITE.howTo.map(h => `<li>${h}</li>`).join("")}</ul>
  <h3>Open decisions</h3>
  <ul>${SITE.open.map(h => `<li>${h}</li>`).join("")}</ul>
  <h3>Editing</h3>
  <ul><li>Statuses live in <code>plans/assets/data/</code>: one <code>device-&lt;id&gt;.js</code> per handset,
    plus <code>software.js</code> and <code>integration.js</code> for the shared layers. Change a status and
    reload — counts, bars, the comparison and filters recompute. See <code>plans/README.md</code>. These pages
    never ship to a phone.</li></ul>
</div>`;

const $ = id => document.getElementById(id);

/* --------------------------------------------------------------- overview */
function deviceCardHtml(d) {
  const items = hwItems(d.id);
  const c = counts(items);
  return `<a class="pagecard devcard" href="${deviceHref(d.id)}">
    <div class="devhead"><h3>${esc(d.name)}</h3><span class="stage">${esc(d.stage)}</span></div>
    <div class="devsub mono">${esc(d.codename)} · ${esc(d.soc)}</div>
    <p>${esc(d.summary)}</p>
    ${bar(c, items.length)}
    <div class="secpill" style="margin-bottom:8px">${c.ok}/${tracked(c)} hardware working · ${pill(c)}</div>
    <span class="go">open ${esc(d.name)} →</span></a>`;
}

function sharedCardHtml(p) {
  const pg = sharedPage(p.id);
  const items = itemsOf(pg);
  const c = counts(items);
  const per = DEVICES.map(d => {
    const dc = counts(items, i => onDevice(i, d.id).s);
    return `<span><b>${dc.ok}</b> on ${esc(d.name)}</span>`;
  }).join("");
  return `<a class="pagecard" href="${p.href}">
    <h3>${p.nav}</h3><p>${esc(pg.cardBlurb || pg.blurb)}</p>
    ${bar(c, items.length)}
    <div class="secpill" style="margin-bottom:6px">${pill(c)}</div>
    <div class="perdev">Working ${per}</div>
    <span class="go">open ${p.nav.toLowerCase()} →</span></a>`;
}

function capCell(dev, cap) {
  const r = capStatus(dev, cap.id);
  if (r.s === "untracked") {
    return `<td class="cell untracked"><span title="No row on this device's page yet">—</span></td>`;
  }
  const d = deviceById(dev);
  const detail = r.rows.map(x => `${x.n}: ${LABEL[x.s].toLowerCase()}`).join("\n");
  return `<td class="cell ${TONE[r.s]}"><a href="${deviceHref(dev)}#cap-${cap.id}" title="${esc(d.name + "\n" + detail)}">${ICON[r.s]}<span>${LABEL[r.s]}</span></a></td>`;
}

function matrixHtml(filterCap) {
  const head = `<thead><tr><th class="capcol">Capability</th>${DEVICES.map(d => {
    const c = counts(hwItems(d.id));
    return `<th><a href="${deviceHref(d.id)}">${esc(d.name)}</a><div class="thsub">${c.ok}/${tracked(c)} working</div></th>`;
  }).join("")}</tr></thead>`;
  const body = CAPS.map(g => {
    const rows = g.items.filter(filterCap || (() => true));
    if (!rows.length) return "";
    return `<tbody><tr class="grp" id="g-${slug(g.group)}"><th colspan="${DEVICES.length + 1}">${esc(g.group)}</th></tr>
      ${rows.map(cap => {
        const st = DEVICES.map(d => capStatus(d.id, cap.id).s);
        const same = st.every(s => s === st[0]);
        return `<tr data-same="${same}" data-text="${esc(cap.n.toLowerCase())}"><th class="capcol">${esc(cap.n)}</th>${DEVICES.map(d => capCell(d.id, cap)).join("")}</tr>`;
      }).join("")}</tbody>`;
  }).join("");
  return `<div class="matrixwrap"><table class="matrix">${head}${body}</table></div>`;
}

function renderOverview() {
  $("topbar").innerHTML = topbarHtml("overview");
  const L = SITE.landing;
  $("head").innerHTML = headerHtml({ ...L, meta: [`${DEVICES.length} devices`, ...L.meta] });
  $("nav").innerHTML = `<div class="navtitle">Devices</div>`
    + DEVICES.map(d => `<a href="${deviceHref(d.id)}">${esc(d.name)}</a>`).join("")
    + `<a href="compare.html">Compare devices</a>`
    + `<div class="navtitle" style="margin-top:14px">Shared</div>`
    + SHARED.map(p => `<a href="${p.href}">${p.nav}</a>` + sharedPage(p.id).sections.slice(0, 6)
        .map(s => `<a class="sub" href="${p.href}#${s.id}">${esc(s.title)}</a>`).join("")).join("")
    + legendHtml(["ok", "partial", "no", "absent"]);

  const sw = counts(itemsOf(PAGE_SOFTWARE));
  $("summary").innerHTML = `<div class="summary">
    <div class="stat"><div class="big">${DEVICES.length}</div><div class="lbl">devices</div></div>
    ${DEVICES.map(d => { const c = counts(hwItems(d.id));
      return `<div class="stat ok"><div class="big">${c.ok}<small>/${tracked(c)}</small></div><div class="lbl">${esc(d.name)} hardware</div></div>`; }).join("")}
    <div class="stat ok"><div class="big">${sw.ok}<small>/${tracked(sw)}</small></div><div class="lbl">shared software</div></div>
  </div>`;

  $("content").innerHTML = `
    <section class="sec" id="devices"><div class="sechead"><h2>Devices</h2></div>
      <p class="secblurb">Each handset has its own bring-up: kernel, firmware, boot and hardware adapters. Open one for
      every component and its evidence.</p>
      <div class="pages">${DEVICES.map(deviceCardHtml).join("")}</div></section>
    <section class="sec" id="shared"><div class="sechead"><h2>Shared across devices</h2></div>
      <p class="secblurb">One mobile shell, one set of apps and one desktop link for every device. Each row shows which
      handsets it has been verified on.</p>
      <div class="pages">${SHARED.map(sharedCardHtml).join("")}</div></section>
    <section class="sec" id="glance"><div class="sechead"><h2>At a glance</h2>
      <span class="secpill"><a href="compare.html">full comparison →</a></span></div>
      ${matrixHtml(c => c.key)}</section>`;
  $("foot").innerHTML = footnoteHtml();
  document.title = "Omarchy Mobile — project plan";
}

/* --------------------------------------------------------------- compare */
function renderCompare() {
  $("topbar").innerHTML = topbarHtml("compare");
  $("head").innerHTML = headerHtml({
    eyebrow: "Project plan · Compare devices", title: "Compare devices",
    blurb: "What a phone owner would ask about, side by side. Each cell rolls up that device's hardware rows: all "
         + "working shows working, none working shows not working, anything between shows partial. Hover for the "
         + "rows behind a cell; click to jump to them.",
    meta: SITE.meta
  });
  $("nav").innerHTML = `<div class="navtitle">On this page</div>`
    + CAPS.map(g => `<a href="#g-${slug(g.group)}">${esc(g.group)}</a>`).join("")
    + `<a href="#software-by-device">Shared software by device</a>`
    + legendHtml(["ok", "partial", "no", "absent"]);
  $("toolbar").innerHTML = `<div class="toolbar">
    <span class="chip" data-mfilter="all" aria-pressed="true">All capabilities</span>
    <span class="chip" data-mfilter="diff" aria-pressed="false">Only where devices differ</span>
    <input type="search" id="q" placeholder="filter by name…" autocomplete="off"></div>`;

  const perSection = (pg, href) => pg.sections.map(sec => {
    const items = groupsOf(sec).flatMap(g => g.items);
    return `<tr><th class="capcol"><a href="${href}#${sec.id}">${esc(sec.title)}</a></th>${DEVICES.map(d => {
      const c = counts(items, i => onDevice(i, d.id).s);
      return `<td class="cell"><a href="${href}?d=${d.id}#${sec.id}">${bar(c, items.length)}<span class="frac">${c.ok}/${items.length} working${c.untested ? ` · ${c.untested} not tried` : ""}</span></a></td>`;
    }).join("")}</tr>`;
  }).join("");

  $("content").innerHTML = matrixHtml()
    + `<section class="sec" id="software-by-device" style="margin-top:36px">
        <div class="sechead"><h2>Shared software by device</h2></div>
        <p class="secblurb">The shell and integration are shared, but each piece still has to be tried on each handset.
        Counts per section; open one to see the rows.</p>
        <div class="matrixwrap"><table class="matrix bars"><thead><tr><th class="capcol">Section</th>${DEVICES.map(d => `<th>${esc(d.name)}</th>`).join("")}</tr></thead>
        <tbody><tr class="grp"><th colspan="${DEVICES.length + 1}">Software</th></tr>${perSection(PAGE_SOFTWARE, "software.html")}</tbody>
        <tbody><tr class="grp"><th colspan="${DEVICES.length + 1}">Integration</th></tr>${perSection(PAGE_INTEGRATION, "integration.html")}</tbody>
        </table></div></section>`;
  $("foot").innerHTML = footnoteHtml();
  document.title = "Compare devices · Omarchy Mobile plan";

  let mf = "all", q = "";
  const apply = () => document.querySelectorAll(".matrix:not(.bars) tbody tr:not(.grp)").forEach(tr => {
    tr.hidden = (mf === "diff" && tr.dataset.same === "true") || (q && !tr.dataset.text.includes(q));
  });
  document.querySelectorAll("[data-mfilter]").forEach(ch => ch.addEventListener("click", () => {
    document.querySelectorAll("[data-mfilter]").forEach(x => x.setAttribute("aria-pressed", String(x === ch)));
    mf = ch.dataset.mfilter; apply();
  }));
  $("q").addEventListener("input", e => { q = e.target.value.trim().toLowerCase(); apply(); });
}

/* --------------------------------------------------------------- device */
function renderDevice(id) {
  const d = deviceById(id);
  if (!d || !HW[id]) {
    $("topbar").innerHTML = topbarHtml(null);
    $("head").innerHTML = headerHtml({ eyebrow: "Project plan", title: "Unknown device",
      blurb: `No device “${id || ""}” here. Pick one from the bar above.`, meta: [] });
    return;
  }
  const page = HW[id];
  const items = itemsOf(page);
  $("topbar").innerHTML = topbarHtml("device:" + id);
  $("head").innerHTML = headerHtml({
    eyebrow: `Device · ${d.codename}`, title: d.name,
    blurb: `${esc(d.summary)} <span class="muted">${esc(page.blurb || "")}</span>`, html: true,
    meta: [d.soc, d.stage, ...d.meta,
      { html: `<a href="${esc(refHref(d.readme))}">README</a>` },
      { html: `<a href="${esc(refHref(d.status))}">current status</a>` }]
  });

  const seen = new Set();
  const anchors = it => (it.cap && !seen.has(it.cap)) ? (seen.add(it.cap), "cap-" + it.cap) : null;
  const swSummary = SHARED.map(p => {
    const all = itemsOf(sharedPage(p.id));
    const c = counts(all, i => onDevice(i, id).s);
    return `<a class="pagecard" href="${p.href}?d=${id}"><h3>${p.nav} on the ${esc(d.name)}</h3>
      ${bar(c, all.length)}<div class="secpill" style="margin-bottom:8px">${pill(c)}</div>
      <span class="go">open ${p.nav.toLowerCase()} for this device →</span></a>`;
  }).join("");

  const c = counts(items);
  $("summary").innerHTML = `<div class="summary">${["ok", "partial", "no", "absent"].filter(k => c[k]).map(k => statHtml(k, c[k])).join("")}
    <div class="stat"><div class="big">${items.length}</div><div class="lbl">tracked here</div></div></div>`;
  $("toolbar").innerHTML = toolbarHtml(["ok", "partial", "no", "absent"], false);
  $("content").innerHTML = page.sections.map(s => sectionHtml(s, undefined, undefined, anchors)).join("")
    + `<section class="sec" id="shared-on-device"><div class="sechead"><h2>Shared layers on this device</h2></div>
       <p class="secblurb">The shell and desktop link are common code; these counts show how much of it has been tried here.</p>
       <div class="pages">${swSummary}</div></section>`;
  $("nav").innerHTML = navHtml([...page.sections, { id: "shared-on-device", title: "Shared layers on this device" }],
    ["ok", "partial", "no", "absent"]);
  $("foot").innerHTML = footnoteHtml();
  document.title = `${d.name} · Omarchy Mobile plan`;
  wireFiltering(items, i => i.s);
}

/* --------------------------------------------------------------- shared pages */
function renderShared(id) {
  const page = sharedPage(id);
  const items = itemsOf(page);
  let view = param("d");
  if (view && !deviceById(view)) view = null;

  $("topbar").innerHTML = topbarHtml(id);
  $("head").innerHTML = headerHtml({ ...page, meta: SITE.meta });
  $("nav").innerHTML = navHtml(page.sections, ORDER);
  $("toolbar").innerHTML = toolbarHtml(ORDER, DEVICES.length > 1);

  const draw = () => {
    const stat = view ? (i => onDevice(i, view).s) : (i => i.s);
    const c = counts(items, stat);
    const dv = view && deviceById(view);
    $("summary").innerHTML = `<div class="summary">${ORDER.filter(k => c[k]).map(k => statHtml(k, c[k])).join("")}
      <div class="stat"><div class="big">${items.length}</div><div class="lbl">${dv ? "tracked · " + esc(dv.name) : "tracked here"}</div></div></div>`;
    $("content").innerHTML = page.sections.map(s => sectionHtml(s, view, stat)).join("");
    document.querySelectorAll("[data-view]").forEach(x => x.setAttribute("aria-pressed", String(x.dataset.view === (view || ""))));
    updateCounts(items, stat);
    applyFilter();
    document.title = `${page.title}${dv ? " on the " + dv.name : ""} · Omarchy Mobile plan`;
  };

  const setView = v => {
    view = v || null;
    const u = new URL(location.href);
    if (view) u.searchParams.set("d", view); else u.searchParams.delete("d");
    history.replaceState(null, "", u);
    draw();
  };
  document.querySelectorAll("[data-view]").forEach(ch => ch.addEventListener("click", () => setView(ch.dataset.view)));
  $("content").addEventListener("click", e => {
    const a = e.target.closest("a.dv");
    if (a) { e.preventDefault(); setView(a.dataset.dev === view ? null : a.dataset.dev); }
  });
  wireFiltering(items, null);
  draw();
}

/* --------------------------------------------------------------- filtering */
let filter = "all", query = "";

function applyFilter() {
  document.querySelectorAll(".card").forEach(card => {
    let any = false;
    card.querySelectorAll(".row").forEach(row => {
      const show = (filter === "all" || row.dataset.s === filter) && (!query || row.dataset.text.includes(query));
      row.classList.toggle("hidden", !show);
      if (show) any = true;
    });
    card.classList.toggle("hidden", !any);
  });
  document.querySelectorAll("section.sec").forEach(sec => {
    const cards = [...sec.querySelectorAll(".card")];
    sec.classList.toggle("hidden", cards.length > 0 && cards.every(c => c.classList.contains("hidden")));
  });
}

function updateCounts(items, stat) {
  const c = counts(items, stat);
  document.querySelectorAll("[data-count]").forEach(el => {
    const k = el.dataset.count;
    el.textContent = k === "all" ? items.length : (c[k] || 0);
    if (k !== "all") el.closest(".chip").hidden = !c[k];
  });
  if (filter !== "all" && !c[filter]) {
    filter = "all";
    document.querySelectorAll(".chip[data-filter]").forEach(x => x.setAttribute("aria-pressed", String(x.dataset.filter === "all")));
  }
}

function wireFiltering(items, stat) {
  if (stat) updateCounts(items, stat);
  document.querySelectorAll(".chip[data-filter]").forEach(chip => {
    chip.addEventListener("click", () => {
      document.querySelectorAll(".chip[data-filter]").forEach(x => x.setAttribute("aria-pressed", String(x === chip)));
      filter = chip.dataset.filter;
      applyFilter();
    });
  });
  $("q").addEventListener("input", e => {
    query = e.target.value.trim().toLowerCase();
    applyFilter();
  });
}

/* --------------------------------------------------------------- theme */
function wireTheme() {
  const root = document.documentElement;
  try { const saved = localStorage.getItem("omplan-theme"); if (saved) root.dataset.theme = saved; } catch (e) {}
  $("themeBtn").addEventListener("click", () => {
    root.dataset.theme = root.dataset.theme === "dark" ? "light" : "dark";
    try { localStorage.setItem("omplan-theme", root.dataset.theme); } catch (e) {}
  });
}

/* --------------------------------------------------------------- boot */
function loadDevices(done) {
  const base = document.currentScript ? document.currentScript.src.replace(/plan\.js(\?.*)?$/, "data/") : "assets/data/";
  let left = DEVICES.length;
  if (!left) return done();
  DEVICES.forEach(d => {
    const s = document.createElement("script");
    s.src = base + "device-" + d.id + ".js";
    s.onload = s.onerror = () => {
      if (!HW[d.id]) HW[d.id] = { blurb: "Device data failed to load.", sections: [] };
      if (--left === 0) done();
    };
    document.head.appendChild(s);
  });
}

function boot() {
  const page = document.documentElement.dataset.page || "overview";
  if (page === "overview") renderOverview();
  else if (page === "compare") renderCompare();
  else if (page === "device") renderDevice(param("d"));
  else renderShared(page);
  wireTheme();
  if (location.hash) { const t = document.getElementById(location.hash.slice(1)); if (t) t.scrollIntoView(); }
}

loadDevices(boot);
