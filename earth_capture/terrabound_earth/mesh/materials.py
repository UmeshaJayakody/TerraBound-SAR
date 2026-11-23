"""Which radar material each surface gets.

The names are the ones sar_pipeline/Scripts/Radar_Materials.m defines; the MATLAB converter turns
each into a POV-Ray finish when the scene is converted with materials='auto'. The colours here are only
for display (Blender, the map preview) and match that file; tests check the two stay in step.
"""
from __future__ import annotations

import numpy as np
from rasterio.features import rasterize

MATERIALS = {
    "concrete":   (0.62, 0.62, 0.60),
    "metal":      (0.55, 0.62, 0.72),
    "vegetation": (0.16, 0.42, 0.18),
    "sand":       (0.86, 0.78, 0.56),
    "soil":       (0.55, 0.42, 0.30),
    "land":       (0.70, 0.66, 0.55),
    "water":      (0.25, 0.50, 0.80),
    "sea":        (0.10, 0.25, 0.55),
    "asphalt":    (0.30, 0.30, 0.32),
    "grass":      (0.48, 0.68, 0.30),
}
NAMES = list(MATERIALS)
INDEX = {n: i for i, n in enumerate(NAMES)}

# ESA WorldCover class -> material of the ground
WORLDCOVER_CLASSES = {
    10: ("Tree cover", "vegetation"),
    20: ("Shrubland", "vegetation"),
    30: ("Grassland", "grass"),
    40: ("Cropland", "grass"),
    50: ("Built-up", "asphalt"),
    60: ("Bare / sparse vegetation", "soil"),
    70: ("Snow and ice", "land"),
    80: ("Permanent water bodies", "water"),
    90: ("Herbaceous wetland", "grass"),
    95: ("Mangroves", "vegetation"),
    100: ("Moss and lichen", "grass"),
    0: ("Unknown", "land"),
}

METAL_BUILDINGS = {"industrial", "warehouse", "hangar", "factory", "manufacture", "shed", "carport", "roof",
                   "storage_tank", "silo"}


def building_material(tags: dict) -> str:
    roof = str(tags.get("roof:material", "")).lower()
    wall = str(tags.get("building:material", "")).lower()
    kind = str(tags.get("building", tags.get("building:part", ""))).lower()
    if roof in ("metal", "tin", "steel", "copper", "zinc") or wall in ("metal", "steel"):
        return "metal"
    if kind in METAL_BUILDINGS:
        return "metal"
    return "concrete"


def ground_materials(landcover: np.ndarray, cell_height: np.ndarray, transform, water_geoms, road_geoms) -> np.ndarray:
    """Material index of every terrain cell: land cover first, then OpenStreetMap water and roads on top.

    landcover:   WorldCover class per cell
    cell_height: terrain height per cell (m above sea level), to tell the sea from inland water
    water_geoms, road_geoms: shapely geometries in the local frame (roads already buffered to width)
    """
    lut = np.full(256, INDEX["land"], dtype=np.uint8)
    for cls, (_, name) in WORLDCOVER_CLASSES.items():
        lut[cls] = INDEX[name]
    mat = lut[landcover]

    # A mostly bare area is a desert: sand rather than soil
    land = landcover[(landcover != 80) & (landcover != 0)]
    if land.size and np.mean(land == 60) > 0.6:
        mat[landcover == 60] = INDEX["sand"]

    shape = landcover.shape
    if water_geoms:
        w = rasterize([(g, 1) for g in water_geoms], out_shape=shape, transform=transform, fill=0, dtype="uint8")
        mat[w == 1] = INDEX["water"]
    is_water = mat == INDEX["water"]
    mat[is_water & (cell_height <= 1.0)] = INDEX["sea"]       # water at sea level is the sea
    if road_geoms:
        r = rasterize([(g, 1) for g in road_geoms], out_shape=shape, transform=transform, fill=0, dtype="uint8")
        mat[(r == 1) & ~(mat == INDEX["water"]) & ~(mat == INDEX["sea"])] = INDEX["asphalt"]
    return mat


def mtl_text(names: list[str]) -> str:
    lines = ["# Radar materials of an Earth Capture scene. The colours are for display only;",
             "# the radar response of each name is set in sar_pipeline/Scripts/Radar_Materials.m.", ""]
    for n in names:
        r, g, b = MATERIALS[n]
        lines += [f"newmtl {n}", f"Kd {r:.3f} {g:.3f} {b:.3f}", "Ka 0 0 0", "Ks 0 0 0", "d 1", "illum 1", ""]
    return "\n".join(lines)
