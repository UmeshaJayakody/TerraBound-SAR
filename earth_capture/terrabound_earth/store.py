"""The queue of areas and the settings, kept in the runs folder so they survive a restart.

    runs/queue.json       the areas, in order, with where each one is
    runs/settings.json    scene and radar settings
    runs/locations.geojson  the same areas as map features (open them in any GIS)
"""
from __future__ import annotations

import datetime as dt
import json
import threading

from . import config
from .aoi import Area
from .scene import SceneSettings
from .views import ViewSettings

STATUSES = {
    "queued": "Waiting",
    "downloading": "Downloading data",
    "ready": "Scene ready",
    "waiting": "Data unavailable, retry later",
    "running": "Making SAR images",
    "done": "Done",
    "partial": "Some views failed",
    "stopped": "Stopped",
    "failed": "Failed",
}


def _now() -> str:
    return dt.datetime.now().isoformat(timespec="seconds")


class Store:
    def __init__(self):
        self.lock = threading.RLock()
        self.qfile = config.runs_dir() / "queue.json"
        self.sfile = config.runs_dir() / "settings.json"
        self.items: list[dict] = []
        self.scene = SceneSettings()
        self.views = ViewSettings()
        self.load()

    # ---- persistence ----------------------------------------------------------------------------
    def load(self):
        with self.lock:
            if self.qfile.exists():
                self.items = json.loads(self.qfile.read_text(encoding="utf-8")).get("items", [])
                for it in self.items:          # anything mid-way when the app closed is waiting again
                    if it["status"] in ("downloading", "running"):
                        it["status"] = "queued"
            if self.sfile.exists():
                s = json.loads(self.sfile.read_text(encoding="utf-8"))
                self.scene = SceneSettings.from_dict(s.get("scene"))
                self.views = ViewSettings.from_dict(s.get("views"))

    def save(self):
        with self.lock:
            self.qfile.write_text(json.dumps({"items": self.items}, indent=1), encoding="utf-8")
            fc = {"type": "FeatureCollection",
                  "features": [Area.from_dict(it["area"]).to_feature() | {"id": it["id"]} for it in self.items]}
            (config.runs_dir() / "locations.geojson").write_text(json.dumps(fc, indent=1), encoding="utf-8")

    def save_settings(self, scene: dict | None, views: dict | None) -> list[str]:
        sc = SceneSettings.from_dict({**self.scene.to_dict(), **(scene or {})})
        vs = ViewSettings.from_dict({**self.views.to_dict(), **(views or {})})
        problems = vs.problems()
        if not 1.0 <= sc.grid_m <= 30.0:
            problems.append("The ground grid must be between 1 and 30 m.")
        if problems:
            return problems
        with self.lock:
            self.scene, self.views = sc, vs
            self.sfile.write_text(json.dumps({"scene": sc.to_dict(), "views": vs.to_dict()}, indent=1),
                                  encoding="utf-8")
        return []

    # ---- the queue ------------------------------------------------------------------------------
    def add(self, area: Area) -> tuple[dict, bool]:
        """Adds an area (or returns the one already there with the same rectangle)."""
        with self.lock:
            for it in self.items:
                if it["id"] == area.id:
                    return it, False
            it = {"id": area.id, "area": area.to_dict(), "status": "queued", "message": "",
                  "views_done": 0, "views_total": 0, "added": _now(), "updated": _now()}
            self.items.append(it)
            self.save()
            return it, True

    def get(self, item_id: str) -> dict | None:
        with self.lock:
            return next((it for it in self.items if it["id"] == item_id), None)

    def update(self, item_id: str, **fields):
        with self.lock:
            it = self.get(item_id)
            if it is not None:
                it.update(fields, updated=_now())
                self.save()

    def remove(self, item_id: str):
        with self.lock:
            self.items = [it for it in self.items if it["id"] != item_id]
            self.save()

    def rename(self, item_id: str, name: str):
        """Changes the label shown in the app only; the area's folder keeps its name."""
        with self.lock:
            it = self.get(item_id)
            if it is not None:
                it["label"] = name.strip()
                self.save()

    def area(self, item_id: str) -> Area:
        it = self.get(item_id)
        if it is None:
            raise KeyError(item_id)
        a = Area.from_dict(it["area"])
        return a

    def snapshot(self) -> list[dict]:
        with self.lock:
            return [dict(it, status_text=STATUSES.get(it["status"], it["status"])) for it in self.items]
