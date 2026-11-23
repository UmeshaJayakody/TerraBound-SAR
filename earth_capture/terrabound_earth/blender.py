"""Opens a captured area in Blender with the SAR View Picker add-on (sar_pipeline/Blender), to place
extra views by hand. Does what sar_pipeline/Scripts/Launch_Blender.m does, without starting MATLAB.

Views captured in Blender are written to runs/<area id>/blender/blender_scene/ and are included in
the dataset export like the app's own views.
"""
from __future__ import annotations

import json
import subprocess

from . import config
from .aoi import Area
from .scene import run_dir, scene_paths
from .views import ViewSettings


def open_in_blender(area: Area, vs: ViewSettings) -> str:
    exe = config.find_blender()
    if not exe:
        raise FileNotFoundError("Blender was not found. Install it, or set BLENDER_PATH to blender.exe.")
    obj = scene_paths(area)["obj"]
    if not obj.exists():
        raise FileNotFoundError("Build the scene first (Prepare).")
    handoff = run_dir(area) / "blender"
    handoff.mkdir(parents=True, exist_ok=True)
    fwd = lambda p: str(p).replace("\\", "/")  # noqa: E731
    cfg = {
        "addon_dir": fwd(config.BLENDER_ADDON), "obj": fwd(obj), "up": "y", "workspace": fwd(config.WORKSPACE),
        "matlab": fwd(config.find_matlab() or "matlab"), "out_dir": fwd(handoff),
        "bandwidth_mhz": vs.bandwidth_mhz, "factors": list(vs.factors), "scale": 1, "materials": "auto",
    }
    cfg_path = handoff / "blender_setup.json"
    cfg_path.write_text(json.dumps(cfg, indent=2), encoding="utf-8")
    subprocess.Popen([exe, "--python", str(config.BLENDER_ADDON / "sar_blender_startup.py"), "--", str(cfg_path)],
                     cwd=str(handoff))
    return str(handoff)
