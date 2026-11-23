# Third-party notices

TerraBound SAR's own code is under the MIT licence (see [LICENSE](LICENSE)). The repository also
contains, or uses, the following work by others. Each keeps its own licence.

## Bundled in this repository

### RaySAR 1.2 (MATLAB code)
- **Where:** `sar_pipeline/RaySAR/`
- **Author:** Stefan Auer, Remote Sensing Technology Institute, German Aerospace Center (DLR), developed during his doctoral thesis at TU München.
- **Source:** <https://github.com/StefanJAuer/RaySAR>, release [RaySAR v1.2](https://github.com/StefanJAuer/RaySAR/releases/tag/1.2).
- **Licence:** GNU Affero General Public License v3. The full text, with RaySAR's own notice, is in [`sar_pipeline/LICENSE-RaySAR.txt`](sar_pipeline/LICENSE-RaySAR.txt).
- **Changes made here:** listed file by file in [docs/raysar_modifications.md](docs/raysar_modifications.md), as the AGPL asks.
- **Citation:** RaySAR's licence requires publications that use it to cite one of these:
  - S. Auer (2011), *3D Synthetic Aperture Radar Simulation for Interpreting Complex Urban Reflection Scenarios*, doctoral thesis, Technische Universität München. <http://mediatum.ub.tum.de/doc/1003958/1003958.pdf>
  - S. Auer, S. Hinz, R. Bamler (2010), "Ray-tracing simulation techniques for understanding high-resolution SAR images", *IEEE Transactions on Geoscience and Remote Sensing* 48(3), 1445–1456. doi:[10.1109/TGRS.2009.2029339](https://doi.org/10.1109/TGRS.2009.2029339)

### RaySAR build of POV-Ray 3.7 (the ray-tracing engine)
- **Where:** `sar_pipeline/POV_Ray/RaySAR/pvengine.exe`, with a byte-identical copy at `sar_pipeline/Scenes/pvengine.exe` that RaySAR's "Manual editing" button starts from the scene folder.
- **What it is:** POV-Ray 3.7.0 modified by Stefan Auer to write every radar signal contribution to `Contributions.txt`. POV-Ray is by the Persistence of Vision Raytracer Pty. Ltd. and the POV-Ray Team (<https://www.povray.org>).
- **Licence:** GNU AGPL v3 (text in `sar_pipeline/LICENSE-RaySAR.txt`).
- **Corresponding source:** in the RaySAR v1.2 release package (`RaySAR_1.2.zip` → `POV-Ray/POV-Ray_3.7_Source_Code_for_RaySAR/povray-3.7.0.0_for_raysar-loc_conwriter.zip`) at <https://github.com/StefanJAuer/RaySAR/releases/tag/1.2>. The upstream POV-Ray source is at <https://github.com/POV-Ray/povray>. The binary here is unchanged from that release.

### POV-Ray 3.7 include files
- **Where:** `sar_pipeline/POV_Ray/include/`
- **Licence:** the standard POV-Ray 3.7 scene library, under the Creative Commons Attribution-ShareAlike 3.0 Unported licence (<https://creativecommons.org/licenses/by-sa/3.0/>), as stated in the files' headers. `crystal.ttf` carries its own copyright notice (Red Mountain Corporation, 1995).
- **Used by the pipeline:** only `colors.inc` and `finish.inc`.

### SAR image formation (AFRL)
- **Where:** `sar_pipeline/SAR_Imaging/bpBasic.m` and `mfBasic.m`.
- **What they are:** the backprojection and matched-filter routines of LeRoy A. Gorham (Air Force Research Laboratory), transcribed from L. A. Gorham and L. Moore (2010), "SAR image formation toolbox for MATLAB", *Proc. SPIE* 7699, 769906, doi:[10.1117/12.855375](https://doi.org/10.1117/12.855375). The original attribution headers are kept in the files.

### MathWorks code shipped inside RaySAR
`sar_pipeline/RaySAR/rectpuls.m` ("Copyright 1988-2004 The MathWorks"), plus `ginput_POV.m` and `ginput_Intersect.m` (adapted from MATLAB's `ginput`, "Copyright 1984-2007 The MathWorks"), are part of the RaySAR 1.2 release and are redistributed here unchanged, as part of it.

### Leaflet 1.9.4
- **Where:** `earth_capture/terrabound_earth/web/vendor/leaflet/`
- **What it is:** the map library of the Earth Capture app. © 2010–2023 Volodymyr Agafonkin, © 2010–2011 CloudMade.
- **Licence:** BSD 2-Clause (`LICENSE` in that folder).

### World cities list
`earth_capture/terrabound_earth/data/cities.csv` is a subset (places of 100,000 people or more) of Natural Earth's *Populated Places*, which is in the public domain (<https://www.naturalearthdata.com>).

## Python packages Earth Capture installs (not bundled)
NumPy (BSD), rasterio (BSD 3-Clause; includes GDAL, MIT/X), pyproj (MIT; includes PROJ, MIT), Shapely (BSD 3-Clause; includes GEOS, LGPL 2.1), mapbox-earcut (ISC), Requests (Apache 2.0), Pillow (MIT-CMU), pywebview (BSD 3-Clause) and pytest (MIT).

## Online services and data
Earth Capture downloads open data, and shows map tiles, from these services. Their data licences are in [DATA_LICENSE.md](DATA_LICENSE.md); see [docs/data_sources.md](docs/data_sources.md) for the details.

| Service | Use | Terms |
|---|---|---|
| Copernicus DEM GLO-30 (AWS Open Data; Microsoft Planetary Computer) | Elevation | Copernicus DEM licence |
| ESA WorldCover 2021 v200 (AWS Open Data; Planetary Computer) | Land cover | CC BY 4.0 |
| OpenStreetMap via the Overpass API | Buildings, water, roads | ODbL 1.0; Overpass usage policy |
| Nominatim | Place search | Nominatim usage policy (at most 1 request per second) |
| OpenStreetMap tiles | Street map, for display only | OSM tile usage policy |
| EOX Sentinel-2 cloudless | Satellite map, for display only | CC BY-NC-SA 4.0, non-commercial use |

Google Earth / Google Maps content is **not** used. Its terms forbid exporting it, building 3D models from it, and using it to train, test or validate machine-learning models (Google Maps Platform Terms of Service §3.2.3).
