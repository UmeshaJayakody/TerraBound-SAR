"""Buildings as block models (LoD1): each outline extruded from the ground to its height."""
from __future__ import annotations

from dataclasses import dataclass

import mapbox_earcut as earcut
import numpy as np
from shapely.geometry import Polygon
from shapely.geometry.polygon import orient

from ..sources.osm import parse_length

METRES_PER_LEVEL = 3.0
MIN_HEIGHT, MAX_HEIGHT = 2.0, 830.0

# Typical heights when OpenStreetMap gives neither a height nor a number of levels
DEFAULT_HEIGHT_M = {
    "house": 6, "detached": 6, "semidetached_house": 6, "terrace": 7, "bungalow": 4, "residential": 9,
    "apartments": 15, "dormitory": 12, "hotel": 20, "commercial": 12, "retail": 8, "office": 15,
    "supermarket": 7, "industrial": 9, "warehouse": 9, "factory": 10, "manufacture": 10, "hangar": 12,
    "garage": 3, "garages": 3, "shed": 3, "hut": 3, "carport": 3, "roof": 4, "kiosk": 3, "service": 4,
    "church": 14, "cathedral": 25, "chapel": 8, "mosque": 12, "temple": 10, "shrine": 6, "school": 9,
    "university": 12, "college": 12, "kindergarten": 5, "hospital": 15, "train_station": 12,
    "transportation": 10, "stadium": 20, "grandstand": 10, "parking": 10, "civic": 12, "government": 15,
    "public": 12, "construction": 9, "ruins": 4, "farm": 6, "barn": 7, "greenhouse": 4, "static_caravan": 3,
}
DEFAULT_ANY = 7.0


def height_of(tags: dict) -> tuple[float, float, str]:
    """(height, min_height, source) in m for an OpenStreetMap building or building:part.

    source says where the height came from: 'height' (tagged), 'levels' (number of storeys x 3 m)
    or 'default' (typical for its type), so a dataset can tell measured from guessed heights.
    """
    min_h = parse_length(tags.get("min_height"))
    if min_h is None:
        ml = _num(tags.get("building:min_level"))
        min_h = ml * METRES_PER_LEVEL if ml is not None else 0.0
    h = parse_length(tags.get("height")) or parse_length(tags.get("building:height"))
    if h is not None and h > 0:
        source = "height"
    else:
        levels = _num(tags.get("building:levels"))
        if levels is not None and levels > 0:
            roof = _num(tags.get("roof:levels")) or 0.0
            h = levels * METRES_PER_LEVEL + 0.5 * roof * METRES_PER_LEVEL
            source = "levels"
        else:
            kind = str(tags.get("building", tags.get("building:part", "yes"))).lower()
            h = float(DEFAULT_HEIGHT_M.get(kind, DEFAULT_ANY))
            source = "default"
    h = float(np.clip(h, MIN_HEIGHT, MAX_HEIGHT))
    min_h = float(np.clip(min_h, 0.0, h - 1.0))
    return h, min_h, source


def _num(v) -> float | None:
    try:
        return float(str(v).split(";")[0].strip())
    except (TypeError, ValueError):
        return None


@dataclass
class Block:
    vertices: np.ndarray      # n x 3, local east, north, up
    faces: np.ndarray         # m x 3, 0-based into vertices


def extrude(poly: Polygon, bottom: float, top: float) -> Block | None:
    """Walls and a flat roof for one polygon (holes allowed), from bottom to top (local up, m)."""
    if poly.is_empty or poly.area < 1.0 or top - bottom < 0.5:
        return None
    poly = orient(poly.simplify(0.05, preserve_topology=True), sign=1.0)   # outer ring anticlockwise
    rings = [np.asarray(poly.exterior.coords)[:-1]] + [np.asarray(r.coords)[:-1] for r in poly.interiors]
    rings = [r[:, :2] for r in rings if len(r) >= 3]
    if not rings:
        return None
    pts = np.vstack(rings)
    n = len(pts)

    # Roof
    ends = np.cumsum([len(r) for r in rings]).astype(np.uint32)
    tri = np.asarray(earcut.triangulate_float64(pts.astype(np.float64), ends), dtype=np.int64).reshape(-1, 3)
    verts = [np.column_stack([pts, np.full(n, top)]), np.column_stack([pts, np.full(n, bottom)])]
    faces = []
    if len(tri):
        # Facing up: anticlockwise seen from above
        p = pts[tri]
        cross = (p[:, 1, 0] - p[:, 0, 0]) * (p[:, 2, 1] - p[:, 0, 1]) - (p[:, 1, 1] - p[:, 0, 1]) * (p[:, 2, 0] - p[:, 0, 0])
        tri[cross < 0] = tri[cross < 0][:, [0, 2, 1]]
        faces.append(tri)

    # Walls: every edge of every ring, facing out (outer rings anticlockwise, holes clockwise)
    start = 0
    for r in rings:
        m = len(r)
        i = start + np.arange(m)
        j = start + (np.arange(m) + 1) % m
        bi, bj = i + n, j + n                     # the same corners at the bottom
        faces.append(np.column_stack([bi, bj, j]))
        faces.append(np.column_stack([bi, j, i]))
        start += m
    return Block(np.vstack(verts), np.vstack(faces))
