"""Builds the 3D scene of an area: ground, buildings and radar materials, as an OBJ for the pipeline.

    runs/<area id>/scene/<area id>.obj   the scene (x east, y up, z south; metres; usemtl per surface)
    runs/<area id>/scene/<area id>.mtl   display colours of the materials
    runs/<area id>/scene/scene.json      where it is on the Earth, what it was built from, statistics
    runs/<area id>/scene/terrain.npz     the ground grid, to look heights up when planning views
    runs/<area id>/scene/preview/        buildings.geojson and materials.png for the map
"""
from __future__ import annotations

import datetime as dt
import json
import math
from pathlib import Path

import numpy as np
import shapely
from PIL import Image
from rasterio.features import rasterize
from shapely.geometry import mapping, shape

from . import __version__, config
from .aoi import Area
from .grid import Grid, grid_for
from .mesh import buildings as bmesh
from .mesh import materials as mats
from .mesh import terrain as tmesh
from .mesh.obj_writer import write_obj
from .sources import osm as osm_src
from .sources import raster


class SceneSettings:
    def __init__(self, grid_m: float = 5.0, margin_m: float = 150.0, max_ground_triangles: int = 600_000,
                 buildings: bool = True, roads: bool = True, water: bool = True, dem_files: list[str] | None = None):
        self.grid_m = float(grid_m)
        self.margin_m = float(margin_m)
        self.max_ground_triangles = int(max_ground_triangles)
        self.buildings = bool(buildings)
        self.roads = bool(roads)
        self.water = bool(water)
        self.dem_files = dem_files or None

    def to_dict(self) -> dict:
        return dict(self.__dict__)

    @classmethod
    def from_dict(cls, d: dict | None) -> "SceneSettings":
        return cls(**{k: v for k, v in (d or {}).items() if k in cls().__dict__})


def run_dir(area: Area) -> Path:
    return config.runs_dir() / area.id


def scene_paths(area: Area) -> dict:
    d = run_dir(area) / "scene"
    return {"dir": d, "obj": d / f"{area.id}.obj", "json": d / "scene.json", "terrain": d / "terrain.npz",
            "preview": d / "preview"}


def load_scene(area: Area) -> dict | None:
    p = scene_paths(area)["json"]
    return json.loads(p.read_text(encoding="utf-8")) if p.exists() else None


def _choose_grid(area: Area, s: SceneSettings, log) -> Grid:
    grid = grid_for(area, s.grid_m, s.margin_m)
    tris = 2 * (grid.nx - 1) * (grid.ny - 1)
    if tris > s.max_ground_triangles:
        spacing = math.ceil(s.grid_m * math.sqrt(tris / s.max_ground_triangles) * 2) / 2
        log(f"  the area is large: ground sampled every {spacing:g} m instead of {s.grid_m:g} m")
        grid = grid_for(area, spacing, s.margin_m)
    return grid


def _to_local(frame, geom):
    return shapely.transform(geom, lambda xy: np.column_stack(frame.to_local(xy[:, 0], xy[:, 1])))


def _to_geo(frame, geom):
    return shapely.transform(geom, lambda xy: np.column_stack(frame.to_geo(xy[:, 0], xy[:, 1])))


def build_scene(area: Area, settings: SceneSettings | None = None, log=print, force: bool = False) -> dict:
    """Builds (or reuses) the scene of an area and returns its scene.json content."""
    s = settings or SceneSettings()
    paths = scene_paths(area)
    if not force and paths["json"].exists() and paths["obj"].exists():
        meta = json.loads(paths["json"].read_text(encoding="utf-8"))
        if meta.get("settings") == s.to_dict():
            log(f"Scene already built: {paths['obj']}")
            return meta
    issues = area.problems()
    if issues:
        raise ValueError(" ".join(issues))
    paths["dir"].mkdir(parents=True, exist_ok=True)
    paths["preview"].mkdir(parents=True, exist_ok=True)
    log(f"Building the scene of {area.name} ({area.size_m[0]:.0f} x {area.size_m[1]:.0f} m)")

    grid = _choose_grid(area, s, log)
    frame = grid.frame
    X, Y = grid.node_xy()

    # 1) Elevation and land cover
    surface, dem_info = raster.elevation_on_grid(grid, log, s.dem_files)
    landcover, lc_info = raster.landcover_on_grid(grid, log)

    # 2) OpenStreetMap
    sources = [dem_info, lc_info]
    blds, water_local, roads_local = [], [], []
    if s.buildings or s.roads or s.water:
        data = osm_src.fetch(grid.geo_bounds(pad_m=50), log)
        sources.append({**osm_src.SOURCE, "timestamp": data.timestamp})
        inside = lambda g: grid.xmin <= g.centroid.x <= grid.xmax and grid.ymin <= g.centroid.y <= grid.ymax  # noqa: E731
        if s.buildings:
            for f in data.buildings:
                g = _to_local(frame, f.geom)
                if not g.is_empty and inside(g):
                    blds.append((g, f.tags, f.osm_id))
        if s.water:
            water_local = [_to_local(frame, f.geom) for f in data.water]
        if s.roads:
            for f, width in data.roads:
                if str(f.tags.get("bridge", "no")) != "no" or str(f.tags.get("tunnel", "no")) != "no":
                    continue                                   # not on the ground here
                roads_local.append(_to_local(frame, f.geom).buffer(width / 2.0))

    # 3) Bare ground in built areas (the DEM is a surface model: buildings are in it), then the
    #    Earth's curvature. Built: near a mapped building, or on WorldCover's built-up class.
    built = np.zeros(grid.node_shape, dtype=bool)
    if blds:
        built = rasterize([(g.buffer(15.0), 1) for g, _, _ in blds], out_shape=grid.node_shape,
                          transform=grid.node_transform, fill=0, dtype="uint8").astype(bool)
    bu = landcover == 50
    built[:-1, :-1] |= bu
    built[:-1, 1:] |= bu
    built[1:, :-1] |= bu
    built[1:, 1:] |= bu
    ground = tmesh.ground_from_surface(surface, built, grid.spacing)
    up = ground - frame.curvature_drop(X, Y)

    # 4) Ground materials
    cell_h = 0.25 * (surface[:-1, :-1] + surface[:-1, 1:] + surface[1:, :-1] + surface[1:, 1:])
    cell_mat = mats.ground_materials(landcover, cell_h, grid.cell_transform, water_local, roads_local)

    # 5) Triangles: ground, then every building on it
    gv, gf, gm = tmesh.mesh(up, X, Y, cell_mat)
    parts_v, parts_f, parts_m = [gv], [gf], [gm]
    offset = len(gv)
    height_sources = {"height": 0, "levels": 0, "default": 0}
    preview = []
    for g, tags, oid in blds:
        h, min_h, src = bmesh.height_of(tags)
        material = mats.building_material(tags)
        polys = list(osm_src.as_multipolygon(g).geoms)
        made = False
        for poly in polys:
            ring = np.asarray(poly.exterior.coords)
            base = float(grid.sample_nodes(up, ring[:, 0], ring[:, 1]).min())
            bottom = base + min_h if min_h > 0 else base - 0.3     # sunk a little so no gap shows
            blk = bmesh.extrude(poly, bottom, base + h)
            if blk is None:
                continue
            parts_v.append(blk.vertices)
            parts_f.append(blk.faces + offset)
            parts_m.append(np.full(len(blk.faces), mats.INDEX[material], dtype=np.uint8))
            offset += len(blk.vertices)
            made = True
        if made:
            height_sources[src] += 1
            geo = _to_geo(frame, g)
            preview.append({"type": "Feature", "geometry": mapping(geo),
                            "properties": {"osm": oid, "height_m": round(h, 1), "height_source": src,
                                           "material": material}})
    V = np.vstack(parts_v)
    F = np.vstack(parts_f)
    M = np.concatenate(parts_m)

    # 6) The OBJ: y = 0 at the lowest point, as the pipeline expects
    y_ref = float(V[:, 2].min())
    obj_v = np.column_stack([V[:, 0], V[:, 2] - y_ref, -V[:, 1]])
    header = [f"Earth Capture scene: {area.name}",
              f"centre {area.center[0]:.6f}, {area.center[1]:.6f} (lat, lon); axes x east, y up, z south; metres",
              "Sources: Copernicus DEM GLO-30, ESA WorldCover 2021, (c) OpenStreetMap contributors (ODbL)",
              "units: metres"]
    counts = write_obj(paths["obj"], obj_v, F, M, mats.NAMES, header)
    log(f"  wrote {paths['obj'].name}: {counts['vertices']} vertices, {counts['triangles']} triangles, "
        f"{len(preview)} buildings")

    # 7) What the views and the dataset need later
    np.savez_compressed(paths["terrain"], up=up.astype(np.float32), surface=surface.astype(np.float32),
                        cell_material=cell_mat, landcover=landcover, xmin=grid.xmin, ymax=grid.ymax,
                        spacing=grid.spacing)
    (paths["preview"] / "buildings.geojson").write_text(
        json.dumps({"type": "FeatureCollection", "features": preview}), encoding="utf-8")
    _materials_png(cell_mat, paths["preview"] / "materials.png")

    ax, ay = frame.to_local([area.west, area.east, area.east, area.west], [area.south, area.south, area.north, area.north])
    in_area = _cells_in(grid, float(np.min(ax)), float(np.max(ax)), float(np.min(ay)), float(np.max(ay)))
    lc_frac = _fractions(landcover[in_area], {k: v[0] for k, v in mats.WORLDCOVER_CLASSES.items()})
    meta = {
        "format": 1,
        "generator": f"Earth Capture {__version__}",
        "created": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "area": area.to_dict(),
        "frame": {"type": "aeqd", "lat0": frame.lat0, "lon0": frame.lon0, "proj": frame.proj},
        "axes": "x east, y up, z south (north is -z), metres",
        "y_ref_m": y_ref,
        "grid": {"xmin": grid.xmin, "ymax": grid.ymax, "spacing": grid.spacing, "nx": grid.nx, "ny": grid.ny},
        "area_local": {"xmin": float(np.min(ax)), "xmax": float(np.max(ax)),
                       "ymin": float(np.min(ay)), "ymax": float(np.max(ay))},
        "geo_bounds": grid.geo_bounds(),
        "obj": paths["obj"].name,
        "counts": counts,
        "buildings": {"count": len(preview), "height_sources": height_sources},
        "landcover_fractions": lc_frac,
        "relief_m": float(np.percentile(surface, 95) - np.percentile(surface, 5)),
        "sources": sources,
        "settings": s.to_dict(),
    }
    paths["json"].write_text(json.dumps(meta, indent=2), encoding="utf-8")
    return meta


def _cells_in(grid: Grid, xmin, xmax, ymin, ymax) -> np.ndarray:
    cx, cy = grid.cell_xy()
    return (cx >= xmin) & (cx <= xmax) & (cy >= ymin) & (cy <= ymax)


def _fractions(values: np.ndarray, labels: dict) -> dict:
    if values.size == 0:
        return {}
    u, c = np.unique(values, return_counts=True)
    return {labels.get(int(k), str(int(k))): round(float(n) / values.size, 4) for k, n in zip(u, c)}


def _materials_png(cell_mat: np.ndarray, path: Path):
    lut = np.zeros((len(mats.NAMES), 4), dtype=np.uint8)
    for i, n in enumerate(mats.NAMES):
        lut[i, :3] = (np.array(mats.MATERIALS[n]) * 255).astype(np.uint8)
        lut[i, 3] = 170
    Image.fromarray(lut[cell_mat], "RGBA").save(path, optimize=True)


class Terrain:
    """The saved ground grid of a scene, for height and land-cover lookups."""

    def __init__(self, area: Area):
        meta = load_scene(area)
        if meta is None:
            raise FileNotFoundError(f"The scene of {area.name} has not been built yet.")
        z = np.load(scene_paths(area)["terrain"])
        self.meta = meta
        self.up = z["up"]
        self.cell_material = z["cell_material"]
        self.landcover = z["landcover"]
        from .geo import LocalFrame
        g = meta["grid"]
        self.grid = Grid(LocalFrame(meta["frame"]["lat0"], meta["frame"]["lon0"]), g["xmin"], g["ymax"],
                         g["spacing"], g["nx"], g["ny"])
        self.y_ref = meta["y_ref_m"]

    def scene_y(self, x, y):
        """Height of the ground in the scene's y (m above the scene's lowest point) at local (east, north)."""
        return self.grid.sample_nodes(self.up, x, y) - self.y_ref

    def fractions_in(self, polygon_local) -> dict:
        """Share of each WorldCover class inside a local polygon."""
        mask = rasterize([(polygon_local, 1)], out_shape=self.grid.cell_shape, transform=self.grid.cell_transform,
                         fill=0, dtype="uint8").astype(bool)
        return _fractions(self.landcover[mask], {k: v[0] for k, v in mats.WORLDCOVER_CLASSES.items()})


def buildings_in(area: Area, polygon_geo) -> list[dict]:
    """Preview buildings (properties) whose outline meets a lon/lat polygon."""
    p = scene_paths(area)["preview"] / "buildings.geojson"
    if not p.exists():
        return []
    fc = json.loads(p.read_text(encoding="utf-8"))
    return [f["properties"] for f in fc["features"] if shape(f["geometry"]).intersects(polygon_geo)]
