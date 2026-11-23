"""Runs the MATLAB SAR pipeline on a captured area and follows its progress.

The app writes a job file (the scene, the views, the radar settings) and starts
    matlab -batch "addpath('.../sar_pipeline/Scripts/Earth'); Run_Earth_Views('job.json')"
MATLAB appends one JSON line per event to progress.jsonl (start, progress, view, done, error), which
is read while it runs. Stopping writes a stop file; MATLAB finishes the view it is on and stops.

    runs/<area id>/sar/job.json         what MATLAB was asked to do
    runs/<area id>/sar/progress.jsonl   what it has done so far
    runs/<area id>/sar/result.json      the views it made
    runs/<area id>/sar/matlab.log       everything MATLAB printed
    runs/<area id>/sar/<area_id>/views/ the images (HR.png, LR_*.png, sar_images.mat, view_info.mat); the
                                        folder name has the dots of the id replaced by _ (see matlab_name)
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import time
from pathlib import Path

from . import config
from .aoi import Area
from .scene import scene_paths, run_dir
from .views import ViewSettings


class MatlabNotFound(RuntimeError):
    pass


def matlab_name(name: str) -> str:
    """The folder name Make_Multi_Angle_Dataset gives a scene: anything but letters, digits, _ and - becomes _."""
    return re.sub(r"[^A-Za-z0-9_-]+", "_", name)


def sar_paths(area: Area) -> dict:
    d = run_dir(area) / "sar"
    return {"dir": d, "job": d / "job.json", "progress": d / "progress.jsonl", "result": d / "result.json",
            "stop": d / "STOP", "log": d / "matlab.log", "views": d / "views.json",
            "root": d / matlab_name(area.id)}


def _m(path: Path) -> str:
    """A path as a MATLAB string literal."""
    return "'" + str(path).replace("\\", "/").replace("'", "''") + "'"


class MatlabRun:
    def __init__(self, area: Area, views: list[dict], vs: ViewSettings, keep_files: bool = False):
        self.area = area
        self.views = views
        self.vs = vs
        self.keep_files = keep_files
        self.p = sar_paths(area)
        self.proc: subprocess.Popen | None = None
        self._read = 0
        self.events: list[dict] = []

    def write_job(self) -> Path:
        self.p["dir"].mkdir(parents=True, exist_ok=True)
        for k in ("progress", "result", "stop"):
            if self.p[k].exists():
                self.p[k].unlink()
        job = {
            "format": 1,
            "obj": str(scene_paths(self.area)["obj"]),
            "out_folder": str(self.p["dir"]),
            "bandwidth_mhz": self.vs.bandwidth_mhz,
            "factors": list(self.vs.factors),
            "materials": "auto",
            "seed": self.vs.seed,
            "keep_files": self.keep_files,
            "progress_file": str(self.p["progress"]),
            "result_file": str(self.p["result"]),
            "stop_file": str(self.p["stop"]),
            "views": self.views,
        }
        self.p["job"].write_text(json.dumps(job, indent=1), encoding="utf-8")
        self.p["views"].write_text(json.dumps({"area": self.area.to_dict(), "settings": self.vs.to_dict(),
                                               "views": self.views}, indent=1), encoding="utf-8")
        return self.p["job"]

    def start(self, matlab: str | None = None) -> None:
        exe = matlab or config.find_matlab()
        if not exe:
            raise MatlabNotFound("MATLAB was not found. Install it, or set TERRABOUND_MATLAB to matlab.exe.")
        job = self.write_job()
        cmd = f"addpath({_m(config.EARTH_MATLAB)}); Run_Earth_Views({_m(job)})"
        log = open(self.p["log"], "w", encoding="utf-8", errors="replace")
        flags = subprocess.CREATE_NO_WINDOW if os.name == "nt" else 0
        self.proc = subprocess.Popen([exe, "-batch", cmd], cwd=str(config.WORKSPACE), stdout=log,
                                     stderr=subprocess.STDOUT, creationflags=flags)

    def poll(self) -> list[dict]:
        """New progress events since the last call."""
        f = self.p["progress"]
        if not f.exists():
            return []
        with open(f, "r", encoding="utf-8", errors="replace") as h:
            h.seek(self._read)
            text = h.read()
            # only whole lines: MATLAB may be in the middle of writing the last one
            cut = text.rfind("\n") + 1
            self._read += len(text[:cut].encode("utf-8"))
        new = []
        for line in text[:cut].splitlines():
            try:
                new.append(json.loads(line))
            except json.JSONDecodeError:
                pass
        self.events += new
        return new

    @property
    def running(self) -> bool:
        return self.proc is not None and self.proc.poll() is None

    def stop(self) -> None:
        self.p["stop"].parent.mkdir(parents=True, exist_ok=True)
        self.p["stop"].write_text("stop", encoding="utf-8")

    def result(self) -> dict | None:
        r = self.p["result"]
        return json.loads(r.read_text(encoding="utf-8")) if r.exists() else None

    def wait(self, on_event=None, should_stop=None, interval: float = 1.0) -> dict:
        while self.running:
            for e in self.poll():
                if on_event:
                    on_event(e)
            if should_stop and should_stop():
                self.stop()
            time.sleep(interval)
        for e in self.poll():
            if on_event:
                on_event(e)
        res = self.result() or {"ok": False, "error": f"MATLAB ended without a result (exit code "
                                                     f"{self.proc.returncode if self.proc else '?'}); see {self.p['log']}"}
        if self.p["stop"].exists():
            self.p["stop"].unlink()
        return res
