"""Suggest places: random areas of a chosen kind (city, coast, farmland ...) inside a region.

Candidates come from a list of world cities (Natural Earth populated places, public domain) for
urban kinds, or from random points for the others. Each candidate is kept only if its ESA WorldCover
land-cover mix, and for mountains its relief, fits the kind. A seed makes the picks repeatable.
"""
from __future__ import annotations

import csv
import math
import random
from dataclasses import dataclass

import numpy as np
import rasterio
from rasterio.windows import from_bounds

from . import config
from .aoi import Area
from .sources import raster

# WorldCover classes: 10 tree, 20 shrub, 30 grass, 40 crop, 50 built-up, 60 bare, 70 snow, 80 water,
# 90 wetland, 95 mangrove, 100 moss


@dataclass
class Kind:
    label: str
    from_cities: bool
    test: object            # fractions dict, relief m -> bool
    jitter_km: float = 0.0


KINDS = {
    "city": Kind("City centre", True, lambda f, r: f.get(50, 0) >= 0.5, jitter_km=3),
    "suburb": Kind("Suburb", True, lambda f, r: 0.2 <= f.get(50, 0) < 0.6, jitter_km=12),
    "coast": Kind("Coast or port", True, lambda f, r: 0.15 <= f.get(80, 0) <= 0.7 and f.get(50, 0) >= 0.1, jitter_km=8),
    "farmland": Kind("Farmland", False, lambda f, r: f.get(40, 0) >= 0.5),
    "forest": Kind("Forest", False, lambda f, r: f.get(10, 0) >= 0.6),
    "desert": Kind("Desert", False, lambda f, r: f.get(60, 0) >= 0.7),
    "mountain": Kind("Mountains", False, lambda f, r: r >= 300 and f.get(80, 0) < 0.2),
    "any": Kind("Anywhere on land", False, lambda f, r: f.get(80, 0) < 0.5 and sum(f.values()) > 0),
}

WORLD = (-180.0, -56.0, 180.0, 72.0)


def _cities(region) -> list[tuple]:
    w, s, e, n = region
    out = []
    with open(config.DATA_DIR / "cities.csv", newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            lat, lon = float(r["lat"]), float(r["lon"])
            if s <= lat <= n and w <= lon <= e:
                out.append((r["name"], r["country"], lat, lon))
    return out


def _random_point(rng: random.Random, region) -> tuple[float, float]:
    """Uniform on the sphere inside the region."""
    w, s, e, n = region
    z = rng.uniform(math.sin(math.radians(s)), math.sin(math.radians(n)))
    return math.degrees(math.asin(z)), rng.uniform(w, e)


def _fractions(area: Area, log) -> dict:
    b = (area.west, area.south, area.east, area.north)
    vals = []
    for p in raster.fetch("landcover", b, log=lambda *_: None):
        with rasterio.open(p) as src:
            win = from_bounds(*b, src.transform).round_offsets().round_lengths()
            a = src.read(1, window=win, boundless=True, fill_value=0)
            vals.append(a.ravel())
    if not vals:
        return {80: 1.0}                     # no tile: open sea
    v = np.concatenate(vals)
    u, c = np.unique(v, return_counts=True)
    return {int(k): float(n) / v.size for k, n in zip(u, c) if k != 0}


def _relief(area: Area) -> float:
    b = (area.west, area.south, area.east, area.north)
    vals = []
    for p in raster.fetch("dem", b, log=lambda *_: None):
        with rasterio.open(p) as src:
            win = from_bounds(*b, src.transform).round_offsets().round_lengths()
            vals.append(src.read(1, window=win, boundless=True, fill_value=0).ravel())
    if not vals:
        return 0.0
    v = np.concatenate(vals)
    return float(np.percentile(v, 95) - np.percentile(v, 5))


def suggest(kind: str, region=WORLD, n: int = 5, side_m: float = 500.0, seed: int = 1, max_tries: int = 60,
            log=print, should_stop=lambda: False) -> list[Area]:
    """Up to n areas of this kind inside region (west, south, east, north)."""
    k = KINDS[kind]
    rng = random.Random(f"{kind}|{seed}|{region}")
    cities = _cities(region) if k.from_cities else []
    if k.from_cities and not cities:
        log("No city in this region; trying random points instead.")
    found = []
    for attempt in range(max_tries * n):
        if len(found) >= n or should_stop():
            break
        if cities:
            name, country, lat, lon = cities[rng.randrange(len(cities))]
            ang, dist = rng.uniform(0, 2 * math.pi), k.jitter_km * math.sqrt(rng.random())
            lat += dist / 111.0 * math.cos(ang)
            lon += dist / (111.0 * max(0.2, math.cos(math.radians(lat)))) * math.sin(ang)
            label = f"{name}, {country}"
        else:
            lat, lon = _random_point(rng, region)
            label = f"{k.label} {abs(lat):.2f}{'N' if lat >= 0 else 'S'} {abs(lon):.2f}{'E' if lon >= 0 else 'W'}"
        area = Area.square(lat, lon, side_m, name=label, tags={"kind": kind})
        try:
            f = _fractions(area, log)
            r = _relief(area) if kind == "mountain" else 0.0
        except Exception as e:  # noqa: BLE001 -- a failed candidate is just skipped
            log(f"  candidate skipped ({e})")
            continue
        if k.test(f, r):
            found.append(area)
            log(f"  found {len(found)}/{n}: {label}")
    if len(found) < n:
        log(f"Found {len(found)} of {n} after {max_tries * n} tries; try a larger region or another kind.")
    return found
