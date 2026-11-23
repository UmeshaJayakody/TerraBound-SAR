# TerraBound SAR

**Paired high- and low-resolution SAR images of real places, for training super-resolution models.**

TerraBound SAR is a final-year project on enhancing low-resolution Synthetic Aperture Radar (SAR) images with a GAN (SRGAN/ESRGAN-style). Supervised training needs pairs of the same scene at high and low resolution, and real ones essentially don't exist publicly: high-resolution SAR archives are mostly restricted or commercial, and no place is imaged at both resolutions under the same conditions.

This project makes those pairs by simulation:
1. Build a 3D scene.
2. Ray-trace the radar echoes with [RaySAR](https://github.com/StefanJAuer/RaySAR).
3. Form the image the way a radar does.
4. Form the low-resolution partners from **less of the same raw radar data**: less bandwidth and a shorter synthetic aperture.

Each pair therefore differs exactly as a real radar's would, and is pixel-aligned by construction.

With **Earth Capture**, the scenes come from anywhere on Earth. Pick places on a map, and the 3D scene of each is built from open data (Copernicus elevation, ESA WorldCover land cover, OpenStreetMap buildings), so a dataset can cover cities, ports, farmland, forests, deserts and mountains worldwide.

![From a place on the map to a SAR super-resolution dataset](docs/images/earth_capture_flow.svg)

## Three ways to use it

| You have | Use | Guide |
|---|---|---|
| Places in mind (or none: it can suggest them) | **Earth Capture**, a map app (Python) | [docs/earth_capture.md](docs/earth_capture.md) |
| Your own 3D models (`.obj`) | **SAR Dataset Studio** (MATLAB) | [docs/obj_workflow.md](docs/obj_workflow.md) |
| A scene and a view you want to place by eye | the **Blender** view picker | [docs/blender.md](docs/blender.md) |

All three end in the same pipeline (`sar_pipeline/`), so the SAR method is identical whichever way a scene is made.

## Quick start

Windows, MATLAB (no toolboxes) and Python 3.10+:

```powershell
powershell -ExecutionPolicy Bypass -File earth_capture\install.ps1
earth_capture\"Earth Capture.bat"
```

Then:
1. Search a place and **Add to queue**.
2. **Make SAR images**.
3. **Export dataset**.

You get `train/val/test` folders of `HR`, `LR_x2`, `LR_x4` and `LR_x8` images, with `metadata.csv` (location, footprint, radar geometry, land cover) and the licence files the data needs. More in [docs/getting_started.md](docs/getting_started.md).

## How the images are made

| Stage | What happens | Code |
|---|---|---|
| Scene | OBJ in metres: ground, buildings, a radar material per surface | `earth_capture/`, or your own model |
| Conversion | POV-Ray scene, cut into small patches so each view loads only what it sees | `sar_pipeline/Scripts/Convert_OBJ_to_POV.m` |
| Ray tracing | Every echo: position, intensity, bounce count (`Contributions.txt`) | RaySAR engine, `Render_POV.m` |
| Raw data | Each scattering cell with a random phase, giving real speckle; simulated phase history | `SAR_Imaging/Synth_PhaseHistory.m` |
| Image formation | Backprojection (Gorham & Moore 2010) | `SAR_Imaging/bpBasic.m` |
| HR / LR pairs | HR from all the data; LR ×2, ×4, ×8 from centred sub-bands and sub-apertures | `SAR_Imaging/Make_HR_LR_Pairs.m` |

The theory, the validation and each stage's GUI are in [docs/pipeline.md](docs/pipeline.md).

## Repository layout

```
earth_capture/     Earth Capture: map app, open-data scene builder, dataset export (Python)
sar_pipeline/      the SAR pipeline: MATLAB scripts, the radar signal chain, RaySAR,
                   the RaySAR engine, the Blender add-on, sample scenes
docs/              documentation
```

Details: [docs/architecture.md](docs/architecture.md).

## Documentation

- [Getting started](docs/getting_started.md)
- [Earth Capture](docs/earth_capture.md)
- [Dataset format](docs/dataset_format.md)
- [The SAR pipeline](docs/pipeline.md): theory, GUIs, validation
- [Your own 3D models](docs/obj_workflow.md)
- [Blender](docs/blender.md)
- [Architecture](docs/architecture.md)
- [Data sources](docs/data_sources.md)
- [Changes made to RaySAR](docs/raysar_modifications.md)
- [References](docs/references.md)

## Limits

- **Physics:** scattering comes from geometric ray tracing with hand-set surface materials. There is no Bragg, volume or polarimetric scattering.
- **Real-world scenes:** terrain from a 30 m elevation model, buildings as flat-roofed blocks, and heights estimated where OpenStreetMap has none (each building's height source is recorded).
- **Speed:** views are rendered one at a time, so a large dataset is an overnight job.

See [docs/earth_capture.md](docs/earth_capture.md#limits).

## Credits

- **RaySAR**, the SAR simulator at the heart of the pipeline, is by **Stefan Auer** (German Aerospace Center, DLR / TU München), and runs on a modified **POV-Ray 3.7**. Both are under the GNU AGPL v3.
- The image formation follows **L. A. Gorham and L. Moore** (AFRL), *SAR image formation toolbox for MATLAB* (2010).
- Real-world scenes use data from **Copernicus DEM** (© DLR e.V., © Airbus Defence and Space GmbH, provided under COPERNICUS by the EU and ESA), **ESA WorldCover** (© ESA WorldCover project) and **OpenStreetMap** (© OpenStreetMap contributors, ODbL).
- The map uses **Leaflet** and **Sentinel-2 cloudless** by EOX.

Full notices: [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [DATA_LICENSE.md](DATA_LICENSE.md). Every paper used: [docs/references.md](docs/references.md).

## Licence and citation

- **Code:** TerraBound SAR's own code is under the [MIT licence](LICENSE). Bundled third-party parts keep their licences ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).
- **Data:** datasets made with it carry the data sources' terms ([DATA_LICENSE.md](DATA_LICENSE.md)).
- **Citation:** see [CITATION.cff](CITATION.cff). Publications using images from this pipeline must also cite RaySAR: S. Auer, S. Hinz, R. Bamler (2010), *Ray-tracing simulation techniques for understanding high-resolution SAR images*, IEEE TGRS 48(3), 1445–1456, doi:[10.1109/TGRS.2009.2029339](https://doi.org/10.1109/TGRS.2009.2029339).
