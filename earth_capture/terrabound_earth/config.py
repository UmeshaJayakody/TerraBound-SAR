"""Where things are: the repository, the MATLAB workspace, the download cache, MATLAB and Blender.

Every location can be overridden with an environment variable, so the app also works from a copy of
the repository somewhere else, or with MATLAB and Blender installed in unusual places.
"""
from __future__ import annotations

import glob
import os
import shutil
import string
from pathlib import Path

PACKAGE_DIR = Path(__file__).resolve().parent
EARTH_DIR = PACKAGE_DIR.parent                      # earth_capture/
REPO_ROOT = EARTH_DIR.parent
WORKSPACE = REPO_ROOT / "sar_pipeline"
SCRIPTS = WORKSPACE / "Scripts"
EARTH_MATLAB = SCRIPTS / "Earth"
BLENDER_ADDON = WORKSPACE / "Blender"
WEB_DIR = PACKAGE_DIR / "web"
DATA_DIR = PACKAGE_DIR / "data"

# Sent with every request to the open-data services, as their usage policies ask. Generic on purpose;
# set EARTH_CAPTURE_USER_AGENT to identify your own installation.
USER_AGENT = os.environ.get("EARTH_CAPTURE_USER_AGENT", "earth-capture-sar/0.1 (python-requests)")


def cache_dir() -> Path:
    """Downloaded elevation, land cover and OpenStreetMap data, so each area is fetched once."""
    p = Path(os.environ.get("EARTH_CAPTURE_CACHE", EARTH_DIR / ".cache"))
    p.mkdir(parents=True, exist_ok=True)
    return p


def runs_dir() -> Path:
    """One folder per captured area: its scene, its views and its SAR images."""
    p = Path(os.environ.get("EARTH_CAPTURE_RUNS", REPO_ROOT / "runs"))
    p.mkdir(parents=True, exist_ok=True)
    return p


def datasets_dir() -> Path:
    p = Path(os.environ.get("EARTH_CAPTURE_DATASETS", REPO_ROOT / "datasets"))
    p.mkdir(parents=True, exist_ok=True)
    return p


def _drives() -> list[str]:
    return [f"{d}:/" for d in string.ascii_uppercase if os.path.exists(f"{d}:/")] if os.name == "nt" else ["/"]


def _newest(paths: list[str]) -> str | None:
    paths = [p for p in paths if os.path.isfile(p)]
    return max(paths, key=os.path.getmtime) if paths else None


def find_matlab() -> str | None:
    """MATLAB's launcher: TERRABOUND_MATLAB, then the PATH, then the usual install folders."""
    env = os.environ.get("TERRABOUND_MATLAB")
    if env and os.path.isfile(env):
        return env
    found = shutil.which("matlab")
    if found:
        return found
    cands = []
    for d in _drives():
        cands += glob.glob(os.path.join(d, "Program Files", "MATLAB", "R*", "bin", "matlab.exe"))
        cands += glob.glob(os.path.join(d, "Apps", "*", "bin", "matlab.exe"))
        cands += glob.glob(os.path.join(d, "MATLAB", "R*", "bin", "matlab.exe"))
    return _newest(cands)


def find_blender() -> str | None:
    """blender.exe: BLENDER_PATH, then the PATH, then the usual install folders."""
    env = os.environ.get("BLENDER_PATH")
    if env and os.path.isfile(env):
        return env
    found = shutil.which("blender")
    if found:
        return found
    cands = []
    for d in _drives():
        cands += glob.glob(os.path.join(d, "Program Files", "Blender Foundation", "*", "blender.exe"))
        cands += glob.glob(os.path.join(d, "Apps", "Blender*", "blender.exe"))
        cands += glob.glob(os.path.join(d, "Blender*", "blender.exe"))
    local = os.environ.get("LOCALAPPDATA")
    if local:
        cands += glob.glob(os.path.join(local, "Programs", "Blender Foundation", "*", "blender.exe"))
    return _newest(cands)
