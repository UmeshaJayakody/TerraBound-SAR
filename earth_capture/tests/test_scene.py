"""Building a whole scene offline, and what the pipeline reads from it."""
import math
import re
from pathlib import Path

import numpy as np

from conftest import LAT, LON, load_json, osm_fixture, read_obj
from terrabound_earth import config
from terrabound_earth.aoi import Area
from terrabound_earth.mesh.materials import MATERIALS
from terrabound_earth.scene import Terrain, build_scene, scene_paths
from terrabound_earth.sources import osm
from terrabound_earth.views import ViewSettings, plan


def test_osm_parsing():
    data = osm.parse(osm_fixture())
    ids = {f.osm_id for f in data.buildings}
    # the industrial outline has a part inside it, so the part replaces it
    assert "way/3" not in ids and "way/4" in ids and "way/1" in ids and "relation/2" in ids
    court = next(f for f in data.buildings if f.osm_id == "relation/2")
    assert len(court.geom.interiors if court.geom.geom_type == "Polygon" else court.geom.geoms[0].interiors) == 1
    assert len(data.water) == 1 and len(data.roads) == 2
    assert osm.parse_width({"lanes": "2"}, "primary") == 7.0
    assert osm.parse_width({}, "primary") == 10


def test_build_scene_offline(offline_sources):
    area = Area.square(LAT, LON, 240, "Test block")
    meta = build_scene(area, log=lambda *_: None)
    p = scene_paths(area)
    V, F, groups = read_obj(p["obj"])
    assert meta["counts"]["triangles"] == len(F) and meta["counts"]["vertices"] == len(V)
    assert F.min() == 1 and F.max() == len(V)                       # 1-based, all valid
    assert abs(V[:, 1].min()) < 1e-6                                # the lowest point is y = 0
    assert set(groups) <= set(MATERIALS) and {"concrete", "metal", "vegetation", "water"} <= set(groups)
    assert meta["buildings"]["count"] == 4
    assert meta["buildings"]["height_sources"] == {"height": 2, "levels": 1, "default": 1}
    assert (p["dir"] / f"{area.id}.mtl").exists()
    # the apartments (24 m tagged, at the centre) stand 24 m above the ground they sit on
    t = Terrain(area)
    here = (np.abs(V[:, 0]) < 16) & (np.abs(V[:, 2]) < 16)
    assert abs(V[here, 1].max() - (t.scene_y(0.0, 0.0) + 24.0)) < 1.0
    # the 20 m bump in the surface model under the city was taken out
    assert float(t.scene_y(0.0, 0.0)) < 6.0
    # built again with the same settings: reused, not rebuilt
    assert build_scene(area, log=lambda *_: None)["created"] == meta["created"]


def test_materials_match_the_matlab_table():
    m = Path(config.SCRIPTS / "Radar_Materials.m").read_text(encoding="utf-8")
    found = dict(re.findall(r"m\('(\w+)',[^\[]*\[([0-9. ]+)\]", m))
    assert set(found) == set(MATERIALS)
    for name, rgb in found.items():
        assert np.allclose([float(v) for v in rgb.split()], MATERIALS[name])


def test_views_land_on_their_ground_point(offline_sources):
    area = Area.square(LAT, LON, 240, "Test block")
    build_scene(area, log=lambda *_: None)
    t = Terrain(area)
    views = plan(area, ViewSettings(n_views=8, window_m=60, seed=4))
    assert len(views) == 8
    for v in views:
        b, i = math.radians(v["bearing_deg"]), math.radians(v["incidence_deg"])
        g = v["ground"]
        # the pipeline aims at height 0: follow the central ray up to the ground height
        s = g["scene_y"] * math.tan(i)
        assert abs(v["center_x"] + s * math.sin(b) - g["x"]) < 1e-2
        assert abs(-v["center_z"] + s * math.cos(b) - g["y"]) < 1e-2
        assert abs(g["scene_y"] - float(t.scene_y(g["x"], g["y"]))) < 1e-2
        assert abs(v["height_m"] - 60 * math.cos(i)) < 1e-2
        assert len(v["footprint"]) == 5
    grid = plan(area, ViewSettings(mode="grid", window_m=80, bearings=[0, 90]))
    assert len(grid) == 3 * 3 * 2


def test_view_settings_limits():
    assert ViewSettings(window_m=400).problems()                     # 2667 px at 0.30 m
    assert not ViewSettings(window_m=250).problems()
    assert ViewSettings(incidence_range=[5, 60]).problems()
    assert abs(ViewSettings().largest_window() - 0.95 * 2000 * 0.149896) < 0.1
