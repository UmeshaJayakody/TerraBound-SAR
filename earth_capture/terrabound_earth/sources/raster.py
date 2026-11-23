"""Elevation (Copernicus GLO-30) and land cover (ESA WorldCover) for an area, on its local grid.

Both are read straight from cloud-optimised GeoTIFFs: only the small window around the area is
downloaded, never the whole tile. They come from the AWS Open Data registry (no account needed);
if that cannot be reached, the same files are read from Microsoft Planetary Computer (no account
needed either). Each window is cached, so an area is downloaded once. A local GeoTIFF can be used
instead of the downloaded elevation (see elevation_on_grid).
"""
from __future__ import annotations

import math
from pathlib import Path

import numpy as np
import rasterio
from rasterio.enums import Resampling
from rasterio.warp import reproject
from rasterio.windows import from_bounds

from ..grid import Grid
from .http import SourceError, cache_path, get_json, url_status

GDAL_ENV = dict(GDAL_DISABLE_READDIR_ON_OPEN="EMPTY_DIR", CPL_VSIL_CURL_ALLOWED_EXTENSIONS=".tif",
                GDAL_HTTP_MAX_RETRY="4", GDAL_HTTP_RETRY_DELAY="2", VSI_CACHE="TRUE")

PC_STAC = "https://planetarycomputer.microsoft.com/api/stac/v1/search"
PC_TOKEN = "https://planetarycomputer.microsoft.com/api/sas/v1/token/{collection}"

DATASETS = {
    "dem": {
        "label": "Copernicus DEM GLO-30",
        "aws": "https://copernicus-dem-30m.s3.amazonaws.com/{name}/{name}.tif",
        "pc_collection": "cop-dem-glo-30", "pc_asset": "data", "pc_match": "",
        "step": 1,
    },
    "landcover": {
        "label": "ESA WorldCover 10 m 2021 v200",
        "aws": "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_{name}_Map.tif",
        "pc_collection": "esa-worldcover", "pc_asset": "map", "pc_match": "2021_v200",
        "step": 3,
    },
}


def _tile_names(kind: str, bounds) -> list[str]:
    """The names of the tiles covering bounds (west, south, east, north)."""
    step = DATASETS[kind]["step"]
    w, s, e, n = bounds
    names = []
    for lat in range(math.floor(s / step) * step, math.floor(n / step) * step + 1, step):
        for lon in range(math.floor(w / step) * step, math.floor(e / step) * step + 1, step):
            ns, ew = ("N" if lat >= 0 else "S"), ("E" if lon >= 0 else "W")
            if kind == "dem":
                names.append(f"Copernicus_DSM_COG_10_{ns}{abs(lat):02d}_00_{ew}{abs(lon):03d}_00_DEM")
            else:
                names.append(f"{ns}{abs(lat):02d}{ew}{abs(lon):03d}")
    return names


def _round_out(bounds, q: float = 0.01):
    """Bounds rounded outwards to a 0.01 degree grid, so nearby areas share cached windows."""
    w, s, e, n = bounds
    return (math.floor(w / q) * q, math.floor(s / q) * q, math.ceil(e / q) * q, math.ceil(n / q) * q)


def _fetch_window(url: str, bounds, cache_key: str) -> Path | None:
    """The part of a remote GeoTIFF inside bounds, saved in the cache. None if it has no overlap."""
    path = cache_path("raster", cache_key, ".tif")
    if path.exists():
        return path
    with rasterio.Env(**GDAL_ENV):
        with rasterio.open(url) as src:
            b = src.bounds
            w, s, e, n = max(bounds[0], b.left), max(bounds[1], b.bottom), min(bounds[2], b.right), min(bounds[3], b.top)
            if w >= e or s >= n:
                return None
            win = from_bounds(w, s, e, n, src.transform).round_offsets().round_lengths()
            data = src.read(1, window=win)
            prof = dict(driver="GTiff", height=data.shape[0], width=data.shape[1], count=1, dtype=data.dtype,
                        crs=src.crs, transform=src.window_transform(win), nodata=src.nodata, compress="deflate")
    tmp = path.with_suffix(".part.tif")
    with rasterio.open(tmp, "w", **prof) as dst:
        dst.write(data, 1)
    tmp.replace(path)
    return path


def _from_aws(kind: str, bounds, log) -> list[Path]:
    ds = DATASETS[kind]
    out = []
    for name in _tile_names(kind, bounds):
        url = ds["aws"].format(name=name)
        key = f"{kind}|{name}|{bounds}"
        cached = cache_path("raster", key, ".tif")
        if cached.exists():
            out.append(cached)
            continue
        status = url_status(url)
        if status == 404 or status == 403:
            continue                      # no tile there: open sea
        if status != 200:
            raise SourceError(f"{ds['label']}: AWS answered {status or 'nothing'} for {name}")
        log(f"  downloading {ds['label']} ({name}) ...")
        p = _fetch_window(url, bounds, key)
        if p is not None:
            out.append(p)
    return out


def _from_planetary_computer(kind: str, bounds, log) -> list[Path]:
    ds = DATASETS[kind]
    from .http import session
    r = session().post(PC_STAC, json={"collections": [ds["pc_collection"]], "bbox": list(bounds), "limit": 20}, timeout=60)
    r.raise_for_status()
    items = [f for f in r.json().get("features", []) if ds["pc_match"] in f["id"]]
    if not items:
        return []
    token = get_json(PC_TOKEN.format(collection=ds["pc_collection"]))["token"]
    out = []
    for it in items:
        href = it["assets"][ds["pc_asset"]]["href"]
        log(f"  downloading {ds['label']} ({it['id']}) from Planetary Computer ...")
        p = _fetch_window(f"{href}?{token}", bounds, f"{kind}|{it['id']}|{bounds}")
        if p is not None:
            out.append(p)
    return out


def fetch(kind: str, bounds, log=print) -> list[Path]:
    """Cached GeoTIFF windows of a dataset covering bounds. An empty list means open sea."""
    bounds = _round_out(bounds)
    try:
        return _from_aws(kind, bounds, log)
    except Exception as e:  # noqa: BLE001 -- any failure of the first mirror means: try the second
        log(f"  AWS Open Data did not work ({e}); using Microsoft Planetary Computer instead")
        try:
            return _from_planetary_computer(kind, bounds, log)
        except Exception as e2:  # noqa: BLE001
            raise SourceError(f"Could not download {DATASETS[kind]['label']}: {e2}") from e2


def to_grid(paths: list[Path], grid: Grid, on: str, resampling: Resampling) -> np.ndarray:
    """Reprojects GeoTIFFs onto the grid's nodes (on='node') or cells (on='cell'). NaN where none covers."""
    shape = grid.node_shape if on == "node" else grid.cell_shape
    transform = grid.node_transform if on == "node" else grid.cell_transform
    dst = np.full(shape, np.nan, dtype=np.float32)
    for p in paths:
        with rasterio.open(p) as src:
            src_data = src.read(1).astype(np.float32)
            nodata = src.nodata
            if nodata is not None:
                src_data[src_data == nodata] = np.nan
            layer = np.full(shape, np.nan, dtype=np.float32)
            reproject(source=src_data, destination=layer, src_transform=src.transform, src_crs=src.crs,
                      src_nodata=np.nan, dst_transform=transform, dst_crs=grid.frame.crs, dst_nodata=np.nan,
                      resampling=resampling)
            dst = np.where(np.isnan(dst), layer, dst)
    return dst


def elevation_on_grid(grid: Grid, log=print, local_files: list[str] | None = None) -> tuple[np.ndarray, dict]:
    """Height above sea level (m) at every node. Open sea, where there is no tile, is 0 m."""
    bounds = grid.geo_bounds(pad_m=200)
    if local_files:
        paths = [Path(p) for p in local_files]
        info = {"name": "Local elevation file", "files": [str(p) for p in paths]}
    else:
        paths = fetch("dem", bounds, log)
        info = dict(DEM_SOURCE)
    h = to_grid(paths, grid, "node", Resampling.cubic)
    missing = float(np.isnan(h).mean())
    h = np.nan_to_num(h, nan=0.0)
    info["missing_fraction"] = round(missing, 4)
    return h, info


def landcover_on_grid(grid: Grid, log=print) -> tuple[np.ndarray, dict]:
    """ESA WorldCover class of every cell (10 tree cover ... 100 moss and lichen; 0 where unknown)."""
    bounds = grid.geo_bounds(pad_m=100)
    paths = fetch("landcover", bounds, log)
    c = to_grid(paths, grid, "cell", Resampling.mode)
    info = dict(LANDCOVER_SOURCE)
    info["missing_fraction"] = round(float(np.isnan(c).mean()), 4)
    return np.nan_to_num(c, nan=0).astype(np.uint8), info


DEM_SOURCE = {
    "name": "Copernicus DEM GLO-30",
    "url": "https://registry.opendata.aws/copernicus-dem/",
    "licence": "Copernicus DEM licence (free use, reproduction and distribution with attribution)",
    "attribution": ("produced using Copernicus WorldDEM-30 (c) DLR e.V. 2010-2014 and (c) Airbus Defence and "
                    "Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved"),
    "note": "A surface model (tops of buildings and trees), 30 m grid; heights above the EGM2008 geoid.",
}

LANDCOVER_SOURCE = {
    "name": "ESA WorldCover 10 m 2021 v200",
    "url": "https://esa-worldcover.org/",
    "licence": "CC BY 4.0",
    "attribution": ("(c) ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) "
                    "processed by ESA WorldCover consortium"),
    "doi": "10.5281/zenodo.7254221",
}
