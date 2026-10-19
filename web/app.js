// WowSim browser side: draws the scene the server sends and forwards input.
"use strict";

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
const arr = v => Array.isArray(v) ? v : [];
const api = (path, body) => fetch(path, body === undefined ? {} : {
  method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body),
}).then(r => r.json());

const stage = $("#stage"), framesEl = $("#frames"), wrap = $("#stageWrap");
let W = 1365, H = 768, scale = 1;
let seq = { chat: 0, err: 0, snd: 0, msg: 0, stub: 0 };
let gen = -1, focusId = null, lastHover = null;
const els = new Map();          // key -> element
const sigs = new Map();         // key -> last item signature
let errors = [];
let pinnedInspect = null;

// ---------------------------------------------------------------- layout
let zoomMode = "fit";
function fit() {
  const r = wrap.getBoundingClientRect();
  const fitScale = Math.min(r.width / W, r.height / H);
  scale = zoomMode === "fit" ? fitScale : Number(zoomMode);
  stage.style.width = W + "px";
  stage.style.height = H + "px";
  const sw = W * scale, sh = H * scale;
  const x = Math.max(0, (r.width - sw) / 2), y = Math.max(0, (r.height - sh) / 2);
  $("#sizer").style.width = Math.max(sw, 1) + x * 2 + "px";
  $("#sizer").style.height = Math.max(sh, 1) + y * 2 + "px";
  stage.style.transform = `translate(${x}px, ${y}px) scale(${scale})`;
}
function setZoom(z, cx, cy) {
  const sc = $("#stageScroll");
  const before = scale;
  const r = sc.getBoundingClientRect();
  // keep the UI point under the cursor (or the centre) in place
  const px = cx ?? r.width / 2, py = cy ?? r.height / 2;
  const ux = (sc.scrollLeft + px) / before, uy = (sc.scrollTop + py) / before;
  zoomMode = z;
  $("#zoom").value = [...$("#zoom").options].some(o => o.value === String(z)) ? String(z) : $("#zoom").value;
  fit();
  sc.scrollLeft = ux * scale - px;
  sc.scrollTop = uy * scale - py;
}
window.addEventListener("resize", fit);

// ---------------------------------------------------------------- colors / text
const rgba = (c, mul = 1) => c ? `rgba(${Math.round(c[0] * 255)},${Math.round(c[1] * 255)},${Math.round(c[2] * 255)},${(c[3] ?? 1) * mul})` : "transparent";
const esc = s => s.replace(/[&<>"]/g, ch => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[ch]));

function iconUrl(path) {
  if (path == null) return null;
  if (typeof path === "number") {
    if (FILE_ICONS[path]) return zam(FILE_ICONS[path]);
    return zam("inv_misc_questionmark");
  }
  const p = String(path).replace(/\//g, "\\");
  const low = p.toLowerCase();
  if (/^\d+$/.test(p)) return iconUrl(Number(p));
  const m = low.match(/^interface\\icons\\(.+?)(\.blp|\.tga|\.png)?$/);
  if (m) return zam(m[1]);
  if (low.startsWith("interface\\addons\\")) return "/media?p=" + encodeURIComponent(p);
  if (!low.includes("\\")) return zam(low); // bare icon names
  return null;
}
const zam = n => `https://wow.zamimg.com/images/wow/icons/large/${n.toLowerCase()}.jpg`;
const FILE_ICONS = { 134400: "inv_misc_questionmark", 136243: "trade_engineering", 135932: "spell_holy_holybolt" };

// Blizzard art we can approximate with CSS.
const SOLID = /(white8x8|chatframebackground|ui-tooltip-background|tooltips\\ui-tooltip-background|interface\\buttons\\white8x8|solidtexture|interface\\common\\white)/;
const BARS = /(ui-statusbar|statusbar|raid-bar-hp-fill|ui-character-skills-bar|minimalist|bar-fill)/;
function builtin(low) {
  if (SOLID.test(low)) return { solid: [1, 1, 1, 1] };
  if (BARS.test(low)) return { bar: true };
  if (low.includes("buttonhilight") || low.includes("ui-common-mousehilight") || low.includes("questtitlehighlight") || low.includes("ui-listbox-highlight"))
    return { css: "background: radial-gradient(ellipse at center, rgba(255,255,255,.55), rgba(255,255,255,.12) 70%, transparent);" };
  if (low.includes("ui-quickslot-depress")) return { css: "background: rgba(0,0,0,.35); box-shadow: inset 0 0 6px #000;" };
  if (low.includes("ui-checkbox-check")) return { css: "background: none;", check: true };
  if (low.includes("iconalert") || low.includes("actionbar-spellalert") || low.includes("ui-actionbutton-border") || low.includes("checkbuttonglow"))
    return { css: "box-shadow: 0 0 6px 3px rgba(255,200,40,.8), inset 0 0 6px rgba(255,200,40,.6); border-radius: 4px;" };
  if (low.includes("tempportraitalphamask") || low.includes("circlemask")) return { css: "border-radius:50%; background: rgba(255,255,255,.08);" };
  if (low.includes("ui-tooltip-border")) return { css: "border: 2px solid rgba(160,160,160,.8); border-radius: 5px;" };
  if (low.includes("ui-panel-button-up") || low.includes("ui-dialogbox-button-up")) return { css: "background: linear-gradient(180deg,#8e1a12,#3e0705); border-radius:3px; border:1px solid #6d5a2b;" };
  return null;
}

function parseText(s, size) {
  // WoW escape sequences -> HTML.
  let out = "", i = 0, open = 0;
  s = String(s);
  while (i < s.length) {
    const ch = s[i];
    if (ch === "|" && i + 1 < s.length) {
      const n = s[i + 1];
      if (n === "|") { out += "|"; i += 2; continue; }
      if (n === "n") { out += "\n"; i += 2; continue; }
      if (n === "c" && /^[0-9a-fA-F]{8}$/.test(s.substr(i + 2, 8))) {
        const hex = s.substr(i + 4, 6);
        out += `<span style="color:#${hex}">`; open++; i += 10; continue;
      }
      if (n === "r") { if (open) { out += "</span>"; open--; } i += 2; continue; }
      if (n === "H") { const e = s.indexOf("|h", i + 2); if (e > 0) { i = e + 2; continue; } }
      if (n === "h") { i += 2; continue; }
      if (n === "T") {
        const e = s.indexOf("|t", i + 2);
        if (e > 0) {
          const parts = s.substring(i + 2, e).split(":");
          const h = Number(parts[1]) || size, w = Number(parts[2]) || h || size;
          const url = iconUrl(parts[0]);
          out += url ? `<img class="ti" src="${url}" style="width:${w || size}px;height:${h || size}px">` : `<i style="display:inline-block;width:${w || size}px;height:${h || size}px;outline:1px dashed #666"></i>`;
          i = e + 2; continue;
        }
      }
      if (n === "A") {
        const e = s.indexOf("|a", i + 2);
        if (e > 0) { out += `<i style="display:inline-block;width:${size}px;height:${size}px;outline:1px dashed #666"></i>`; i = e + 2; continue; }
      }
      if (n === "K") { const e = s.indexOf("|k", i + 2); if (e > 0) { out += "***"; i = e + 2; continue; } }
    }
    out += esc(ch);
    i++;
  }
  while (open--) out += "</span>";
  return out;
}

// Fonts: WoW path -> CSS family served by /font (same file the server measured with).
const fontFamilies = new Map();
function fontFamily(path) {
  const key = (path || "").toLowerCase();
  let fam = fontFamilies.get(key);
  if (fam) return fam;
  fam = "wf" + fontFamilies.size;
  fontFamilies.set(key, fam);
  const ff = new FontFace(fam, `url(/font?p=${encodeURIComponent(path || "")})`);
  ff.load().then(f => { document.fonts.add(f); sigs.clear(); }).catch(() => {});
  return fam;
}

function textShadow(item) {
  const parts = [];
  const fl = (item.fl || "").toUpperCase();
  const sc = item.sc || 1;
  if (fl.includes("OUTLINE")) {
    const w = (fl.includes("THICK") ? 2 : 1) * sc;
    parts.push(`${w}px 0 0 #000`, `-${w}px 0 0 #000`, `0 ${w}px 0 #000`, `0 -${w}px 0 #000`, `${w}px ${w}px 0 #000`, `-${w}px -${w}px 0 #000`, `${w}px -${w}px 0 #000`, `-${w}px ${w}px 0 #000`);
  }
  if (item.sh) parts.push(`${item.sh[4] * sc}px ${-item.sh[5] * sc}px 0 ${rgba(item.sh)}`);
  return parts.join(",");
}

// ---------------------------------------------------------------- rendering
function clipStyle(item, el) {
  const c = item.cl;
  if (!c) { el.style.clipPath = ""; return; }
  const t = Math.max(0, c[1] - item.y), l = Math.max(0, c[0] - item.x);
  const r = Math.max(0, item.x + item.w - (c[0] + c[2])), b = Math.max(0, item.y + item.h - (c[1] + c[3]));
  el.style.clipPath = (t || l || r || b) ? `inset(${t}px ${r}px ${b}px ${l}px)` : "";
  if (c[2] <= 0 || c[3] <= 0 || l >= item.w || t >= item.h) el.style.clipPath = "inset(100%)";
}

function place(el, item, z) {
  const s = el.style;
  s.left = item.x + "px"; s.top = item.y + "px";
  s.width = Math.max(0, item.w) + "px"; s.height = Math.max(0, item.h) + "px";
  s.opacity = item.a < 1 ? item.a : "";
  s.zIndex = z;
  clipStyle(item, el);
}

function drawTexture(el, item) {
  const s = el.style;
  el.className = "tex";
  el.innerHTML = "";
  s.background = ""; s.backgroundImage = ""; s.webkitMaskImage = ""; s.maskImage = ""; s.filter = ""; s.mixBlendMode = "";
  s.transform = item.rot ? `rotate(${-item.rot}rad)` : "";
  s.cssText += "";
  const vc = item.vc || [1, 1, 1, 1];
  let alphaMul = vc[3] ?? 1;
  if (item.g) {
    const a = item.g.a, b = item.g.b;
    const dir = (item.g.o || "").toUpperCase() === "VERTICAL" ? "to top" : "to right";
    s.background = `linear-gradient(${dir}, ${rgba([a[0] * vc[0], a[1] * vc[1], a[2] * vc[2], a[3] ?? 1])}, ${rgba([b[0] * vc[0], b[1] * vc[1], b[2] * vc[2], b[3] ?? 1])})`;
  } else if (item.c) {
    const c = item.c;
    s.background = rgba([c[0] * vc[0], c[1] * vc[1], c[2] * vc[2], (c[3] ?? 1)]);
  } else if (item.tex != null) {
    const low = String(item.tex).toLowerCase().replace(/\//g, "\\");
    const url = iconUrl(item.tex);
    const bi = url ? null : builtin(low);
    if (url) {
      const tc = item.tc || [0, 1, 0, 1];
      const tw = Math.max(0.0001, tc[1] - tc[0]), th = Math.max(0.0001, tc[3] - tc[2]);
      const bw = item.w / tw, bh = item.h / th;
      s.backgroundImage = `url("${url}")`;
      s.backgroundSize = `${bw}px ${bh}px`;
      s.backgroundPosition = `${-tc[0] * bw}px ${-tc[2] * bh}px`;
      if (item.tile) s.backgroundRepeat = "repeat";
      if (vc[0] < 0.99 || vc[1] < 0.99 || vc[2] < 0.99) {
        s.backgroundColor = rgba([vc[0], vc[1], vc[2], 1]);
        s.backgroundBlendMode = "multiply";
        s.webkitMaskImage = s.backgroundImage;
        s.webkitMaskSize = s.backgroundSize;
        s.webkitMaskPosition = s.backgroundPosition;
        s.webkitMaskRepeat = item.tile ? "repeat" : "no-repeat";
      }
    } else if (bi && bi.solid) {
      s.background = rgba([vc[0], vc[1], vc[2], 1]);
    } else if (bi && bi.bar) {
      s.background = `linear-gradient(180deg, ${rgba([Math.min(1, vc[0] * 1.25), Math.min(1, vc[1] * 1.25), Math.min(1, vc[2] * 1.25), 1])} 0%, ${rgba([vc[0], vc[1], vc[2], 1])} 45%, ${rgba([vc[0] * 0.6, vc[1] * 0.6, vc[2] * 0.6, 1])} 100%)`;
    } else if (bi && bi.css) {
      s.cssText += bi.css;
      if (bi.check) el.innerHTML = `<div style="position:absolute;left:30%;top:12%;width:26%;height:52%;border:solid ${rgba([vc[0], vc[1] * 0.82, 0, 1])};border-width:0 ${Math.max(2, item.w / 9)}px ${Math.max(2, item.w / 9)}px 0;transform:rotate(40deg)"></div>`;
    } else {
      el.classList.add("missing");
      el.title = String(item.tex);
      s.background = rgba([vc[0], vc[1], vc[2], 0.08]);
    }
  } else if (item.at) {
    el.classList.add("missing");
    el.title = "atlas: " + item.at;
    s.background = rgba([vc[0], vc[1], vc[2], 0.1]);
  }
  if (item.ds) s.filter = `grayscale(${item.ds === true ? 1 : item.ds})`;
  if (item.bm === "ADD" || item.bm === "MOD") s.mixBlendMode = item.bm === "ADD" ? "plus-lighter" : "multiply";
  if (alphaMul < 1) s.opacity = (item.a ?? 1) * alphaMul;
}

function drawFont(el, item) {
  el.className = "fs";
  const s = el.style;
  const sc = item.sc || 1;
  const size = item.z * sc;
  s.fontFamily = `${fontFamily(item.f)}, "Segoe UI", sans-serif`;
  s.fontSize = size + "px";
  s.lineHeight = (size + (item.sp || 0) * sc) + "px";
  s.color = rgba(item.c);
  s.textShadow = textShadow(item);
  s.alignItems = item.jv === "TOP" ? "flex-start" : item.jv === "BOTTOM" ? "flex-end" : "center";
  s.textAlign = item.jh === "LEFT" ? "left" : item.jh === "RIGHT" ? "right" : "center";
  const oneLine = item.h <= size * 1.6 + 0.5 && !String(item.t).includes("\n") && !String(item.t).includes("|n");
  if (item.nw || oneLine) el.classList.add("nowrap");
  if (item.nw) el.classList.add("trunc");
  el.innerHTML = `<span>${parseText(item.t, size)}</span>`;
}

function drawBackdrop(el, item) {
  el.className = "bd";
  const bgLow = (item.bg || "").toLowerCase(), edLow = (item.ed || "").toLowerCase();
  const bc = item.bc || [1, 1, 1, 1], ec = item.ec || [1, 1, 1, 1];
  const ins = item.ins || [0, 0, 0, 0];
  let html = "";
  if (item.bg) {
    let base = [1, 1, 1];
    let img = null;
    if (bgLow.includes("dialogbox-background-dark")) base = [0.02, 0.02, 0.02];
    else if (bgLow.includes("dialogbox-gold-background")) base = [0.32, 0.24, 0.08];
    else if (bgLow.includes("dialogbox-background")) base = [0.12, 0.12, 0.13];
    else if (bgLow.includes("sliderbar-background")) base = [0.05, 0.05, 0.05];
    else if (bgLow.startsWith("interface\\addons\\") || bgLow.startsWith("interface/addons/")) img = "/media?p=" + encodeURIComponent(item.bg);
    else if (!SOLID.test(bgLow)) base = [0.4, 0.4, 0.4];
    const col = rgba([base[0] * bc[0], base[1] * bc[1], base[2] * bc[2], bc[3] ?? 1]);
    const st = `left:${ins[0]}px;right:${ins[1]}px;top:${ins[2]}px;bottom:${ins[3]}px;`;
    html += img ? `<div class="bdbg" style="${st}background:url('${img}') ${item.tile ? "repeat" : "0 0/100% 100%"};opacity:${bc[3] ?? 1}"></div>`
      : `<div class="bdbg" style="${st}background:${col};border-radius:${edLow.includes("tooltip-border") ? 4 : edLow.includes("dialogbox") ? 6 : 0}px"></div>`;
  }
  if (item.ed) {
    const es = item.es || 8;
    let css;
    if (edLow.includes("tooltip-border")) {
      css = `border:${Math.max(1, es / 7)}px solid ${rgba([0.75 * ec[0], 0.75 * ec[1], 0.75 * ec[2], ec[3] ?? 1])};border-radius:${es / 3.2}px;box-shadow: inset 0 0 0 1px rgba(0,0,0,.6)`;
    } else if (edLow.includes("dialogbox-gold-border")) {
      css = `border:${es / 6}px solid ${rgba([0.85 * ec[0], 0.65 * ec[1], 0.2 * ec[2], ec[3] ?? 1])};border-radius:${es / 5}px;box-shadow: 0 0 0 1px #000, inset 0 0 0 1px #000`;
    } else if (edLow.includes("dialogbox-border") || edLow.includes("dialogframe")) {
      css = `border:${es / 6}px solid ${rgba([0.55 * ec[0], 0.5 * ec[1], 0.42 * ec[2], ec[3] ?? 1])};border-radius:${es / 5}px;box-shadow: 0 0 0 1px #000, inset 0 0 0 1px #000, inset 0 0 0 ${es / 10}px rgba(0,0,0,.25)`;
    } else if (edLow.includes("sliderbar-border")) {
      css = `border:1px solid ${rgba([0.5 * ec[0], 0.5 * ec[1], 0.5 * ec[2], ec[3] ?? 1])};border-radius:4px`;
    } else {
      css = `border:${es}px solid ${rgba(ec)}`;
    }
    html += `<div class="bdedge" style="${css}"></div>`;
  }
  el.innerHTML = html;
}

function drawSkin(el, item) {
  el.className = `sk-${item.sk}` + (item.p ? " p" : "") + (item.d ? " d" : "") + (item.hv ? " hv" : "") + (item.c ? " c" : "") + (item.o === "VERTICAL" ? " o-v" : "");
  el.innerHTML = "";
  if (item.sk === "slider") {
    const v = Math.max(0, Math.min(1, item.v || 0));
    el.innerHTML = item.o === "VERTICAL" ? `<i style="top:${v * 100}%"></i>` : `<i style="left:${7 + v * (item.w - 14)}px"></i>`;
  } else if (item.sk === "scrollbar") {
    const v = Math.max(0, Math.min(1, item.v || 0));
    el.innerHTML = `<i style="top:${13 + v * (item.h - 26)}px"></i>`;
  }
}

function drawEditBox(el, item) {
  el.className = "eb";
  let input = el.firstChild;
  const want = item.ml ? "TEXTAREA" : "INPUT";
  if (!input || input.tagName !== want) {
    el.innerHTML = "";
    input = document.createElement(want.toLowerCase());
    input.spellcheck = false;
    input.autocomplete = "off";
    input.dataset.id = item.i;
    input.addEventListener("input", () => {
      api("/api/input", { type: "text", id: item.i, text: input.value, cursor: input.selectionStart });
    });
    input.addEventListener("keydown", e => {
      const map = { Enter: "ENTER", Escape: "ESCAPE", Tab: "TAB" };
      e.stopPropagation();
      if (map[e.key] && !(e.key === "Enter" && want === "TEXTAREA")) {
        e.preventDefault();
        api("/api/input", { type: "keydown", key: map[e.key], mods: mods(e) });
      } else if (map[e.key] === "ENTER") {
        api("/api/input", { type: "keydown", key: "ENTER", mods: mods(e) });
      }
    });
    input.addEventListener("mousedown", e => e.stopPropagation());
    input.addEventListener("focus", () => {
      if (focusId !== item.i) api("/api/input", { type: "down", x: item.x + 2, y: item.y + 2, button: "LeftButton" }).then(() => api("/api/input", { type: "up", x: item.x + 2, y: item.y + 2, button: "LeftButton" }));
    });
    el.appendChild(input);
    input._rev = -1;
  }
  input.type = item.pw ? "password" : "text";
  const sc = item.sc || 1;
  const s = input.style;
  s.fontFamily = `${fontFamily(item.f)}, "Arial Narrow", sans-serif`;
  s.fontSize = item.z * sc + "px";
  s.color = rgba(item.c);
  s.textAlign = (item.jh || "LEFT").toLowerCase();
  const ins = item.ins || [0, 0, 0, 0];
  el.style.padding = `${ins[2] * sc}px ${ins[1] * sc}px ${ins[3] * sc}px ${ins[0] * sc}px`;
  if (item.max) input.maxLength = item.max;
  const focused = document.activeElement === input;
  if (!focused || input._rev !== item.rev) {
    if (input.value !== item.t) input.value = item.t;
  }
  input._rev = item.rev;
  if (item.hl && focused) {
    const [a, b] = item.hl;
    try { input.setSelectionRange(a, b < 0 ? input.value.length : b); } catch (_) {}
  }
}

function drawMessages(el, item) {
  el.className = "msg" + (item.top ? " top" : "");
  const s = el.style;
  s.fontFamily = `${fontFamily(item.f)}, "Arial Narrow", sans-serif`;
  s.fontSize = item.z + "px";
  s.lineHeight = (item.z + 2) + "px";
  s.textAlign = (item.jh || "LEFT").toLowerCase();
  s.textShadow = "1px -1px 0 #000";
  el.innerHTML = item.lines.map(l => `<div style="color:${rgba(l.c)}">${parseText(l.t, item.z)}</div>`).join("");
}

function drawCooldown(el, item) {
  el.className = "cd";
  const deg = (1 - item.p) * 360;
  const col = item.sw ? rgba(item.sw) : "transparent";
  el.style.background = item.rev
    ? `conic-gradient(${col} 0deg ${deg}deg, transparent ${deg}deg 360deg)`
    : `conic-gradient(transparent 0deg ${deg}deg, ${col} ${deg}deg 360deg)`;
  el.style.fontSize = Math.max(9, Math.min(item.w, item.h) * 0.42) + "px";
  if (item.n != null && item.n > 0.5) {
    const n = item.n;
    const txt = n >= 3600 ? Math.ceil(n / 3600) + "h" : n >= 60 ? Math.ceil(n / 60) + "m" : String(Math.ceil(n));
    el.innerHTML = `<b>${txt}</b>`;
  } else el.innerHTML = "";
}

function drawLine(el, item) {
  const dx = item.x2 - item.x1, dy = item.y2 - item.y1;
  const len = Math.hypot(dx, dy);
  const s = el.style;
  el.className = "";
  s.left = item.x1 + "px"; s.top = (item.y1 - item.th / 2) + "px";
  s.width = len + "px"; s.height = item.th + "px";
  s.transformOrigin = `0 ${item.th / 2}px`;
  s.transform = `rotate(${Math.atan2(dy, dx)}rad)`;
  const vc = item.vc || [1, 1, 1, 1], c = item.c || [1, 1, 1, 1];
  s.background = rgba([c[0] * vc[0], c[1] * vc[1], c[2] * vc[2], (c[3] ?? 1) * (vc[3] ?? 1)]);
  s.opacity = item.a < 1 ? item.a : "";
}

function render(scene) {
  const seen = new Set();
  for (let z = 0; z < scene.length; z++) {
    const item = scene[z];
    const key = item.k + item.i;
    seen.add(key);
    let el = els.get(key);
    if (!el) {
      el = document.createElement("div");
      els.set(key, el);
      framesEl.appendChild(el);
    }
    const sig = JSON.stringify(item) + "|" + z;
    if (sigs.get(key) === sig && item.k !== "e") continue;
    sigs.set(key, sig);
    if (item.k === "ln") { drawLine(el, item); el.style.zIndex = z; continue; }
    place(el, item, z);
    switch (item.k) {
      case "t": drawTexture(el, item); break;
      case "s": drawFont(el, item); break;
      case "b": drawBackdrop(el, item); break;
      case "k": drawSkin(el, item); break;
      case "e": drawEditBox(el, item); break;
      case "m": drawMessages(el, item); break;
      case "cd": drawCooldown(el, item); break;
      case "ph": el.className = "ph"; el.textContent = item.t; break;
    }
  }
  for (const [key, el] of els) {
    if (!seen.has(key)) { el.remove(); els.delete(key); sigs.delete(key); }
  }
}

// ---------------------------------------------------------------- input
const BUTTONS = ["LeftButton", "MiddleButton", "RightButton", "Button4", "Button5"];
const mods = e => ({ shift: e.shiftKey, ctrl: e.ctrlKey, alt: e.altKey });
function uiPos(e) {
  const r = stage.getBoundingClientRect();
  return { x: (e.clientX - r.left) / scale, y: (e.clientY - r.top) / scale };
}
let lastMove = 0, moveTimer = null, pendingMove = null, cursor = { x: 0, y: 0 };
function sendMove() {
  if (!pendingMove) return;
  const m = pendingMove; pendingMove = null; lastMove = performance.now();
  api("/api/input", m);
}
stage.addEventListener("mousemove", e => {
  const p = uiPos(e);
  cursor = p;
  pendingMove = { type: "move", x: p.x, y: p.y, mods: mods(e) };
  const since = performance.now() - lastMove;
  if (since > 30) sendMove();
  else if (!moveTimer) moveTimer = setTimeout(() => { moveTimer = null; sendMove(); }, 30 - since);
});
stage.addEventListener("mousedown", e => {
  if (e.target.closest(".eb")) return;
  e.preventDefault();
  if (document.activeElement && document.activeElement !== stage) document.activeElement.blur();
  stage.focus();
  const p = uiPos(e);
  pendingMove = null;
  api("/api/input", { type: "down", x: p.x, y: p.y, button: BUTTONS[e.button] || "LeftButton", mods: mods(e) });
});
window.addEventListener("mouseup", e => {
  const p = uiPos(e);
  sendMove();
  api("/api/input", { type: "up", x: p.x, y: p.y, button: BUTTONS[e.button] || "LeftButton", mods: mods(e) });
});
stage.addEventListener("contextmenu", e => e.preventDefault());
stage.addEventListener("wheel", e => {
  e.preventDefault();
  if (e.ctrlKey) {
    const levels = [0.2, 0.25, 0.33, 0.5, 0.67, 0.75, 1, 1.25, 1.5, 2, 3, 4];
    let next;
    if (e.deltaY < 0) next = levels.find(l => l > scale + 0.001) ?? 4;
    else next = [...levels].reverse().find(l => l < scale - 0.001) ?? 0.2;
    const r = $("#stageScroll").getBoundingClientRect();
    setZoom(next, e.clientX - r.left, e.clientY - r.top);
    return;
  }
  const p = uiPos(e);
  api("/api/input", { type: "wheel", x: p.x, y: p.y, delta: e.deltaY < 0 ? 1 : -1, mods: mods(e) });
}, { passive: false });

const KEYMAP = { Enter: "ENTER", Escape: "ESCAPE", Tab: "TAB", " ": "SPACE", ArrowUp: "UP", ArrowDown: "DOWN", ArrowLeft: "LEFT", ArrowRight: "RIGHT",
  Backspace: "BACKSPACE", Delete: "DELETE", Home: "HOME", End: "END", PageUp: "PAGEUP", PageDown: "PAGEDOWN", Shift: "LSHIFT", Control: "LCTRL", Alt: "LALT" };
const wowKey = e => KEYMAP[e.key] || (e.key.length === 1 ? e.key.toUpperCase() : e.key.toUpperCase());
stage.addEventListener("keydown", e => {
  if (e.key === "Enter" && focusId == null) { e.preventDefault(); $("#chatInput").focus(); return; }
  if (e.key === "/" && focusId == null) { e.preventDefault(); const c = $("#chatInput"); c.value = "/"; c.focus(); return; }
  if (["Tab", " ", "ArrowUp", "ArrowDown"].includes(e.key)) e.preventDefault();
  api("/api/input", { type: "keydown", key: wowKey(e), mods: mods(e) });
});
stage.addEventListener("keyup", e => api("/api/input", { type: "keyup", key: wowKey(e), mods: mods(e) }));

// Chat box
const chatInput = $("#chatInput"), chatLines = $("#chatLines");
const history = []; let histPos = 0;
chatInput.addEventListener("keydown", e => {
  e.stopPropagation();
  if (e.key === "Enter") {
    const t = chatInput.value.trim();
    if (t) { history.push(t); histPos = history.length; api("/api/input", { type: "chat", text: t }); }
    chatInput.value = ""; chatInput.blur(); stage.focus();
  } else if (e.key === "Escape") { chatInput.value = ""; chatInput.blur(); stage.focus(); }
  else if (e.key === "ArrowUp" && history.length) { histPos = Math.max(0, histPos - 1); chatInput.value = history[histPos]; e.preventDefault(); }
  else if (e.key === "ArrowDown" && history.length) { histPos = Math.min(history.length, histPos + 1); chatInput.value = history[histPos] || ""; e.preventDefault(); }
});
chatInput.addEventListener("focus", () => $("#chat").classList.add("active"));
chatInput.addEventListener("blur", () => $("#chat").classList.remove("active"));
function addChat(line) {
  const d = document.createElement("div");
  d.style.color = rgba(line.c);
  d.innerHTML = `<span class="ts">${line.time || ""}</span>${parseText(line.t, 13)}`;
  chatLines.appendChild(d);
  while (chatLines.children.length > 300) chatLines.firstChild.remove();
  chatLines.scrollTop = chatLines.scrollHeight;
}

// ---------------------------------------------------------------- toasts & sound
function toast(html, cls = "", ms = 3500) {
  const t = document.createElement("div");
  t.className = "toast " + cls;
  t.innerHTML = html;
  $("#toasts").appendChild(t);
  setTimeout(() => t.remove(), ms);
  while ($("#toasts").children.length > 5) $("#toasts").firstChild.remove();
}
let audioCtx = null;
function playSound(s) {
  toast(`♪ ${s.kind === "kit" ? "Sound kit " + s.id : esc(String(s.id))}`, "snd", 1800);
  if (!$("#sound").checked) return;
  try {
    if (s.kind === "file" && /interface[\\/]+addons/i.test(String(s.id))) {
      new Audio("/media?p=" + encodeURIComponent(s.id)).play().catch(() => {});
      return;
    }
    audioCtx = audioCtx || new AudioContext();
    const o = audioCtx.createOscillator(), g = audioCtx.createGain();
    o.frequency.value = 520 + (Number(s.id) % 7) * 70;
    g.gain.setValueAtTime(0.08, audioCtx.currentTime);
    g.gain.exponentialRampToValueAtTime(0.0001, audioCtx.currentTime + 0.18);
    o.connect(g).connect(audioCtx.destination);
    o.start(); o.stop(audioCtx.currentTime + 0.2);
  } catch (_) {}
}

// ---------------------------------------------------------------- errors / stubs / msgs
function renderErrors() {
  const box = $("#errors");
  box.innerHTML = errors.length ? "" : `<p class="hint">No errors. 🎉</p>`;
  for (const e of [...errors].reverse()) {
    const d = document.createElement("div");
    d.className = "err";
    d.innerHTML = `<span class="c">×${e.count}</span><div class="m">${esc(e.msg)}</div><pre>${esc(e.stack || "")}</pre>`;
    box.appendChild(d);
  }
  const b = $("#errBadge");
  b.hidden = errors.length === 0;
  b.textContent = errors.length;
}

// ---------------------------------------------------------------- poll loop
let polling = false;
async function poll() {
  if (polling) return;
  polling = true;
  try {
    const insp = $("#inspect").checked;
    const q = `chat=${seq.chat}&err=${seq.err}&snd=${seq.snd}&msg=${seq.msg}&stub=${seq.stub}` + (insp ? `&inspect=1&ix=${cursor.x}&iy=${H - cursor.y}` : "");
    const st = await fetch("/api/state?" + q).then(r => r.json());
    if (st.idle) { $("#idle").hidden = false; render([]); }
    else {
      $("#idle").hidden = true;
      if (st.gen !== gen) {
        if (gen !== -1) { addChat({ t: "— UI reloaded —", c: [0.6, 0.6, 0.6], time: "" }); }
        gen = st.gen;
        seq = { chat: 0, err: 0, snd: 0, msg: 0, stub: 0 };
        errors = [];
        renderErrors();
        $("#addonMsgs").textContent = "";
        refreshInfo();
      }
      if (st.W !== W || st.H !== H) { W = st.W; H = st.H; fit(); }
      render(arr(st.scene));
      focusId = st.focus ?? null;
      if (focusId != null) {
        const inp = $(`.eb [data-id="${focusId}"]`);
        if (inp && document.activeElement !== inp) inp.focus();
      } else {
        const a = document.activeElement;
        if (a && a.closest && a.closest(".eb")) { a.blur(); stage.focus(); }
      }
      for (const c of arr(st.chat)) { addChat(c); seq.chat = Math.max(seq.chat, c.seq); }
      if (arr(st.errors).length) {
        for (const e of st.errors) {
          seq.err = Math.max(seq.err, e.seq);
          const ex = errors.find(x => x.msg === e.msg);
          if (ex) Object.assign(ex, e); else { errors.push(e); toast(`<b>Lua error</b><br>${esc(e.msg).slice(0, 220)}`, "err", 6000); }
        }
        renderErrors();
      }
      if (st.errorCount === 0 && errors.length) { errors = []; renderErrors(); }
      for (const s of arr(st.sounds)) { seq.snd = Math.max(seq.snd, s.seq); playSound(s); }
      for (const m of arr(st.addonMsgs)) {
        seq.msg = Math.max(seq.msg, m.seq);
        const box = $("#addonMsgs");
        box.textContent += `${m.time} [${m.prefix}] ${m.channel}${m.target ? " → " + m.target : ""}: ${m.msg}\n`;
        box.scrollTop = box.scrollHeight;
      }
      if (st.stubs) {
        seq.stub = st.stubSeq;
        $("#stubs").textContent = st.stubs.map(s => `${s.n}  ×${s.c}`).join("\n");
      }
      if (st.openChat != null) { chatInput.value = st.openChat; chatInput.focus(); }
      if (insp) renderInspect(st.inspect || []);
      else $("#inspectBox").hidden = !pinnedInspect;
      $("#pauseBtn").textContent = st.paused ? "Resume" : "Pause";
    }
  } catch (e) {
    console.error("poll failed", e);
    $("#idle").hidden = false;
    $("#idle").innerHTML = "<h2>Server not reachable</h2><p>Start it with <code>WowSim.bat</code>.</p>";
  }
  polling = false;
  setTimeout(poll, 33);
}

function renderInspect(list) {
  const box = $("#inspectBox");
  const top = pinnedInspect ? null : list[0];
  if (top) {
    box.hidden = false;
    Object.assign(box.style, { left: top.box.x + "px", top: top.box.y + "px", width: top.box.w + "px", height: top.box.h + "px" });
    box.innerHTML = `<span>${esc(top.name)} ${top.w}×${top.h}</span>`;
  } else if (!pinnedInspect) box.hidden = true;
  if (pinnedInspect) return;
  const el = $("#inspectList");
  el.innerHTML = list.map((f, i) => `<div class="fr" data-i="${i}"><b>${esc(f.name)}</b> <span class="meta">${f.type} · ${f.w}×${f.h} · ${f.strata} ${f.level}${f.mouse ? " · mouse" : ""}${f.parent ? " · parent " + esc(f.parent) : ""}</span>${f.points.map(p => `<code>${esc(p)}</code>`).join("")}</div>`).join("")
    || `<p class="hint">Nothing under the cursor.</p>`;
  $$(".fr", el).forEach(d => d.onclick = () => {
    const f = list[d.dataset.i];
    pinnedInspect = f;
    d.classList.add("pin");
    Object.assign(box.style, { left: f.box.x + "px", top: f.box.y + "px", width: f.box.w + "px", height: f.box.h + "px" });
    box.innerHTML = `<span>📌 ${esc(f.name)} ${f.w}×${f.h} (click game view to unpin)</span>`;
    box.hidden = false;
  });
}
stage.addEventListener("click", () => { if (pinnedInspect) { pinnedInspect = null; } });

// ---------------------------------------------------------------- side panel
$$("#tabs button").forEach(b => b.onclick = () => {
  $$("#tabs button").forEach(x => x.classList.toggle("on", x === b));
  $$(".panel").forEach(p => p.classList.toggle("on", p.id === "tab-" + b.dataset.tab));
  if (b.dataset.tab === "events") loadEvents();
});

let addonCatalog = [], loadedPaths = [];
async function refreshAddons() {
  const r = await api("/api/addons");
  addonCatalog = r.addons; loadedPaths = r.loaded;
  $("#autoreload").checked = r.autoreload;
  showScreen(r.screen);
  renderAddonList();
}
function renderAddonList() {
  const f = $("#addonFilter").value.toLowerCase();
  const box = $("#addonList");
  const groups = {};
  for (const a of addonCatalog) {
    if (f && !(a.name + a.title).toLowerCase().includes(f)) continue;
    (groups[a.source] = groups[a.source] || []).push(a);
  }
  const checked = new Set($$("input:checked", box).map(i => i.value));
  const useLoaded = !box.dataset.touched;
  box.innerHTML = Object.entries(groups).map(([g, list]) => `<div class="grp">${esc(g)}</div>` + list.map(a => {
    const on = useLoaded ? loadedPaths.includes(a.path) : checked.has(a.path);
    return `<label><input type="checkbox" value="${esc(a.path)}" ${on ? "checked" : ""}> ${parseText(a.title, 12)} <span class="v">${esc(a.version)}</span></label>`;
  }).join("")).join("") || `<p class="hint" style="padding:8px">No addons found.</p>`;
  $$("input", box).forEach(i => i.onchange = () => { box.dataset.touched = "1"; });
}
$("#addonFilter").oninput = renderAddonList;
$("#loadBtn").onclick = async () => {
  const paths = $$("#addonList input:checked").map(i => i.value);
  $("#loadBtn").textContent = "Loading…";
  const r = await api("/api/load", { paths });
  $("#loadBtn").textContent = "Load";
  delete $("#addonList").dataset.touched;
  if (r.error) toast(esc(r.error), "err");
  refreshAddons(); refreshInfo();
};

let info = {};
async function refreshInfo() {
  info = await api("/api/info");
  if (!info || !info.addons) return;
  $("#loadedNames").innerHTML = info.addons.length ? info.addons.map(a => `<b>${parseText(a.title, 12)}</b> ${esc(a.version)}`).join(" · ") : "nothing loaded";
  $("#running").innerHTML = info.addons.map(a => `<div><b>${esc(a.name)}</b> ${esc(a.version)} — ${a.files.length} files${a.saved.length ? " · saves " + esc(a.saved.join(", ")) : ""}</div>`).join("") || `<p class="hint">Nothing loaded.</p>`;
  $("#categories").innerHTML = arr(info.categories).map(c => `<span class="chip" data-c="${esc(c.name)}">${c.sub ? "↳ " : ""}${parseText(c.name, 12)}</span>`).join("") || `<span class="hint">None registered.</span>`;
  $$("#categories .chip").forEach(ch => ch.onclick = () => api("/api/options", { name: ch.dataset.c }));
  $("#slash").innerHTML = arr(info.slash).map(s => `<span class="chip">${esc(s)}</span>`).join("") || `<span class="hint">None.</span>`;
  $$("#slash .chip").forEach(ch => ch.onclick = () => { chatInput.value = ch.textContent + " "; chatInput.focus(); });
  $("#bootLog").textContent = arr(info.boot).join("\n");
  $("#svAddon").innerHTML = info.addons.filter(a => a.saved.length).map(a => `<option>${esc(a.name)}</option>`).join("");
  fillProfile(info.profile, info.classes);
  $("#speed").value = info.speed || 1; $("#speedVal").textContent = (info.speed || 1) + "×";
}

function getPath(obj, path) { return path.split(".").reduce((o, k) => o && o[k], obj); }
function fillProfile(p, classes) {
  if (!p) return;
  const cs = $("#classSel");
  if (classes && cs.options.length !== classes.length) cs.innerHTML = classes.map(c => `<option>${c}</option>`).join("");
  $$("[data-p]").forEach(el => {
    if (document.activeElement === el) return;
    const v = getPath(p, el.dataset.p);
    if (el.type === "checkbox") el.checked = !!v;
    else if (v !== undefined && v !== null) el.value = v;
    const show = $(`[data-show="${el.dataset.p}"]`);
    if (show) show.textContent = el.value;
  });
  $("#spells").value = (Array.isArray(p.spells) ? p.spells : []).map(s => `${s.id} ${s.name || ""} ${typeof s.icon === "string" ? s.icon.replace(/^Interface\\Icons\\/i, "") : ""}`.trim()).join("\n");
}
$$("[data-p]").forEach(el => {
  const send = () => {
    let v = el.type === "checkbox" ? el.checked : el.value;
    if (el.type === "number" || el.type === "range" || el.dataset.p === "group") v = Number(v);
    const [key, sub] = el.dataset.p.split(".");
    api("/api/profile", { key, sub, value: v });
    const show = $(`[data-show="${el.dataset.p}"]`);
    if (show) show.textContent = el.value;
  };
  el.addEventListener(el.type === "range" ? "input" : "change", send);
});
$("#spellsBtn").onclick = () => {
  const spells = $("#spells").value.split("\n").map(l => l.trim()).filter(Boolean).map(l => {
    const parts = l.split(/\s+/);
    const id = Number(parts[0]);
    let icon = parts.length > 2 ? parts[parts.length - 1] : undefined;
    let name = parts.slice(1, icon ? -1 : undefined).join(" ");
    if (icon && !/_/.test(icon)) { name = parts.slice(1).join(" "); icon = undefined; }
    const rec = { id };
    if (name) rec.name = name;
    if (icon) rec.icon = "Interface\\Icons\\" + icon;
    return rec;
  });
  api("/api/profile", { key: "spells", value: spells });
  toast("Spells applied — SPELLS_CHANGED fired");
};
const SPELL_PRESETS = {"WARRIOR": [6603, 78, 772, 6343, 100, 6673, 2687, 1715, 7384, 5308, 1680, 12294, 23881, 355, 2565, 72, 6572, 23922, 676, 1160, 6552, 18499, 2457, 71, 2458, 20252, 1719, 871, 12975], "PALADIN": [6603, 635, 19750, 20271, 21084, 20375, 20164, 20165, 20166, 21082, 19740, 19742, 465, 7294, 853, 498, 642, 633, 1022, 1044, 879, 2812, 24275, 26573, 20925, 20473, 4987, 25780], "HUNTER": [6603, 75, 3044, 1978, 2643, 19434, 1130, 2973, 1495, 2974, 5116, 781, 13165, 5118, 13163, 1499, 13795, 3045, 19506, 883, 136, 3034, 19801, 5384, 20736, 19574], "ROGUE": [6603, 1752, 2098, 53, 1784, 6770, 1766, 5171, 1943, 2983, 1776, 703, 8676, 1833, 408, 5277, 1856, 14183, 13750, 13877, 16511, 2094, 14177], "PRIEST": [5019, 585, 589, 17, 2050, 2054, 2061, 139, 8092, 586, 8122, 1243, 588, 14914, 527, 528, 2944, 15407, 15473, 13908, 10060, 15286, 15487, 14751], "SHAMAN": [6603, 403, 421, 8042, 8050, 8056, 331, 8004, 1064, 324, 8017, 8024, 8033, 8232, 3599, 5394, 8071, 8075, 5730, 2484, 8143, 8512, 16190, 17364, 16166, 2645, 370], "MAGE": [5019, 133, 116, 5143, 2136, 122, 120, 2948, 11366, 1449, 2139, 1953, 118, 1459, 168, 6143, 1463, 12051, 11426, 12472, 12042, 11129, 2120, 10, 11958], "WARLOCK": [5019, 686, 172, 980, 348, 5782, 689, 1120, 1454, 687, 706, 702, 1714, 1490, 603, 6353, 5676, 17877, 18265, 6789, 5484, 688, 697, 712, 691, 1949, 5740, 17962], "DRUID": [6603, 5176, 8921, 2912, 5570, 339, 770, 774, 5185, 8936, 740, 1126, 467, 5487, 768, 783, 6807, 779, 99, 6795, 5211, 1082, 1079, 5221, 22568, 1822, 5217, 22812, 29166, 20484, 17116, 18562, 24858]};
$("#presetBtn").onclick = () => {
  const cls = $("#classSel").value;
  const ids = SPELL_PRESETS[cls];
  if (!ids) { toast("No preset for " + cls); return; }
  api("/api/profile", { key: "spells", value: ids.map(id => ({ id })) });
  $("#spells").value = ids.join("\n");
  toast(`${ids.length} ${cls.toLowerCase()} spells applied — names load in the background, then SPELLS_CHANGED fires`, "", 5000);
};
$("#speed").oninput = () => { $("#speedVal").textContent = $("#speed").value + "×"; api("/api/settings", { speed: Number($("#speed").value) }); };

// Events tab
let eventCatalog = null;
async function loadEvents() {
  if (eventCatalog) return;
  eventCatalog = await api("/api/events");
  $("#eventList").innerHTML = eventCatalog.map(e => `<option value="${e.n}">`).join("");
}
$("#eventName").oninput = () => {
  const e = (eventCatalog || []).find(x => x.n === $("#eventName").value.trim());
  $("#eventPayload").textContent = e ? (e.p.length ? "Payload: " + e.p.join(", ") : "No payload") + ` (${e.s})` : "";
};
function parseArgs(s) {
  s = s.trim();
  if (!s) return [];
  try { const v = JSON.parse("[" + s + "]"); return v; } catch (_) {}
  return s.split(",").map(x => {
    x = x.trim();
    if (x === "true") return true;
    if (x === "false") return false;
    if (x === "nil") return null;
    if (x !== "" && !isNaN(Number(x))) return Number(x);
    return x.replace(/^["']|["']$/g, "");
  });
}
function fire(event, args) { api("/api/event", { event, args }).then(() => toast(`Fired <b>${esc(event)}</b>`, "", 1500)); }
$("#fireBtn").onclick = () => { const n = $("#eventName").value.trim(); if (n) fire(n, parseArgs($("#eventArgs").value)); };
const QUICK = [
  ["PLAYER_ENTERING_WORLD", [false, true]], ["PLAYER_TARGET_CHANGED", []], ["GROUP_ROSTER_UPDATE", []],
  ["ZONE_CHANGED_NEW_AREA", []], ["SPELLS_CHANGED", []], ["BAG_UPDATE", [0]], ["PLAYER_REGEN_DISABLED", []],
  ["PLAYER_REGEN_ENABLED", []], ["UNIT_HEALTH", ["player"]], ["SPELL_UPDATE_COOLDOWN", []], ["QUEST_LOG_UPDATE", []],
  ["PLAYER_LEVEL_UP", [61]], ["UNIT_AURA", ["player"]], ["UPDATE_MOUSEOVER_UNIT", []],
];
$("#quickEvents").innerHTML = QUICK.map(([n], i) => `<span class="chip" data-i="${i}">${n}</span>`).join("");
$$("#quickEvents .chip").forEach(c => c.onclick = () => { const [n, a] = QUICK[c.dataset.i]; fire(n, a); });

// Console
async function runCode() {
  const code = $("#code").value;
  if (!code.trim()) return;
  const out = $("#out");
  const r = await api("/api/exec", { code });
  out.innerHTML += `<span class="cmd">&gt; ${esc(code)}</span>\n<span class="res">${esc(r.result ?? r.error ?? "")}</span>\n`;
  out.scrollTop = out.scrollHeight;
}
$("#runBtn").onclick = runCode;
$("#code").addEventListener("keydown", e => { if (e.key === "Enter" && e.ctrlKey) { e.preventDefault(); runCode(); } });
$("#clearOut").onclick = () => $("#out").textContent = "";

// Errors
$("#clearErrors").onclick = () => { api("/api/clearerrors", {}); errors = []; renderErrors(); };

// SavedVariables
$("#svShow").onclick = async () => { const r = await api("/api/saved?addon=" + encodeURIComponent($("#svAddon").value)); $("#svText").textContent = r.text; };
$("#svReset").onclick = async () => {
  const n = $("#svAddon").value;
  if (!n || !confirm(`Delete the simulator's saved settings for ${n} and reload? (Your game's WTF files are not touched.)`)) return;
  await api("/api/resetsaved", { addon: n });
  toast(`${esc(n)} settings reset`);
};

// Top bar
$("#reloadBtn").onclick = async () => { $("#reloadBtn").textContent = "Reloading…"; await api("/api/reload", {}); $("#reloadBtn").textContent = "Reload UI"; };
$("#autoreload").onchange = () => api("/api/settings", { autoreload: $("#autoreload").checked });
$("#zoom").onchange = () => setZoom($("#zoom").value);
$("#pauseBtn").onclick = () => api("/api/settings", { paused: $("#pauseBtn").textContent === "Pause" });
function showScreen(sc) {
  const sv = `${Math.round(sc[0])}x${Math.round(sc[1])}`;
  const sel = $("#screen");
  let opt = [...sel.options].find(o => o.value === sv);
  if (!opt) {
    opt = [...sel.options].find(o => o.dataset.custom) || document.createElement("option");
    opt.dataset.custom = "1";
    opt.value = sv;
    opt.textContent = `Custom · ${sv.replace("x", "×")}`;
    if (!opt.parentNode) sel.insertBefore(opt, sel.lastElementChild);
  }
  sel.value = sv;
  sel.dataset.last = sv;
}
$("#screen").onchange = () => {
  const sel = $("#screen");
  let v = sel.value;
  if (v === "custom") {
    const ans = prompt("Screen size in UI units (width x height), e.g. 2400x1350", sel.dataset.last || "1920x1080");
    const m = ans && ans.match(/^\s*(\d{3,5})\s*[x×*, ]\s*(\d{3,5})\s*$/);
    if (!m) { sel.value = sel.dataset.last || "1365x768"; return; }
    v = `${m[1]}x${m[2]}`;
  }
  const size = v.split("x").map(Number);
  showScreen(size);
  api("/api/settings", { screen: size }).then(() => { if (zoomMode !== "fit") setZoom("fit"); });
};
$("#showMissing").onchange = () => { document.body.classList.toggle("hideMissing", !$("#showMissing").checked); try { localStorage.setItem("wowsim.missing", $("#showMissing").checked ? "1" : "0"); } catch (_) {} };
$("#inspect").onchange = () => { if (!$("#inspect").checked) { pinnedInspect = null; $("#inspectBox").hidden = true; } };
try {
  if (localStorage.getItem("wowsim.missing") === "0") { $("#showMissing").checked = false; document.body.classList.add("hideMissing"); }
  if (localStorage.getItem("wowsim.sound") === "1") $("#sound").checked = true;
} catch (_) {}
$("#sound").onchange = () => { try { localStorage.setItem("wowsim.sound", $("#sound").checked ? "1" : "0"); } catch (_) {} };

fit();
refreshAddons();
refreshInfo();
poll();
stage.focus();
