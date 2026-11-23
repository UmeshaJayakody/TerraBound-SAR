# Changes to RaySAR 1.2

`sar_pipeline/RaySAR/` holds the MATLAB part of RaySAR 1.2 by Stefan Auer (Remote Sensing Technology Institute, German Aerospace Center (DLR)). It comes from the [RaySAR v1.2 release](https://github.com/StefanJAuer/RaySAR/releases/tag/1.2), in `MATLAB_part/MATLAB_code`. RaySAR is licensed under the GNU AGPL v3, and the AGPL asks that modified files say they were changed. This page lists every change this project made to those files in 2026. The comparison ignores line endings.

None of the changes touch how RaySAR computes anything. The reflectivity maps, the elevation and tomography tools and the 3D exports work exactly as in 1.2.

## Summary

| File | Change |
|---|---|
| `Light_Theme.m` | **New.** Puts one of RaySAR's original windows in MATLAB's light theme. On MATLAB R2025a and later, a dark desktop theme otherwise makes the 2011 layouts unreadable. It does nothing on older releases. |
| `RaySAR.m`, `Elevation.m`, `Focused_Pts.m`, `Intersection.m` | 3 lines each: a call to `Light_Theme` when the window opens. |
| `Simulation_Data.m` | **Manual editing** and **Rendering** buttons rewritten (+125 / −13 lines). See below. |
| `Maps.m` | **Realistic SAR image** panel added (+225 lines, nothing removed). See below. |

The `.fig` layout files are unchanged. All other files are identical to RaySAR 1.2. When the workspace folder was renamed to `sar_pipeline`, three comment lines in `Simulation_Data.m` that named the old folder were updated; no code changed.

## `Simulation_Data.m`

In 1.2, both buttons changed into a relative folder (`../POV_Ray/POV_reg` or `../POV_Ray/RaySAR`) and called `system('pvengine.exe')`. That froze MATLAB until POV-Ray closed. It failed silently when a POV-Ray window was already open, and it opened POV-Ray with no scene loaded.

Two local helpers replace those calls:

- **`launch_pvengine`** (Manual editing):
  - Checks first that no POV-Ray window is open.
  - Starts the engine without blocking MATLAB.
  - Opens the chosen `.pov` file straight away with `/EDIT`.
- **`render_headless`** (Rendering):
  - Renders through `Scripts/Render_POV.m`, which runs the engine with its windows hidden and closes it when the render ends.
  - Writes `Contributions.txt` next to the scene.
  - Reports clearly whether the file was produced.

The stock POV-Ray in `POV_Ray/POV_reg` was used only by the old Manual editing call. It is no longer needed and has been removed from the repository.

## `Maps.m`

A **Realistic SAR image** panel is added to the 2D maps window from code; `Maps.fig` is not edited. It runs this project's radar signal chain (`SAR_Imaging/Run_SAR_From_Contributions`) on the contributions loaded with **Load data**:

1. Simulated raw radar data.
2. Backprojection.
3. An HR image, plus lower-resolution images formed from less of the same raw data.

The existing reflectivity-map controls are untouched.

## Citing RaySAR

RaySAR's licence asks every publication that uses it to cite one of these:

- S. Auer (2011). *3D Synthetic Aperture Radar Simulation for Interpreting Complex Urban Reflection Scenarios.* Doctoral thesis, Technische Universität München. <http://mediatum.ub.tum.de/doc/1003958/1003958.pdf>
- S. Auer, S. Hinz, R. Bamler (2010). Ray-tracing simulation techniques for understanding high-resolution SAR images. *IEEE Transactions on Geoscience and Remote Sensing* 48(3), 1445–1456. doi:[10.1109/TGRS.2009.2029339](https://doi.org/10.1109/TGRS.2009.2029339)
