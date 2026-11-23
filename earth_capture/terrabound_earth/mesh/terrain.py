"""The ground: a triangle mesh over the grid, two triangles per cell."""
from __future__ import annotations

import numpy as np


def _min_filter(a: np.ndarray, k: int) -> np.ndarray:
    """Minimum over a k x k window (k odd), done separably; edges repeat."""
    r = k // 2
    p = np.pad(a, ((0, 0), (r, r)), mode="edge")
    m = np.lib.stride_tricks.sliding_window_view(p, k, axis=1).min(axis=-1)
    p = np.pad(m, ((r, r), (0, 0)), mode="edge")
    return np.lib.stride_tricks.sliding_window_view(p, k, axis=0).min(axis=-1)


def _max_filter(a: np.ndarray, k: int) -> np.ndarray:
    return -_min_filter(-a, k)


def _box_mean(a: np.ndarray, k: int) -> np.ndarray:
    """Mean over a k x k window (k odd), edges repeated."""
    r = k // 2
    p = np.pad(a, r, mode="edge").astype(np.float64)
    c = np.cumsum(np.cumsum(np.pad(p, ((1, 0), (1, 0))), axis=0), axis=1)
    s = c[k:, k:] - c[:-k, k:] - c[k:, :-k] + c[:-k, :-k]
    return (s / (k * k)).astype(a.dtype)


def ground_from_surface(surface: np.ndarray, built: np.ndarray, spacing: float, window_m: float = 150.0,
                        smooth_m: float = 40.0) -> np.ndarray:
    """Bare ground where the elevation is a surface model that includes buildings.

    The Copernicus DEM gives the height of the top of whatever is there, so a city's buildings are
    already in it, smeared over its 30 m cells. Extruding the OpenStreetMap buildings on top of that
    would count them twice. Inside built areas (built: True), the ground is taken as a grey-scale
    opening of the surface: the lowest height within window_m, then the highest of those, which
    removes bumps narrower than the window and keeps the slope of the land. In a dense city the
    buildings cover most of every 60 m, so the window has to be wider than a city block (150 m by
    default); terrain features smaller than that under a city are flattened. The result is then
    smoothed over smooth_m, and blended into the untouched surface at the edge of the built area,
    so no step appears there.
    """
    if not built.any():
        return surface.copy()
    k = max(3, int(round(window_m / spacing)) | 1)
    opened = np.minimum(surface, _max_filter(_min_filter(surface, k), k))
    ks = max(3, int(round(smooth_m / spacing)) | 1)
    opened = np.minimum(surface, _box_mean(opened, ks))
    weight = _box_mean(built.astype(np.float32), ks)       # 1 inside built areas, fading to 0 outside
    weight = np.clip(weight * 2.0, 0.0, 1.0)
    return surface - weight * (surface - opened)


def mesh(up: np.ndarray, x: np.ndarray, y: np.ndarray, cell_material: np.ndarray):
    """Vertices (local east, north, up) and triangles of the ground.

    up, x, y: node grids (row 0 north). cell_material: material of each cell. Returns
    (vertices n x 3, faces m x 3 with 0-based indices, face_material m), each triangle facing up.
    """
    ny, nx = up.shape
    verts = np.column_stack([x.ravel(), y.ravel(), up.ravel()])
    idx = np.arange(ny * nx).reshape(ny, nx)
    a = idx[:-1, :-1].ravel()      # north-west corner of each cell
    b = idx[:-1, 1:].ravel()       # north-east
    c = idx[1:, :-1].ravel()       # south-west
    d = idx[1:, 1:].ravel()        # south-east
    # Counter-clockwise seen from above (x east, y north): sw -> se -> ne, sw -> ne -> nw
    t1 = np.column_stack([c, d, b])
    t2 = np.column_stack([c, b, a])
    faces = np.vstack([t1, t2])
    mats = np.concatenate([cell_material.ravel(), cell_material.ravel()])
    return verts, faces, mats
