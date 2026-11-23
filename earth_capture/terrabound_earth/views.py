"""Where the radar looks from: the SAR views of a captured area.

A view is a ground window (a square of side window_m on the terrain), the compass bearing of the
radar as seen from the scene (0 = the radar is north of the scene, 90 = east), and the incidence
angle from the vertical. The pipeline aims each view at height 0 of the scene (its lowest point);
on raised ground that would move the window sideways by height x tan(incidence), so the aim point
is shifted to put the window on the chosen ground point.

Views come out in the schema of the pipeline's views file (see sar_pipeline/Scripts/Earth/
Run_Earth_Views.m and Make_SAR_From_Blender.m), plus the ground point and footprint in degrees.
"""
from __future__ import annotations

import json
import math
import random
from dataclasses import asdict, dataclass, field

import numpy as np

from .aoi import Area
from .scene import Terrain, scene_paths

C = 299792458.0


def pixel_m(bandwidth_mhz: float) -> float:
    """Image pixel size: half the range resolution c / 2B."""
    return C / (2.0 * bandwidth_mhz * 1e6) / 2.0


def resolution_m(bandwidth_mhz: float) -> float:
    return C / (2.0 * bandwidth_mhz * 1e6)


@dataclass
class ViewSettings:
    bandwidth_mhz: float = 500.0                         # 0.30 m resolution
    factors: list = field(default_factory=lambda: [2, 4, 8])
    mode: str = "random"                                 # "random" or "grid"
    n_views: int = 12                                    # random mode: views per area
    bearings: list = field(default_factory=lambda: [0, 90, 180, 270])   # grid mode
    incidence_range: list = field(default_factory=lambda: [30, 60])
    incidences: list | None = None                       # grid mode: fixed list instead of the range
    window_m: float = 150.0                              # side of the ground window
    structure_bias: float = 0.7                          # random mode: share of views centred on buildings
    seed: int = 1
    max_px: int = 2000                                   # the pipeline leaves out larger images

    def to_dict(self) -> dict:
        return asdict(self)

    @classmethod
    def from_dict(cls, d: dict | None) -> "ViewSettings":
        known = cls().__dict__
        return cls(**{k: v for k, v in (d or {}).items() if k in known})

    def largest_window(self) -> float:
        """The widest window whose image stays under max_px (with 5 % to spare)."""
        return 0.95 * self.max_px * pixel_m(self.bandwidth_mhz)

    def problems(self) -> list[str]:
        out = []
        if not 10 <= self.bandwidth_mhz <= 5000:
            out.append("Bandwidth must be between 10 and 5000 MHz.")
        lo, hi = self.incidence_range
        if not (10 <= lo <= hi <= 85):
            out.append("Incidence angles must be between 10 and 85 degrees.")
        if self.window_m > self.largest_window():
            out.append(f"A {self.window_m:.0f} m window at {resolution_m(self.bandwidth_mhz):.2f} m resolution "
                       f"is more than {self.max_px} px across; the largest is {self.largest_window():.0f} m.")
        if self.window_m < 10:
            out.append("The window must be at least 10 m.")
        if any(f < 2 for f in self.factors):
            out.append("Every lower-resolution factor must be 2 or more.")
        return out


def footprint(frame, x, y, side, bearing_deg) -> list[list[float]]:
    """Corners [lon, lat] of a square ground window centred on local (x east, y north)."""
    b = math.radians(bearing_deg)
    toward = np.array([math.sin(b), math.cos(b)])          # from the scene to the radar, (east, north)
    across = np.array([math.cos(b), -math.sin(b)])
    h = side / 2.0
    pts = [np.array([x, y]) + sa * h * across + st * h * toward for sa, st in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    lon, lat = frame.to_geo([p[0] for p in pts], [p[1] for p in pts])
    ring = [[float(a), float(b_)] for a, b_ in zip(lon, lat)]
    return ring + [ring[0]]


def make_view(terrain: Terrain, name: str, x: float, y: float, bearing: float, incidence: float, side: float) -> dict:
    """One view on ground point (x east, y north), in the views-file schema plus where it is."""
    hc = float(terrain.scene_y(x, y))
    b, i = math.radians(bearing), math.radians(incidence)
    shift = hc * math.tan(i)
    obj_x, obj_z = x, -y                                   # the scene's axes: z is south
    lon, lat = terrain.grid.frame.to_geo(x, y)
    return {
        "name": name,
        "bearing_deg": round(float(bearing) % 360, 4),
        "incidence_deg": round(float(incidence), 4),
        "center_x": round(obj_x - shift * math.sin(b), 3),
        "center_z": round(obj_z + shift * math.cos(b), 3),
        "width_m": round(side, 3),
        "height_m": round(side * math.cos(i), 3),          # the camera's height covers `side` of ground
        "ground": {"x": round(x, 3), "y": round(y, 3), "scene_y": round(hc, 3),
                   "lon": round(float(lon), 7), "lat": round(float(lat), 7)},
        "footprint": footprint(terrain.grid.frame, x, y, side, bearing),
    }


def plan(area: Area, settings: ViewSettings) -> list[dict]:
    """The views of an area, from its built scene."""
    issues = settings.problems()
    if issues:
        raise ValueError(" ".join(issues))
    t = Terrain(area)
    al = t.meta["area_local"]
    side = float(settings.window_m)
    rng = random.Random(settings.seed)
    lo_i, hi_i = settings.incidence_range

    # Window centres: far enough in that the window stays on the area (when the area is big enough)
    half = side / 2.0
    xs = (al["xmin"] + half, al["xmax"] - half)
    ys = (al["ymin"] + half, al["ymax"] - half)
    if xs[0] > xs[1]:
        xs = ((al["xmin"] + al["xmax"]) / 2,) * 2
    if ys[0] > ys[1]:
        ys = ((al["ymin"] + al["ymax"]) / 2,) * 2

    views = []
    if settings.mode == "grid":
        nx = _tiles(al["xmax"] - al["xmin"], side)
        ny = _tiles(al["ymax"] - al["ymin"], side)
        cx = np.linspace(xs[0], xs[1], nx) if nx > 1 else [sum(xs) / 2]
        cy = np.linspace(ys[1], ys[0], ny) if ny > 1 else [sum(ys) / 2]
        incs = settings.incidences or [None]
        k = 0
        for inc in incs:
            for bearing in settings.bearings:
                for y in cy:
                    for x in cx:
                        k += 1
                        i = inc if inc is not None else rng.uniform(lo_i, hi_i)
                        views.append(make_view(t, f"g{k:03d}", float(x), float(y), bearing, round(i, 1), side))
        return views

    # Random: centres on buildings most of the time (they are what SAR images are about), else anywhere
    centres = _building_centres(area, t)
    for k in range(1, settings.n_views + 1):
        if centres and rng.random() < settings.structure_bias:
            x, y = centres[rng.randrange(len(centres))]
            x += rng.uniform(-side / 4, side / 4)
            y += rng.uniform(-side / 4, side / 4)
            x = min(max(x, xs[0]), xs[1])
            y = min(max(y, ys[0]), ys[1])
        else:
            x, y = rng.uniform(*xs), rng.uniform(*ys)
        bearing = round(rng.uniform(0, 360), 1)
        inc = round(rng.uniform(lo_i, hi_i), 1)
        views.append(make_view(t, f"r{k:03d}", x, y, bearing, inc, side))
    return views


def _tiles(length: float, side: float) -> int:
    """Windows needed to cover a length (a 240 m side is three 80 m windows, not four)."""
    return max(1, math.ceil(length / side - 1e-3))


def _building_centres(area: Area, t: Terrain) -> list[tuple[float, float]]:
    p = scene_paths(area)["preview"] / "buildings.geojson"
    if not p.exists():
        return []
    from shapely.geometry import shape
    fc = json.loads(p.read_text(encoding="utf-8"))
    out = []
    for f in fc["features"]:
        c = shape(f["geometry"]).centroid
        x, y = t.grid.frame.to_local(c.x, c.y)
        out.append((float(x), float(y)))
    return out


def estimate(area: Area, scene_meta: dict | None, settings: ViewSettings) -> dict:
    """How many views and how big their images, for the summary before a run."""
    if settings.mode == "grid":
        w, h = area.size_m
        n = (_tiles(w, settings.window_m) * _tiles(h, settings.window_m)
             * len(settings.bearings) * len(settings.incidences or [None]))
    else:
        n = settings.n_views
    px = settings.window_m / pixel_m(settings.bandwidth_mhz)
    return {"views": int(n), "image_px": int(round(px)), "resolution_m": round(resolution_m(settings.bandwidth_mhz), 3),
            "lr_resolution_m": [round(resolution_m(settings.bandwidth_mhz) * f, 3) for f in settings.factors]}
