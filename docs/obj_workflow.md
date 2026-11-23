# Making a dataset from your own 3D models (SAR Dataset Studio)

`SAR_Dataset_GUI` makes many SAR image pairs from one `.obj` model:
- whole-scene images from several sides;
- many partial views from any direction, angle and place, including low side views where walls show.

For real places on the map instead of a model, use [Earth Capture](earth_capture.md). The **Real world (map)...** button at the bottom of this window opens it.

```matlab
cd('path/to/TerraBound-SAR/sar_pipeline')
addpath('Scripts', 'SAR_Imaging');
SAR_Dataset_GUI
```

## The window, step by step

Every setting has a default, so you can click **Next** all the way through. Problems show as a message under the settings.

| Step | What you choose |
|---|---|
| 1 Object | The `.obj` file and where to save. Which way is up and the file's units (both automatic). The object's surface and the ground. The file is read as soon as you choose it, and the window says what it found: size, up direction, units, and any material names in the file. |
| 2 What to create | **Complete set** (recommended), **One full image**, **Views around the object**, **Choose views on a map**, or **Choose views in Blender** (see [blender.md](blender.md)) |
| 3 Views | The directions, angles and windows (below) |
| 4 Radar and images | The resolution (fixed, the same for every object, or automatic from the object's size). The lower-resolution versions (`2 4 8` by default). The speckle seed, the highest bounce level, rays per pixel, the image orientation, which files to keep. |
| 5 Run | A summary, **Start** / **Stop**, progress, a table of views, a preview |
| 6 Results | Every image made, a larger view, and **Download** to a folder or a `.zip`, in training layout or one folder per view |

### Views and windows

A **view** is one image from one direction (bearing) and incidence angle (from straight down: 40° looks fairly from above, 70° and more from the side). A **window** is the part of the scene the view covers.

- **Complete set:** whole-scene views from several sides, plus partial views. These are windows of 40–100 m from random directions, places and angles, 35 % of them low side views (62–80°). Their number can follow the size of the object, so each part is seen about 3 times.
- **One full image**, or **Views around the object:** every combination of a set of directions, angles and window positions.

Random choices are repeatable: the same settings and seed give the same views. **Save settings...** / **Load settings...** keep a set of choices in a `.json` file.

### Object surface and radar materials

The **Object surface** list gives the whole model one radar response:
- concrete buildings;
- metal (ships, vehicles);
- vegetation;
- sand;
- soil;
- your own POV-Ray finish.

If the model's faces have material names (`usemtl` lines), choose **By material name in the file**. Then each face gets the response its name stands for in `Radar_Materials.m`: `concrete`, `metal`, `vegetation`, `grass`, `sand`, `soil`, `land`, `water`, `sea` or `asphalt`. Faces without a known name get concrete. Step 1 lists the names found and how many of them are radar materials.

To prepare a model this way, name its materials after those radar materials in your 3D software before exporting the OBJ.

## What you get

```
<save folder>/<object name>/
    scene/<name>.pov            the converted object
    views/v001_whole_az000_inc40/   HR.png, LR_mid.png, LR_low.png, LR_vlow.png, sar_images.mat
    views/v009_win40_az150_inc72/   the same, for a partial view
    dataset_index.csv           one row per view
    settings.json
```

- At the default fixed resolution (500 MHz, 0.30 m), every image of every object has the same resolution and pixel size. A view that would be more than 2000 px across is left out and reported. Use smaller windows or a coarser resolution for those.
- HR and LR images of a view are pixel-aligned. The LR images come from less radar data, not from blurring (see [pipeline.md](pipeline.md#part-4-the-radar-signal-chain)).
- A stopped run carries on where it stopped, because finished views with the same settings are skipped.

## Any model, any size

- **Any file size:** a 220 MB city of 3.8 million triangles reads in about 16 s.
- **Polygons:** triangles, quads and larger polygons can be mixed.
- **Up axis:** worked out from the shape.
- **Units:** taken from the file's header comment when it gives a believable size, and otherwise judged from the size.
- **Large scenes:** cut into small patches, and each view loads only the patches it can see. A window on a 5.6 km city costs about what a window on a street does, and images are identical with and without this.

## Without the window

```matlab
opts.full_bearings = [0 90 180 270];   % whole scene from four sides ...
opts.full_incidences = [40 65];        % ... at two angles
opts.coverage = 3;                     % partial views: each part seen about 3 times
opts.window_m = [40 100];              % windows of 40 to 100 m
opts.side_fraction = 0.35;             % 35 % of them from a low side angle
opts.bw = 500e6;                       % the same resolution for every object
opts.materials = 'auto';               % optional: radar finish per material name
[index, notes, run] = Make_Multi_Angle_Dataset('object.obj', 'D:/dataset', opts);
```

`help Make_Multi_Angle_Dataset` lists every option. It runs with `matlab -batch`, with no display.

## The sample scenes

`sar_pipeline/Scenes/` holds the scenes this project started from:

| Scene | Made from |
|---|---|
| Castelia, CityBlock1, Desert, Forest, Frigate, MountBlend, Pond, Street | `.obj` models; the models themselves are not in the repository |
| City_01, Urban_01 | procedurally |

`Scripts/Sample_Scenes/` records how each was made, with its exact settings:

```matlab
Convert_Sample_Scene()                                       % lists them
Convert_Sample_Scene('Frigate_01', 'path/to/your/obj files') % or set TERRABOUND_OBJ_DIR
run('Scripts/Sample_Scenes/gen_city01.m')                    % the procedural ones
Run_Reflectivity_Pipeline('Street_01')                       % RaySAR's reflectivity-map route for a scene
```
