"use strict";
/* Earth Capture: the map page. Talks to the local server (server.py) through /api/<call>. */

const $ = (s) => document.querySelector(s);
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));

async function api(name, args = {}) {
  const r = await fetch(`/api/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Token": window.TOKEN },
    body: JSON.stringify(args),
  });
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || r.statusText);
  return j;
}

function toast(msg) { console.log(msg); $("#settings-msg").textContent = msg; }

/* ---------------------------------------------------------------- map */
const map = L.map("map", { zoomControl: true, worldCopyJump: true }).setView([20, 10], 3);
const satellite = L.tileLayer("https://tiles.maps.eox.at/wmts/1.0.0/s2cloudless-2023_3857/default/g/{z}/{y}/{x}.jpg", {
  maxZoom: 19, maxNativeZoom: 15,
  attribution: 'Sentinel-2 cloudless 2023 by <a href="https://s2maps.eu">EOX IT Services GmbH</a> (contains modified Copernicus Sentinel data 2023)',
}).addTo(map);
const streets = L.tileLayer("https://tile.openstreetmap.org/{z}/{x}/{y}.png", {
  maxZoom: 19, attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors',
});
const queueLayer = L.layerGroup().addTo(map);
const overlayLayer = L.layerGroup().addTo(map);
L.control.layers({ "Satellite (Sentinel-2)": satellite, "Streets (OpenStreetMap)": streets },
  { "Queued areas": queueLayer, "Scene preview and views": overlayLayer }, { collapsed: true }).addTo(map);
L.control.scale({ imperial: false }).addTo(map);

/* ---------------------------------------------------------------- the area being chosen */
let area = null;            // {west, south, east, north, name}
let areaRect = null;
let handles = [];
let drawing = false;
let drawStart = null;

function squareAt(lat, lon, side) {
  const mLat = 111132.92 - 559.82 * Math.cos(2 * lat * Math.PI / 180);
  const mLon = 111412.84 * Math.cos(lat * Math.PI / 180);
  const dLat = side / 2 / mLat, dLon = side / 2 / mLon;
  return { south: lat - dLat, north: lat + dLat, west: lon - dLon, east: lon + dLon };
}

function setArea(b, name) {
  area = { west: Math.min(b.west, b.east), east: Math.max(b.west, b.east),
           south: Math.min(b.south, b.north), north: Math.max(b.south, b.north),
           name: name ?? (area ? area.name : "Area") };
  const bounds = [[area.south, area.west], [area.north, area.east]];
  if (!areaRect) {
    areaRect = L.rectangle(bounds, { color: "#ff3df5", weight: 2, fillOpacity: 0.08, interactive: false }).addTo(map);
  } else {
    areaRect.setBounds(bounds);
  }
  placeHandles();
  $("#area-card").classList.remove("hidden");
  $("#area-name").value = area.name;
  areaInfoSoon();
}

function clearArea() {
  area = null;
  if (areaRect) { map.removeLayer(areaRect); areaRect = null; }
  handles.forEach((h) => map.removeLayer(h));
  handles = [];
  $("#area-card").classList.add("hidden");
}

function placeHandles() {
  handles.forEach((h) => map.removeLayer(h));
  handles = [];
  const icon = L.divIcon({ className: "handle" });
  const corners = [["south", "west"], ["south", "east"], ["north", "east"], ["north", "west"]];
  corners.forEach(([ns, ew]) => {
    const m = L.marker([area[ns], area[ew]], { draggable: true, icon }).addTo(map);
    m.on("drag", (e) => {
      const p = e.target.getLatLng();
      const b = { ...area };
      b[ns] = p.lat; b[ew] = p.lng;
      setAreaLive(b);
    });
    m.on("dragend", () => placeHandles());
    handles.push(m);
  });
  const mid = L.marker([(area.south + area.north) / 2, (area.west + area.east) / 2],
    { draggable: true, icon: L.divIcon({ className: "handle", html: "" }), title: "Drag to move the area" }).addTo(map);
  let start = null;
  mid.on("dragstart", () => { start = { ...area, c: mid.getLatLng() }; });
  mid.on("drag", (e) => {
    const p = e.target.getLatLng();
    const dLat = p.lat - start.c.lat, dLon = p.lng - start.c.lng;
    setAreaLive({ west: start.west + dLon, east: start.east + dLon, south: start.south + dLat, north: start.north + dLat });
  });
  mid.on("dragend", () => placeHandles());
  handles.push(mid);
}

function setAreaLive(b) {
  area = { ...area, west: Math.min(b.west, b.east), east: Math.max(b.west, b.east),
           south: Math.min(b.south, b.north), north: Math.max(b.south, b.north) };
  areaRect.setBounds([[area.south, area.west], [area.north, area.east]]);
  areaInfoSoon();
}

let infoTimer = null;
function areaInfoSoon() { clearTimeout(infoTimer); infoTimer = setTimeout(areaInfo, 250); }
async function areaInfo() {
  if (!area) return;
  try {
    const i = await api("area_info", { area });
    const e = i.estimate;
    $("#area-facts").innerHTML =
      `${i.width_m} × ${i.height_m} m (${i.area_km2} km²)<br>` +
      `${e.views} views · images about ${e.image_px} px · ${e.resolution_m} m resolution, LR ${e.lr_resolution_m.join(" / ")} m`;
    $("#area-problems").innerHTML = i.problems.map(esc).join("<br>");
    $("#add-btn").disabled = i.problems.length > 0;
  } catch (err) { $("#area-problems").textContent = err.message; }
}

$("#area-name").addEventListener("input", () => { if (area) area.name = $("#area-name").value; });
$("#clear-area-btn").addEventListener("click", clearArea);

$("#draw-btn").addEventListener("click", () => {
  drawing = !drawing;
  $("#draw-btn").classList.toggle("active", drawing);
  map.getContainer().classList.toggle("drawing", drawing);
  if (drawing) map.dragging.disable(); else map.dragging.enable();
});
map.on("mousedown", (e) => { if (drawing) { drawStart = e.latlng; } });
map.on("mousemove", (e) => {
  if (!drawing || !drawStart) return;
  const b = { south: drawStart.lat, north: e.latlng.lat, west: drawStart.lng, east: e.latlng.lng };
  if (!areaRect) setArea(b, "Area"); else setAreaLive(b);
});
map.on("mouseup", () => {
  if (!drawing || !drawStart) return;
  drawStart = null;
  drawing = false;
  $("#draw-btn").classList.remove("active");
  map.getContainer().classList.remove("drawing");
  map.dragging.enable();
  if (area) placeHandles();
});

$("#square-btn").addEventListener("click", () => {
  const c = map.getCenter();
  const side = Number($("#square-size").value) || 500;
  setArea(squareAt(c.lat, c.lng, side), area ? area.name : "Area");
  if (map.getZoom() < 14) map.setView(c, 15);
});

$("#add-btn").addEventListener("click", async () => {
  if (!area) return;
  area.name = $("#area-name").value || "Area";
  try {
    const r = await api("add", { area });
    if (!r.ok) { $("#area-problems").innerHTML = r.problems.map(esc).join("<br>"); return; }
    selected = r.id;
    clearArea();
    refresh(true);
  } catch (err) { $("#area-problems").textContent = err.message; }
});

/* ---------------------------------------------------------------- search */
$("#search-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const q = $("#search").value.trim();
  if (!q) return;
  $("#search-results").innerHTML = '<li class="muted">Searching…</li>';
  try {
    const res = await api("search", { q });
    $("#search-results").innerHTML = res.length ? "" : '<li class="muted">Nothing found.</li>';
    res.forEach((p) => {
      const li = document.createElement("li");
      li.textContent = p.name;
      li.addEventListener("click", () => {
        const [w, s, e, n] = p.bbox;
        map.fitBounds([[s, w], [n, e]], { maxZoom: 16 });
        const side = Number($("#square-size").value) || 500;
        setArea(squareAt(p.lat, p.lon, side), p.name.split(",")[0]);
        $("#search-results").innerHTML = "";
      });
      $("#search-results").appendChild(li);
    });
  } catch (err) { $("#search-results").innerHTML = `<li class="problems">${esc(err.message)}</li>`; }
});

/* ---------------------------------------------------------------- queue */
let state = null;
let selected = null;
let lastQueueKey = "";
let lastResultsKey = "";
const STATUS_COLOUR = { queued: "#8a94a0", downloading: "#1f6feb", ready: "#1f6feb", running: "#1f6feb",
  done: "#1e8e3e", partial: "#b26a00", stopped: "#b26a00", waiting: "#c0392b", failed: "#c0392b" };

function renderQueue(q) {
  const key = JSON.stringify(q.map((i) => [i.id, i.status, i.views_done, i.views_total, i.message, i.label])) + selected;
  if (key === lastQueueKey) return;
  lastQueueKey = key;
  const done = q.filter((i) => i.status === "done").length;
  $("#queue-count").textContent = q.length ? `${done} of ${q.length} done` : "";
  const ul = $("#queue");
  ul.innerHTML = q.length ? "" : '<li class="muted">No areas yet. Choose one above, or Suggest places.</li>';
  queueLayer.clearLayers();
  q.forEach((it) => {
    const a = it.area;
    const name = it.label || a.name;
    const li = document.createElement("li");
    if (it.id === selected) li.classList.add("selected");
    const counts = it.views_total ? ` · ${it.views_done}/${it.views_total} views` : "";
    li.innerHTML = `<div class="q-head"><span class="q-name" title="${esc(it.id)}">${esc(name)}</span>
      <span class="status ${esc(it.status)}">${esc(it.status_text)}</span></div>
      <div class="q-msg">${esc(it.id.split("_").slice(-1)[0])}${counts}${it.message ? " · " + esc(it.message) : ""}</div>
      <div class="q-actions"></div>`;
    const acts = li.querySelector(".q-actions");
    const btn = (label, fn, title = "") => {
      const b = document.createElement("button");
      b.type = "button"; b.textContent = label; b.title = title;
      b.addEventListener("click", (ev) => { ev.stopPropagation(); fn(); });
      acts.appendChild(b);
    };
    btn("Make", () => api("run", { ids: [it.id] }).then(() => refresh(true)), "Make the SAR images of this area only");
    if (["ready", "done", "partial", "stopped", "running"].includes(it.status)) {
      btn("Blender", () => api("open_blender", { id: it.id }).catch((e) => alert(e.message)), "Place extra views by hand in Blender");
    }
    if (["waiting", "failed", "stopped"].includes(it.status)) btn("Retry", () => api("retry", { id: it.id }).then(() => refresh(true)));
    btn("Rename", () => { const n = prompt("Name", name); if (n) api("rename", { id: it.id, name: n }).then(() => refresh(true)); });
    btn("Remove", () => { if (confirm(`Remove ${name} from the queue? Its files stay in the runs folder.`)) api("remove", { id: it.id }).then(() => refresh(true)); });
    li.addEventListener("click", () => select(it.id, true));
    ul.appendChild(li);

    const r = L.rectangle([[a.south, a.west], [a.north, a.east]],
      { color: STATUS_COLOUR[it.status] || "#888", weight: it.id === selected ? 3 : 2, fillOpacity: 0.05 });
    r.bindTooltip(`${name}: ${it.status_text}`);
    r.on("click", () => select(it.id, false));
    queueLayer.addLayer(r);
  });
}

async function select(id, zoom) {
  selected = id;
  lastQueueKey = "";
  lastResultsKey = "";
  const it = state.queue.find((i) => i.id === id);
  if (!it) return;
  if (zoom) map.fitBounds([[it.area.south, it.area.west], [it.area.north, it.area.east]], { padding: [40, 40], maxZoom: 17 });
  renderQueue(state.queue);
  await showOverlays(id);
  await showResults(true);
}

async function showOverlays(id) {
  overlayLayer.clearLayers();
  try {
    const o = await api("overlays", { id });
    if (!o.ok) return;
    L.imageOverlay(o.materials, o.bounds, { opacity: 0.6, interactive: false }).addTo(overlayLayer);
    const res = await fetch(o.buildings);
    const fc = await res.json();
    const colour = { height: "#e74c3c", levels: "#f39c12", default: "#ffffff" };
    L.geoJSON(fc, {
      style: (f) => ({ color: colour[f.properties.height_source], weight: 1, fillOpacity: 0.25 }),
      onEachFeature: (f, l) => l.bindTooltip(`${f.properties.height_m} m (${f.properties.height_source}), ${f.properties.material}`),
    }).addTo(overlayLayer);
  } catch (err) { console.warn(err); }
}

/* ---------------------------------------------------------------- results */
async function showResults(force = false) {
  if (!selected) return;
  const it = state.queue.find((i) => i.id === selected);
  if (!it) return;
  const key = `${selected}|${it.views_done}|${it.status}`;
  if (!force && key === lastResultsKey) return;
  lastResultsKey = key;
  $("#results-of").textContent = `· ${it.label || it.area.name}`;
  let res = [];
  try { res = await api("results", { id: selected }); } catch (err) { console.warn(err); }
  const g = $("#results");
  const done = res.filter((r) => r.hr);
  if (!done.length) {
    g.innerHTML = `<p class="muted">No images yet${res.length ? ` (${res.length} views, none finished)` : ""}.</p>`;
    return;
  }
  g.innerHTML = '<p class="muted small">Shown in map orientation, as the export writes them. Click to enlarge.</p>';
  done.forEach((r) => {
    const d = document.createElement("div");
    d.className = "shot";
    const lr = r.lr.map((l) => `<img src="${l.url}" data-cap="LR ×${l.factor} · ${esc(r.view)}" class="flip" alt="LR x${l.factor}">`).join("");
    d.innerHTML = `<div class="cap">bearing ${Number(r.bearing).toFixed(0)}° · incidence ${Number(r.incidence).toFixed(0)}° · ${esc(r.view)}${r.from === "blender" ? " · from Blender" : ""}</div>
      <div class="imgs"><img src="${r.hr}" data-cap="HR · ${esc(r.view)}" class="flip" alt="HR">${lr}</div>`;
    d.addEventListener("mouseenter", () => highlightFootprint(r));
    g.appendChild(d);
    if (r.footprint) {
      L.polygon(r.footprint.map(([lon, lat]) => [lat, lon]), { color: "#00e5ff", weight: 1, fill: false, dashArray: "4 3" })
        .bindTooltip(r.view).addTo(overlayLayer);
    }
  });
  g.querySelectorAll("img").forEach((img) => img.addEventListener("click", () => {
    $("#lb-img").src = img.src;
    $("#lb-img").className = img.className;
    $("#lb-cap").textContent = img.dataset.cap;
    $("#lightbox").classList.remove("hidden");
  }));
}
let fpLayer = null;
function highlightFootprint(r) {
  if (fpLayer) overlayLayer.removeLayer(fpLayer);
  if (!r.footprint) return;
  fpLayer = L.polygon(r.footprint.map(([lon, lat]) => [lat, lon]), { color: "#00e5ff", weight: 3, fillOpacity: 0.15 }).addTo(overlayLayer);
}
$("#lightbox").addEventListener("click", () => $("#lightbox").classList.add("hidden"));

/* ---------------------------------------------------------------- actions */
$("#prepare-btn").addEventListener("click", () => api("prepare", {}).then(() => refresh(true)));
$("#run-btn").addEventListener("click", () => api("run", {}).then(() => refresh(true)));
$("#stop-btn").addEventListener("click", () => api("stop", {}).then(() => refresh(true)));
$("#export-btn").addEventListener("click", () => {
  const lr = document.querySelector('input[name="lr-size"]:checked').value;
  api("export", { lr_size: lr }).then(() => refresh(true));
});
$("#open-datasets-btn").addEventListener("click", () => {
  const p = state?.worker?.last_result?.export?.dir || state?.paths?.datasets;
  if (p) api("open_folder", { path: p });
});

$("#suggest-btn").addEventListener("click", () => $("#suggest-dlg").showModal());
$("#suggest-dlg").addEventListener("close", async () => {
  if ($("#suggest-dlg").returnValue !== "ok") return;
  const f = new FormData($("#suggest-form"));
  let region = null;
  if (f.get("where") === "view") {
    const b = map.getBounds();
    region = [Math.max(-180, b.getWest()), Math.max(-85, b.getSouth()), Math.min(180, b.getEast()), Math.min(85, b.getNorth())];
  }
  await api("suggest", { kind: f.get("kind"), region, n: Number(f.get("n")), side_m: Number(f.get("side_m")), seed: Number(f.get("seed")) });
  refresh(true);
});

/* ---------------------------------------------------------------- settings */
let settingsLoaded = false;
function loadSettings(s) {
  const f = $("#settings-form");
  const v = s.views;
  f.bandwidth_mhz.value = String(v.bandwidth_mhz);
  f.factors.value = v.factors.join(" ");
  f.mode.value = v.mode;
  f.n_views.value = v.n_views;
  f.window_m.value = v.window_m;
  f.inc_lo.value = v.incidence_range[0];
  f.inc_hi.value = v.incidence_range[1];
  f.bearings.value = v.bearings.join(" ");
  f.seed.value = v.seed;
  f.grid_m.value = s.scene.grid_m;
}
$("#settings-form").addEventListener("submit", async (ev) => {
  ev.preventDefault();
  const f = ev.target;
  const nums = (t) => t.split(/[\s,]+/).filter(Boolean).map(Number);
  const views = {
    bandwidth_mhz: Number(f.bandwidth_mhz.value), factors: nums(f.factors.value), mode: f.mode.value,
    n_views: Number(f.n_views.value), window_m: Number(f.window_m.value),
    incidence_range: [Number(f.inc_lo.value), Number(f.inc_hi.value)], bearings: nums(f.bearings.value), seed: Number(f.seed.value),
  };
  const r = await api("settings", { views, scene: { grid_m: Number(f.grid_m.value) } });
  $("#settings-msg").textContent = r.ok ? "Saved." : r.problems.join(" ");
  if (r.ok) areaInfoSoon();
});

/* ---------------------------------------------------------------- polling */
function renderTools(t) {
  const chip = (name, path, need) => `<span class="chip ${path ? "" : (need ? "bad" : "")}" title="${esc(path || "not found")}">${name}: ${path ? "found" : "not found"}</span>`;
  $("#tools").innerHTML = chip("MATLAB", t.matlab, true) + chip("Blender", t.blender, false);
}

function renderWorker(w) {
  const show = w.busy || w.log.length > 0;
  $("#progress-sec").classList.toggle("hidden", !show);
  $("#stop-btn").classList.toggle("hidden", !w.busy);
  ["#prepare-btn", "#run-btn", "#export-btn", "#suggest-btn"].forEach((s) => { $(s).disabled = w.busy; });
  const [d, n] = w.progress;
  $("#task").textContent = w.busy ? `${w.task}${w.item ? ": " + w.item : ""}${n ? ` (${d}/${n} views)` : ""}${w.stopping ? " · stopping…" : ""}` : "Idle.";
  $("#bar-fill").style.width = n ? `${(100 * d) / n}%` : (w.busy ? "15%" : "0");
  const log = $("#log");
  const atEnd = log.scrollTop + log.clientHeight >= log.scrollHeight - 4;
  log.textContent = w.log.join("\n");
  if (atEnd) log.scrollTop = log.scrollHeight;
  const ex = w.last_result && w.last_result.export;
  if (ex) $("#export-result").innerHTML = `${ex.pairs} image pairs from ${ex.areas} areas →<br><code>${esc(ex.dir)}</code>`;
}

async function refresh(force = false) {
  try {
    state = await api("state");
  } catch (err) { console.warn(err); return; }
  renderTools(state.tools);
  if (force) lastQueueKey = "";
  renderQueue(state.queue);
  renderWorker(state.worker);
  if (!settingsLoaded) {
    loadSettings(state.settings);
    const k = $("#suggest-kind");
    Object.entries(state.kinds).forEach(([v, label]) => k.add(new Option(label, v)));
    settingsLoaded = true;
    if (state.queue.length) {
      const last = state.queue[state.queue.length - 1];
      map.fitBounds([[last.area.south, last.area.west], [last.area.north, last.area.east]], { padding: [60, 60], maxZoom: 15 });
    }
  }
  if (selected) showResults();
}

refresh(true);
setInterval(refresh, 1500);
