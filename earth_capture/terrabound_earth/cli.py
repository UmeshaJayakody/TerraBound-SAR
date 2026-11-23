"""Command line: everything the app does, for scripts and large batches.

    python -m terrabound_earth                      open the app (map window)
    python -m terrabound_earth app --browser        the app in the web browser
    python -m terrabound_earth doctor               check MATLAB, Blender and the data servers
    python -m terrabound_earth run --lat 6.9355 --lon 79.843 --size 400 --name "Colombo Fort"
    python -m terrabound_earth batch places.csv     columns: name, lat, lon[, size_m]
    python -m terrabound_earth suggest city --region 79.5 5.9 82 9.9 --n 5
    python -m terrabound_earth queue                show the queue
    python -m terrabound_earth export --lr-size native
"""
from __future__ import annotations

import argparse
import csv
import sys

from . import __version__, config


def _area(args):
    from .aoi import Area
    if args.bbox:
        w, s, e, n = args.bbox
        return Area(w, s, e, n, name=args.name or "Area")
    if args.lat is None or args.lon is None:
        sys.exit("Give --lat and --lon (and --size), or --bbox WEST SOUTH EAST NORTH.")
    return Area.square(args.lat, args.lon, args.size, name=args.name or "Area")


def _run_queue(store, ids, with_sar=True):
    from .worker import Worker
    w = Worker(store)
    w.log = lambda t: print(t)
    w._run(ids, with_sar)


def main(argv=None) -> None:
    p = argparse.ArgumentParser(prog="python -m terrabound_earth", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--version", action="version", version=__version__)
    sub = p.add_subparsers(dest="cmd")

    a = sub.add_parser("app", help="open the app")
    a.add_argument("--browser", action="store_true", help="in the web browser instead of a window")
    a.add_argument("--port", type=int, default=0)

    sub.add_parser("doctor", help="check that everything needed is there")

    for name in ("build", "run"):
        r = sub.add_parser(name, help="build the scene of one area" if name == "build" else
                           "build one area and make its SAR images")
        r.add_argument("--lat", type=float)
        r.add_argument("--lon", type=float)
        r.add_argument("--size", type=float, default=500.0, help="side of the square, m (default 500)")
        r.add_argument("--bbox", type=float, nargs=4, metavar=("WEST", "SOUTH", "EAST", "NORTH"))
        r.add_argument("--name", default="")
        r.add_argument("--views", type=int, help="number of views (random mode)")
        r.add_argument("--window", type=float, help="ground window side, m")
        r.add_argument("--bandwidth", type=float, help="radar bandwidth, MHz (500 = 0.30 m)")

    b = sub.add_parser("batch", help="add many areas from a CSV and make them all")
    b.add_argument("csv")
    b.add_argument("--size", type=float, default=500.0)
    b.add_argument("--prepare-only", action="store_true", help="only download data and build scenes")

    s = sub.add_parser("suggest", help="add suggested places to the queue")
    s.add_argument("kind", choices=["city", "suburb", "coast", "farmland", "forest", "desert", "mountain", "any"])
    s.add_argument("--region", type=float, nargs=4, metavar=("WEST", "SOUTH", "EAST", "NORTH"))
    s.add_argument("--n", type=int, default=5)
    s.add_argument("--size", type=float, default=500.0)
    s.add_argument("--seed", type=int, default=1)

    sub.add_parser("queue", help="show the queue")
    q = sub.add_parser("process", help="prepare and make every area in the queue")
    q.add_argument("--prepare-only", action="store_true")

    e = sub.add_parser("export", help="collect every finished area into a training dataset")
    e.add_argument("--out", help="folder (default: datasets/sar_dataset_<time>)")
    e.add_argument("--lr-size", choices=["aligned", "native"], default="aligned")
    e.add_argument("--no-mirror-fix", action="store_true", help="keep the pipeline's mirrored orientation")

    args = p.parse_args(argv)
    if args.cmd in (None, "app"):
        from .app import main as app_main
        return app_main(getattr(args, "browser", False), getattr(args, "port", 0))

    if args.cmd == "doctor":
        return _doctor()

    from .store import Store
    store = Store()
    if args.cmd in ("build", "run"):
        area = _area(args)
        vs = {k: v for k, v in {"n_views": args.views, "window_m": args.window,
                                "bandwidth_mhz": args.bandwidth}.items() if v is not None}
        if vs:
            problems = store.save_settings(None, vs)
            if problems:
                sys.exit(" ".join(problems))
        it, _ = store.add(area)
        if args.cmd == "build":
            from .scene import build_scene
            build_scene(area, store.scene)
        else:
            _run_queue(store, [it["id"]])
    elif args.cmd == "batch":
        from .aoi import Area
        ids = []
        with open(args.csv, newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                size = float(row.get("size_m") or args.size)
                it, _ = store.add(Area.square(float(row["lat"]), float(row["lon"]), size, name=row.get("name", "")))
                ids.append(it["id"])
        print(f"{len(ids)} areas in the queue.")
        _run_queue(store, ids, with_sar=not args.prepare_only)
    elif args.cmd == "suggest":
        from .suggest import WORLD, suggest
        for area in suggest(args.kind, tuple(args.region) if args.region else WORLD, args.n, args.size, args.seed):
            store.add(area)
    elif args.cmd == "queue":
        for it in store.snapshot():
            print(f"{it['status_text']:<32} {it['views_done']:>3}/{it['views_total']:<3} {it['area']['name']}  ({it['id']})")
    elif args.cmd == "process":
        _run_queue(store, None, with_sar=not args.prepare_only)
    elif args.cmd == "export":
        from .dataset import export, finished_areas
        export(finished_areas(), args.out, mirror_fix=not args.no_mirror_fix, lr_size=args.lr_size)


def _doctor() -> None:
    from .sources.http import url_status
    ok = True
    print(f"Earth Capture {__version__}")
    print(f"  repository      {config.REPO_ROOT}")
    print(f"  SAR pipeline    {config.WORKSPACE}  {'OK' if config.SCRIPTS.exists() else 'MISSING'}")
    m = config.find_matlab()
    print(f"  MATLAB          {m or 'NOT FOUND - install MATLAB or set TERRABOUND_MATLAB'}")
    ok &= bool(m)
    b = config.find_blender()
    print(f"  Blender         {b or 'not found (optional; set BLENDER_PATH)'}")
    print(f"  cache           {config.cache_dir()}")
    print(f"  runs            {config.runs_dir()}")
    checks = {
        "Copernicus DEM (AWS)": "https://copernicus-dem-30m.s3.amazonaws.com/readme.html",
        "ESA WorldCover (AWS)": "https://esa-worldcover.s3.eu-central-1.amazonaws.com/v200/2021/map/ESA_WorldCover_10m_2021_v200_N06E078_Map.tif",
        "Planetary Computer": "https://planetarycomputer.microsoft.com/api/stac/v1/",
        "Nominatim (place search)": "https://nominatim.openstreetmap.org/status",
    }
    for name, url in checks.items():
        st = url_status(url, timeout=20)
        result = "reachable" if 200 <= st < 400 else "not reachable (" + (str(st) if st else "no answer") + ")"
        print(f"  {name:<34}{result}")
    from .sources.http import session
    from .sources.osm import OVERPASS_SERVERS
    any_osm = False
    for url in OVERPASS_SERVERS:            # a tiny real query: mirrors do not all have a status page
        try:
            r = session().post(url, data={"data": "[out:json][timeout:15];node(1);out ids;"}, timeout=30)
            good = r.status_code == 200 and "json" in r.headers.get("content-type", "")
            result = "reachable" if good else f"busy or down (HTTP {r.status_code})"
        except Exception:  # noqa: BLE001
            good, result = False, "not reachable (no answer)"
        any_osm |= good
        print(f"  {'Overpass ' + url.split('/')[2]:<34}{result}")
    if not any_osm:
        print("  No OpenStreetMap server answered just now. New areas will wait; try again later.")
    if not ok:
        sys.exit(1)
