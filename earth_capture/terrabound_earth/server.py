"""The app's local web server: the map page, and a small JSON API the page calls.

It listens on 127.0.0.1 only, and every API call must carry the token printed into the page, so
other web pages open in a browser cannot use it.
"""
from __future__ import annotations

import csv
import json
import mimetypes
import os
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, quote, urlparse

from . import __version__, config
from .aoi import Area
from .blender import open_in_blender
from .dataset import image_roots, lr_files
from .scene import load_scene, scene_paths
from .sources.http import session
from .store import Store
from .suggest import KINDS
from .views import estimate
from .worker import Worker

NOMINATIM = "https://nominatim.openstreetmap.org/search"


class App:
    def __init__(self):
        self.token = secrets.token_urlsafe(24)
        self.store = Store()
        self.worker = Worker(self.store)
        self.window = None                 # the pywebview window, when there is one
        self._search_lock = threading.Lock()
        self._last_search = 0.0

    # ---- helpers --------------------------------------------------------------------------------
    def run_url(self, path: Path) -> str:
        rel = path.resolve().relative_to(config.runs_dir().resolve()).as_posix()
        return f"/runs/{quote(rel)}?t={self.token}&v={int(path.stat().st_mtime)}"

    # ---- API ------------------------------------------------------------------------------------
    def api_state(self, _):
        return {"version": __version__, "queue": self.store.snapshot(), "worker": self.worker.state(),
                "settings": {"scene": self.store.scene.to_dict(), "views": self.store.views.to_dict()},
                "tools": {"matlab": config.find_matlab(), "blender": config.find_blender()},
                "paths": {"runs": str(config.runs_dir()), "datasets": str(config.datasets_dir())},
                "kinds": {k: v.label for k, v in KINDS.items()}}

    def api_search(self, a):
        q = str(a.get("q", "")).strip()
        if not q:
            return []
        with self._search_lock:            # Nominatim's policy: at most one request a second
            wait = 1.0 - (time.time() - self._last_search)
            if wait > 0:
                time.sleep(wait)
            self._last_search = time.time()
            r = session().get(NOMINATIM, params={"q": q, "format": "jsonv2", "limit": 8}, timeout=30)
        r.raise_for_status()
        out = []
        for p in r.json():
            s, n, w, e = (float(v) for v in p["boundingbox"])
            out.append({"name": p.get("display_name", q), "lat": float(p["lat"]), "lon": float(p["lon"]),
                        "bbox": [w, s, e, n]})
        return out

    def api_area_info(self, a):
        area = Area.from_dict(a["area"])
        w, h = area.size_m
        return {"id": area.id, "width_m": round(w), "height_m": round(h), "area_km2": round(area.area_km2, 3),
                "problems": area.problems(), "estimate": estimate(area, None, self.store.views)}

    def api_add(self, a):
        area = Area.from_dict(a["area"])
        issues = area.problems()
        if issues:
            return {"ok": False, "problems": issues}
        it, new = self.store.add(area)
        return {"ok": True, "id": it["id"], "new": new}

    def api_remove(self, a):
        self.store.remove(a["id"])
        return {"ok": True}

    def api_rename(self, a):
        self.store.rename(a["id"], a.get("name", ""))
        return {"ok": True}

    def api_retry(self, a):
        self.store.update(a["id"], status="queued", message="")
        return {"ok": True}

    def api_settings(self, a):
        problems = self.store.save_settings(a.get("scene"), a.get("views"))
        return {"ok": not problems, "problems": problems}

    def api_prepare(self, a):
        return {"ok": self.worker.prepare(a.get("ids")), "busy": self.worker.busy}

    def api_run(self, a):
        return {"ok": self.worker.run(a.get("ids")), "busy": self.worker.busy}

    def api_stop(self, _):
        self.worker.stop()
        return {"ok": True}

    def api_suggest(self, a):
        region = a.get("region") or [-180, -56, 180, 72]
        ok = self.worker.suggest(a.get("kind", "city"), tuple(float(v) for v in region), int(a.get("n", 5)),
                                 float(a.get("side_m", 500)), int(a.get("seed", 1)))
        return {"ok": ok}

    def api_export(self, a):
        return {"ok": self.worker.export(a.get("ids"), a.get("lr_size", "aligned"), a.get("out_dir"))}

    def api_overlays(self, a):
        area = self.store.area(a["id"])
        meta = load_scene(area)
        if meta is None:
            return {"ok": False}
        pv = scene_paths(area)["preview"]
        w, s, e, n = meta["geo_bounds"]
        return {"ok": True, "buildings": self.run_url(pv / "buildings.geojson"),
                "materials": self.run_url(pv / "materials.png"), "bounds": [[s, w], [n, e]],
                "stats": {"buildings": meta["buildings"], "triangles": meta["counts"]["triangles"],
                          "landcover": meta["landcover_fractions"], "relief_m": round(meta["relief_m"], 1)}}

    def api_results(self, a):
        area = self.store.area(a["id"])
        out = []
        for root, planned in image_roots(area):
            idx = root / "dataset_index.csv"
            if not idx.exists():
                continue
            with open(idx, newline="", encoding="utf-8") as f:
                for r in csv.DictReader(f):
                    vdir = root / "views" / r["view"]
                    item = {"view": r["view"], "status": r["status"], "message": r["message"],
                            "bearing": r["bearing_deg"], "incidence": r["incidence_deg"],
                            "from": "blender" if root.name == "blender_scene" else "app"}
                    name = r["view"].split("_")[1] if "_" in r["view"] else ""
                    if name in planned:
                        item["footprint"] = planned[name]["footprint"]
                    if (vdir / "HR.png").exists():
                        item["hr"] = self.run_url(vdir / "HR.png")
                        item["lr"] = [{"factor": f, "url": self.run_url(p)} for f, p in lr_files(vdir)]
                    out.append(item)
        return out

    def api_open_blender(self, a):
        return {"ok": True, "folder": open_in_blender(self.store.area(a["id"]), self.store.views)}

    def api_open_folder(self, a):
        p = Path(a["path"]).resolve()
        allowed = [config.runs_dir().resolve(), config.datasets_dir().resolve(), config.REPO_ROOT.resolve()]
        if not any(p == r or r in p.parents for r in allowed) or not p.exists():
            return {"ok": False, "error": "Only folders of this project can be opened."}
        os.startfile(str(p))  # noqa: S606 -- a local folder chosen in the app
        return {"ok": True}

    def api_pick_folder(self, _):
        if self.window is None:
            return {"ok": False}
        import webview
        res = self.window.create_file_dialog(webview.FOLDER_DIALOG)
        return {"ok": bool(res), "path": res[0] if res else None}


def make_handler(app: App):
    class Handler(BaseHTTPRequestHandler):
        server_version = "EarthCapture"

        def log_message(self, *args):     # quiet
            pass

        def _send(self, code: int, body: bytes, ctype: str):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Content-Type-Options", "nosniff")
            self.end_headers()
            self.wfile.write(body)

        def _json(self, code: int, obj):
            self._send(code, json.dumps(obj).encode("utf-8"), "application/json")

        def _file(self, root: Path, rel: str):
            root = root.resolve()
            p = (root / rel).resolve()
            if root not in p.parents or not p.is_file():
                return self._send(404, b"not found", "text/plain")
            ctype = mimetypes.guess_type(p.name)[0] or "application/octet-stream"
            if p.suffix == ".geojson":
                ctype = "application/geo+json"
            self._send(200, p.read_bytes(), ctype)

        def do_GET(self):
            u = urlparse(self.path)
            if u.path in ("/", "/index.html"):
                html = (config.WEB_DIR / "index.html").read_text(encoding="utf-8").replace("__TOKEN__", app.token)
                return self._send(200, html.encode("utf-8"), "text/html; charset=utf-8")
            if u.path.startswith("/static/"):
                return self._file(config.WEB_DIR, u.path[len("/static/"):])
            if u.path.startswith("/runs/"):
                if parse_qs(u.query).get("t", [""])[0] != app.token:
                    return self._send(403, b"forbidden", "text/plain")
                from urllib.parse import unquote
                return self._file(config.runs_dir(), unquote(u.path[len("/runs/"):]))
            self._send(404, b"not found", "text/plain")

        def do_POST(self):
            u = urlparse(self.path)
            if self.headers.get("X-Token") != app.token:
                return self._json(403, {"error": "forbidden"})
            if not u.path.startswith("/api/"):
                return self._json(404, {"error": "not found"})
            fn = getattr(app, "api_" + u.path[len("/api/"):], None)
            if fn is None:
                return self._json(404, {"error": "no such call"})
            try:
                n = int(self.headers.get("Content-Length") or 0)
                args = json.loads(self.rfile.read(n) or b"{}")
                self._json(200, fn(args))
            except Exception as e:  # noqa: BLE001 -- the page shows the message
                self._json(500, {"error": str(e)})

    return Handler


def serve(app: App, port: int = 0) -> ThreadingHTTPServer:
    httpd = ThreadingHTTPServer(("127.0.0.1", port), make_handler(app))
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    return httpd
