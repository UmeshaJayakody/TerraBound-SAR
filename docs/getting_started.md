# Getting started

## What you need

| | Needed for | Notes |
|---|---|---|
| Windows 10/11 | everything | the RaySAR engine is a Windows program |
| MATLAB | making SAR images | any recent release; **no toolboxes**; Java is not needed |
| Python 3.10+ | Earth Capture (real places) | from python.org; 3.11 recommended |
| Blender | placing views by hand | optional; tested with 5.2 |
| Internet | Earth Capture, the first time each area is captured | not needed for anything else |

## Real places: Earth Capture

```powershell
git clone https://github.com/UmeshaJayakody/TerraBound-SAR.git
cd TerraBound-SAR
powershell -ExecutionPolicy Bypass -File earth_capture\install.ps1
```

Then double-click `earth_capture\Earth Capture.bat`. To make your first images:

1. Search for a place and click it.
2. **Add to queue**.
3. **Make SAR images**.
4. When the area shows **Done**, **Export dataset**.

The full guide is [earth_capture.md](earth_capture.md).

## Your own 3D models: SAR Dataset Studio

In MATLAB:

```matlab
cd('path/to/TerraBound-SAR/sar_pipeline')
addpath('Scripts', 'SAR_Imaging');
SAR_Dataset_GUI
```

Choose an `.obj` file, then click **Next** through the steps and **Start**. The full guide is [obj_workflow.md](obj_workflow.md).

## One scene, stage by stage (RaySAR's own windows)

```matlab
cd('path/to/TerraBound-SAR/sar_pipeline')
addpath('RaySAR', 'Scripts', 'SAR_Imaging');
RaySAR
```

See [pipeline.md](pipeline.md).

## Checking the installation

```powershell
earth_capture\.venv\Scripts\python.exe -m terrabound_earth doctor     # MATLAB, Blender, data servers
earth_capture\.venv\Scripts\python.exe -m pytest earth_capture\tests  # Earth Capture's tests (offline)
python sar_pipeline\Blender\sar_view_picker.py --selftest             # the Blender add-on's geometry
```

In MATLAB, from `sar_pipeline/SAR_Imaging`: `test_forward_model` and `test_paper_fig1` check the radar signal chain.

## Troubleshooting

- **"MATLAB: not found"** in Earth Capture: set the `TERRABOUND_MATLAB` environment variable to your `matlab.exe`.
- **An area shows "Data unavailable, retry later":** every server for one of the data sources failed. Try again later with **Retry**; areas already downloaded are not affected.
- **A render never finishes:** only one copy of the RaySAR engine can run at a time. Close any open "POV-Ray for Windows" window (also check the taskbar and Task Manager), then run again. Finished views are kept.
- **Images look mirrored compared with the map:** that is the pipeline's raw orientation. The Earth Capture export and gallery flip them back (see [earth_capture.md](earth_capture.md#views-and-orientation)).
