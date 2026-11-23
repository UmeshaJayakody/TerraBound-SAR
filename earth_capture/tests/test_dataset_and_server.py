"""Exporting a dataset from finished views, and the app's server."""
import csv
import json
import re

import numpy as np
import requests
from PIL import Image

from conftest import LAT, LON
from terrabound_earth import dataset
from terrabound_earth.aoi import Area
from terrabound_earth.matlab_bridge import sar_paths
from terrabound_earth.scene import build_scene
from terrabound_earth.views import ViewSettings, plan


def _fake_run(area, views):
    """What a finished MATLAB run leaves behind: index, HR and LR images per view."""
    sp = sar_paths(area)
    root = sp["root"]
    rows = []
    for k, v in enumerate(views, 1):
        vid = f"v{k:03d}_{v['name']}_az{v['bearing_deg']:03.0f}_inc{v['incidence_deg']:02.0f}"
        vdir = root / "views" / vid
        vdir.mkdir(parents=True)
        img = np.zeros((40, 64), np.uint8)
        img[:, :8] = 255                                            # a bright strip on the left
        Image.fromarray(img).save(vdir / "HR.png")
        for name in ("mid", "low", "vlow"):
            Image.fromarray(img).save(vdir / f"LR_{name}.png")
        rows.append({"view": vid, "bearing_deg": v["bearing_deg"], "incidence_deg": v["incidence_deg"],
                     "center_x": v["center_x"], "center_z": v["center_z"], "window": 1, "window_m": "60.0 x 40.0",
                     "status": "done", "bandwidth_mhz": 500, "hr_res_m": 0.3, "image_px": 64, "image_py": 40,
                     "seed": k, "seconds": 1, "hr": "", "lr": "", "message": ""})
    with open(root / "dataset_index.csv", "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    sp["views"].write_text(json.dumps({"views": views}), encoding="utf-8")


def test_results_folder_matches_matlab():
    from terrabound_earth.matlab_bridge import matlab_name
    a = Area.square(6.9355, 79.843, 400, "Colombo Fort")
    # Make_Multi_Angle_Dataset: regexprep(name, '[^A-Za-z0-9_-]+', '_')
    assert sar_paths(a)["root"].name == "colombo_fort_6_9355N_79_8430E_400x400m"
    assert matlab_name("a.b  c-d_e") == "a_b_c-d_e"


def test_split_by_area_is_stable_and_complete():
    ids = [f"a{i}" for i in range(10)]
    s = dataset.split_areas(ids)
    assert s == dataset.split_areas(list(reversed(ids)))
    assert set(s.values()) == {"train", "val", "test"} and sum(v == "train" for v in s.values()) == 8
    assert set(dataset.split_areas(["x", "y"]).values()) == {"train"}


def test_export(offline_sources, tmp_path):
    area = Area.square(LAT, LON, 240, "Test block")
    build_scene(area, log=lambda *_: None)
    views = plan(area, ViewSettings(n_views=3, window_m=60))
    _fake_run(area, views)
    assert [a.id for a in dataset.finished_areas()] == [area.id]
    out = dataset.export([area], tmp_path / "ds", lr_size="native", log=lambda *_: None)
    assert out["pairs"] == 3 and out["lr_factors"] == [2, 4, 8]
    rows = [json.loads(l) for l in open(tmp_path / "ds" / "metadata.jsonl", encoding="utf-8")]
    r = rows[0]
    hr = np.asarray(Image.open(tmp_path / "ds" / r["hr_path"]))
    assert hr[:, -8:].min() == 255 and hr[:, :8].max() == 0           # flipped left-right
    lr4 = Image.open(tmp_path / "ds" / r["lr_x4_path"])
    assert lr4.size == (16, 10)                                       # native: a quarter of the HR size
    assert r["buildings"] >= 0 and abs(r["lat"] - LAT) < 0.01 and r["split"] == "train"
    for f in ("README.md", "ATTRIBUTION.md", "DATA_LICENSE.md", "dataset_info.json", "metadata.csv"):
        assert (tmp_path / "ds" / f).exists()
    assert "OpenStreetMap" in (tmp_path / "ds" / "DATA_LICENSE.md").read_text(encoding="utf-8")


def test_server_needs_its_token_and_stays_in_its_folders():
    from terrabound_earth.server import App, serve
    app = App()
    httpd = serve(app)
    base = f"http://127.0.0.1:{httpd.server_address[1]}"
    try:
        page = requests.get(base + "/", timeout=10).text
        assert re.search(r'window.TOKEN = "([^"]+)"', page).group(1) == app.token
        assert requests.post(base + "/api/state", json={}, timeout=10).status_code == 403
        ok = requests.post(base + "/api/state", json={}, headers={"X-Token": app.token}, timeout=10)
        assert ok.status_code == 200 and "queue" in ok.json()
        assert requests.get(base + "/static/../server.py", timeout=10).status_code == 404
        assert requests.get(base + f"/runs/../x?t={app.token}", timeout=10).status_code == 404
        assert requests.get(base + "/runs/queue.json?t=wrong", timeout=10).status_code == 403
        bad = requests.post(base + "/api/add", json={"area": Area.square(0, 0, 9000).to_dict()},
                            headers={"X-Token": app.token}, timeout=10).json()
        assert bad["ok"] is False and bad["problems"]
    finally:
        httpd.shutdown()
