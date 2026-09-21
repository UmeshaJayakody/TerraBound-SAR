"""SAR View Picker: choose SAR views in Blender, get the SAR images.

The easy way: click "Add the yellow window box". When Blender is opened by the SAR window, the
window sees where the box is at all times: there is nothing to save or send. A yellow box lies on the ground: it
IS the window. Click it, press G to move it, R to turn it (the little triangle marks the
side the radar is on), S to resize it, and set the look Angle in the SAR panel.

The other way, for people who like cameras: you place orthographic cameras in Blender.
Each camera whose name starts with "SAR" is one SAR image: where it looks from (direction and angle), what it looks
at (the position), and how much it covers (the size of its frame). Press "Capture"
and the model and the camera are handed to MATLAB, which makes the HR image and
its lower-resolution versions, and the pictures are loaded back into Blender.
Blender waits while MATLAB works (about a minute); there is no background timer.

Install: Blender > Edit > Preferences > Add-ons > Install..., choose this file,
tick "SAR View Picker". The panel is in the 3D viewport sidebar (press N), tab SAR.
Or run it from Blender's Text Editor with Run Script.

How a camera becomes a SAR view (all in Blender's own units, taken as metres):
  * The camera looks along its own -Z, as always. The point where that line meets
    the ground (the lowest point of the model) is the CENTRE of the window.
  * INCIDENCE is the angle between the viewing direction and straight down.
  * DIRECTION (bearing) is where the radar sits: 0 is on the +Y side of the
    window looking towards -Y, 90 is on the +X side, 180 on the -Y side.
  * The WINDOW is the camera's orthographic frame: Ortho Scale is its larger side,
    and the render resolution's shape gives the other side.
  * Roll, and lens shift, are ignored: a radar frame always has its azimuth
    axis level.
The model is exported with Blender's default OBJ axes (forward -Z, up Y) and the
SAR pipeline uses those coordinates as they are. It treats them as a
left-handed scene, as it does for every model, so the SAR image is the
left-right mirror of what a Blender camera would show. Like any radar image, its
top is the near side (closest to the radar).

The geometry (view_from_camera, camera_from_view) needs no Blender and is
checked by:  python sar_view_picker.py --selftest
"""

bl_info = {
    "name": "SAR View Picker",
    "author": "FYP SAR pipeline",
    "version": (1, 0, 0),
    "blender": (3, 3, 0),
    "location": "3D Viewport > Sidebar (N) > SAR",
    "description": "Choose SAR views with orthographic cameras and make the SAR images with MATLAB",
    "category": "Import-Export",
}

import json
import math
import os
import random
import re
import subprocess
import sys

try:
    import bpy
    from mathutils import Vector
except ImportError:          # outside Blender: only the geometry and the self-test are available
    bpy = None
    Vector = None

MIN_INCIDENCE = 10.0         # what the SAR pipeline supports, degrees from straight down
MAX_INCIDENCE = 85.0
MAX_PX = 2000                # the pipeline leaves out views whose image would be wider than this


# ---------------------------------------------------------------------------------
# Geometry. Plain numbers only, so it can be tested without Blender.
# Blender world: X east, Y north, Z up. Model (OBJ) coordinates after export with
# forward -Z, up Y: x = X, y = Z, z = -Y.
# ---------------------------------------------------------------------------------

def view_from_camera(location, forward, ortho_scale, res_x, res_y, ground_z):
    """The SAR view an orthographic camera stands for.

    location:    camera position in Blender world coordinates
    forward:     the direction it looks in (its -Z axis, in world coordinates)
    ortho_scale: the camera's Ortho Scale (its frame's larger side)
    res_x, res_y: the scene's render resolution (gives the frame's shape)
    ground_z:    height of the ground, the lowest point of the model
    Returns a dict for the views file. Raises ValueError with a plain message.
    """
    fx, fy, fz = forward
    n = math.sqrt(fx * fx + fy * fy + fz * fz)
    if n == 0:
        raise ValueError("The camera has no viewing direction.")
    fx, fy, fz = fx / n, fy / n, fz / n
    if fz >= 0:
        raise ValueError("The camera must look down at the model, not up or level.")
    lx, ly, lz = location
    if lz <= ground_z:
        raise ValueError("The camera is below the ground of the model.")

    incidence = math.degrees(math.acos(-fz))
    if incidence < MIN_INCIDENCE or incidence > MAX_INCIDENCE:
        raise ValueError("The look angle is %.0f degrees from straight down; it must be between %d and %d." %
                         (incidence, MIN_INCIDENCE, MAX_INCIDENCE))

    t = (ground_z - lz) / fz                       # along the view line to the ground
    gx, gy = lx + t * fx, ly + t * fy              # the centre of the window, on the ground
    # The radar sits opposite the horizontal heading. Rounded to 0.0001 degree, because Blender keeps
    # rotations in single precision, and 359.99997 should read as 0, not as 360.
    bearing = round(math.degrees(math.atan2(-fx, -fy)), 4) % 360.0

    if res_x >= res_y:
        width, height = ortho_scale, ortho_scale * res_y / res_x
    else:
        width, height = ortho_scale * res_x / res_y, ortho_scale
    return {
        "bearing_deg": bearing,
        "incidence_deg": incidence,
        "center_x": gx,        # model x
        "center_z": -gy,       # model z
        "width_m": width,
        "height_m": height,
    }


def camera_from_view(view, ground_z, distance=200.0):
    """The camera position and viewing direction for a view; the inverse of
    view_from_camera. Used to place a new camera, and to test the geometry."""
    b = math.radians(view["bearing_deg"])
    i = math.radians(view["incidence_deg"])
    gx, gy = view["center_x"], -view["center_z"]
    off = (distance * math.sin(i) * math.sin(b), distance * math.sin(i) * math.cos(b), distance * math.cos(i))
    location = (gx + off[0], gy + off[1], ground_z + off[2])
    forward = (-off[0] / distance, -off[1] / distance, -off[2] / distance)
    return location, forward


def view_from_window(center_xy, y_axis_xy, width, depth, incidence):
    """The SAR view a yellow window box on the ground stands for.

    center_xy:  the box's centre (X, Y) in Blender world coordinates
    y_axis_xy:  the box's own +Y axis as (X, Y); it points to the side the radar is on
    width:      the box's size across, in metres
    depth:      its size along that axis, the length of ground the view covers
    incidence:  the look angle from straight down, in degrees
    """
    if incidence < MIN_INCIDENCE or incidence > MAX_INCIDENCE:
        raise ValueError("The Angle is %.0f degrees; it must be between %d and %d." % (incidence, MIN_INCIDENCE, MAX_INCIDENCE))
    sx, sy = y_axis_xy
    if math.hypot(sx, sy) == 0:
        raise ValueError("The box has no direction (is it lying flat?).")
    if width <= 0 or depth <= 0:
        raise ValueError("The box has no size.")
    bearing = round(math.degrees(math.atan2(sx, sy)), 4) % 360.0      # the radar is on the +Y side of the box
    return {
        "bearing_deg": bearing,
        "incidence_deg": incidence,
        "center_x": center_xy[0],
        "center_z": -center_xy[1],
        "width_m": width,
        "height_m": depth * math.cos(math.radians(incidence)),       # the depth is the frame's height laid out along the ground
    }


def window_from_view(view):
    """The box (centre X, Y, rotation about Z in radians, width, depth) for a view; the inverse of
    view_from_window."""
    rot = -math.radians(view["bearing_deg"])            # +Y of the box, rotated by rot, is (sin b, cos b)
    depth = view["height_m"] / math.cos(math.radians(view["incidence_deg"]))
    return view["center_x"], -view["center_z"], rot, view["width_m"], depth


def predicted_px(view, bandwidth_mhz):
    """About how many pixels the HR image of a view will be, [columns, rows], at a radar bandwidth.

    Pixels are half a resolution cell (c / 2B), and at a low look angle the ground stretches out along
    the range by about tan(incidence): the same rule the SAR pipeline uses to size a view."""
    pix = 299792458.0 / (2.0 * bandwidth_mhz * 1e6) / 2.0
    w, h = view["width_m"], view["height_m"]
    rows = max(h * math.tan(math.radians(view["incidence_deg"])), h)
    return w / pix, rows / pix


def size_problem(name, view, bandwidth_mhz):
    """A plain sentence if the view's image would be too big, else ''."""
    cols, rows = predicted_px(view, bandwidth_mhz)
    if max(cols, rows) <= MAX_PX:
        return ""
    pix = 299792458.0 / (2.0 * bandwidth_mhz * 1e6) / 2.0
    ok_width = MAX_PX * pix * min(1.0, view["width_m"] / max(view["width_m"], view["height_m"] * max(
        math.tan(math.radians(view["incidence_deg"])), 1.0)))
    return ("%s: its window is %.0f m wide, which would be an image %.0f x %.0f pixels at %.2f m resolution (the limit is %d). "
            "Make the camera's Ortho Scale smaller, about %.0f or less." %
            (name, view["width_m"], cols, rows, 2 * pix, MAX_PX, ok_width))


def make_payload(obj_path, out_dir, bandwidth_mhz, factors, views):
    """What is written to the views file that MATLAB reads."""
    return {
        "format": 1,
        "obj": obj_path,
        "out_folder": out_dir,
        "bandwidth_mhz": bandwidth_mhz,
        "factors": factors,
        "views": views,
    }


def parse_factors(text):
    out = []
    for tok in re.split(r"[,\s]+", text.strip()):
        if tok:
            out.append(float(tok))
    return out


def safe_name(name):
    """The name MATLAB gives the view folder for a camera."""
    return re.sub(r"[^A-Za-z0-9-]+", "-", name)


# ---------------------------------------------------------------------------------
# Self-test, run outside Blender
# ---------------------------------------------------------------------------------

def _selftest():
    rnd = random.Random(1)
    worst = 0.0
    for _ in range(2000):
        view = {"bearing_deg": rnd.uniform(0, 360), "incidence_deg": rnd.uniform(MIN_INCIDENCE + 0.1, MAX_INCIDENCE - 0.1),
                "center_x": rnd.uniform(-90, 90), "center_z": rnd.uniform(-90, 90),
                "width_m": rnd.uniform(10, 200), "height_m": rnd.uniform(10, 200)}
        ground = rnd.uniform(-5, 5)
        loc, fwd = camera_from_view(view, ground, rnd.uniform(50, 400))
        rx, ry = rnd.choice([(1920, 1080), (1080, 1920), (1000, 1000)])
        big = max(view["width_m"], view["height_m"])
        got = view_from_camera(loc, fwd, big, rx, ry, ground)
        db = abs((got["bearing_deg"] - view["bearing_deg"] + 180) % 360 - 180)
        worst = max(worst, db, abs(got["incidence_deg"] - view["incidence_deg"]),
                    abs(got["center_x"] - view["center_x"]), abs(got["center_z"] - view["center_z"]))
    assert worst < 2e-4, "round trip failed by %g" % worst        # bearing is rounded to 0.0001 degree
    print("round trip (2000 random cameras): worst error %.2e" % worst)

    # The same convention as the MATLAB side (Scripts/POV_Header.m): the sensor is at
    #   look_at + dist * [sin(i) sin(b), cos(i), -sin(i) cos(b)]   in model (x, y up, z).
    # In Blender world that is X = x, Y = -z, Z = y.
    worst = 0.0
    for b in range(0, 360, 15):
        for i in (10, 25, 45, 60, 75, 85):
            br, ir = math.radians(b), math.radians(i)
            x, y, z = 200 * math.sin(ir) * math.sin(br), 200 * math.cos(ir), -200 * math.sin(ir) * math.cos(br)
            loc = (x + 7.0, -z - 3.0, y + 1.0)                 # about the ground point (7, -3 in Blender), ground at 1
            fwd = (-x, z, -y)                                  # from the sensor to the ground point
            got = view_from_camera(loc, fwd, 60, 1000, 1000, 1.0)
            worst = max(worst, abs((got["bearing_deg"] - b + 180) % 360 - 180), abs(got["incidence_deg"] - i))
    assert worst < 2e-4, "MATLAB convention mismatch by %g" % worst
    print("matches the MATLAB sensor position formula: worst error %.2e deg" % worst)

    # Plain cases anyone can check by eye
    cases = [
        ("radar on the +Y (north) side, looking south", (0, 100, 100), (0, -1, -1), 0),
        ("radar on the +X (east) side, looking west",   (100, 0, 100), (-1, 0, -1), 90),
        ("radar on the -Y (south) side, looking north", (0, -100, 100), (0, 1, -1), 180),
        ("radar on the -X (west) side, looking east",   (-100, 0, 100), (1, 0, -1), 270),
    ]
    for label, loc, fwd, want in cases:
        got = view_from_camera(loc, fwd, 50, 1920, 1080, 0.0)
        assert abs(got["bearing_deg"] - want) < 1e-9 and abs(got["incidence_deg"] - 45) < 1e-9, label
        print("%-48s bearing %3.0f, incidence 45, centre (%.0f, %.0f), window %.0f x %.1f m" %
              (label, got["bearing_deg"], got["center_x"], got["center_z"], got["width_m"], got["height_m"]))

    worst = 0.0
    for _ in range(2000):
        view = {"bearing_deg": rnd.uniform(0, 360), "incidence_deg": rnd.uniform(MIN_INCIDENCE + 0.1, MAX_INCIDENCE - 0.1),
                "center_x": rnd.uniform(-90, 90), "center_z": rnd.uniform(-90, 90),
                "width_m": rnd.uniform(10, 200), "height_m": rnd.uniform(10, 200)}
        cx, cy, rot, w, d = window_from_view(view)
        y_axis = (-math.sin(rot), math.cos(rot))          # where the box's +Y points after turning it by rot about Z
        got = view_from_window((cx, cy), y_axis, w, d, view["incidence_deg"])
        worst = max(worst, abs((got["bearing_deg"] - view["bearing_deg"] + 180) % 360 - 180),
                    abs(got["height_m"] - view["height_m"]), abs(got["center_z"] - view["center_z"]),
                    abs(got["width_m"] - view["width_m"]))
    assert worst < 2e-4, "yellow box round trip failed by %g" % worst
    print("yellow box round trip (2000 random views): worst error %.2e" % worst)
    b0 = view_from_window((0, 0), (0, 1), 60, 60, 45)          # the box's +Y points north: the radar is north
    b1 = view_from_window((0, 0), (1, 0), 60, 60, 45)          # +Y points east: the radar is east
    assert b0["bearing_deg"] == 0 and b1["bearing_deg"] == 90
    print("yellow box: +Y north -> direction 0, +Y east -> direction 90")

    v = {"width_m": 60.0, "height_m": 45.0, "incidence_deg": 50.0}
    cols, rows = predicted_px(v, 500.0)
    assert abs(cols - 400) < 1 and 300 < rows < 450, (cols, rows)
    assert size_problem("cam", v, 500.0) == ""
    big = {"width_m": 171439.0, "height_m": 128579.0, "incidence_deg": 45.0}
    msg = size_problem("SAR_View", big, 500.0)
    assert msg and "Ortho Scale" in msg
    print("size check: a 60 m window is %.0f x %.0f px (fine); a 171 km window is refused: %s" % (cols, rows, msg[:70]))

    for bad, why in [(((0, 0, 100), (0, 1, 0)), "level"), (((0, 0, 100), (0, 1, 1)), "looking up"),
                     (((0, 0, 100), (0, 0.99, -0.01)), "too flat")]:
        try:
            view_from_camera(bad[0], bad[1], 50, 1000, 1000, 0.0)
            raise AssertionError("no error for a camera that is %s" % why)
        except ValueError as e:
            print("rejected (%s): %s" % (why, e))
    print("self-test passed")


# ---------------------------------------------------------------------------------
# Blender part
# ---------------------------------------------------------------------------------

if bpy is not None:

    _state = {"proc": None, "log": None, "result": None, "out_dir": None}

    def _settings(context):
        return context.scene.sar_view

    def _out_dir(context):
        s = _settings(context)
        if s.out_dir.startswith("//") and not bpy.data.filepath:
            raise RuntimeError("Save the .blend file first, or choose an output folder.")
        return os.path.normpath(bpy.path.abspath(s.out_dir))

    def _is_window(o):
        return o.type == "MESH" and bool(o.get("sar_window"))

    def _windows(context):
        return [o for o in context.scene.objects if _is_window(o)]

    def _meshes(context):
        """The model: visible meshes, except the yellow window boxes."""
        return [o for o in context.view_layer.objects if o.type == "MESH" and o.visible_get() and not _is_window(o)]

    def _ground_z(context):
        """The lowest point of the visible meshes, in world coordinates."""
        low = None
        for o in _meshes(context):
            for c in o.bound_box:
                z = (o.matrix_world @ Vector(c)).z
                low = z if low is None else min(low, z)
        if low is None:
            raise RuntimeError("There is no visible mesh in the scene to make SAR images of.")
        return low

    def _sar_cameras(context):
        return [o for o in context.scene.objects if o.type == "CAMERA" and o.name.startswith("SAR")]

    def _camera_view(context, cam, ground_z):
        if cam.data.type != "ORTHO":
            raise ValueError("Set the camera's Type to Orthographic.")
        r = context.scene.render
        res_x = r.resolution_x * r.resolution_percentage / 100.0
        res_y = r.resolution_y * r.resolution_percentage / 100.0
        forward = cam.matrix_world.to_3x3() @ Vector((0, 0, -1))
        v = view_from_camera(tuple(cam.matrix_world.translation), tuple(forward), cam.data.ortho_scale,
                             res_x, res_y, ground_z)
        v["name"] = cam.name
        return v

    def _export_obj(filepath):
        """Exports the visible meshes with the default OBJ axes (forward -Z, up Y). The yellow
        window boxes are hidden while it runs, so they do not become part of the model."""
        boxes = [(o, o.hide_get()) for o in bpy.context.scene.objects if _is_window(o)]
        for o, _ in boxes:
            o.hide_set(True)
        try:
            if hasattr(bpy.ops.wm, "obj_export"):                      # Blender 3.3 and later
                bpy.ops.wm.obj_export(filepath=filepath, forward_axis="NEGATIVE_Z", up_axis="Y",
                                      export_selected_objects=False, apply_modifiers=True,
                                      export_materials=False, export_uv=False, export_normals=False)
            else:                                                      # older Blender
                bpy.ops.export_scene.obj(filepath=filepath, axis_forward="-Z", axis_up="Y", use_selection=False,
                                         use_mesh_modifiers=True, use_materials=False, use_uvs=False,
                                         use_normals=False)
        finally:
            for o, was_hidden in boxes:
                o.hide_set(was_hidden)

    # ---- the steps, as plain functions so they can be run without pressing buttons ----

    def _window_view(context, o, ground_z):
        m = o.matrix_world.to_3x3()
        ax, ay = m @ Vector((1, 0, 0)), m @ Vector((0, 1, 0))
        return dict(view_from_window((o.matrix_world.translation.x, o.matrix_world.translation.y), (ay.x, ay.y),
                                     ax.length, ay.length, float(o.get("sar_angle", 50.0))), name=o.name)

    def _object_view(context, o, ground_z):
        return _window_view(context, o, ground_z) if _is_window(o) else _camera_view(context, o, ground_z)

    def _view_objects(context):
        """Everything that is a SAR view: the yellow boxes and the SAR cameras."""
        return _windows(context) + _sar_cameras(context)

    def _chosen_cameras(context):
        """The SAR views (boxes or cameras) that are selected, or all of them if none is."""
        objs = _view_objects(context)
        picked = [c for c in objs if c.select_get()]
        return picked or objs

    def collect_views(context, cams=None):
        """The view of each SAR camera (all of them by default). Raises RuntimeError with a plain message."""
        ground = _ground_z(context)
        if cams is None:
            cams = _view_objects(context)
        if not cams:
            raise RuntimeError("There is no SAR view yet. Click 'Add the yellow window box' and put it where you want the image.")
        views, problems = [], []
        for cam in cams:
            try:
                views.append(_object_view(context, cam, ground))
            except ValueError as e:
                problems.append("%s: %s" % (cam.name, e))
        bw = _settings(context).bandwidth_mhz
        for v in views:
            p = size_problem(v["name"], v, bw)
            if p:
                problems.append(p)
        if problems:
            raise RuntimeError("Fix these views first. " + " | ".join(problems))
        return views

    def write_views(context, out_dir, cams=None):
        """Exports the model and writes the views file. Returns (obj_path, json_path, views)."""
        s = _settings(context)
        views = collect_views(context, cams)
        os.makedirs(out_dir, exist_ok=True)
        obj_path = os.path.join(out_dir, "blender_scene.obj")
        _export_obj(obj_path)
        json_path = os.path.join(out_dir, "sar_views.json")
        with open(json_path, "w") as f:
            json.dump(make_payload(obj_path, out_dir, s.bandwidth_mhz, parse_factors(s.factors), views), f, indent=2)
        return obj_path, json_path, views

    def start_matlab(context, json_path, out_dir):
        """Starts MATLAB in the background on a views file."""
        s = _settings(context)
        ws = bpy.path.abspath(s.workspace)
        if not s.workspace or not os.path.isdir(os.path.join(ws, "Scripts")):
            raise RuntimeError("Set 'Project folder' to the RaySAR_Workspace folder (the one containing Scripts).")
        ws = ws.replace("\\", "/").rstrip("/")
        jp = json_path.replace("\\", "/")
        cmd = "addpath('%s/Scripts'); Make_SAR_From_Blender('%s');" % (ws.replace("'", "''"), jp.replace("'", "''"))
        log = open(os.path.join(out_dir, "matlab_log.txt"), "w")
        flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        _state["proc"] = subprocess.Popen([bpy.path.abspath(s.matlab), "-batch", cmd], stdout=log,
                                          stderr=subprocess.STDOUT, creationflags=flags)
        _state["log"] = log
        _state["out_dir"] = out_dir
        _state["result"] = os.path.join(out_dir, "blender_scene", "blender_result.json")

    def load_results(context):
        """Loads the pictures MATLAB made. Returns how many views were loaded."""
        s = _settings(context)
        with open(_state["result"]) as f:
            res = json.load(f)
        loaded = 0
        views = res.get("views", [])
        if isinstance(views, dict):          # MATLAB's JSON writer turns a list of one into the item itself
            views = [views]
        for v in views:
            if v.get("status") != "done":
                continue
            hr = bpy.data.images.load(v["hr"], check_existing=True)
            hr.name = "SAR_%s_HR" % v["camera"]
            loaded += 1
            lr_files = v.get("lr", [])
            if isinstance(lr_files, str):
                lr_files = [lr_files]
            for path in lr_files:
                lr = bpy.data.images.load(path, check_existing=True)
                lr.name = "SAR_%s_%s" % (v["camera"], os.path.splitext(os.path.basename(path))[0])
        s.status = "Done: %d SAR image%s loaded. Click Show to see them." % (loaded, "" if loaded == 1 else "s")
        notes = res.get("notes") or []
        if isinstance(notes, str):
            notes = [notes]
        if notes:
            s.status += " Note: " + " ".join(notes)
        return loaded

    # ---- live hand-off: the SAR window can always see where the boxes are -----------------------------
    #
    # When Blender is opened by the SAR window, the add-on writes the current views to sar_live.json
    # every time the scene changes (moving a box, turning it, changing the Angle...). This is an event
    # handler, not a timer: it runs when something changed and does nothing otherwise. The window's
    # Capture button reads that file, so nothing has to be saved or sent first.

    _live = {"dir": None, "last": None}

    def _live_handler(scene, depsgraph=None):
        d = _live["dir"]
        if not d:
            return
        try:
            ctx = bpy.context
            s = ctx.scene.sar_view
            payload = make_payload(os.path.join(d, "blender_scene.obj"), d, s.bandwidth_mhz, parse_factors(s.factors), [])
            payload["problems"] = []
            try:
                payload["views"] = collect_views(ctx)
            except RuntimeError as e:
                payload["problems"] = [str(e)]
            key = json.dumps([[round(x, 4) if isinstance(x, float) else x for x in v.values()] for v in payload["views"]]
                             + payload["problems"])
            if key == _live["last"]:
                return                                       # nothing about the views changed
            _live["last"] = key
            path = os.path.join(d, "sar_live.json")
            with open(path + ".tmp", "w") as f:
                json.dump(payload, f, indent=2)
            os.replace(path + ".tmp", path)                  # the window never reads a half-written file
        except Exception:
            pass                                             # a handler must never break Blender

    def enable_live(out_dir):
        """Start keeping sar_live.json in out_dir up to date."""
        _live["dir"] = out_dir
        _live["last"] = None
        if _live_handler not in bpy.app.handlers.depsgraph_update_post:
            bpy.app.handlers.depsgraph_update_post.append(_live_handler)
        _live_handler(bpy.context.scene)

    def disable_live():
        _live["dir"] = None
        if _live_handler in bpy.app.handlers.depsgraph_update_post:
            bpy.app.handlers.depsgraph_update_post.remove(_live_handler)

    class SARSettings(bpy.types.PropertyGroup):
        matlab: bpy.props.StringProperty(name="MATLAB", default="matlab", subtype="FILE_PATH",
                                         description="The MATLAB program (just 'matlab' if it is on the PATH)")
        workspace: bpy.props.StringProperty(name="Project folder", default="", subtype="DIR_PATH",
                                            description="The RaySAR_Workspace folder (the one with Scripts and SAR_Imaging)")
        out_dir: bpy.props.StringProperty(name="Save in", default="//sar_out", subtype="DIR_PATH",
                                          description="Where the SAR images and the views file are written")
        bandwidth_mhz: bpy.props.FloatProperty(name="Bandwidth [MHz]", default=500.0, min=10.0, max=5000.0,
                                               description="Sets the resolution: 500 MHz is 0.30 m")
        factors: bpy.props.StringProperty(name="Lower-resolution versions", default="2 4 8",
                                          description="How many times coarser than the HR image, e.g. 2 4 8")
        status: bpy.props.StringProperty(name="Status", default="")

    class SAR_OT_add_window(bpy.types.Operator):
        bl_idname = "sar.add_window"
        bl_label = "Add the yellow window box"
        bl_description = ("Add a yellow box on the ground: it is the window a SAR image will cover. Click it, then G to move it, "
                          "R to turn it (the triangle marks the side the radar is on), S to resize it")

        def execute(self, context):
            try:
                ground = _ground_z(context)
            except RuntimeError as e:
                self.report({"ERROR"}, str(e))
                return {"CANCELLED"}
            pts = [o.matrix_world @ Vector(c) for o in _meshes(context) for c in o.bound_box]
            cx = sum(p.x for p in pts) / len(pts)
            cy = sum(p.y for p in pts) / len(pts)
            size = max(max(p.x for p in pts) - min(p.x for p in pts), max(p.y for p in pts) - min(p.y for p in pts))
            angle = 50.0
            width = max(min(size * 0.5, 100.0), 10.0)               # a window the radar can resolve, whatever the model's size
            depth = width * 0.75 / math.cos(math.radians(angle))
            mesh = bpy.data.meshes.new("SAR_Window")
            # a unit square on the ground, and a small triangle on its +Y edge: the side the radar is on
            mesh.from_pydata([(-0.5, -0.5, 0), (0.5, -0.5, 0), (0.5, 0.5, 0), (-0.5, 0.5, 0),
                              (-0.09, 0.5, 0), (0.09, 0.5, 0), (0.0, 0.66, 0)], [], [(0, 1, 2, 3), (4, 5, 6)])
            mesh.update()
            mat = bpy.data.materials.get("SAR_yellow") or bpy.data.materials.new("SAR_yellow")
            mat.diffuse_color = (1.0, 0.85, 0.0, 0.4)          # yellow, and see-through so the model shows below
            mesh.materials.append(mat)
            o = bpy.data.objects.new("SAR_Window", mesh)
            # Only the box's X and Y matter to the SAR view, so it floats just above the model, where it
            # can be seen from above, instead of being hidden inside it.
            top = max(p.z for p in pts)
            o.location = (cx, cy, top + 0.05 * max(1.0, size / 1000.0))
            o.scale = (width, depth, 1.0)
            o.lock_scale[2] = True
            o.show_wire = True
            o.show_transparent = True
            o["sar_window"] = True
            o["sar_angle"] = angle
            try:
                o.id_properties_ui("sar_angle").update(min=MIN_INCIDENCE, max=MAX_INCIDENCE,
                                                       description="How far from straight down the radar looks. 45 is typical; higher looks from the side")
            except Exception:
                pass
            context.scene.collection.objects.link(o)
            for other in context.selected_objects:
                other.select_set(False)
            o.select_set(True)
            context.view_layer.objects.active = o
            self.report({"INFO"}, "Added %s. Click the yellow box, then G to move it, R to turn it, S to resize it." % o.name)
            return {"FINISHED"}

    class SAR_OT_add_camera(bpy.types.Operator):
        bl_idname = "sar.add_camera"
        bl_label = "Add SAR view camera"
        bl_description = "Add an orthographic camera looking at the middle of the model. Move and rotate it to choose the view"

        def execute(self, context):
            try:
                ground = _ground_z(context)
            except RuntimeError as e:
                self.report({"ERROR"}, str(e))
                return {"CANCELLED"}
            meshes = _meshes(context)
            pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
            cx = sum(p.x for p in pts) / len(pts)
            cy = sum(p.y for p in pts) / len(pts)
            size = max(max(p.x for p in pts) - min(p.x for p in pts), max(p.y for p in pts) - min(p.y for p in pts))
            view = {"bearing_deg": 0.0, "incidence_deg": 45.0, "center_x": cx, "center_z": -cy}
            loc, fwd = camera_from_view(view, ground, max(2 * size, 50.0))
            data = bpy.data.cameras.new("SAR_View")
            data.type = "ORTHO"
            # half the model, but never more than 150 m: a window has to be small enough for the radar's
            # resolution, and a big model would otherwise start with a window kilometres wide
            data.ortho_scale = max(min(size * 0.5, 150.0), 10.0)
            data.clip_end = max(10.0 * size, 1000.0)
            cam = bpy.data.objects.new("SAR_View", data)
            cam.location = loc
            cam.rotation_euler = Vector(fwd).to_track_quat("-Z", "Y").to_euler()
            context.scene.collection.objects.link(cam)
            for o in context.selected_objects:
                o.select_set(False)
            cam.select_set(True)
            context.view_layer.objects.active = cam
            self.report({"INFO"}, "Added %s. Move (G) and rotate (R) it, and change Ortho Scale, to choose the view." % cam.name)
            return {"FINISHED"}

    class SAR_OT_look_through(bpy.types.Operator):
        bl_idname = "sar.look_through"
        bl_label = "Look through"
        bl_description = "See the window this camera covers"
        camera: bpy.props.StringProperty()

        def execute(self, context):
            cam = bpy.data.objects.get(self.camera)
            if cam is None:
                return {"CANCELLED"}
            context.scene.camera = cam
            if context.space_data and context.space_data.type == "VIEW_3D":
                context.space_data.region_3d.view_perspective = "CAMERA"
            return {"FINISHED"}

    class SAR_OT_show_image(bpy.types.Operator):
        bl_idname = "sar.show_image"
        bl_label = "Show"
        bl_description = "Show this SAR image in a new window"
        image: bpy.props.StringProperty()

        def execute(self, context):
            img = bpy.data.images.get(self.image)
            if img is None:
                return {"CANCELLED"}
            try:
                bpy.ops.render.view_show("INVOKE_DEFAULT")
                for area in context.window_manager.windows[-1].screen.areas:
                    if area.type == "IMAGE_EDITOR":
                        area.spaces.active.image = img
            except Exception as e:      # older or unusual set-ups: say where the image is
                self.report({"WARNING"}, "Open an Image Editor and choose %s (%s)" % (img.name, e))
            return {"FINISHED"}

    class SAR_OT_open_folder(bpy.types.Operator):
        bl_idname = "sar.open_folder"
        bl_label = "Open the folder"

        def execute(self, context):
            try:
                path = _out_dir(context)
                if sys.platform.startswith("win"):
                    os.startfile(path)
                elif sys.platform == "darwin":
                    subprocess.Popen(["open", path])
                else:
                    subprocess.Popen(["xdg-open", path])
            except Exception as e:
                self.report({"ERROR"}, str(e))
                return {"CANCELLED"}
            return {"FINISHED"}

    class SAR_OT_send_views(bpy.types.Operator):
        bl_idname = "sar.send_views"
        bl_label = "Send views to the SAR window"
        bl_description = ("Save the model and the SAR cameras where the SAR window (SAR_Dataset_GUI) can pick them up. "
                          "Then go back to that window and click 'Import the views from Blender'")

        def execute(self, context):
            s = _settings(context)
            try:
                obj_path, json_path, views = write_views(context, _out_dir(context))
            except Exception as e:
                s.status = "Error: %s" % e
                self.report({"ERROR"}, str(e))
                return {"CANCELLED"}
            s.status = "Sent %d view%s. Go back to the SAR window and click 'Import the views from Blender'." % (
                len(views), "" if len(views) == 1 else "s")
            self.report({"INFO"}, s.status)
            return {"FINISHED"}

    def run_matlab(context, json_path, out_dir):
        """Runs MATLAB on a views file and waits for it. Raises RuntimeError with what went wrong."""
        start_matlab(context, json_path, out_dir)
        proc = _state["proc"]
        proc.wait()
        _state["log"].close()
        if proc.returncode != 0 or not os.path.isfile(_state["result"]):
            tail = ""
            try:
                with open(os.path.join(out_dir, "matlab_log.txt")) as f:
                    tail = " ".join(f.read().strip().splitlines()[-3:])
            except OSError:
                pass
            raise RuntimeError("MATLAB did not finish: %s" % tail)

    class SAR_OT_capture(bpy.types.Operator):
        bl_idname = "sar.capture"
        bl_label = "Capture"
        bl_description = ("Make the SAR image of the selected SAR camera (or of every SAR camera if none is selected). "
                          "Blender waits while MATLAB works, about a minute")

        def execute(self, context):
            s = _settings(context)
            wm = context.window_manager
            try:
                cams = _chosen_cameras(context)
                out_dir = _out_dir(context)
                obj_path, json_path, views = write_views(context, out_dir, cams)
                s.status = "MATLAB is making %d SAR image%s ..." % (len(views), "" if len(views) == 1 else "s")
                wm.progress_begin(0, 1)
                if context.window:
                    context.window.cursor_modal_set("WAIT")
                try:
                    run_matlab(context, json_path, out_dir)
                finally:
                    wm.progress_end()
                    if context.window:
                        context.window.cursor_modal_restore()
                load_results(context)
            except Exception as e:
                s.status = "Error: %s" % e
                self.report({"ERROR"}, str(e))
                return {"CANCELLED"}
            # show the first picture of the view that was captured
            first = safe_name(views[0]["name"])
            img = "SAR_%s_HR" % first
            if img in bpy.data.images:
                try:
                    bpy.ops.sar.show_image(image=img)
                except Exception:
                    pass
            self.report({"INFO"}, s.status)
            return {"FINISHED"}

    class SAR_PT_panel(bpy.types.Panel):
        bl_label = "SAR views"
        bl_idname = "SAR_PT_panel"
        bl_space_type = "VIEW_3D"
        bl_region_type = "UI"
        bl_category = "Item"          # next to the Transform box, which is where people already look

        def draw(self, context):
            layout = self.layout
            s = _settings(context)

            box = layout.box()
            box.label(text="1. Choose the views", icon="CAMERA_DATA")
            box.operator("sar.add_window", icon="MESH_PLANE")
            box.label(text="Click the yellow box: G moves it, R turns it,")
            box.label(text="S resizes it. The triangle is where the radar sits.")
            box.operator("sar.add_camera", text="Or add a SAR camera (advanced)", icon="ADD")
            try:
                ground = _ground_z(context)
            except RuntimeError as e:
                ground = None
                box.label(text=str(e), icon="ERROR")
            for obj in _view_objects(context):
                row = box.row(align=True)
                row.label(text=obj.name, icon="MESH_PLANE" if _is_window(obj) else "CAMERA_DATA")
                if not _is_window(obj):
                    op = row.operator("sar.look_through", text="", icon="VIEWZOOM")
                    op.camera = obj.name
                elif obj in context.selected_objects:
                    box.prop(obj, '["sar_angle"]', text="Angle")
                if ground is not None:
                    try:
                        v = _object_view(context, obj, ground)
                        box.label(text="  direction %.0f  angle %.0f  window %.0f x %.0f m" %
                                  (v["bearing_deg"], v["incidence_deg"], v["width_m"], v["height_m"]))
                        box.label(text="  centre x %.1f, z %.1f" % (v["center_x"], v["center_z"]))
                        cols, rows = predicted_px(v, s.bandwidth_mhz)
                        if max(cols, rows) > MAX_PX:
                            box.label(text="  TOO BIG: image %.0f x %.0f px. Make it smaller." % (cols, rows), icon="ERROR")
                        else:
                            box.label(text="  image about %.0f x %.0f px" % (cols, rows))
                    except ValueError as e:
                        box.label(text="  " + str(e), icon="ERROR")

            box = layout.box()
            box.label(text="2. Capture", icon="RENDER_STILL")
            box.operator("sar.capture", icon="CAMERA_DATA")
            box.label(text="Makes the SAR image of the selected box or camera.")
            box.operator("sar.send_views", icon="EXPORT")
            box.label(text="Or send the views to the SAR window.")
            if s.status:
                box.label(text=s.status)

            box = layout.box()
            box.label(text="Settings", icon="PREFERENCES")
            box.prop(s, "workspace")
            box.prop(s, "matlab")
            box.prop(s, "out_dir")
            box.prop(s, "bandwidth_mhz")
            box.label(text="  = %.2f m resolution" % (299792458.0 / (2 * s.bandwidth_mhz * 1e6)))
            box.prop(s, "factors")

            box = layout.box()
            box.label(text="Results", icon="IMAGE_DATA")
            names = sorted(i.name for i in bpy.data.images if i.name.startswith("SAR_") and i.name.endswith("_HR"))
            for n in names:
                row = box.row(align=True)
                row.label(text=n)
                op = row.operator("sar.show_image", text="HR")
                op.image = n
                for lr in sorted(i.name for i in bpy.data.images if i.name.startswith(n[:-2] + "LR_")):
                    op = row.operator("sar.show_image", text=lr.split("_LR_")[-1])
                    op.image = lr
            if names:
                box.operator("sar.open_folder", icon="FILE_FOLDER")

    _classes = (SARSettings, SAR_OT_add_window, SAR_OT_add_camera, SAR_OT_look_through, SAR_OT_show_image,
                SAR_OT_open_folder, SAR_OT_send_views, SAR_OT_capture, SAR_PT_panel)

    def register():
        for c in _classes:
            bpy.utils.register_class(c)
        bpy.types.Scene.sar_view = bpy.props.PointerProperty(type=SARSettings)

    def unregister():
        disable_live()
        del bpy.types.Scene.sar_view
        for c in reversed(_classes):
            bpy.utils.unregister_class(c)


if __name__ == "__main__":
    if bpy is None:
        if "--selftest" in sys.argv:
            _selftest()
        else:
            print("Run this file inside Blender, or with --selftest to check the geometry.")
    else:
        register()
