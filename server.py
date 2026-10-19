"""WowSim - run a WoW addon on Windows and look at it in a browser.

The addon runs in a real Lua 5.1 interpreter (lupa) inside this process with a
pretend WoW API. The browser page draws the frames and sends mouse/keyboard
input back. Nothing here touches the game or its AddOns folder.

    python server.py [--port 8642] [--addon PATH_TO_ADDON_FOLDER ...]
"""

import argparse
import json
import os
import re
import sys
import threading
import time
import traceback
import urllib.parse
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from io import BytesIO

import lupa.lua51 as lupa

HERE = os.path.dirname(os.path.abspath(__file__))
ADDONDEV = os.path.dirname(HERE)
LUA_DIR = os.path.join(HERE, "lua")
WEB_DIR = os.path.join(HERE, "web")
SAVED_DIR = os.path.join(HERE, "saved")
CONFIG_PATH = os.path.join(HERE, "config.json")
API_DOCS = os.path.join(ADDONDEV, "API", "Interface", "AddOns", "Blizzard_APIDocumentationGenerated")
WOW_ADDONS = r"C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns"
WIN_FONTS = os.path.join(os.environ.get("WINDIR", r"C:\Windows"), "Fonts")

# Blizzard utility code reused from the Forever UI mirror (fills only missing globals).
BLIZZARD_FILL = [
    "Blizzard_SharedXMLBase/Mixin.lua", "Blizzard_SharedXMLBase/TableUtil.lua", "Blizzard_SharedXMLBase/FunctionUtil.lua",
    "Blizzard_SharedXMLBase/MathUtil.lua", "Blizzard_SharedXMLBase/Flags.lua", "Blizzard_SharedXMLBase/EnumUtil.lua",
    "Blizzard_SharedXMLBase/CallbackRegistry.lua", "Blizzard_SharedXMLBase/Color.lua", "Blizzard_SharedXMLBase/Rectangle.lua",
    "Blizzard_SharedXMLBase/AnchorUtil.lua", "Blizzard_SharedXMLBase/TextureUtil.lua", "Blizzard_SharedXMLBase/TimerUtil.lua",
    "Blizzard_SharedXMLBase/FrameUtil.lua", "Blizzard_SharedXMLBase/ProxyUtil.lua", "Blizzard_SharedXMLBase/SecureTypes.lua", "Blizzard_SharedXMLBase/Pools.lua",
    "Blizzard_SharedXML/SharedColorConstants.lua", "Blizzard_SharedXML/SharedConstants.lua", "Blizzard_SharedXML/ColorUtil.lua",
    "Blizzard_SharedXML/StringUtil.lua", "Blizzard_SharedXML/FormattingUtil.lua", "Blizzard_SharedXML/TimeUtil.lua",
    "Blizzard_SharedXML/LinkUtil.lua", "Blizzard_SharedXML/Vector2D.lua", "Blizzard_SharedXML/Vector3D.lua",
    "Blizzard_SharedXML/EasingUtil.lua", "Blizzard_SharedXML/SortUtil.lua", "Blizzard_SharedXML/DataProvider.lua",
    "Blizzard_SharedXML/TypeUtil.lua", "Blizzard_SharedXML/Interpolator.lua", "Blizzard_SharedXML/CircularBuffer.lua",
    "Blizzard_SharedXML/MoneyFormatter.lua", "Blizzard_SharedXML/UnitUtil.lua", "Blizzard_SharedXML/EventUtil.lua",
    "Blizzard_SharedXML/ClassColors.lua", "Blizzard_SharedXML/Dump.lua", "Blizzard_SharedXML/InputUtil.lua",
    "Blizzard_ObjectAPI/Mainline/ObjectCache.lua", "Blizzard_ObjectAPI/Mainline/AsyncCallbackSystem.lua",
    "Blizzard_ObjectAPI/Mainline/ContinuableContainer.lua", "Blizzard_ObjectAPI/Mainline/ItemLocation.lua",
    "Blizzard_ObjectAPI/Mainline/Item.lua", "Blizzard_ObjectAPI/Mainline/Spell.lua", "Blizzard_ObjectAPI/Mainline/PlayerLocation.lua",
    "Blizzard_ObjectAPI/Mainline/SpellBookItemLocation.lua", "Blizzard_ObjectAPI/Mainline/UiMapPoint.lua",
    "Blizzard_ObjectAPI/Mainline/Quest.lua", "Blizzard_ChatFrameBase/Shared/ChatFrameConstants.lua",
    "Blizzard_ChatFrameBase/Shared/ChatFrameUtil.lua",
]
BLIZZ_ROOT = os.path.join(ADDONDEV, "API", "Interface", "AddOns")

LUA_FILES = ["util.lua", "widgets.lua", "scene.lua", "fonts.lua", "api.lua", "templates.lua", "blizzard.lua", "docs.lua", "runtime.lua"]

# WoW font files are packed in the game data, so map them to Windows fonts.
FONT_MAP = {
    "frizqt": "seguisb.ttf",
    "arialn": "ARIALN.TTF",
    "skurri": "trebucbd.ttf",
    "morpheus": "georgiab.ttf",
    "2002": "segoeui.ttf",
}

try:
    from PIL import Image, ImageFont
except ImportError:  # measuring falls back to an estimate
    Image = ImageFont = None


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


# ---------------------------------------------------------------------------
# Addon discovery
# ---------------------------------------------------------------------------

# WoW Forever's TOC game type (seen in installed addons: [AllowLoadGameType camelot, forever]).
GAME_TYPES = {"camelot", "forever"}
GAME_FOLDERS = ["Camelot", "Forever", "Vanilla", "Mainline", "Standard", "Classic"]
DIRECTIVE = re.compile(r"\s*\[(Allow|Exclude)Load(GameType|TextLocale|Environment)\s+([^\]]*)\]", re.I)


def directives_allow(line):
    ok = True
    for kind, what, values in DIRECTIVE.findall(line):
        vals = {v.strip().lower() for v in values.split(",") if v.strip()}
        if what.lower() == "gametype":
            hit = bool(vals & GAME_TYPES)
        elif what.lower() == "textlocale":
            hit = "enus" in vals
        else:
            hit = "global" in vals or "glue" not in vals
        if kind.lower() == "allow" and not hit:
            ok = False
        if kind.lower() == "exclude" and hit:
            ok = False
    return ok, DIRECTIVE.sub("", line).strip()


def parse_toc(path):
    meta, files = {}, []
    with open(path, "r", encoding="utf-8-sig", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("##"):
                ok, clean = directives_allow(line)
                m = re.match(r"##\s*([^:]+?)\s*:\s*(.*)$", clean)
                if m and ok:
                    meta[m.group(1)] = m.group(2).strip()
            elif line.startswith("#"):
                continue
            else:
                ok, clean = directives_allow(line)
                if ok and clean:
                    files.append(clean.replace("/", "\\"))
    return meta, files


def find_toc(folder):
    name = os.path.basename(os.path.normpath(folder))
    candidates = [f"{name}.toc", f"{name}_Mainline.toc", f"{name}-Mainline.toc", f"{name}_Vanilla.toc", f"{name}-Classic.toc"]
    for c in candidates:
        p = os.path.join(folder, c)
        if os.path.isfile(p):
            return p
    for f in sorted(os.listdir(folder)):
        if f.lower().endswith(".toc") and f.lower().startswith(name.lower()):
            return os.path.join(folder, f)
    return None


def discover_addons():
    found = []
    seen = set()

    def add(folder, source):
        toc = find_toc(folder)
        if not toc:
            return
        key = os.path.normcase(os.path.abspath(folder))
        if key in seen:
            return
        seen.add(key)
        meta, _ = parse_toc(toc)
        found.append({
            "name": os.path.basename(folder),
            "path": os.path.abspath(folder),
            "title": re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", meta.get("Title", os.path.basename(folder))),
            "version": meta.get("Version", ""),
            "source": source,
        })

    # Addondev layout: Addondev\<Addon>\<Addon>\<Addon>.toc
    if os.path.isdir(ADDONDEV):
        for d in sorted(os.listdir(ADDONDEV)):
            outer = os.path.join(ADDONDEV, d)
            if not os.path.isdir(outer) or d in ("WowSim", "API"):
                continue
            inner = os.path.join(outer, d)
            if os.path.isdir(inner):
                add(inner, "Addondev")
            for sub in sorted(os.listdir(outer)):
                p = os.path.join(outer, sub)
                if os.path.isdir(p) and sub not in ("releases", "tests", "tools", "showcase") and p != inner:
                    if find_toc(p):
                        add(p, "Addondev")
    if os.path.isdir(WOW_ADDONS):
        for d in sorted(os.listdir(WOW_ADDONS)):
            p = os.path.join(WOW_ADDONS, d)
            if os.path.isdir(p) and not d.startswith("Blizzard_"):
                add(p, "Installed (read-only)")
    return found


# ---------------------------------------------------------------------------
# Text measurement for FontString sizes
# ---------------------------------------------------------------------------

class Fonts:
    def __init__(self):
        self.cache = {}

    def file_for(self, wow_path, addon_dirs):
        p = (wow_path or "").replace("/", "\\")
        low = p.lower()
        for key, fname in FONT_MAP.items():
            if key in low:
                return os.path.join(WIN_FONTS, fname)
        # Fonts shipped inside an addon: Interface\AddOns\<Addon>\...
        m = re.match(r"interface\\addons\\([^\\]+)\\(.+)$", low)
        if m:
            for name, folder in addon_dirs.items():
                if name.lower() == m.group(1):
                    cand = os.path.join(folder, p.split("\\", 3)[3])
                    if os.path.isfile(cand):
                        return cand
        return os.path.join(WIN_FONTS, FONT_MAP["frizqt"])

    def measure(self, text, wow_path, size, addon_dirs):
        if ImageFont is None:
            return len(text) * size * 0.55
        path = self.file_for(wow_path, addon_dirs)
        key = (path, int(round(size * 4)))
        font = self.cache.get(key)
        if font is None:
            try:
                font = ImageFont.truetype(path, max(1, int(round(size * 4))))
            except Exception:
                font = ImageFont.truetype(os.path.join(WIN_FONTS, "arial.ttf"), max(1, int(round(size * 4))))
            self.cache[key] = font
        return font.getlength(text) / 4.0


FONTS = Fonts()


# ---------------------------------------------------------------------------
# Spell names/icons (fetched from Wowhead's classic tooltip data, cached on disk)
# ---------------------------------------------------------------------------

class SpellCache:
    PATH = os.path.join(HERE, "cache", "spells.json")

    def __init__(self):
        self.lock = threading.Lock()
        self.queue = []
        self.failed = set()
        try:
            with open(self.PATH, "r", encoding="utf-8") as f:
                self.data = json.load(f)
        except Exception:
            self.data = {}
        self.event = threading.Event()
        threading.Thread(target=self.worker, daemon=True).start()

    def get(self, sid):
        key = str(int(sid))
        rec = self.data.get(key)
        if rec:
            return rec["name"], rec["icon"]
        with self.lock:
            if key not in self.queue and key not in self.failed:
                self.queue.append(key)
                self.event.set()
        return None

    def worker(self):
        import urllib.request
        while True:
            self.event.wait()
            with self.lock:
                key = self.queue.pop(0) if self.queue else None
                if not self.queue:
                    self.event.clear()
            if key is None:
                continue
            try:
                req = urllib.request.Request(f"https://nether.wowhead.com/tooltip/spell/{key}?dataEnv=4",
                                             headers={"User-Agent": "WowSim/1.0 (addon sandbox)"})
                with urllib.request.urlopen(req, timeout=8) as r:
                    d = json.loads(r.read().decode("utf-8"))
                name, icon = d.get("name"), d.get("icon") or "inv_misc_questionmark"
                if not name:
                    raise ValueError("no such spell")
                self.data[key] = {"name": name, "icon": icon}
                os.makedirs(os.path.dirname(self.PATH), exist_ok=True)
                with open(self.PATH, "w", encoding="utf-8") as f:
                    json.dump(self.data, f, indent=0, sort_keys=True)
                SIM.on_spell_loaded(int(key), name, icon)
            except Exception:
                self.failed.add(key)


SPELLS = None


# ---------------------------------------------------------------------------
# The simulation
# ---------------------------------------------------------------------------

class Sim:
    def __init__(self):
        self.lock = threading.RLock()
        self.lua = None
        self.addons = []           # [{name, path, meta, files, savedvars}]
        self.addon_dirs = {}
        self.boot_log = []
        self.started = 0
        self.watch = {}            # path -> mtime
        self.autoreload = True
        self.paused = False
        self.speed = 1.0
        self.pending = []          # requests from Lua (reload, fstack)
        self.config = self.load_config()
        self.screen = self.config.get("screen", [1365, 768])
        self.generation = 0
        self.doc_chunks = None

    # -- config ------------------------------------------------------------
    def load_config(self):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            return {}

    def save_config(self):
        try:
            with open(CONFIG_PATH, "w", encoding="utf-8") as f:
                json.dump(self.config, f, indent=2)
        except Exception as e:
            log("could not save config:", e)

    # -- python callbacks used from Lua --------------------------------------
    def _measure(self, text, font, size):
        try:
            return FONTS.measure(text, font, float(size), self.addon_dirs)
        except Exception:
            return len(text) * float(size) * 0.55

    def _file_exists(self, wow_path):
        p = (wow_path or "").replace("/", "\\").lower()
        if p.startswith("interface\addons\\"):
            return resolve_addon_path(wow_path) is not None
        return p.startswith("fonts\\") or p.startswith("interface\\") or p.startswith("sound\\")

    def _spell_info(self, sid):
        try:
            return SPELLS.get(sid) if SPELLS else None
        except (TypeError, ValueError):
            return None

    def on_spell_loaded(self, sid, name, icon):
        with self.lock:
            if self.lua is not None:
                try:
                    self.sim.spellLoaded(sid, name, icon)
                except Exception as e:
                    log("spellLoaded failed:", e)

    def _request(self, what):
        self.pending.append(str(what))

    # -- lifecycle -------------------------------------------------------------
    def load_docs(self):
        if self.doc_chunks is not None:
            return self.doc_chunks
        chunks = []
        if os.path.isdir(API_DOCS):
            for f in sorted(os.listdir(API_DOCS)):
                if f.endswith(".lua"):
                    try:
                        with open(os.path.join(API_DOCS, f), "r", encoding="utf-8", errors="replace") as fh:
                            chunks.append((f, fh.read()))
                    except Exception:
                        pass
        self.doc_chunks = chunks
        return chunks

    def start(self, addon_paths, profile=None):
        """(Re)create the Lua world and load the given addon folders."""
        with self.lock:
            if self.lua is not None:
                self.save_saved_variables()
            self.generation += 1
            self.boot_log = []
            t0 = time.time()
            L = lupa.LuaRuntime(unpack_returned_tuples=True, register_eval=False)
            self.lua = L
            L.execute("__SIM = {}; __SIM_load = function(code, name) local f, e = loadstring(code, name) if not f then error(e, 0) end return f() end")
            sim = L.globals()["__SIM"]
            py = L.table()
            py.measure = self._measure
            py.request = self._request
            py.fileExists = self._file_exists
            py.spellInfo = self._spell_info
            sim.py = py
            for f in LUA_FILES:
                with open(os.path.join(LUA_DIR, f), "r", encoding="utf-8") as fh:
                    code = fh.read()
                try:
                    L.globals()["__SIM_load"](code, "@WowSim/" + f)
                except Exception as e:
                    raise RuntimeError(f"WowSim core {f} failed: {e}")
            g = L.globals()
            self.sim = g["__SIM"]
            # Strip things WoW does not have.
            L.execute("io = nil; require = nil; dofile = nil; loadfile = nil; package = nil; module = nil")
            docs = self.load_docs()
            for name, code in docs:
                self.sim.loadDocChunk(code, name)
            nf, ns, ne = self.sim.installDocs()
            self.boot_log.append(f"API docs: {len(docs)} files, {nf} functions ({ns} stubbed), {ne} events")
            filled, failed = 0, []
            for rel in BLIZZARD_FILL:
                full = os.path.join(BLIZZ_ROOT, rel.replace("/", os.sep))
                if not os.path.isfile(full):
                    continue
                with open(full, "r", encoding="utf-8-sig", errors="replace") as fh:
                    res = self.sim.fillFromBlizzard(fh.read(), rel)
                ok, err, added = (list(res) + [None, None, None])[:3] if isinstance(res, tuple) else (res, None, 0)
                filled += added or 0
                if not ok:
                    failed.append(os.path.basename(rel) + ": " + str(err)[:120])
            self.boot_log.append(f"FrameXML fill: {filled} globals from {len(BLIZZARD_FILL)} Blizzard files" + (f" ({len(failed)} partial)" if failed else ""))
            for f in failed:
                self.boot_log.append("  partial " + f)
            self.sim.screenW, self.sim.screenH = self.screen[0], self.screen[1]
            if profile:
                self.apply_profile(profile)
            elif self.config.get("profile"):
                self.apply_profile(self.config["profile"])

            # Load addons in order.
            self.addons = []
            self.addon_dirs = {}
            self.watch = {}
            for f in LUA_FILES:
                self.watch[os.path.join(LUA_DIR, f)] = os.path.getmtime(os.path.join(LUA_DIR, f))
            ordered = self.with_dependencies(addon_paths)
            for i, path in enumerate(ordered, start=1):
                self.load_addon(path, i)
            self.sim.login()
            self.started = time.time()
            self.last_tick = time.time()
            self.boot_log.append(f"Booted in {time.time() - t0:.2f}s")
            log(" | ".join(self.boot_log))

    def with_dependencies(self, paths):
        """Put required dependencies (found next to the addon) ahead of it, like the client."""
        out, seen = [], set()

        def visit(path, chain=()):
            key = os.path.normcase(os.path.abspath(path))
            if key in seen or key in chain:
                return
            toc = find_toc(path)
            if toc:
                meta, _ = parse_toc(toc)
                deps = []
                for k, v in meta.items():
                    if k.lower() in ("dependencies", "requireddeps") or re.match(r"(?i)^dep\w*$", k):
                        deps += [d.strip() for d in v.split(",") if d.strip()]
                for d in deps:
                    if d.lower().startswith("blizzard_"):
                        continue
                    cand = os.path.join(os.path.dirname(os.path.abspath(path)), d)
                    if os.path.isdir(cand) and find_toc(cand):
                        if os.path.normcase(os.path.abspath(cand)) not in seen:
                            self.boot_log.append(f"{os.path.basename(path)} needs {d}: loading it too")
                        visit(cand, chain + (key,))
                    else:
                        self.boot_log.append(f"{os.path.basename(path)} needs {d}, which was not found")
            seen.add(key)
            out.append(os.path.abspath(path))

        for p in paths:
            visit(p)
        return out

    def apply_profile(self, prof):
        P = self.sim.profile
        for k, v in prof.items():
            if isinstance(v, dict):
                t = P[k]
                if t is None:
                    t = self.lua.table()
                    P[k] = t
                for sk, sv in v.items():
                    t[sk] = self.to_lua(sv)
            else:
                P[k] = self.to_lua(v)

    def to_lua(self, v):
        if isinstance(v, dict):
            t = self.lua.table()
            for k, x in v.items():
                t[k] = self.to_lua(x)
            return t
        if isinstance(v, list):
            t = self.lua.table()
            for i, x in enumerate(v, start=1):
                t[i] = self.to_lua(x)
            return t
        return v

    def load_addon(self, path, index):
        toc = find_toc(path)
        if not toc:
            self.boot_log.append(f"No .toc in {path}")
            return
        name = os.path.basename(os.path.normpath(path))
        meta, files = parse_toc(toc)
        meta_t = self.lua.table()
        for k, v in meta.items():
            meta_t[k] = v
        self.sim.registerAddon(name, meta_t, index)
        self.addon_dirs[name] = path
        self.watch[toc] = os.path.getmtime(toc)
        saved = [s.strip() for s in (meta.get("SavedVariables", "") + "," + meta.get("SavedVariablesPerCharacter", "")).split(",") if s.strip()]
        rec = {"name": name, "path": path, "meta": meta, "files": [], "saved": saved}
        self.addons.append(rec)
        count = 0
        for rel in files:
            count += self.load_file(rec, rel)
        # SavedVariables load after the code, before ADDON_LOADED.
        sv = os.path.join(SAVED_DIR, name + ".lua")
        if os.path.isfile(sv):
            with open(sv, "r", encoding="utf-8", errors="replace") as fh:
                self.sim.runSaved(fh.read(), name)
        self.sim.addonLoaded(name)
        self.boot_log.append(f"{name}: {count} files")

    def load_file(self, rec, rel):
        rel = rel.replace("[TextLocale]", "enUS").replace("[Family]", "Mainline")
        if "[Game]" in rel:
            for g in GAME_FOLDERS:
                if os.path.isfile(os.path.join(rec["path"], rel.replace("[Game]", g))):
                    rel = rel.replace("[Game]", g)
                    break
        full = os.path.join(rec["path"], rel)
        if not os.path.isfile(full):
            self.sim.reportError(self.lua.table_from({"msg": f"{rec['name']}: file listed in TOC not found: {rel}", "stack": ""}))
            return 0
        self.watch[full] = os.path.getmtime(full)
        if rel.lower().endswith(".xml"):
            return self.load_xml(rec, full)
        if not rel.lower().endswith(".lua"):
            return 0
        with open(full, "r", encoding="utf-8-sig", errors="replace") as fh:
            code = fh.read()
        chunk = "Interface/AddOns/" + rec["name"] + "/" + rel.replace("\\", "/")
        self.sim.runFile(code, chunk, rec["name"])
        rec["files"].append(rel)
        return 1

    def load_xml(self, rec, full):
        """Only <Script file> and <Include file> are understood (enough for libraries)."""
        base = os.path.dirname(full)
        with open(full, "r", encoding="utf-8-sig", errors="replace") as fh:
            xml = fh.read()
        xml_no_comments = re.sub(r"<!--.*?-->", "", xml, flags=re.S)
        count = 0
        for m in re.finditer(r"<(Script|Include)\s+file\s*=\s*\"([^\"]+)\"", xml_no_comments):
            rel = os.path.relpath(os.path.join(base, m.group(2).replace("/", "\\")), rec["path"])
            count += self.load_file(rec, rel)
        if re.search(r"<(Frame|Button|CheckButton|Texture|FontString|Ui)\b[^>]*\b(name|parent)=", xml_no_comments):
            self.sim.noteStub("XML frame definitions are not simulated: " + os.path.relpath(full, rec["path"]))
        return count

    def save_saved_variables(self, final=True):
        if self.lua is None:
            return
        os.makedirs(SAVED_DIR, exist_ok=True)
        if final:
            try:
                self.sim.logout()
            except Exception:
                pass
        for rec in self.addons:
            if not rec["saved"]:
                continue
            names = self.lua.table()
            for i, n in enumerate(rec["saved"], start=1):
                names[i] = n
            try:
                text = self.sim.saveVariables(names)
            except Exception as e:
                log("saving", rec["name"], "failed:", e)
                continue
            path = os.path.join(SAVED_DIR, rec["name"] + ".lua")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)

    def reset_saved_variables(self, name):
        path = os.path.join(SAVED_DIR, name + ".lua")
        if os.path.isfile(path):
            os.remove(path)

    def reload(self, save=True):
        paths = [a["path"] for a in self.addons]
        profile = self.current_profile()
        with self.lock:
            if not save:
                self.lua = None
            self.start(paths, profile)

    def current_profile(self):
        if self.lua is None:
            return self.config.get("profile")
        try:
            return json.loads(self.sim.json(self.sim.profile))
        except Exception:
            return None

    # -- per-frame -------------------------------------------------------------
    def tick(self):
        with self.lock:
            if self.lua is None:
                return
            now = time.time()
            dt = now - self.last_tick
            self.last_tick = now
            if not self.paused:
                try:
                    self.sim.tick(dt * self.speed)
                except Exception as e:
                    log("tick error:", e)
            while self.pending:
                req = self.pending.pop(0)
                if req == "reload":
                    threading.Thread(target=self.reload, daemon=True).start()

    def files_changed(self):
        changed = []
        for p, m in list(self.watch.items()):
            try:
                if os.path.getmtime(p) != m:
                    changed.append(p)
            except OSError:
                changed.append(p)
        return changed


SIM = Sim()


# ---------------------------------------------------------------------------
# Media (addon textures, sounds, fonts)
# ---------------------------------------------------------------------------

def resolve_addon_path(wow_path):
    p = (wow_path or "").replace("/", "\\")
    m = re.match(r"(?i)interface\\addons\\([^\\]+)\\(.+)$", p)
    if not m:
        return None
    for name, folder in SIM.addon_dirs.items():
        if name.lower() == m.group(1).lower():
            cand = os.path.join(folder, m.group(2))
            if os.path.isfile(cand):
                return cand
            # WoW lets you omit the extension.
            for ext in (".tga", ".blp", ".png", ".jpg", ".ogg", ".mp3", ".wav"):
                if os.path.isfile(cand + ext):
                    return cand + ext
    return None


_png_cache = {}


def image_as_png(path):
    mt = os.path.getmtime(path)
    hit = _png_cache.get(path)
    if hit and hit[0] == mt:
        return hit[1]
    img = Image.open(path)
    img = img.convert("RGBA")
    buf = BytesIO()
    img.save(buf, "PNG")
    data = buf.getvalue()
    _png_cache[path] = (mt, data)
    return data


# ---------------------------------------------------------------------------
# HTTP
# ---------------------------------------------------------------------------

CONTENT_TYPES = {
    ".html": "text/html; charset=utf-8", ".js": "application/javascript; charset=utf-8",
    ".css": "text/css; charset=utf-8", ".png": "image/png", ".jpg": "image/jpeg", ".ogg": "audio/ogg",
    ".mp3": "audio/mpeg", ".wav": "audio/wav", ".ttf": "font/ttf", ".svg": "image/svg+xml",
}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def send(self, code, body, ctype="application/json; charset=utf-8", extra=None):
        if isinstance(body, str):
            body = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def json(self, obj, code=200):
        self.send(code, json.dumps(obj))

    def body(self):
        n = int(self.headers.get("Content-Length") or 0)
        if not n:
            return {}
        try:
            return json.loads(self.rfile.read(n).decode("utf-8"))
        except Exception:
            return {}

    # -- GET ------------------------------------------------------------------
    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        q = urllib.parse.parse_qs(u.query)
        path = u.path
        try:
            if path == "/" or path == "/index.html":
                return self.static("index.html")
            if path.startswith("/static/"):
                return self.static(path[len("/static/"):])
            if path == "/api/addons":
                return self.json({"addons": discover_addons(), "loaded": [a["path"] for a in SIM.addons],
                                  "autoreload": SIM.autoreload, "screen": SIM.screen})
            if path == "/api/state":
                return self.state(q)
            if path == "/api/info":
                with SIM.lock:
                    if SIM.lua is None:
                        return self.json({})
                    data = json.loads(SIM.sim.info())
                data["boot"] = SIM.boot_log
                data["addons"] = [{"name": a["name"], "title": a["meta"].get("Title", a["name"]), "saved": a["saved"],
                                   "files": a["files"], "version": a["meta"].get("Version", "")} for a in SIM.addons]
                data["paused"] = SIM.paused
                data["speed"] = SIM.speed
                return self.json(data)
            if path == "/api/events":
                with SIM.lock:
                    if SIM.lua is None:
                        return self.json([])
                    return self.send(200, SIM.sim.json(SIM.sim.eventCatalog()))
            if path == "/api/saved":
                name = (q.get("addon") or [""])[0]
                with SIM.lock:
                    rec = next((a for a in SIM.addons if a["name"] == name), None)
                    if not rec:
                        return self.json({"text": ""})
                    names = SIM.lua.table()
                    for i, n in enumerate(rec["saved"], start=1):
                        names[i] = n
                    return self.json({"text": SIM.sim.saveVariables(names) or "-- (nothing saved yet)"})
            if path == "/media":
                return self.media((q.get("p") or [""])[0])
            if path == "/font":
                return self.font((q.get("p") or [""])[0])
            return self.send(404, "not found", "text/plain")
        except Exception as e:
            traceback.print_exc()
            return self.json({"error": str(e)}, 500)

    def static(self, rel):
        full = os.path.normpath(os.path.join(WEB_DIR, rel))
        if not full.startswith(WEB_DIR) or not os.path.isfile(full):
            return self.send(404, "not found", "text/plain")
        with open(full, "rb") as fh:
            data = fh.read()
        self.send(200, data, CONTENT_TYPES.get(os.path.splitext(full)[1].lower(), "application/octet-stream"))

    def state(self, q):
        def num(k, d=0):
            try:
                return float((q.get(k) or [d])[0])
            except ValueError:
                return d
        with SIM.lock:
            if SIM.lua is None:
                return self.json({"scene": [], "idle": True})
            inspect = (q.get("inspect") or ["0"])[0] == "1"
            text = SIM.sim.state(num("chat"), num("err"), num("snd"), num("msg"), num("stub"), inspect,
                                 num("ix"), num("iy"))
            gen = SIM.generation
        self.send(200, text[:-1] + ',"gen":%d,"paused":%s}' % (gen, "true" if SIM.paused else "false"))

    def media(self, wow_path):
        path = resolve_addon_path(wow_path)
        if not path:
            return self.send(404, "no such addon file", "text/plain")
        ext = os.path.splitext(path)[1].lower()
        if ext in (".tga", ".blp") and Image is not None:
            try:
                return self.send(200, image_as_png(path), "image/png", {"Cache-Control": "no-cache"})
            except Exception as e:
                return self.send(500, f"image decode failed: {e}", "text/plain")
        with open(path, "rb") as fh:
            data = fh.read()
        self.send(200, data, CONTENT_TYPES.get(ext, "application/octet-stream"))

    def font(self, wow_path):
        path = FONTS.file_for(wow_path, SIM.addon_dirs)
        if not os.path.isfile(path):
            return self.send(404, "font missing", "text/plain")
        with open(path, "rb") as fh:
            data = fh.read()
        self.send(200, data, "font/ttf", {"Cache-Control": "max-age=3600"})

    # -- POST -----------------------------------------------------------------
    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        path = u.path
        b = self.body()
        try:
            if path == "/api/load":
                paths = [os.path.abspath(p) for p in b.get("paths", []) if os.path.isdir(p)]
                SIM.config["lastAddons"] = paths
                SIM.save_config()
                SIM.start(paths, SIM.current_profile())
                return self.json({"ok": True, "boot": SIM.boot_log})
            if path == "/api/reload":
                SIM.reload(save=b.get("save", True))
                return self.json({"ok": True, "boot": SIM.boot_log})
            if path == "/api/resetsaved":
                name = b.get("addon")
                with SIM.lock:
                    paths = [a["path"] for a in SIM.addons]
                    SIM.lua = None  # skip saving the current values
                    SIM.reset_saved_variables(name)
                    SIM.start(paths, SIM.config.get("profile"))
                return self.json({"ok": True})
            if path == "/api/input":
                return self.input(b)
            if path == "/api/exec":
                with SIM.lock:
                    if SIM.lua is None:
                        return self.json({"result": "no addon loaded"})
                    res = SIM.sim.exec(b.get("code", ""))
                return self.json({"result": res})
            if path == "/api/event":
                return self.fire(b)
            if path == "/api/profile":
                with SIM.lock:
                    if SIM.lua is None:
                        return self.json({"ok": False})
                    key, value, sub = b.get("key"), b.get("value"), b.get("sub")
                    SIM.sim.setProfile(key, SIM.to_lua(value), sub)
                    SIM.config["profile"] = SIM.current_profile()
                SIM.save_config()
                return self.json({"ok": True})
            if path == "/api/settings":
                if "autoreload" in b:
                    SIM.autoreload = bool(b["autoreload"])
                if "paused" in b:
                    SIM.paused = bool(b["paused"])
                if "speed" in b:
                    SIM.speed = max(0.1, min(10.0, float(b["speed"])))
                if "screen" in b:
                    w, h = b["screen"]
                    SIM.screen = [float(w), float(h)]
                    SIM.config["screen"] = SIM.screen
                    SIM.save_config()
                    with SIM.lock:
                        if SIM.lua is not None:
                            SIM.sim.screenW, SIM.sim.screenH = SIM.screen
                            SIM.sim.invalidate()
                            SIM.sim.fireEvent("DISPLAY_SIZE_CHANGED")
                return self.json({"ok": True})
            if path == "/api/options":
                with SIM.lock:
                    name = b.get("name")
                    SIM.lua.globals().Settings.OpenToCategory(name)
                return self.json({"ok": True})
            if path == "/api/clearerrors":
                with SIM.lock:
                    if SIM.lua is not None:
                        SIM.lua.execute("__SIM.errors = {}")
                return self.json({"ok": True})
            return self.send(404, "not found", "text/plain")
        except Exception as e:
            traceback.print_exc()
            return self.json({"error": str(e)}, 500)

    def input(self, b):
        t = b.get("type")
        with SIM.lock:
            if SIM.lua is None:
                return self.json({"ok": False})
            s = SIM.sim
            mods = b.get("mods")
            if mods:
                s.mods.shift, s.mods.ctrl, s.mods.alt = bool(mods.get("shift")), bool(mods.get("ctrl")), bool(mods.get("alt"))
            x, y = b.get("x", 0), b.get("y", 0)
            # The browser sends top-left coordinates; WoW is bottom-left.
            wy = SIM.screen[1] - y
            if t == "move":
                s.mouseMove(x, wy)
            elif t == "down":
                s.lastClickButton = b.get("button", "LeftButton")
                s.mouseDown(x, wy, b.get("button", "LeftButton"))
            elif t == "up":
                s.mouseUp(x, wy, b.get("button", "LeftButton"))
            elif t == "wheel":
                s.mouseWheel(x, wy, b.get("delta", 0))
            elif t == "keydown":
                s.keyDown(b.get("key", ""))
            elif t == "keyup":
                s.keyUp(b.get("key", ""))
            elif t == "text":
                s.editText(int(b.get("id")), b.get("text", ""), b.get("cursor"))
            elif t == "chat":
                s.chatInput(b.get("text", ""))
        return self.json({"ok": True})

    def fire(self, b):
        event = b.get("event", "")
        args = b.get("args", [])
        with SIM.lock:
            if SIM.lua is None:
                return self.json({"ok": False})
            vals = []
            for a in args:
                vals.append(SIM.to_lua(a))
            SIM.sim.fireEvent(event, *vals)
        return self.json({"ok": True})


# ---------------------------------------------------------------------------
# Background loops
# ---------------------------------------------------------------------------

def tick_loop():
    while True:
        SIM.tick()
        time.sleep(1 / 60)


def watch_loop():
    last_save = time.time()
    while True:
        time.sleep(0.6)
        # Closing the console window kills us without warning, so persist SavedVariables now and then.
        if SIM.lua is not None and time.time() - last_save > 20:
            last_save = time.time()
            try:
                with SIM.lock:
                    SIM.save_saved_variables(final=False)
            except Exception as e:
                log("autosave failed:", e)
        if not SIM.autoreload or SIM.lua is None:
            continue
        try:
            changed = SIM.files_changed()
        except Exception:
            changed = []
        if changed:
            time.sleep(0.25)  # let the editor finish writing
            log("changed:", ", ".join(os.path.basename(c) for c in changed), "- reloading")
            try:
                SIM.reload()
            except Exception as e:
                log("reload failed:", e)


def main():
    global SPELLS
    SPELLS = SpellCache()
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=8642)
    ap.add_argument("--addon", action="append", default=[])
    ap.add_argument("--no-browser", action="store_true")
    args = ap.parse_args()
    paths = [os.path.abspath(p) for p in args.addon] or [p for p in SIM.config.get("lastAddons", []) if os.path.isdir(p)]
    try:
        SIM.start(paths)
    except Exception:
        traceback.print_exc()
    threading.Thread(target=tick_loop, daemon=True).start()
    threading.Thread(target=watch_loop, daemon=True).start()
    srv = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    url = f"http://localhost:{args.port}/"
    log("WowSim running at", url)
    if not args.no_browser:
        threading.Timer(0.6, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        with SIM.lock:
            SIM.save_saved_variables()
        log("saved variables written, bye")


if __name__ == "__main__":
    main()
