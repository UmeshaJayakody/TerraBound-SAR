"""Shared fixtures. Every test runs offline, in its own runs and cache folders."""
from __future__ import annotations

import json
import sys
from pathlib import Path

import numpy as np
import pytest
import rasterio
from rasterio.transform import from_origin

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

LAT, LON = 6.9355, 79.8430


@pytest.fixture(autouse=True)
def isolated(tmp_path, monkeypatch):
    monkeypatch.setenv("EARTH_CAPTURE_RUNS", str(tmp_path / "runs"))
    monkeypatch.setenv("EARTH_CAPTURE_CACHE", str(tmp_path / "cache"))
    monkeypatch.setenv("EARTH_CAPTURE_DATASETS", str(tmp_path / "datasets"))
    yield tmp_path


def _write_tif(path: Path, data: np.ndarray, west: float, north: float, res: float, nodata=None):
    prof = dict(driver="GTiff", height=data.shape[0], width=data.shape[1], count=1, dtype=data.dtype,
                crs="EPSG:4326", transform=from_origin(west, north, res, res), nodata=nodata)
    with rasterio.open(path, "w", **prof) as dst:
        dst.write(data, 1)
    return path


def osm_fixture() -> dict:
    """Two buildings near the centre (one with a courtyard), a building split into parts, a pond, a road
    and a bridge."""
    def sq(cx, cy, half):
        d = half / 111000.0
        return [{"lat": cy - d, "lon": cx - d}, {"lat": cy - d, "lon": cx + d}, {"lat": cy + d, "lon": cx + d},
                {"lat": cy + d, "lon": cx - d}, {"lat": cy - d, "lon": cx - d}]
    return {"osm3s": {"timestamp_osm_base": "2026-11-23T00:00:00Z"}, "elements": [
        {"type": "way", "id": 1, "tags": {"building": "apartments", "height": "24 m"}, "geometry": sq(LON, LAT, 15)},
        {"type": "relation", "id": 2, "tags": {"building": "yes", "type": "multipolygon", "building:levels": "4"},
         "members": [{"type": "way", "role": "outer", "geometry": sq(LON + 0.0006, LAT, 20)},
                     {"type": "way", "role": "inner", "geometry": sq(LON + 0.0006, LAT, 8)}]},
        {"type": "way", "id": 3, "tags": {"building": "industrial"}, "geometry": sq(LON - 0.0008, LAT + 0.0005, 25)},
        {"type": "way", "id": 4, "tags": {"building:part": "yes", "height": "40"}, "geometry": sq(LON - 0.0008, LAT + 0.0005, 10)},
        {"type": "way", "id": 8, "tags": {"building": "warehouse"}, "geometry": sq(LON + 0.0008, LAT - 0.0004, 12)},
        {"type": "way", "id": 5, "tags": {"natural": "water"}, "geometry": sq(LON, LAT - 0.0008, 20)},
        {"type": "way", "id": 6, "tags": {"highway": "primary"},
         "geometry": [{"lat": LAT + 0.0009, "lon": LON - 0.001}, {"lat": LAT + 0.0009, "lon": LON + 0.001}]},
        {"type": "way", "id": 7, "tags": {"highway": "secondary", "bridge": "yes"},
         "geometry": [{"lat": LAT - 0.0009, "lon": LON - 0.001}, {"lat": LAT - 0.0009, "lon": LON + 0.001}]},
    ]}


@pytest.fixture
def offline_sources(tmp_path, monkeypatch):
    """Replaces the downloads with a gently sloping 30 m DEM, a land-cover map and the OSM fixture."""
    from terrabound_earth.sources import osm, raster
    d = tmp_path / "fixtures"
    d.mkdir()
    res = 1 / 3600.0
    n = 120
    yy, xx = np.mgrid[0:n, 0:n]
    dem = (5.0 + 0.02 * xx + 0.01 * yy).astype(np.float32)          # metres, a gentle slope
    dem[58:62, 58:62] += 20.0                                         # a 120 m city block in the surface model
    dem_tif = _write_tif(d / "dem.tif", dem, LON - n / 2 * res, LAT + n / 2 * res, res)
    lc = np.full((n * 3, n * 3), 50, np.uint8)                        # built-up
    lc[:, :170] = 10                                                  # trees from 100 m west of the centre
    lc_tif = _write_tif(d / "lc.tif", lc, LON - n / 2 * res, LAT + n / 2 * res, res / 3, nodata=0)
    monkeypatch.setattr(raster, "fetch", lambda kind, bounds, log=print: [dem_tif if kind == "dem" else lc_tif])
    monkeypatch.setattr(osm, "post_json_cached", lambda urls, data, kind, timeout=180, log=print: osm_fixture())
    return d


def read_obj(path: Path):
    v, f, groups, cur = [], [], {}, None
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if line.startswith("v "):
            v.append([float(x) for x in line.split()[1:4]])
        elif line.startswith("usemtl "):
            cur = line.split()[1]
        elif line.startswith("f "):
            f.append([int(x) for x in line.split()[1:4]])
            groups[cur] = groups.get(cur, 0) + 1
    return np.array(v), np.array(f), groups


def load_json(p):
    return json.loads(Path(p).read_text(encoding="utf-8"))
