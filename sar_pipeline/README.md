# RaySAR SAR Super-Resolution Dataset Pipeline

A self-contained, working pipeline that generates synthetic SAR (Synthetic Aperture Radar) image datasets for training a super-resolution model. Real matched HR/LR SAR image pairs of the same scene don't exist publicly, so this pipeline generates them synthetically: build a 3D scene, ray-trace it into a radar image, then synthetically degrade that image into matching low-resolution versions.

Everything needed to run it is already inside this folder — the RaySAR-adapted ray-tracing engine, its support library, RaySAR's own MATLAB code, and the GUIs written on top of it. The only thing you need to install yourself is MATLAB (no toolboxes required), on Windows.

---

## Part 1 — What happens in each stage, theoretically

Four stages, each one a real, separate program run:

```
STAGE 1            STAGE 2              STAGE 3                  STAGE 4
Build a 3D    -->   Ray-trace it    -->  Turn the radar     -->   Synthetically
scene (.pov)        (pvengine.exe)       signal data into         degrade the HR
                     produces             an HR grayscale          image into
                     Contributions.txt    SAR image (MATLAB)       several LR
                                                                    versions (MATLAB)
```

**Stage 1 — Build a 3D scene.** A `.pov` file is a plain-text description of a 3D scene in POV-Ray's own language: camera, light, ground, and objects (buildings, streets, cars, or an imported real 3D model). Converting a real `.obj` 3D model into one works like this:

1. **Read and parse the geometry.** A `.obj` file is just two plain-text lists: `v x y z` lines (every vertex position) and `f a b c ...` lines (which vertices connect to form each surface).
2. **Triangulate every face.** POV-Ray's mesh format (`mesh2`) only accepts triangles, but `.obj` faces can have 4+ corners (quads, pentagons, etc.) — each such face is fan-triangulated.
3. **Fix the ground height.** The RaySAR engine hard-requires the ground plane at Y≥0 with all geometry above it — go below that and it silently produces zero output, no error at all. The whole model is shifted up so its true minimum Y becomes exactly 0.
4. **Split the mesh into many small chunks** rather than one giant block, mirroring how procedurally-generated scenes are already structured as many small objects.
5. **Write the `.pov` file** — standard camera/light setup (co-located, orthographic, 45° incidence), ground plane at Y=0, then each mesh chunk written out as its own `mesh2 {...}` block.

**Stage 2 — Ray-trace it.** `pvengine.exe` (a modified build of POV-Ray, created for the RaySAR project) reads the `.pov` file and simulates how radar signals would bounce off every surface in the scene — direct hits, ground bounces, double/triple/multi-bounce reflections off corners, all of it. It writes every single signal contribution — its position, intensity, and how many bounces it took — into a plain text file called `Contributions.txt`.

**Stage 3 — Build the HR image.** `Contributions.txt` is just a huge list of numbers, not an image. RaySAR's own `Gen_Refl_Map` function bins all those signal contributions into pixels based on their position, sums up the signal in each pixel, and produces the actual grayscale SAR image — this is the "HR" (high-resolution) ground-truth image.

**Stage 4 — Degrade to LR.** A real low-resolution SAR capture isn't just a shrunk version of a high-resolution one — it's blurrier and has more speckle noise (radar's characteristic grainy texture). This stage takes the HR image and applies: a mild blur, downsampling by some factor, and realistic multiplicative speckle noise (the same statistical model — averaged independent-look exponential noise — that real SAR speckle follows), at several different severity "tiers."

The result of running all four stages once: one `HR.png` and several `LR_<tier>.png` files, pixel-aligned, ready to be a training pair.

**Stage 5 (optional, and more realistic) — form the image the way a radar does.** Stages 3 and 4 above stop at a reflectivity map and then fake the low-resolution version by blurring it. Part 4 of this README adds the radar signal chain that RaySAR leaves out, which produces images with real speckle, real sidelobes, and LR versions made by collecting less radar data instead of blurring.

---

## Part 2 — Setup

1. **Install MATLAB** (Windows). No toolboxes are required — everything here is written to run on a bare install. Check what you have with `ver` at the MATLAB prompt.
2. **Open MATLAB and set the current folder to this repo** (`sar_pipeline`), then put its code folders on the MATLAB path:
   ```matlab
   cd('path/to/sar_pipeline')
   addpath('RaySAR');
   addpath('Scripts');
   ```
3. That's it — POV-Ray does **not** need to be separately installed system-wide. The ray-tracing engine (`pvengine.exe`), its support library, and RaySAR's own MATLAB code are all already bundled inside this folder (`POV_Ray/`, `RaySAR/`).
4. Pick a folder to work out of for a scene (e.g. `Scenes/`) — this is the folder you'll point both GUIs at below.

---

## Part 3 — Running each stage through its GUI

### Stage 1 GUI: OBJ → POV converter

`Scripts/OBJ_to_POV_GUI.m` — pick a `.obj` file and a result folder, click Convert.

```matlab
addpath('RaySAR'); addpath('Scripts');
OBJ_to_POV_GUI
```

1. **Browse...** next to ".obj file" — pick the model to convert.
2. **Browse...** next to "Result folder" — pick (or create) the folder to save the converted scene into.
3. Click **Convert**. The output `.pov` filename is derived from the `.obj` filename (e.g. `desert.obj` → `desert.pov`). Status text reports the finished path, or the error message if conversion fails.

### Stage 2 GUI: rendering the scene

RaySAR's own MATLAB GUI (`RaySAR/Simulation_Data.m`):

```matlab
addpath('RaySAR'); RaySAR
```

1. Set **Object Model** to the folder containing your `.pov` scene.
2. Click **Rendering**, pick the `.pov` file from the dialog that appears, and wait for the "Render complete" popup — this can take a few minutes for large scenes. `Contributions.txt` is written into that same folder.
3. (Optional) **Manual editing** opens a chosen `.pov` file's source directly in the POV-Ray editor, for inspecting or hand-tweaking a scene before rendering.

### Stage 3 GUI: building the HR reflectivity map

Same RaySAR GUI, **2D maps** tab:

1. Click **Load Data** and pick the `Contributions.txt` produced in Stage 2.
2. Set azimuth/range pixel spacing and bounds (or use the Histogram buttons to help pick good values), check **Coherent summation** if wanted.
3. Click **Reflectivity Map**. The HR image and per-bounce-level layers are written out as `.jpg`/`.fig` files.

### Stage 4: degrading to LR

No GUI for this stage — run it directly in MATLAB once you have an HR image path:

```matlab
addpath('Scripts');
tiers(1) = struct('name','mid',  'scale',2, 'looks',4, 'blur_sigma',0.6);
tiers(2) = struct('name','low',  'scale',4, 'looks',2, 'blur_sigma',1.2);
tiers(3) = struct('name','vlow', 'scale',8, 'looks',1, 'blur_sigma',2.0);
Degrade_To_LR('path/to/HR_image.jpg', 'path/to/output_folder', tiers);
```

Each `tiers` entry is one severity level: `scale` is the downsampling factor, `looks` controls how noisy the speckle is (1 look is the noisiest, most realistic single-look SAR speckle), `blur_sigma` is how much blur to apply before downsampling.

### Stage 5 GUI: realistic SAR image (radar signal chain)

The **Realistic SAR image** panel on the right of the same **2D maps** window forms a real SAR image from the data loaded with **Load data**, instead of the reflectivity map above. It is the GUI for Part 4 below, and it produces the HR image and the LR images together, so it replaces Stage 4 for these images.

1. **Load data** with the `Contributions.txt` from Stage 2, as in Stage 3. Nothing else in the window needs to be filled in.
2. Set the panel:
   - **Bandwidth [MHz]** sets the HR resolution, c / (2 x bandwidth): 500 MHz gives 0.30 m. The panel shows the resolution it gives.
   - **Lower-resolution factors** are how many times coarser each LR image is. `2 4 8` gives the `mid`, `low` and `vlow` images; any other factor is named `x<factor>`. Leave it empty for the HR image only.
   - **Speckle seed**: the same seed gives the same speckle, a different one gives another realisation of the same scene.
   - **Output folder**: empty means a `SAR_Results` folder inside the Object Model folder. **Browse...** picks another. If it already holds SAR images you are asked before they are replaced.
3. Click **Create SAR images**. The status box reports progress, and when it finishes a window shows the HR and LR images side by side. `Street_01` takes about a minute; a much larger scene or a wider bandwidth takes longer, and you are shown an estimate and asked to confirm before a run longer than a minute and a half.

The panel also follows two settings from the rest of the window: **Range Coordinate: Top Down** decides how the PNGs are oriented (the same way RaySAR orients its own maps), and **Bounce level to be displayed** limits which bounce levels go into the image. The image is formed in the slant plane whichever geometry is chosen.

The panel writes `HR.png`, one `LR_<name>.png` per factor and `sar_images.mat` (the complex images, which keep the phase) to the output folder.

---

## Part 4 — Realistic SAR images: adding the radar signal chain

### Why this stage exists

RaySAR is a **reflectivity map** simulator, not a radar simulator. It traces rays, records where the energy lands in the azimuth-range plane, and bins it into pixels. It never transmits a waveform, never flies a synthetic aperture, never produces raw data, and never runs an image formation algorithm. It goes straight from geometry to picture.

It helps to separate two layers of physics:

| Layer | What it decides | RaySAR |
|---|---|---|
| Scattering | how much energy returns, and from where | approximated geometrically, and validated against real urban SAR |
| Imaging | how the radar turns those returns into a picture | **absent** |

Everything that makes RaySAR output look unlike real SAR (too clean, no speckle, no star-shaped bright points) belongs to the second layer. This stage supplies it, following Gorham and Moore, *SAR image formation toolbox for MATLAB*, SPIE Vol. 7699 (2010).

### What is taken from that paper

| From the paper | Used for |
|---|---|
| Eq. (5) signal model | simulating what the receiver measures from each scatterer |
| Eqs. (4), (6) differential range | geometry of each pulse, motion compensated to the scene centre |
| Eq. (7), (9) alias-free scene size | checking the scene fits the collection, warns if not |
| Eq. (8) range resolution, c/2B | sets how fine the image is in range |
| Eq. (10) cross-range resolution, lambda/2*theta_a | sets how fine the image is in azimuth |
| Eqs. (20), (21) range profile via `ifft` | fast image formation |
| Eq. (22) image as a sum over pulses | the backprojection itself |
| Appendix A.1, A.2 | `mfBasic.m` and `bpBasic.m`, used as published |

### The chain

```
RaySAR ray tracing  ->  Contributions.txt         (Stage 2, unchanged)
contributions       ->  point scatterers          Contributions_To_Scatterers.m
scatterers          ->  raw radar data            Synth_PhaseHistory.m   (Eq. 5)
raw data            ->  focused image             bpBasic.m              (Eqs. 21, 22)
less raw data       ->  genuinely coarser images  Make_HR_LR_Pairs.m
```

Two design points matter:

- **Amplitude comes from RaySAR, phase does not.** RaySAR folds the propagation phase into its coherent sum because it has no propagation model. Here the forward model derives that phase from the geometry, so reusing RaySAR's would count it twice. Each cell instead gets a random phase, the standard model of a surface that is rough at the wavelength scale. That phase diversity is what produces speckle, rather than noise multiplied on afterwards.
- **LR images are formed from less data, not by blurring.** The HR image uses the full bandwidth and the full aperture. Each LR image is formed from a centred subset of the same raw data: half the bandwidth and half the aperture gives twice the resolution cell in both directions. The point spread function broadens correctly, the sidelobes move, and the speckle changes on its own. Every image is formed on the same pixel grid, so pairs are aligned by construction.

### Running it

```matlab
cd('SAR_Imaging')
run_street01_sar          % uses Scenes/Contributions.txt from Stage 2
```

The same chain is available from the RaySAR GUI (Stage 5 above), and both call `SAR_Imaging/Run_SAR_From_Contributions.m`.

Output lands in `SAR_Imaging/results/Street_01/`: `HR.png` plus one `LR_<tier>.png` per tier. On the Street_01 scene the whole stage takes about a minute.

### Validation

| Test | Result |
|---|---|
| `test_paper_fig1.m` reproduces the paper's Figure 1 | peaks land exactly on the three targets; measured resolution 0.249 m range and 0.295 m cross-range against 0.250 and 0.286 predicted by Eqs. (8) and (10) |
| matched filter vs backprojection, two independent algorithms | magnitude correlation 1.0000 |
| `test_forward_model.m`, fast model vs the exact Eq. (5) sum | 0.26 percent relative difference, correlation 0.999997 |
| Street_01 resolution tiers actually achieved | 0.30, 0.60, 1.20, 2.39 m, halving as the equations require |

### What this does not fix

Only the imaging layer changes. Scattering amplitudes still come from RaySAR's geometric ray tracing, so there is still no frequency-dependent or material-dependent scattering, no Bragg scattering (a sea surface remains unrealistic), no volume scattering (a forest remains unrealistic), and no polarimetry. The honest description of this work is that RaySAR supplies validated scattering geometry, and this stage adds the SAR signal chain it omits.


---

## Part 5 — One object, many image pairs (SAR Dataset Studio)

Parts 1 to 4 make one image pair from one scene. This part makes **many** from one `.obj` file: whole-scene images from several sides, and many partial views, including side views from a low angle, from any direction and place. A bigger object gets more of them. It needs nothing but this folder and MATLAB.

```matlab
addpath('Scripts'); addpath('SAR_Imaging');
SAR_Dataset_GUI
```

### The window, step by step

Every step has a plain-language explanation on screen and a default for every setting, so you can click **Next** all the way through. Problems are shown as a message under the settings; nothing pops up, and the ray tracer's own windows stay hidden.

| Step | What you choose |
|---|---|
| 1 Object | the `.obj` file; the folder to save in; which way is up and what units the file uses (both automatic, see *Any object, any size* below); the object's surface and the ground (presets from the scenes already made, or your own POV-Ray finish). The window reads the file as soon as you choose it and says what it found: size, up direction, units |
| 2 What to create | **Complete set** (recommended), **One full image**, **Views around the object**, **Choose views on a map**, or **Choose views in Blender** (see Part 6) |
| 3 Views | see below |
| 4 Radar and images | resolution (fixed, the same for every object, or automatic from the object's size); the lower-resolution versions (`2 4 8` = 2x, 4x and 8x coarser, or none); speckle seed; highest bounce level; rays per image pixel; image orientation; whether to keep the complex images and the ray tracer's files; whether to redo finished views |
| 5 Run | a summary, **Start** and **Stop**, a progress bar, a table of views, and a preview of the HR and lower-resolution images of any view |
| 6 Results | every image that was made, a larger view of any of them, and **Download** to any folder or `.zip` file you choose |

A **view** is one image seen from one direction (bearing) and one incidence angle, the angle from straight down: 40 looks fairly from above, 70 or more looks from the side, with long shadows and walls showing. A **window** is the part of the scene it covers: the whole object, or a piece of it placed anywhere over the object. Settings for step 3:

- **Complete set**: whole-scene views from several sides (4 directions is one from each side) at one or more angles, plus many partial views. Partial views are windows of a size in metres (40 to 100 by default), from random directions, places and angles. A share of them, 35 % by default, are **side views** taken from a low angle (62 to 80 degrees), and the rest look from above (25 to 60 degrees). How many partial views there are can be **automatic**: enough that each part of the object is seen about 3 times, so a large object gets more views than a small one, or a fixed number.
- **One full image**: one direction and one incidence angle, for the whole object.
- **Views around the object**: a number of evenly spaced directions, one or more incidence angles, a window size, and windows per side (2 places windows at 2 x 2 spots over the object). Every combination is made, so 8 directions at 3 angles is 24 views.

Random choices are repeatable: the same settings and seed give the same views.

**Save settings...** and **Load settings...** keep a set of choices in a `.json` file. Every run also writes `settings.json` next to its images.

### Viewing and downloading (step 6)

**Every view gets an HR image and three lower-resolution versions by default** (2x, 4x and 8x coarser, from less radar data, not blurring). That is the `2 4 8` in step 4. If you empty that box, only HR images are made, and the window says so in capitals.

When a run finishes, the window opens on **Results** by itself, showing **only the images of that run**, so the many earlier images that a folder collects over time (every Blender capture goes into the same folder, for one) are not mixed in. The **History** button adds the older images, newest first with the date each was made, and **Latest render only** goes back. (A run records which views it handled in `last_run.json`; for a folder made before that, the latest render is taken to be the newest views made one after another.) Downloading gives what is shown. Results shows the images as thumbnails, 12 to a page, with a filter (all views, whole-scene views, partial views, side views of 60 degrees or more, views from above, failed views), and a larger picture of the one you click together with all its lower-resolution versions. **Open another dataset...** loads a dataset made earlier, so you can come back to it any time.

**Download...** copies the images to a place you choose, a folder or one `.zip` file. You choose:

- **Which views**: every view in the list (the filter applies), or only the selected one.
- **Arrange as**: *Training layout*, with folders `HR/`, `LR_mid/`, `LR_low/`, `LR_vlow/` and the same file name in each (`<object>_<view>.png`), which is what paired training wants; or *One folder per view*, as the views were made.
- **Include**: HR images, lower-resolution images, the complex images (`.mat`), and `index.csv` with `settings.json`.

Files with the same names in the chosen place are replaced.

### What you get

```
<save folder>/<object name>/
    scene/<name>.pov            the converted object
    views/v001_whole_az000_inc40/   HR.png, LR_mid.png, LR_low.png, LR_vlow.png, sar_images.mat
    views/v009_win40_az150_inc72/   the same, for a partial view (window 40 %, seen from 72 degrees)
    dataset_index.csv           one row per view: direction, angle, window, size, status, files
    settings.json
```

- With the default **fixed** resolution (500 MHz, 0.30 m), every image of every object has the same resolution and pixel size, so the whole data set is comparable. A smaller window is simply a smaller image. With **automatic**, an object's whole scene comes out about a chosen number of pixels across, and every view of that object shares that resolution.
- **Large objects.** A view whose image would be very large at the chosen resolution (more than 2000 pixels across) is left out and reported, instead of running for hours; use smaller windows or a coarser resolution for those. The window says so in step 3 before you start, for the whole-scene views of a large object at a fixed resolution. Very tall low-angle views are long because the ground stretches out along the range.
- HR and LR images of a view are pixel aligned. LR images come from less radar data (Part 4), not from blurring.
- Each view gets its own speckle seed (the seed, then seed + 1, and so on).
- A run that is stopped, or interrupted, carries on where it stopped: views already done with the same settings are skipped. Failed views are listed in `dataset_index.csv` with the reason, and are retried by starting again.

### Running it without the window

The window only sets options for one function, which is what a server or a batch job should call:

```matlab
opts.full_bearings = [0 90 180 270];   % whole scene from the four sides ...
opts.full_incidences = [40 65];        % ... at two angles
opts.coverage = 3;                     % partial views: each part seen about 3 times
opts.window_m = [40 100];              % windows of 40 to 100 m
opts.side_fraction = 0.35;             % 35 % of them look from a low side angle
opts.bw = 500e6;                       % the same resolution on every object
[index, notes, run] = Make_Multi_Angle_Dataset('object.obj', 'D:/dataset', opts);
```

Units and the up axis are automatic (`opts.scale = 'auto'`, `opts.up_axis = 'auto'`); give `opts.scale = 0.0254` or `opts.up_axis = 'z'` to set them yourself. `Analyze_OBJ('object.obj')` and `Resolve_Model` report what was found without making anything.

`index` is the whole dataset folder, including views from earlier runs into the same folder; `run` is only the views this call made (or found already made), so it is the one to check for success. `help Make_Multi_Angle_Dataset` lists every option. It runs from `matlab -batch` with no display; this is how it was tested.

### Any object, any size

The software works out what an `.obj` file is, so a file from any program can be used as it is. Nothing has to be prepared or converted first.

- **Any file size.** The file is read in blocks, so its text is never held in memory whole (only the vertex and triangle numbers are). Triangles, quads and larger polygons can be mixed, with or without texture and normal indices; larger polygons are cut into triangles. A 40 MB city (485 000 triangles) is read in about 6 s, and a 220 MB one of 3.8 million triangles in about 16 s.
- **Which way is up.** A scene that is much wider than tall (a city, terrain, the sea) has its short axis up. Otherwise the axis that most of the surface faces is taken as up, and Y when that is unclear. Choose Y or Z yourself if it is wrong; the window says how it decided.
- **Units.** Files do not say, except in a comment at the top when they are lucky (`File units = inches` from SketchUp, `centimeters` from Maya). That comment is used if it gives a believable size. If not, the first of metres, centimetres, millimetres, inches and feet that gives a believable size is used (a few metres to some tens of kilometres, and not taller than the highest mountain). A model too small for a radar is enlarged by a power of ten. Everything is then in metres, and the window shows the size it made. Set the units yourself if a guess is wrong. Castelia City, for example, says inches in its header, which makes it 6.9 km by 8.7 km and 697 m tall; taken as metres it would be 343 km across.
- **Only what is in view is loaded.** A large scene is cut into small pieces, ordered by where they are, and each view loads only the pieces that can affect it: those in the straight tube of space between the window and the sensor, widened by a margin for bounced rays. A window on a 5.6 km city of 3.8 million triangles costs about what a window on a street does. Images are identical with and without this (checked pixel for pixel on the street scene).
- **Views go where the object has something to show.** Random windows are placed on ground with structure on it (walls and steep slopes), not on bare ground or open water, and the number of views follows the amount of such ground, not the size of the bounding box. Castelia City covers 60 km² in its box, and about 2 km² of it has structure on it.
- **Very large scenes at fixed resolution.** At 0.30 m, a scene of kilometres does not fit in one image, so its whole-scene views are left out and its windows are made; choose **Automatic** resolution in step 4 to get the whole scene at a coarser resolution (Castelia City: 32 m, about 500 pixels across, in under a minute).
- If the converted scene was made with different choices (units, up, surface) or from an older version of the software, it is converted again, and the views made from it are made again.

### Things worth knowing

- **Ray tracer windows and the "Could not load internal editor" box.** The engine is the GUI build of POV-Ray, which asks that question at the start of every run because this build has no editor component. `Render_POV.m` turns the engine's *Use Editor* setting off (`UseEditors=0` in `pvengine.ini`, in your POV-Ray documents folder, before every render) and hides the engine's own windows while it works. The RaySAR GUI's **Rendering** button uses the same code.
- **Colours.** RaySAR's original windows were designed for the light Windows theme and were partly unreadable under a dark MATLAB theme. They now switch themselves to the light theme (MATLAB R2025a or later; earlier releases need nothing). The new window follows your MATLAB theme.
- **Windows and stray rays.** Each image is sized from the single-bounce returns, which fill the sensor's frame exactly. A few multi-bounce rays can land hundreds of metres away; sizing from all rays used to stretch small windows into mostly black images.
- **One render at a time.** The engine allows one copy to run at a time, so views are made one after another. Small windows take about 10 to 20 s each and a whole scene about a minute.
- **Server use.** The engine (`pvengine.exe`) is a Windows program, and MATLAB needs a full licence. A Windows machine running `matlab -batch` works as it is. A Linux server needs a Linux build of the RaySAR engine, or Wine, and either MATLAB or a port of `SAR_Imaging`.


---

## Part 6 — Choosing views by eye: on a map, or in Blender

Instead of typing angles, you can choose each SAR image by looking at the object. There are two ways, both inside `SAR_Dataset_GUI` (step 2, pick the mode). Neither runs anything in the background: everything happens when you press a button.

### On a map (no other program needed)

Step 3 shows the object from above, north up. **Click** to put the window there, choose the direction, angle and size, and see the exact ground the picture will cover (the blue frame), with a triangle for where the radar sits. Set **A click sets** to *Where the radar sits* and a click chooses the direction instead. **Add this view** keeps it (orange on the map, listed below); do this as many times as you like.

### In Blender

Blender is optional, and needed only for this mode. It is found automatically if it is installed (a copy is in `D:\Apps\Blender` on this machine).

1. In the window, choose **Choose views in Blender** (step 2). In step 3 click **Open Blender**. Blender opens on a top view of your object, with a **yellow box** on it.
2. The yellow box is the window. Click it, then `G` moves it, `R` turns it (the small triangle is the side the radar is on) and `S` resizes it. The look **Angle** is a slider in the **SAR views** panel, which sits under the Transform box in the sidebar (press `N` if it is hidden). The panel shows the box's direction, angle, window size, centre and the size the image will be. Add more boxes with **Add the yellow window box**.
3. Back in the window click **Capture**. There is **nothing to save or send**: when Blender is opened from the window, it keeps a small file (`sar_live.json`) up to date whenever the scene changes, so Capture takes the boxes exactly where they are now. If *Make the images right away* is ticked, it then makes the images and opens **Results**. (This uses a Blender event handler that runs only when something changes, not a timer.) A box that is far too big is reported instead, with the size to use.

You can also press **Capture** inside Blender (SAR views panel). That makes the image of the selected camera (or of every SAR camera if none is selected) and shows it; Blender waits while MATLAB works, about a minute.

To use the add-on on its own: **Edit > Preferences > Add-ons > Install...** and choose `Blender/sar_view_picker.py`.

### How a box or a camera becomes a SAR view

A yellow box: its centre is the centre of the window; the side its triangle points to (its own +Y axis) is where the radar sits; its width across is the window width; its length along that direction is the length of ground the view covers; the Angle slider is the look angle. A window has to be small enough for the radar's resolution (a 0.30 m resolution allows about 300 m across): the panel shows the image size, and a box that is far too big is refused with the reason.

For people who prefer cameras, an orthographic camera named `SAR...` works too:

| The camera | The SAR view |
|---|---|
| where its viewing line meets the ground (the lowest point of the model) | the **centre** of the window |
| the angle between its viewing direction and straight down | the **incidence angle** (10 to 85 degrees) |
| which side it looks from | the **direction**: 0 is the radar on the +Y side looking towards -Y, 90 on the +X side, 180 on the -Y side, 270 on the -X side |
| its orthographic frame: Ortho Scale is the larger side, the render resolution's shape gives the other | the **window**, in metres |

Roll and lens shift are ignored, because a radar frame always has its azimuth axis level. A camera that looks up or level, or at less than 10 or more than 85 degrees from straight down, is reported in the panel instead of being used.

Like every image this pipeline makes, the SAR image has the radar's near side at the top, and the model is treated as a left-handed scene, so the picture is the left-right mirror of what the Blender camera shows. The position, direction and angle you choose are exactly what is used.

The images are written like any other dataset: `<Save images in>/blender_scene/views/v001_<camera name>_az..._inc.../`. Views already done with the same settings are skipped, so adding a camera only makes the new one; if you change the model, everything is made again.

### Without the window

The add-on writes a plain views file and calls `Make_SAR_From_Blender`, so the same can be done by hand:

```matlab
Make_SAR_From_Blender('D:/sar_out/sar_views.json')
```

The file holds `obj` (the model, exported with Blender's default OBJ axes), `out_folder`, `bandwidth_mhz`, `factors`, and a list of `views`, each with `name`, `bearing_deg`, `incidence_deg`, `center_x`, `center_z`, `width_m` and `height_m`. `help Make_SAR_From_Blender` describes it.

### What has been tested

- **The geometry**: `python Blender/sar_view_picker.py --selftest` (cameras to views and back, agreement with the sensor position used by the MATLAB side, the four compass cases).
- **In real Blender 5.2.2**: the add-on's buttons (add camera, Send views, Capture, Show) and its panel, with Blender's own camera maths giving the view that was asked for; the window's **Open Blender** (the object loads, a camera is added) and the views it brings back; and the whole MATLAB side, including skipping finished views and converting again when the model changes.
- **The map picker**: clicks give the right centre and direction, and the views run through the normal pipeline.
- **Capture reading the saved Blender file** was added last and has been checked in pieces, not yet end to end by hand; if it reports a problem, click **Send views to the SAR window** in Blender and Capture again.
