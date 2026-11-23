# sar_pipeline

The SAR simulation and imaging pipeline of TerraBound SAR. It turns a 3D scene into SAR images: RaySAR ray tracing, then the radar signal chain (raw data, backprojection), then HR images and low-resolution partners formed from less of the same raw data.

```matlab
cd('path/to/TerraBound-SAR/sar_pipeline')
addpath('RaySAR', 'Scripts', 'SAR_Imaging');
SAR_Dataset_GUI     % many image pairs from an .obj model
RaySAR              % RaySAR's own windows, one stage at a time
```

| Folder | What is in it |
|---|---|
| `Scripts/` | Scene conversion (`Convert_OBJ_to_POV`, `Radar_Materials`), views, rendering (`Render_POV`), the dataset driver (`Make_Multi_Angle_Dataset`), the GUIs, the Blender helpers |
| `Scripts/Earth/` | `Run_Earth_Views`, the entry point of Earth Capture (`../earth_capture`) |
| `Scripts/Sample_Scenes/` | How each sample scene was made |
| `SAR_Imaging/` | The radar signal chain (Gorham & Moore 2010) and its tests |
| `RaySAR/` | RaySAR 1.2 by Stefan Auer (DLR), AGPL v3. Changes: `docs/raysar_modifications.md` |
| `POV_Ray/` | The RaySAR build of POV-Ray 3.7 (`pvengine.exe`, AGPL v3) and its include files (CC BY-SA 3.0) |
| `Blender/` | The SAR View Picker add-on |
| `Scenes/`, `Test_Runs/` | Sample scenes, and RaySAR's Box and Step reference scenes |

The documentation is in [`../docs`](../docs):
- [pipeline.md](../docs/pipeline.md): theory, GUIs, validation
- [obj_workflow.md](../docs/obj_workflow.md)
- [blender.md](../docs/blender.md)
- [earth_capture.md](../docs/earth_capture.md)

RaySAR's licence: [LICENSE-RaySAR.txt](LICENSE-RaySAR.txt).
