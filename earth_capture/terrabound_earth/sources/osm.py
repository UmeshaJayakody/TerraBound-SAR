"""OpenStreetMap features for an area: buildings (with their heights), water areas and roads.

Fetched with one Overpass API query, from the first of several public servers that answers, and
cached. OpenStreetMap data is (c) OpenStreetMap contributors and available under the Open Database
Licence (ODbL); scenes built from it carry that notice (see DATA_LICENSE.md).
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

from shapely.geometry import LineString, MultiPolygon, Polygon
from shapely.ops import polygonize, unary_union
from shapely.strtree import STRtree

from .http import post_json_cached

OVERPASS_SERVERS = [
    "https://overpass-api.de/api/interpreter",
    "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]

SOURCE = {
    "name": "OpenStreetMap",
    "url": "https://www.openstreetmap.org/copyright",
    "licence": "ODbL 1.0",
    "attribution": "(c) OpenStreetMap contributors",
}

ROAD_WIDTH_M = {   # typical paved width when the way has no width or lanes tag
    "motorway": 14, "trunk": 12, "primary": 10, "secondary": 8, "tertiary": 7, "unclassified": 6,
    "residential": 6, "living_street": 5, "service": 4, "motorway_link": 7, "trunk_link": 7,
    "primary_link": 7, "secondary_link": 6, "tertiary_link": 6, "pedestrian": 6, "busway": 7,
}

WATER_TAGS = [("natural", "water"), ("waterway", "riverbank"), ("landuse", "reservoir"), ("landuse", "basin"),
              ("water", None)]


@dataclass
class Feature:
    geom: object              # shapely geometry in longitude / latitude
    tags: dict = field(default_factory=dict)
    osm_id: str = ""


@dataclass
class OsmData:
    buildings: list           # Feature with Polygon/MultiPolygon: building outlines and building:parts
    water: list               # Feature with Polygon/MultiPolygon
    roads: list               # (Feature with LineString, width in m)
    timestamp: str = ""


def _query(bounds) -> str:
    w, s, e, n = bounds
    bb = f"{s:.6f},{w:.6f},{n:.6f},{e:.6f}"
    return f"""[out:json][timeout:180][maxsize:536870912];
(
  way["building"]({bb});
  relation["building"]["type"="multipolygon"]({bb});
  way["building:part"]({bb});
  relation["building:part"]["type"="multipolygon"]({bb});
  way["natural"="water"]({bb});
  relation["natural"="water"]({bb});
  way["waterway"="riverbank"]({bb});
  way["landuse"~"^(reservoir|basin)$"]({bb});
  relation["landuse"~"^(reservoir|basin)$"]({bb});
  way["highway"~"^({'|'.join(ROAD_WIDTH_M)})$"]({bb});
);
out geom;"""


def _ring(geometry) -> list[tuple[float, float]]:
    return [(p["lon"], p["lat"]) for p in geometry if p is not None]


def _way_polygon(el) -> Polygon | None:
    pts = _ring(el.get("geometry") or [])
    if len(pts) < 4 or pts[0] != pts[-1]:
        return None
    poly = Polygon(pts)
    if not poly.is_valid:
        poly = poly.buffer(0)
    return poly if not poly.is_empty else None


def _relation_polygon(el):
    """A multipolygon relation: outer rings minus inner rings, joined from their member ways."""
    outer, inner = [], []
    for m in el.get("members", []):
        if m.get("type") != "way" or not m.get("geometry"):
            continue
        pts = _ring(m["geometry"])
        if len(pts) < 2:
            continue
        (inner if m.get("role") == "inner" else outer).append(LineString(pts))
    if not outer:
        return None
    shell = unary_union(list(polygonize(outer)))
    if shell.is_empty:
        return None
    if inner:
        holes = unary_union(list(polygonize(inner)))
        if not holes.is_empty:
            shell = shell.difference(holes)
    if not shell.is_valid:
        shell = shell.buffer(0)
    return shell if not shell.is_empty else None


def _is_water(tags: dict) -> bool:
    for k, v in WATER_TAGS:
        if k in tags and (v is None or tags[k] == v):
            return True
    return False


def parse_width(tags: dict, highway: str) -> float:
    w = parse_length(tags.get("width"))
    if w and 1 <= w <= 60:
        return w
    try:
        lanes = float(str(tags.get("lanes", "")).split(";")[0])
        if 1 <= lanes <= 12:
            return 3.5 * lanes
    except ValueError:
        pass
    return float(ROAD_WIDTH_M.get(highway, 5))


_LEN = re.compile(r"^\s*([0-9]+(?:[.,][0-9]+)?)\s*(m|meters?|metres?|ft|feet|')?\s*$", re.I)


def parse_length(value) -> float | None:
    """'12', '12 m', '12.5m', '40 ft', "40'" -> metres; None if it cannot be read."""
    if value is None:
        return None
    m = _LEN.match(str(value).split(";")[0])
    if not m:
        return None
    v = float(m.group(1).replace(",", "."))
    unit = (m.group(2) or "m").lower()
    if unit in ("ft", "feet", "'"):
        v *= 0.3048
    return v


def parse(data: dict) -> OsmData:
    buildings, parts, water, roads = [], [], [], []
    for el in data.get("elements", []):
        tags = el.get("tags") or {}
        oid = f"{el['type']}/{el['id']}"
        if el["type"] == "way" and "highway" in tags and tags["highway"] in ROAD_WIDTH_M and "building" not in tags:
            pts = _ring(el.get("geometry") or [])
            if len(pts) >= 2 and tags.get("area") != "yes":
                roads.append((Feature(LineString(pts), tags, oid), parse_width(tags, tags["highway"])))
            continue
        geom = _way_polygon(el) if el["type"] == "way" else _relation_polygon(el)
        if geom is None:
            continue
        if "building:part" in tags and tags.get("building:part") != "no":
            parts.append(Feature(geom, tags, oid))
        elif "building" in tags and tags.get("building") != "no":
            buildings.append(Feature(geom, tags, oid))
        elif _is_water(tags):
            water.append(Feature(geom, tags, oid))

    # Simple 3D Buildings: where an outline has parts, the parts describe it and the outline is left out
    if parts:
        tree = STRtree([p.geom.representative_point() for p in parts])
        kept = []
        for b in buildings:
            hits = tree.query(b.geom, predicate="contains")
            if len(hits) == 0:
                kept.append(b)
        buildings = kept + parts
    return OsmData(buildings, water, roads, (data.get("osm3s") or {}).get("timestamp_osm_base", ""))


def fetch(bounds, log=print) -> OsmData:
    """Buildings, water and roads inside bounds (west, south, east, north), from the cache or Overpass."""
    log("  OpenStreetMap buildings, water and roads ...")
    data = post_json_cached(OVERPASS_SERVERS, {"data": _query(bounds)}, "osm", log=log)
    out = parse(data)
    log(f"  OpenStreetMap: {len(out.buildings)} buildings, {len(out.water)} water areas, {len(out.roads)} roads")
    return out


def as_multipolygon(geom) -> MultiPolygon:
    if isinstance(geom, Polygon):
        return MultiPolygon([geom])
    if isinstance(geom, MultiPolygon):
        return geom
    polys = [g for g in getattr(geom, "geoms", []) if isinstance(g, Polygon)]
    return MultiPolygon(polys)
