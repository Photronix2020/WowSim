"""Blizzard game data for WowSim, fetched on demand from wago.tools and cached.

- GlobalStrings for the exact Forever build (ITEM_LEVEL, SPELL_FAILED_..., ~27k strings)
- Texture atlases (SetAtlas names -> file + texture coordinates + size)
- Real UI art and fonts: a texture path is mapped to its file ID with the community
  listfile, then the file is downloaded once and converted to PNG.

Nothing here is redistributed with WowSim; it all lands in cache/ (gitignored).
Set "blizzardData": false in config.json to turn it off.
"""

import csv
import io
import json
import os
import re
import sqlite3
import threading
import time
import urllib.request

WAGO = "https://wago.tools"
LISTFILE_URL = "https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv"
UA = {"User-Agent": "WowSim/1.0 (local addon sandbox; github.com/Photronix2020/WowSim)"}
DEFAULT_BUILD = "1.60.1.70009"


def _get(url, timeout=30):
    req = urllib.request.Request(url, headers=UA)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def normalize(path):
    p = str(path).replace("\\", "/").strip().lstrip("/").lower()
    return re.sub(r"/+", "/", p)


class BlizzardData:
    def __init__(self, cache_dir, build=None, log=print, enabled=True):
        self.dir = cache_dir
        self.build = build or DEFAULT_BUILD
        self.log = log
        self.enabled = enabled
        os.makedirs(os.path.join(self.dir, "files"), exist_ok=True)
        os.makedirs(os.path.join(self.dir, "png"), exist_ok=True)
        self.db_path = os.path.join(self.dir, "listfile.sqlite")
        self.listfile_state = "off" if not enabled else "unknown"
        self.listfile_error = None
        self.atlas = {}
        self.missing = set()           # fdids we failed to fetch
        self.failed_tables = set()
        self.fetch_locks = {}
        self.lock = threading.Lock()
        self.local = threading.local()
        if enabled:
            if os.path.isfile(self.db_path):
                self.listfile_state = "ready"
            else:
                threading.Thread(target=self.build_listfile, daemon=True).start()

    # -- exact-build DB2 tables ------------------------------------------------
    def table(self, name):
        """Return CSV rows for a DB2 table at our build (cached on disk)."""
        if not self.enabled:
            return []
        path = os.path.join(self.dir, f"{name}-{self.build}.csv")
        if not os.path.isfile(path):
            if name in self.failed_tables:
                return []   # already failed this session (offline?); do not stall every reload
            try:
                data = _get(f"{WAGO}/db2/{name}/csv?build={self.build}", timeout=20)
                if not data.startswith(b"ID") and b"," not in data[:200]:
                    raise ValueError("unexpected response")
                with open(path, "wb") as f:
                    f.write(data)
            except Exception as e:
                self.log(f"Blizzard data: could not fetch {name} for {self.build}: {e}")
                self.failed_tables.add(name)
                return []
        with open(path, "r", encoding="utf-8", newline="") as f:
            return list(csv.DictReader(f))

    def global_strings(self):
        out = {}
        for row in self.table("GlobalStrings"):
            tag, text = row.get("BaseTag"), row.get("TagText_lang")
            if tag and text is not None:
                out[tag] = text
        return out

    def load_atlases(self):
        if self.atlas or not self.enabled:
            return len(self.atlas)
        files = {}
        for row in self.table("UiTextureAtlas"):
            try:
                files[row["ID"]] = (int(row["FileDataID"]), int(row["AtlasWidth"]), int(row["AtlasHeight"]))
            except (KeyError, ValueError):
                pass
        for row in self.table("UiTextureAtlasMember"):
            try:
                fdid, aw, ah = files[row["UiTextureAtlasID"]]
                l, r, t, b = (int(row[k]) for k in ("CommittedLeft", "CommittedRight", "CommittedTop", "CommittedBottom"))
                w = int(row["OverrideWidth"]) or int(row["Width"])
                h = int(row["OverrideHeight"]) or int(row["Height"])
                flags = int(row.get("CommittedFlags") or 0)
            except (KeyError, ValueError):
                continue
            self.atlas[row["CommittedName"].lower()] = {
                "file": fdid, "width": w, "height": h,
                "left": l / aw, "right": r / aw, "top": t / ah, "bottom": b / ah,
                "tilesH": bool(flags & 4), "tilesV": bool(flags & 2),
            }
        return len(self.atlas)

    def atlas_info(self, name):
        return self.atlas.get(str(name).lower())

    # -- listfile (path <-> file ID) ---------------------------------------------
    def build_listfile(self):
        self.listfile_state = "downloading"
        tmp = self.db_path + ".tmp"
        try:
            t0 = time.time()
            self.log("Blizzard art: downloading the community listfile (one time, ~150 MB)...")
            req = urllib.request.Request(LISTFILE_URL, headers=UA)
            if os.path.exists(tmp):
                os.remove(tmp)
            con = sqlite3.connect(tmp)
            con.execute("CREATE TABLE files (stem TEXT, path TEXT, fdid INTEGER)")
            rows, n = [], 0
            with urllib.request.urlopen(req, timeout=60) as r:
                for raw in io.TextIOWrapper(r, encoding="utf-8", errors="replace"):
                    fdid, _, path = raw.rstrip("\r\n").partition(";")
                    low = path[:10].lower()
                    if not (low.startswith("interface/") or low.startswith("fonts/")):
                        continue
                    try:
                        fid = int(fdid)
                    except ValueError:
                        continue
                    path = normalize(path)
                    stem = re.sub(r"\.(blp|tga|png|jpg|ttf|otf)$", "", path)
                    rows.append((stem, path, fid))
                    n += 1
                    if len(rows) >= 50000:
                        con.executemany("INSERT INTO files VALUES (?,?,?)", rows)
                        rows = []
            if rows:
                con.executemany("INSERT INTO files VALUES (?,?,?)", rows)
            con.execute("CREATE INDEX stem_i ON files(stem)")
            con.execute("CREATE INDEX fdid_i ON files(fdid)")
            con.commit()
            con.close()
            os.replace(tmp, self.db_path)
            self.listfile_state = "ready"
            self.log(f"Blizzard art: listfile ready ({n} interface/font files, {time.time() - t0:.0f}s)")
        except Exception as e:
            self.listfile_state = "failed"
            self.listfile_error = str(e)
            self.log(f"Blizzard art: listfile download failed: {e}")

    def _db(self):
        con = getattr(self.local, "con", None)
        if con is None:
            con = sqlite3.connect(self.db_path, check_same_thread=False)
            self.local.con = con
        return con

    def resolve(self, path_or_id):
        """WoW texture path or file ID -> (fdid, normalized path) or None."""
        if not self.enabled:
            return None
        s = str(path_or_id).strip()
        if re.fullmatch(r"\d+", s):
            fid = int(s)
            path = None
            if self.listfile_state == "ready":
                row = self._db().execute("SELECT path FROM files WHERE fdid=? LIMIT 1", (fid,)).fetchone()
                path = row[0] if row else None
            return fid, path
        if self.listfile_state != "ready":
            return None
        p = normalize(s)
        stem = re.sub(r"\.(blp|tga|png|jpg|ttf|otf)$", "", p)
        rows = self._db().execute("SELECT fdid, path FROM files WHERE stem=?", (stem,)).fetchall()
        if not rows:
            return None
        rows.sort(key=lambda r: (not r[1].endswith(".blp"), not r[1].endswith(".ttf")))
        return rows[0][0], rows[0][1]

    # -- files -------------------------------------------------------------------------
    def fetch(self, fdid):
        """Raw file bytes for a file ID (downloaded once)."""
        path = os.path.join(self.dir, "files", str(fdid))
        if os.path.isfile(path):
            with open(path, "rb") as f:
                return f.read()
        if fdid in self.missing:
            return None
        with self.lock:
            lk = self.fetch_locks.setdefault(fdid, threading.Lock())
        with lk:
            if os.path.isfile(path):
                with open(path, "rb") as f:
                    return f.read()
            try:
                data = _get(f"{WAGO}/api/casc/{fdid}?download", timeout=30)
                if len(data) < 16 or data[:1] == b"<" or data[:1] == b"{":
                    raise ValueError("not a file")
                with open(path + ".tmp", "wb") as f:
                    f.write(data)
                os.replace(path + ".tmp", path)
                return data
            except Exception:
                self.missing.add(fdid)
                return None

    def png(self, fdid):
        """PNG bytes for an image file ID, plus (width, height)."""
        out = os.path.join(self.dir, "png", f"{fdid}.png")
        if os.path.isfile(out):
            with open(out, "rb") as f:
                return f.read()
        data = self.fetch(fdid)
        if data is None:
            return None
        from PIL import Image
        try:
            img = Image.open(io.BytesIO(data)).convert("RGBA")
        except Exception:
            self.missing.add(fdid)
            return None
        buf = io.BytesIO()
        img.save(buf, "PNG")
        png = buf.getvalue()
        with open(out, "wb") as f:
            f.write(png)
        return png

    def font_file(self, wow_path):
        """Local path to a real WoW font file, or None."""
        hit = self.resolve(wow_path)
        if not hit:
            return None
        fdid = hit[0]
        path = os.path.join(self.dir, "files", str(fdid))
        if os.path.isfile(path) or self.fetch(fdid) is not None:
            with open(path, "rb") as f:
                head = f.read(4)
            if head in (b"\x00\x01\x00\x00", b"OTTO", b"true"):
                return path
        return None

    def status(self):
        return {"enabled": self.enabled, "build": self.build, "listfile": self.listfile_state,
                "atlases": len(self.atlas), "error": self.listfile_error}
