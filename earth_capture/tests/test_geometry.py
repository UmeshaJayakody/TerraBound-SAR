"""The local frame, areas, terrain and building geometry."""
import math

import numpy as np
from shapely.geometry import Polygon

from terrabound_earth.aoi import Area
from terrabound_earth.geo import LocalFrame
from terrabound_earth.mesh import buildings as b
from terrabound_earth.mesh import terrain as t


def test_frame_round_trip_is_below_a_centimetre():
    f = LocalFrame(6.9355, 79.843)
    lon = 79.843 + np.linspace(-0.02, 0.02, 21)
    lat = 6.9355 + np.linspace(-0.02, 0.02, 21)
    x, y = f.to_local(lon, lat)
    lon2, lat2 = f.to_geo(x, y)
    err_m = np.hypot((lon2 - lon) * 111000 * math.cos(math.radians(6.9)), (lat2 - lat) * 111000)
    assert err_m.max() < 0.01
    x0, y0 = f.to_local(79.843, 6.9355)
    assert abs(x0) < 1e-6 and abs(y0) < 1e-6
    xe, _ = f.to_local(79.843 + 0.01, 6.9355)       # 0.01 degree east at 6.9 N is about 1105 m
    assert 1100 < xe < 1110


def test_curvature_drop_at_one_kilometre():
    assert abs(LocalFrame.curvature_drop(1000.0, 0.0) - 0.0785) < 0.001


def test_area_square_size_id_and_limits():
    a = Area.square(6.9355, 79.843, 400, "Colombo Fort")
    w, h = a.size_m
    assert abs(w - 400) < 1 and abs(h - 400) < 1
    assert a.id == Area.square(6.9355, 79.843, 400, "Colombo Fort").id
    assert a.id.startswith("colombo_fort_6.9355N_79.8430E")
    assert not a.problems()
    assert Area.square(0, 0, 5000).problems()                  # 25 km2 is too big
    assert Area.square(0, 0, 20).problems()                    # too small
    assert Area.from_feature(a.to_feature()).id == a.id


def test_heights_from_tags():
    assert b.height_of({"building": "yes", "height": "24 m"})[::2] == (24.0, "height")
    assert b.height_of({"building": "yes", "height": "40'"})[0] == 40 * 0.3048
    h, mn, src = b.height_of({"building": "yes", "building:levels": "4", "roof:levels": "1"})
    assert (h, src) == (13.5, "levels")
    assert b.height_of({"building": "garage"})[::2] == (3.0, "default")
    assert b.height_of({"building": "unknown_kind"})[0] == b.DEFAULT_ANY
    h, mn, _ = b.height_of({"building:part": "yes", "height": "30", "min_height": "12"})
    assert (h, mn) == (30.0, 12.0)


def test_extruded_block_is_closed_and_faces_outwards():
    poly = Polygon([(0, 0), (20, 0), (20, 10), (0, 10)], holes=[[(5, 3), (8, 3), (8, 6), (5, 6)]])
    blk = b.extrude(poly, 2.0, 14.0)
    V, F = blk.vertices, blk.faces
    assert V[:, 2].min() == 2.0 and V[:, 2].max() == 14.0
    p = V[F]
    n = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
    area2 = np.linalg.norm(n, axis=1)
    roof = np.isclose(p[:, :, 2], 14.0).all(axis=1)
    assert np.all(n[roof, 2] > 0)                                   # roof faces up
    assert np.isclose(area2[roof].sum() / 2, poly.area)             # and covers the outline exactly
    walls = ~roof
    centre = np.array([10.0, 5.0])
    mid = p[walls].mean(axis=1)[:, :2]
    out = (mid - centre)
    hole = (mid[:, 0] > 4.9) & (mid[:, 0] < 8.1) & (mid[:, 1] > 2.9) & (mid[:, 1] < 6.1)
    # outer walls point away from the middle, courtyard walls point into the courtyard
    dots = np.einsum("ij,ij->i", n[walls][:, :2], out)
    assert np.all(dots[~hole] > 0)
    court = np.array([6.5, 4.5])
    assert np.all(np.einsum("ij,ij->i", n[walls][hole][:, :2], court - mid[hole]) > 0)
    # every roof and wall edge is shared by exactly two faces, except the open bottom
    edges = {}
    for tri in F:
        for a, c in ((0, 1), (1, 2), (2, 0)):
            e = tuple(sorted((tri[a], tri[c])))
            edges[e] = edges.get(e, 0) + 1
    bottom = {e: k for e, k in edges.items() if V[e[0], 2] == 2.0 and V[e[1], 2] == 2.0}
    assert all(k == 2 for e, k in edges.items() if e not in bottom)


def test_ground_recovery_removes_a_block_and_keeps_the_slope():
    yy, xx = np.mgrid[0:80, 0:80].astype(float)
    ground = 10 + 0.05 * xx
    surface = ground.copy()
    surface[30:40, 30:40] += 25.0                                   # a 50 m block on a 5 m grid
    built = np.zeros_like(surface, bool)
    built[20:50, 20:50] = True
    g = t.ground_from_surface(surface, built, spacing=5.0)
    assert np.abs(g[30:40, 30:40] - ground[30:40, 30:40]).max() < 1.5
    assert np.allclose(g[:, :5], surface[:, :5])                     # far from anything built: untouched
    assert np.all(g <= surface + 1e-6)


def test_ground_mesh_faces_up():
    x, y = np.meshgrid(np.arange(4.0) * 5, -np.arange(3.0) * 5)
    up = np.random.default_rng(0).normal(0, 0.5, x.shape)
    V, F, M = t.mesh(up, x, y, np.zeros((2, 3), np.uint8))
    p = V[F]
    n = np.cross(p[:, 1] - p[:, 0], p[:, 2] - p[:, 0])
    assert len(F) == 2 * 2 * 3 and np.all(n[:, 2] > 0) and len(M) == len(F)
