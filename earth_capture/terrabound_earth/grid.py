"""The regular grid a scene's terrain is sampled on, in the area's local frame.

Heights live on the grid's nodes (the corners of the terrain triangles); land cover and materials
live on its cells (the squares between nodes). Row 0 is the northern edge, as in an image.
"""
from __future__ import annotations

import math
from dataclasses import dataclass

import numpy as np
from affine import Affine

from .aoi import Area
from .geo import LocalFrame


@dataclass
class Grid:
    frame: LocalFrame
    xmin: float
    ymax: float
    spacing: float
    nx: int            # nodes east-west
    ny: int            # nodes north-south

    @property
    def xmax(self) -> float:
        return self.xmin + (self.nx - 1) * self.spacing

    @property
    def ymin(self) -> float:
        return self.ymax - (self.ny - 1) * self.spacing

    @property
    def node_shape(self) -> tuple[int, int]:
        return self.ny, self.nx

    @property
    def cell_shape(self) -> tuple[int, int]:
        return self.ny - 1, self.nx - 1

    @property
    def node_transform(self) -> Affine:
        """Pixel centres on the nodes."""
        s = self.spacing
        return Affine(s, 0, self.xmin - s / 2, 0, -s, self.ymax + s / 2)

    @property
    def cell_transform(self) -> Affine:
        """Pixels are the cells between nodes."""
        s = self.spacing
        return Affine(s, 0, self.xmin, 0, -s, self.ymax)

    def node_xy(self) -> tuple[np.ndarray, np.ndarray]:
        x = self.xmin + self.spacing * np.arange(self.nx)
        y = self.ymax - self.spacing * np.arange(self.ny)
        return np.meshgrid(x, y)

    def cell_xy(self) -> tuple[np.ndarray, np.ndarray]:
        x = self.xmin + self.spacing * (np.arange(self.nx - 1) + 0.5)
        y = self.ymax - self.spacing * (np.arange(self.ny - 1) + 0.5)
        return np.meshgrid(x, y)

    def geo_bounds(self, pad_m: float = 0.0) -> tuple[float, float, float, float]:
        """(west, south, east, north) in degrees that contains the whole grid, plus pad_m."""
        xs = np.linspace(self.xmin - pad_m, self.xmax + pad_m, 9)
        ys = np.linspace(self.ymin - pad_m, self.ymax + pad_m, 9)
        X = np.concatenate([xs, xs, np.full(9, xs[0]), np.full(9, xs[-1])])
        Y = np.concatenate([np.full(9, ys[0]), np.full(9, ys[-1]), ys, ys])
        lon, lat = self.frame.to_geo(X, Y)
        return float(lon.min()), float(lat.min()), float(lon.max()), float(lat.max())

    def sample_nodes(self, values: np.ndarray, x, y) -> np.ndarray:
        """Bilinear interpolation of a node grid at local points (clamped to the grid)."""
        x = np.asarray(x, float)
        y = np.asarray(y, float)
        fx = np.clip((x - self.xmin) / self.spacing, 0, self.nx - 1.000001)
        fy = np.clip((self.ymax - y) / self.spacing, 0, self.ny - 1.000001)
        i0 = np.floor(fx).astype(int)
        j0 = np.floor(fy).astype(int)
        tx = fx - i0
        ty = fy - j0
        v00 = values[j0, i0]
        v01 = values[j0, i0 + 1]
        v10 = values[j0 + 1, i0]
        v11 = values[j0 + 1, i0 + 1]
        return (v00 * (1 - tx) * (1 - ty) + v01 * tx * (1 - ty) + v10 * (1 - tx) * ty + v11 * tx * ty)


def grid_for(area: Area, spacing: float, margin_m: float) -> Grid:
    """A grid over the area plus a margin on every side, in a frame centred on the area."""
    lat0, lon0 = area.center
    frame = LocalFrame(lat0, lon0)
    lons = np.array([area.west, area.east, area.east, area.west, (area.west + area.east) / 2, (area.west + area.east) / 2])
    lats = np.array([area.south, area.south, area.north, area.north, area.south, area.north])
    x, y = frame.to_local(lons, lats)
    xmin = math.floor((x.min() - margin_m) / spacing) * spacing
    xmax = math.ceil((x.max() + margin_m) / spacing) * spacing
    ymin = math.floor((y.min() - margin_m) / spacing) * spacing
    ymax = math.ceil((y.max() + margin_m) / spacing) * spacing
    nx = int(round((xmax - xmin) / spacing)) + 1
    ny = int(round((ymax - ymin) / spacing)) + 1
    return Grid(frame, xmin, ymax, spacing, nx, ny)
