/* ==========================================================================
   Omarchy Mobile project plan — shared renderer
   No build step, no modules, no network. Plain scripts, works from file://.
   Each page declares a PAGE_* object (see assets/data/*.js) and sets
   <html data-page="hardware|software|integration|overview">.
   ========================================================================== */

const PAGES = [
  { id: "hardware",    href: "hardware.html",    nav: "Hardware" },
  { id: "software",    href: "software.html",    nav: "Software" },
  { id: "integration", href: "integration.html", nav: "Integration" }
];

/* Resolved here because plan.js is always the last script loaded. */
const PAGE_BY_ID = { hardware: PAGE_HARDWARE, software: PAGE_SOFTWARE, integration: PAGE_INTEGRATION };
const allItems = () => PAGES.flatMap(p => itemsOf(PAGE_BY_ID[p.id]));

const ICON = {
  ok:      '<svg class="ico ok" viewBox="0 0 24 24" role="img" aria-label="working"><circle cx="12" cy="12" r="10" fill="currentColor" opacity=".16"/><path d="M7.2 12.6l3.1 3.1 6.5-6.9" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  partial: '<svg class="ico warn" viewBox="0 0 24 24" role="img" aria-label="partially working"><circle cx="12" cy="12" r="10" fill="currentColor" opacity=".16"/><path d="M12 2a10 10 0 0 1 0 20z" fill="currentColor" opacity=".3"/><path d="M7.2 12.6l3.1 3.1 6.5-6.9" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg>',
  no:      '<svg class="ico bad" viewBox="0 0 24 24" role="img" aria-label="not working"><circle cx="12" cy="12" r="10" fill="currentColor" opacity=".16"/><path d="M8.6 8.6l6.8 6.8M15.4 8.6l-6.8 6.8" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>',
  absent:  '<svg class="ico na" viewBox="0 0 24 24" role="img" aria-label="not present on this handset"><circle cx="12" cy="12" r="10" fill="currentColor" opacity=".14"/><path d="M8 12h8" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg>'
};

const LABEL = {
  ok: "Working", partial: "Partial", no: "Not working", absent: "Not present",
  all: "All"
};
const LEGEND = {
  ok: "Working — verified on the handset",
  partial: "Partial — running, not fully proven",
  no: "Not working — nothing usable yet",
  absent: "Not present on this handset (no hardware to bring up)"
};
const ORDER = ["ok", "partial", "no", "absent"];

const esc = s => String(s).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

const slug = s => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

function groupsOf(sec) {
  return sec.groups || [{ title: null, items: sec.items || [] }];
}
function itemsOf(sectionOrPage) {
  return sectionOrPage.sections.flatMap(s => groupsOf(s).flatMap(g => g.items));
}
function counts(items) {
  const c = { ok: 0, partial: 0, no: 0, absent: 0 };
  items.forEach(i => { c[i.s] = (c[i.s] || 0) + 1; });
  return c;
}
function bar(c, total) {
  const t = total || 1;
  return `<div class="bar" title="${c.ok} working, ${c.partial} partial, ${c.no} not working, ${c.absent} not present">
    ${ORDER.map(k => `<i class="${k === 'partial' ? 'warn' : k === 'no' ? 'bad' : k === 'absent' ? 'na' : 'ok'}" style="width:${(c[k] || 0) / t * 100}%"></i>`).join("")}
  </div>`;
}
function pill(c) {
  return `${c.ok} working · ${c.partial} partial · ${c.no} not working` + (c.absent ? ` · ${c.absent} not present` : "");
}

/* --------------------------------------------------------------- fragments */
function rowHtml(it) {
  return `<div class="row" data-s="${it.s}" data-text="${esc((it.n + " " + (it.note || "")).toLowerCase())}">
    ${ICON[it.s]}
    <div>
      <div class="name">${esc(it.n)}</div>
      ${it.note ? `<div class="note">${esc(it.note)}</div>` : ""}
      ${it.ref ? `<span class="ref mono">${esc(it.ref)}</span>` : ""}
    </div>
  </div>`;
}

function sectionHtml(sec) {
  const groups = groupsOf(sec);
  const all = groups.flatMap(g => g.items);
  const c = counts(all);

  let h = `<section class="sec" id="${sec.id}">
    <div class="sechead"><h2>${esc(sec.title)}</h2><span class="secpill">${pill(c)}</span></div>
    ${sec.blurb ? `<p class="secblurb">${esc(sec.blurb)}</p>` : ""}
    ${bar(c, all.length)}`;

  groups.forEach(g => {
    const gid = g.id || (sec.id + "-" + slug(g.title || "items"));
    const gc = counts(g.items);
    h += `<div class="card" id="${gid}">`;
    if (g.title) {
      h += `<h3>${esc(g.title)}<span class="counts">${gc.ok} / ${g.items.length}</span></h3>`;
    }
    if (g.note) h += `<div class="groupnote">${esc(g.note)}</div>`;
    h += g.items.map(rowHtml).join("");
    h += `</div>`;
  });

  if (sec.notes && sec.notes.length) {
    h += `<div class="card"><div class="groupnote">${sec.notes.map(n => `<p style="margin:0 0 8px">${esc(n)}</p>`).join("")}</div></div>`;
  }
  return h + `</section>`;
}

function navHtml(page) {
  let h = `<div class="navtitle">On this page</div>`;
  page.sections.forEach(s => {
    h += `<a href="#${s.id}">${esc(s.title)}</a>`;
    (s.groups || []).forEach(g => {
      if (g.title) h += `<a class="sub" href="#${s.id}-${slug(g.title)}">${esc(g.title)}</a>`;
    });
  });
  h += `<div class="legend"><h4>Status key</h4>`;
  ORDER.forEach(k => { h += `<div class="l">${ICON[k]} ${esc(LEGEND[k])}</div>`; });
  return h + `</div>`;
}

function topbarHtml(activeId) {
  const tabs = PAGES.map(p => {
    const t = counts(itemsOf(PAGE_BY_ID[p.id]));
    return `<a href="${p.href}" class="${p.id === activeId ? "active" : ""}">${p.nav}<span class="n">${t.ok}/${t.ok + t.partial + t.no}</span></a>`;
  }).join("");
  return `<div class="inner">
    <a class="brand" href="index.html"><span class="dot"></span><b>Omarchy Mobile</b><span>· OnePlus 7 Pro</span></a>
    <nav class="tabs">${tabs}</nav>
    <div class="tools"><button class="chip" id="themeBtn" title="switch light / dark">theme</button></div>
  </div>`;
}

function headerHtml(page) {
  return `<div class="eyebrow">${esc(page.eyebrow)}</div>
    <h1>${esc(page.title)}</h1>
    <p class="sub">${esc(page.blurb)}</p>
    <div class="meta">${(page.meta || SITE.meta).map(m => `<span class="mono">${esc(m)}</span>`).join("")}</div>`;
}

function summaryHtml(items) {
  const c = counts(items);
  return `<div class="summary">
    ${ORDER.map(k => `<div class="stat ${k === "partial" ? "warn" : k === "no" ? "bad" : k === "absent" ? "na" : "ok"}">
      <div class="big">${c[k] || 0}</div><div class="lbl">${LABEL[k].toLowerCase()}</div></div>`).join("")}
    <div class="stat"><div class="big">${items.length}</div><div class="lbl">tracked here</div></div>
  </div>`;
}

const toolbarHtml = () => `<div class="toolbar">
  ${["all", ...ORDER].map(k => `<span class="chip" data-filter="${k}" aria-pressed="${k === "all"}">${LABEL[k]}<span class="n" data-count="${k}"></span></span>`).join("")}
  <input type="search" id="q" placeholder="filter by name…" autocomplete="off">
</div>`;

const footnoteHtml = () => `<div class="footnote">
  <h3>How to read this page</h3>
  <ul>${SITE.howTo.map(h => `<li>${h}</li>`).join("")}</ul>
  <h3>Open decisions</h3>
  <ul>${SITE.open.map(h => `<li>${h}</li>`).join("")}</ul>
  <h3>Editing</h3>
  <ul><li>Statuses live in <code>plans/assets/data/*.js</code>. Change <code>s: "no"</code> to
    <code>"partial"</code> or <code>"ok"</code> and reload — counts, bars and filters recompute.
    See <code>plans/README.md</code>. This page never ships to the phone.</li></ul>
</div>`;

/* --------------------------------------------------------------- rendering */
function renderPage(id) {
  const page = PAGE_BY_ID[id];
  const items = itemsOf(page);
  const total = allItems();

  document.getElementById("topbar").innerHTML = topbarHtml(id);
  document.getElementById("head").innerHTML = headerHtml(page);
  document.getElementById("nav").innerHTML = navHtml(page);

  const c = counts(items);
  const stats = ORDER.filter(k => c[k]).map(k =>
    `<div class="stat ${k === "partial" ? "warn" : k === "no" ? "bad" : k === "absent" ? "na" : "ok"}">
       <div class="big">${c[k]}</div><div class="lbl">${LABEL[k].toLowerCase()}</div></div>`).join("");
  const t = counts(total);
  document.getElementById("summary").innerHTML = `<div class="summary">
    ${stats}
    <div class="stat"><div class="big">${items.length}</div><div class="lbl">tracked here</div></div>
    <div class="stat"><div class="big">${t.ok}<small style="font-size:14px;color:var(--faint)">/${t.ok + t.partial + t.no}</small></div><div class="lbl">working, whole project</div></div>
  </div>`;

  document.getElementById("content").innerHTML = page.sections.map(sectionHtml).join("");
  document.getElementById("foot").innerHTML = footnoteHtml();
  document.title = `${page.title} · Omarchy Mobile plan`;
}

function renderOverview() {
  const total = allItems();
  const c = counts(total);

  document.getElementById("topbar").innerHTML = topbarHtml(null);
  document.getElementById("head").innerHTML = headerHtml(SITE.landing);
  document.getElementById("nav").innerHTML = (() => {
    let h = `<div class="navtitle">Sections</div>`;
    PAGES.forEach(p => {
      const pg = PAGE_BY_ID[p.id];
      h += `<a href="${p.href}">${p.nav}</a>` + pg.sections.slice(0, 8).map(s => `<a class="sub" href="${p.href}#${s.id}">${esc(s.title)}</a>`).join("");
    });
    h += `<div class="legend"><h4>Status key</h4>`;
    ORDER.forEach(k => { h += `<div class="l">${ICON[k]} ${esc(LEGEND[k])}</div>`; });
    return h + "</div>";
  })();

  document.getElementById("summary").innerHTML = `<div class="summary">
    ${ORDER.map(k => `<div class="stat ${k === "partial" ? "warn" : k === "no" ? "bad" : k === "absent" ? "na" : "ok"}">
      <div class="big">${c[k]}</div><div class="lbl">${LABEL[k].toLowerCase()}</div></div>`).join("")}
    <div class="stat"><div class="big">${total.length}</div><div class="lbl">tracked items</div></div>
  </div>`;

  document.getElementById("content").innerHTML = `<div class="pages">
    ${PAGES.map(p => {
      const pg = PAGE_BY_ID[p.id];
      const pc = counts(itemsOf(pg));
      return `<a class="pagecard" href="${p.href}">
        <h3>${p.nav}</h3><p>${esc(pg.cardBlurb || pg.blurb)}</p>
        ${bar(pc, itemsOf(pg).length)}
        <div class="secpill" style="margin-bottom:8px">${pill(pc)}</div>
        <span class="go">open ${p.nav.toLowerCase()} →</span></a>`;
    }).join("")}
  </div>`;

  document.getElementById("foot").innerHTML = footnoteHtml();
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

function wireFiltering(items) {
  const c = counts(items);
  document.querySelectorAll("[data-count]").forEach(el => {
    const k = el.dataset.count;
    el.textContent = k === "all" ? items.length : (c[k] || 0);
    if (k !== "all" && !c[k]) el.closest(".chip").hidden = true;
  });
  document.querySelectorAll(".chip[data-filter]").forEach(chip => {
    chip.addEventListener("click", () => {
      document.querySelectorAll(".chip[data-filter]").forEach(x => x.setAttribute("aria-pressed", String(x === chip)));
      filter = chip.dataset.filter;
      applyFilter();
    });
  });
  document.getElementById("q").addEventListener("input", e => {
    query = e.target.value.trim().toLowerCase();
    applyFilter();
  });
}

/* --------------------------------------------------------------- theme */
function wireTheme() {
  const root = document.documentElement;
  try { const saved = localStorage.getItem("omplan-theme"); if (saved) root.dataset.theme = saved; } catch (e) {}
  document.getElementById("themeBtn").addEventListener("click", () => {
    root.dataset.theme = root.dataset.theme === "dark" ? "light" : "dark";
    try { localStorage.setItem("omplan-theme", root.dataset.theme); } catch (e) {}
  });
}

/* --------------------------------------------------------------- boot */
const PAGE_ID = document.documentElement.dataset.page || "overview";
document.getElementById("topbar").className = "topbar";

if (PAGE_ID === "overview") {
  renderOverview();
} else {
  document.getElementById("toolbar").innerHTML = toolbarHtml();
  renderPage(PAGE_ID);
  wireFiltering(itemsOf(PAGE_BY_ID[PAGE_ID]));
}
wireTheme();
