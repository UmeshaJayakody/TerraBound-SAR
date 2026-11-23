"""Start-up script for Blender when SAR_Dataset_GUI opens it.

Run as:  blender --python sar_blender_startup.py -- <setup.json>

It switches on the SAR View Picker add-on, loads the object (with the axes set
up so its up direction is up in Blender), puts a yellow window box on it, and shows
a top view with the SAR tab ready in the sidebar. The person then moves the box
(or adds more), saves (Ctrl+S), and clicks Capture in the SAR window.
"""
import json
import os
import sys

import bpy

cfg_path = sys.argv[sys.argv.index("--") + 1]
with open(cfg_path) as f:
    cfg = json.load(f)

sys.path.insert(0, cfg["addon_dir"])
import sar_view_picker as A

try:
    A.register()
except Exception:            # already registered
    pass


def write_ready(ok, error=""):
    """Leaves a note next to the setup file saying whether the object loaded, for whoever is watching."""
    meshes = [o for o in bpy.data.objects if o.type == "MESH" and not o.get("sar_window")]
    windows = [o for o in bpy.data.objects if o.get("sar_window")]
    cams = [o for o in bpy.data.objects if o.type == "CAMERA"]
    with open(os.path.join(cfg["out_dir"], "blender_ready.txt"), "w") as f:
        json.dump({"ok": ok, "meshes": len(meshes), "windows": len(windows), "cameras": len(cams), "error": error}, f)


def show_material_colours():
    """The imported materials' colours (from the file's .mtl, e.g. the radar materials of an Earth Capture
    scene: concrete grey, water blue, trees green) as their viewport colours, so the default Solid view
    shows which surface is what."""
    for m in bpy.data.materials:
        try:
            bsdf = m.node_tree.nodes.get("Principled BSDF") if m.use_nodes and m.node_tree else None
            if bsdf is not None:
                c = bsdf.inputs["Base Color"].default_value
                m.diffuse_color = (c[0], c[1], c[2], 1.0)
        except Exception:
            pass                                            # a colour is only a convenience


def setup():
    ctx = bpy.context
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)

    # The file's up direction becomes Blender's up (Z). Most OBJ files are Y up (forward -Z);
    # 3ds Max style files are Z up (forward Y), which needs no conversion at all.
    if cfg.get("up", "y") == "z":
        axes = dict(forward_axis="Y", up_axis="Z")
    else:
        axes = dict(forward_axis="NEGATIVE_Z", up_axis="Y")
    axes["global_scale"] = float(cfg.get("scale", 1.0))     # metres per unit of the file, so it opens at its real size
    try:
        bpy.ops.wm.obj_import(filepath=cfg["obj"], **axes)
    except Exception as e:
        print("SAR: could not import %s: %s" % (cfg["obj"], e))
        write_ready(False, "could not import the object: %s" % e)
        return None

    s = ctx.scene.sar_view
    s.out_dir = cfg["out_dir"]
    s.workspace = cfg.get("workspace", "")
    s.matlab = cfg.get("matlab", "matlab")
    s.bandwidth_mhz = float(cfg.get("bandwidth_mhz", 500.0))
    s.factors = " ".join(str(f) for f in cfg.get("factors", [2, 4, 8]))
    s.materials = str(cfg.get("materials", "") or "")
    show_material_colours()
    ctx.scene.render.resolution_x = 1000      # a 4:3 frame; the camera's Ortho Scale is its width
    ctx.scene.render.resolution_y = 750

    win = ctx.window_manager.windows[0]
    area = next((a for a in win.screen.areas if a.type == "VIEW_3D"), None)
    region = next((r for r in area.regions if r.type == "WINDOW"), None) if area else None
    if area is None:
        return None
    with ctx.temp_override(window=win, area=area, region=region):
        try:
            bpy.ops.sar.add_window()          # the yellow box, on the model, ready to be moved
        except Exception as e:
            print("SAR: could not add the yellow window box: %s" % e)
        area.spaces.active.show_region_ui = True          # the sidebar, where the SAR tab is
        # A top view of the model, so the yellow box can be placed by eye
        from mathutils import Quaternion, Vector
        meshes = [o for o in bpy.data.objects if o.type == "MESH" and not o.get("sar_window")]
        pts = [o.matrix_world @ Vector(c) for o in meshes for c in o.bound_box]
        if pts:
            xs, ys = [p.x for p in pts], [p.y for p in pts]
            r3d = area.spaces.active.region_3d
            r3d.view_perspective = "ORTHO"
            r3d.view_rotation = Quaternion((1.0, 0.0, 0.0, 0.0))          # looking straight down
            r3d.view_location = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, 0.0)
            r3d.view_distance = max(max(xs) - min(xs), max(ys) - min(ys)) * 1.3
    # The model, exported once, and the live hand-off: from now on sar_live.json follows the boxes, so the
    # window's Capture button always sees where they are, with nothing to save or send.
    try:
        A._export_obj(os.path.join(cfg["out_dir"], "blender_scene.obj"), materials=s.materials)
        A.enable_live(cfg["out_dir"])
    except Exception as e:
        print("SAR: could not start the live hand-off: %s" % e)
    # Also save the scene where the window can find it, as a fallback if the live file is missing.
    try:
        bpy.ops.wm.save_as_mainfile(filepath=os.path.join(cfg["out_dir"], "blender_scene.blend"))
    except Exception as e:
        print("SAR: could not save the scene: %s" % e)
    print("SAR: ready. Open the SAR tab in the sidebar (N).")
    write_ready(True)
    return None


setup()      # Blender's window already exists when a --python script runs, so nothing has to wait
