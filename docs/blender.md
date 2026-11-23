# Choosing views in Blender

Instead of typing angles, you can place each SAR image by eye in Blender (optional; tested with Blender 5.2). This works for your own models (from the SAR Dataset GUI) and for real places captured with Earth Capture.

## Opening a scene in Blender

- **Your own model:** in `SAR_Dataset_GUI`, choose **Choose views in Blender** in step 2, then click **Open Blender** in step 3. Blender is found automatically, or set it with **Browse...**.
- **A real place:** in Earth Capture, click **Blender** on an area in the queue, once its scene is built. The ground, buildings, roads and water show in their material colours. Views made here keep each surface's radar material.

Blender opens on a top view of the scene with a **yellow box** on it.

## Placing views

1. **The yellow box is the window.**
   - Click it, then `G` moves it, `R` turns it and `S` resizes it.
   - The small triangle marks the side the radar is on.
   - The look **Angle** is a slider in the **SAR views** panel of the sidebar (press `N` to show it).
   - The panel shows the box's direction, angle, window size, centre and image size.
   - Add more boxes with **Add the yellow window box**.
2. **Make the images:**
   - In the SAR Dataset GUI, click **Capture**. Blender keeps a small file (`sar_live.json`) up to date whenever the scene changes, so Capture takes the boxes exactly where they are now.
   - Or press **Capture** inside Blender. It makes the image of the selected box or camera (or of all of them) and shows it. Blender waits while MATLAB works.

For an Earth Capture area, the images go to `runs/<area>/blender/blender_scene/`, and **Export dataset** includes them, with `views_from = blender` in the metadata.

## How a box or a camera becomes a SAR view

- **A yellow box:**
  - its centre is the centre of the window;
  - the side its triangle points to (its own +Y axis) is where the radar sits;
  - its width is the window width, and its length is the ground the view covers;
  - the Angle slider is the incidence angle.

  At 0.30 m resolution a window can be about 300 m across. Too big a box is refused with the size to use.
- **An orthographic camera named `SAR...`** works too:
  - where its viewing line meets the ground is the window's centre;
  - its angle from straight down is the incidence (10–85°);
  - the side it looks from is the direction (0 = the radar on the +Y side, which is north for an Earth Capture scene, 90 = +X / east);
  - its frame is the window.

  Roll and lens shift are ignored.

The images, like every image the pipeline makes, are the left-right mirror of the Blender view: the scene is right-handed and the engine left-handed. Earth Capture's export flips them back (see [earth_capture.md](earth_capture.md#views-and-orientation)). The position, direction and angle you choose are exactly what is used.

## Without the window

The add-on writes a views file and calls `Make_SAR_From_Blender`:

```matlab
Make_SAR_From_Blender('path/to/sar_views.json')
```

The file holds:
- `obj`: the model, exported with Blender's default OBJ axes;
- `out_folder`, `bandwidth_mhz`, `factors`;
- optionally `materials: "auto"`;
- the `views`, each with `name`, `bearing_deg`, `incidence_deg`, `center_x`, `center_z`, `width_m` and `height_m`.

## Installing the add-on by hand

**Edit > Preferences > Add-ons > Install...** and choose `sar_pipeline/Blender/sar_view_picker.py`. The geometry can be checked without Blender:

```
python sar_pipeline/Blender/sar_view_picker.py --selftest
```
