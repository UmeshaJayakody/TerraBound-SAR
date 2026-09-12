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
2. **Open MATLAB and set the current folder to this repo** (`RaySAR_Workspace`), then put its code folders on the MATLAB path:
   ```matlab
   cd('path/to/RaySAR_Workspace')
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
