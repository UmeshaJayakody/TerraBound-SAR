"""The local metric frame a scene is built in.

Positions on the Earth (longitude, latitude) become metres east and north of the area's centre with
an azimuthal equidistant projection centred there. Within a few kilometres this is the local
tangent plane to millimetres. Heights also drop with the Earth's curvature, (x^2 + y^2) / 2R, about
8 cm at 1 km, so a long flat area curves away from the radar as it really does.

The scene files use the axes of the rest of the pipeline (sar_pipeline, Blender add-on):
    x = east, y = up, z = south (north is -z), in metres.
"""
from __future__ import annotations

import math

import numpy as np
from pyproj import CRS, Transformer

EARTH_RADIUS = 6371008.8   # mean radius, m


class LocalFrame:
    def __init__(self, lat0: float, lon0: float):
        self.lat0 = float(lat0)
        self.lon0 = float(lon0)
        self.proj = (f"+proj=aeqd +lat_0={self.lat0:.9f} +lon_0={self.lon0:.9f} "
                     "+x_0=0 +y_0=0 +datum=WGS84 +units=m +no_defs")
        self.crs = CRS.from_proj4(self.proj)
        self._fwd = Transformer.from_crs("EPSG:4326", self.crs, always_xy=True)
        self._inv = Transformer.from_crs(self.crs, "EPSG:4326", always_xy=True)

    def to_local(self, lon, lat):
        """(lon, lat) in degrees -> (x east, y north) in metres."""
        x, y = self._fwd.transform(np.asarray(lon, dtype=float), np.asarray(lat, dtype=float))
        return x, y

    def to_geo(self, x, y):
        """(x east, y north) in metres -> (lon, lat) in degrees."""
        lon, lat = self._inv.transform(np.asarray(x, dtype=float), np.asarray(y, dtype=float))
        return lon, lat

    @staticmethod
    def curvature_drop(x, y):
        return (np.asarray(x, dtype=float) ** 2 + np.asarray(y, dtype=float) ** 2) / (2.0 * EARTH_RADIUS)


def metres_per_degree(lat: float) -> tuple[float, float]:
    """Approximate size of one degree of longitude and latitude at a latitude, in metres."""
    m_lat = 111132.92 - 559.82 * math.cos(2 * math.radians(lat)) + 1.175 * math.cos(4 * math.radians(lat))
    m_lon = 111412.84 * math.cos(math.radians(lat)) - 93.5 * math.cos(3 * math.radians(lat))
    return m_lon, m_lat


def local_to_obj(x, y, up):
    """Local (east, north, up) to the scene's axes: x east, y up, z south."""
    return np.column_stack([np.asarray(x, float), np.asarray(up, float), -np.asarray(y, float)])


def obj_to_local(obj_x, obj_z):
    """The scene's (x, z) back to local (east, north)."""
    return np.asarray(obj_x, float), -np.asarray(obj_z, float)
