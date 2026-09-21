"""Reads the SAR cameras out of a saved .blend file, without opening Blender's interface.

Run as:  blender -b <file.blend> --python sar_blender_export.py -- <handoff folder>

It does what the "Send views to the SAR window" button does: exports the model
and writes sar_views.json into the hand-off folder. SAR_Dataset_GUI runs it when
the Capture button is pressed, so the views can be taken straight from the file
Blender saved (Ctrl+S) with nothing else to click in Blender.
"""
import os
import sys

import bpy

handoff = sys.argv[sys.argv.index("--") + 1]
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import sar_view_picker as A

A.register()
bpy.context.scene.sar_view.out_dir = handoff
result = bpy.ops.sar.send_views()
print("SAR export:", result, "|", bpy.context.scene.sar_view.status)
sys.exit(0 if result == {"FINISHED"} else 1)
