"""Collects the SAR images of captured areas into one training dataset.

    <dataset>/train|val|test/HR/<id>.png
    <dataset>/train|val|test/LR_x2/<id>.png    (and LR_x4, LR_x8, ... for the factors used)
    <dataset>/metadata.csv, metadata.jsonl     one row per image pair: where, how, from what
    <dataset>/dataset_info.json                settings, counts, sources
    <dataset>/README.md, ATTRIBUTION.md, DATA_LICENSE.md

Areas, not single images, are split between train, validation and test, so no place is in two
splits. An image pair's id is <area id>__<view>.

Orientation: the pipeline's images are the left-right mirror of the scene, because the scene is
right-handed (as OBJ files are) and the POV-Ray engine left-handed (documented in sar_pipeline). The
export flips them back (mirror_fix), so the image matches the map.
"""
from __future__ import annotations

import csv
import datetime as dt
import hashlib
import json
import math
import shutil
from pathlib import Path

from PIL import Image
from shapely.geometry import Polygon

from . import __version__, config
from .aoi import Area
from .matlab_bridge import sar_paths
from .scene import Terrain, buildings_in, load_scene
from .views import footprint

TIER_NAMES = {2: "mid", 4: "low", 8: "vlow"}     # names the pipeline gives the LR images (Make_HR_LR_Pairs)
TIER_FACTORS = {v: k for k, v in TIER_NAMES.items()}


def tier_file(factor: int) -> str:
    return f"LR_{TIER_NAMES.get(int(factor), f'x{int(factor)}')}.png"


def lr_files(vdir: Path) -> list[tuple[int, Path]]:
    """(factor, file) of every LR image in a view folder, smallest factor first."""
    out = []
    for p in vdir.glob("LR_*.png"):
        tier = p.stem[3:]
        f = TIER_FACTORS.get(tier)
        if f is None and tier.startswith("x") and tier[1:].isdigit():
            f = int(tier[1:])
        if f:
            out.append((f, p))
    return sorted(out)


def image_roots(area: Area) -> list[tuple[Path, dict]]:
    """Where an area's SAR images are: the app's runs, and views added by hand in Blender."""
    sp = sar_paths(area)
    planned = {}
    if sp["views"].exists():
        planned = {v["name"]: v for v in json.loads(sp["views"].read_text(encoding="utf-8"))["views"]}
    roots = [(sp["root"], planned)]
    blender = config.runs_dir() / area.id / "blender" / "blender_scene"
    if blender.exists():
        roots.append((blender, {}))
    return roots


def _read_index(path: Path) -> list[dict]:
    if not path.exists():
        return []
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def _ground_of(t: Terrain, row: dict) -> tuple[float, float]:
    """The ground point a view looks at, from its aim point (for views not planned by this app)."""
    b = math.radians(float(row["bearing_deg"]))
    i = math.radians(float(row["incidence_deg"]))
    ax, ay = float(row["center_x"]), -float(row["center_z"])
    x, y = ax, ay
    for _ in range(5):                       # the shift depends on the height where it lands
        s = float(t.scene_y(x, y)) * math.tan(i)
        x, y = ax + s * math.sin(b), ay + s * math.cos(b)
    return x, y


def split_areas(area_ids: list[str], ratios=(0.8, 0.1, 0.1)) -> dict:
    """train / val / test for each area, the same every time for the same set of areas."""
    order = sorted(area_ids, key=lambda a: hashlib.sha1(a.encode()).hexdigest())
    n = len(order)
    n_test = round(n * ratios[2]) if n >= 3 else 0
    n_val = round(n * ratios[1]) if n >= 3 else 0
    if n >= 3:
        n_test, n_val = max(1, n_test), max(1, n_val)
    out = {}
    for k, a in enumerate(order):
        out[a] = "test" if k < n_test else ("val" if k < n_test + n_val else "train")
    return out


def export(areas: list[Area], out_dir: Path | None = None, mirror_fix: bool = True, lr_size: str = "aligned",
           ratios=(0.8, 0.1, 0.1), log=print) -> dict:
    """Writes the dataset of every finished view of these areas. lr_size: 'aligned' keeps each LR image
    on the HR pixel grid (as the pipeline makes it); 'native' shrinks it by its factor."""
    stamp = dt.datetime.now().strftime("%Y%m%d_%H%M%S")
    out = Path(out_dir) if out_dir else config.datasets_dir() / f"sar_dataset_{stamp}"
    out.mkdir(parents=True, exist_ok=True)
    splits = split_areas([a.id for a in areas], ratios)
    rows, sources, factors_seen = [], {}, set()

    for area in areas:
        meta = load_scene(area)
        found = [(root, planned, r) for root, planned in image_roots(area)
                 for r in _read_index(root / "dataset_index.csv")]
        if meta is None or not found:
            log(f"  {area.name}: no SAR images yet, left out")
            continue
        t = Terrain(area)
        for s in meta["sources"]:
            sources[s["name"]] = s
        n_area = 0
        for root, planned, r in found:
            if r["status"] != "done":
                continue
            vdir = root / "views" / r["view"]
            hr = vdir / "HR.png"
            if not hr.exists():
                continue
            lrs = lr_files(vdir)
            factors = [f for f, _ in lrs]
            name = r["view"].split("_")[1] if "_" in r["view"] else r["view"]
            v = planned.get(name)
            if v is not None:
                gx, gy, lon, lat, fp = v["ground"]["x"], v["ground"]["y"], v["ground"]["lon"], v["ground"]["lat"], v["footprint"]
                side = v["width_m"]
            else:
                gx, gy = _ground_of(t, r)
                lon, lat = (float(c) for c in t.grid.frame.to_geo(gx, gy))
                side = float(str(r["window_m"]).split("x")[0])
                fp = footprint(t.grid.frame, gx, gy, side, float(r["bearing_deg"]))
            split = splits[area.id]
            source = "blender" if root.name == "blender_scene" else "app"
            pid = f"{area.id}__{r['view']}" + ("_blender" if source == "blender" else "")
            sizes = _write_pair(vdir, out / split, pid, lrs, mirror_fix, lr_size)
            factors_seen.update(factors)
            poly_geo = Polygon(fp)
            in_win = buildings_in(area, poly_geo)
            hs = {"height": 0, "levels": 0, "default": 0}
            for b in in_win:
                hs[b["height_source"]] = hs.get(b["height_source"], 0) + 1
            x_l, y_l = t.grid.frame.to_local([p[0] for p in fp], [p[1] for p in fp])
            lc = t.fractions_in(Polygon(list(zip(x_l, y_l))))
            rows.append({
                "id": pid, "split": split, "area_id": area.id, "place": area.name, "view": r["view"],
                "lat": round(lat, 7), "lon": round(lon, 7),
                "footprint_wkt": poly_geo.wkt,
                "bearing_deg": float(r["bearing_deg"]), "incidence_deg": float(r["incidence_deg"]),
                "window_m": side, "bandwidth_mhz": float(r["bandwidth_mhz"]),
                "hr_resolution_m": float(r["hr_res_m"]) if r["hr_res_m"] not in ("", "NaN") else None,
                "lr_factors": " ".join(str(f) for f in factors),
                "hr_size": f"{sizes['hr'][0]}x{sizes['hr'][1]}",
                "lr_size": " ".join(f"{w}x{h}" for w, h in sizes["lr"]),
                "buildings": len(in_win), "heights_tagged": hs["height"], "heights_from_levels": hs["levels"],
                "heights_default": hs["default"], "landcover": json.dumps(lc),
                "seed": int(float(r["seed"])), "mirror_fixed": mirror_fix, "lr_layout": lr_size, "views_from": source,
                "hr_path": f"{split}/HR/{pid}.png",
                **{f"lr_x{f}_path": f"{split}/LR_x{f}/{pid}.png" for f in factors},
            })
            n_area += 1
        log(f"  {area.name}: {n_area} image pairs ({splits[area.id]})")

    _write_metadata(out, rows)
    info = {"created": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
            "generator": f"Earth Capture {__version__} + TerraBound SAR pipeline (RaySAR)",
            "pairs": len(rows), "areas": len({r["area_id"] for r in rows}),
            "splits": {s: sum(1 for r in rows if r["split"] == s) for s in ("train", "val", "test")},
            "lr_factors": sorted(factors_seen), "lr_layout": lr_size, "mirror_fixed": mirror_fix,
            "sources": list(sources.values())}
    (out / "dataset_info.json").write_text(json.dumps(info, indent=2), encoding="utf-8")
    _write_texts(out, info)
    log(f"Dataset: {len(rows)} image pairs from {info['areas']} areas in {out}")
    return {"dir": str(out), **info}


def _write_pair(vdir: Path, split_dir: Path, pid: str, lrs: list[tuple[int, Path]], mirror_fix: bool,
                lr_size: str) -> dict:
    def load(p):
        im = Image.open(p)
        return im.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if mirror_fix else im

    (split_dir / "HR").mkdir(parents=True, exist_ok=True)
    hr = load(vdir / "HR.png")
    hr.save(split_dir / "HR" / f"{pid}.png", optimize=True)
    lr_sizes = []
    for f, src in lrs:
        im = load(src)
        if lr_size == "native":
            im = im.resize((max(1, im.width // int(f)), max(1, im.height // int(f))), Image.Resampling.LANCZOS)
        d = split_dir / f"LR_x{int(f)}"
        d.mkdir(parents=True, exist_ok=True)
        im.save(d / f"{pid}.png", optimize=True)
        lr_sizes.append(im.size)
    return {"hr": hr.size, "lr": lr_sizes}


def _write_metadata(out: Path, rows: list[dict]):
    with open(out / "metadata.jsonl", "w", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r) + "\n")
    if rows:
        keys = list(dict.fromkeys(k for r in rows for k in r))
        with open(out / "metadata.csv", "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=keys)
            w.writeheader()
            w.writerows(rows)


def _write_texts(out: Path, info: dict):
    src_lines = "\n".join(f"- **{s['name']}** ({s.get('licence', '')}): {s.get('attribution', '')}"
                          for s in info["sources"])
    (out / "ATTRIBUTION.md").write_text(
        "# Attribution\n\nThe scenes behind these images were built from:\n\n" + src_lines +
        "\n\nThe images were simulated with RaySAR (S. Auer, DLR / TU Munich) and the TerraBound SAR pipeline. "
        "Publications using them must cite RaySAR: S. Auer, S. Hinz, R. Bamler (2010), Ray-tracing simulation "
        "techniques for understanding high-resolution SAR images, IEEE TGRS 48(3), 1445-1456, "
        "doi:10.1109/TGRS.2009.2029339.\n", encoding="utf-8")
    (out / "DATA_LICENSE.md").write_text(
        "# Data licence\n\n"
        "- The 3D scenes (OBJ files, building outlines, materials) contain data from OpenStreetMap and are "
        "available under the Open Database Licence (ODbL) 1.0: (c) OpenStreetMap contributors.\n"
        "- Elevation: Copernicus DEM GLO-30 (Copernicus DEM licence; see ATTRIBUTION.md for the required notice). "
        "The European Union and ESA are not liable for any use of it.\n"
        "- Land cover: ESA WorldCover 2021, CC BY 4.0.\n"
        "- The simulated SAR images are offered under CC BY 4.0. Because the scenes they were made from contain "
        "OpenStreetMap data, check the OSMF attribution guidelines before redistributing the images and scenes "
        "together, and keep the ODbL notice with the scenes.\n", encoding="utf-8")
    (out / "README.md").write_text(
        f"# Simulated SAR super-resolution dataset\n\n{info['pairs']} HR/LR image pairs from {info['areas']} "
        f"real-world areas, made with Earth Capture and the TerraBound SAR pipeline on {info['created'][:10]}.\n\n"
        "- `train/`, `val/`, `test/`: split by area, so no place is in two splits.\n"
        "- `HR/<id>.png`: the full-resolution SAR image (8-bit, dB scale, -35 dB floor).\n"
        f"- `LR_x<f>/<id>.png`: the same scene imaged with 1/f of the bandwidth and 1/f of the aperture "
        f"(factors {', '.join(str(f) for f in info['lr_factors'])}); layout: {info['lr_layout']}.\n"
        "- `metadata.csv` / `metadata.jsonl`: one row per pair (location, footprint, radar geometry, land cover, "
        "building counts and how their heights are known).\n\n"
        "See ATTRIBUTION.md and DATA_LICENSE.md before publishing anything made from it.\n", encoding="utf-8")


def finished_areas() -> list[Area]:
    """Every captured area that has SAR images."""
    out = []
    for d in sorted(config.runs_dir().iterdir()):
        sj = d / "scene" / "scene.json"
        if sj.exists() and (any((d / "sar").glob("*/dataset_index.csv"))
                            or (d / "blender" / "blender_scene" / "dataset_index.csv").exists()):
            out.append(Area.from_dict(json.loads(sj.read_text(encoding="utf-8"))["area"]))
    return out


def copy_scene(area: Area, dest: Path):
    """Copies an area's scene files (for sharing the geometry alongside the images)."""
    src = config.runs_dir() / area.id / "scene"
    shutil.copytree(src, dest / area.id, dirs_exist_ok=True)
