# Data licence

This file is about the **data** TerraBound SAR makes or uses: the real-world 3D scenes Earth Capture
builds, and the SAR images and datasets made from them. The code is covered by [LICENSE](LICENSE)
and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Every dataset Earth Capture exports carries its own copy of these notices (`ATTRIBUTION.md` and
`DATA_LICENSE.md` in the dataset folder).

## What the scenes are made from

| Data | Licence | Notice to keep with anything made from it |
|---|---|---|
| **OpenStreetMap** buildings, water areas, roads | Open Database Licence (ODbL) 1.0 | © OpenStreetMap contributors |
| **Copernicus DEM GLO-30** elevation | Copernicus DEM licence: free reproduction, distribution, adaptation and combination with other data | "produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved". The European Union and ESA accept no liability for any use of the data. |
| **ESA WorldCover 10 m 2021 v200** land cover | CC BY 4.0 | © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium |

## What that means for what you share

- **The 3D scenes** (`runs/<area>/scene/`: the OBJ, MTL, `scene.json` and preview files) contain OpenStreetMap data. They are a *derivative database* under the ODbL: share them under the ODbL, keep the © OpenStreetMap contributors notice, and point to how they were made (this repository).
- **The simulated SAR images** are offered under **CC BY 4.0**, with the attributions above and the RaySAR citation (see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)).
  - Whether images rendered from OSM-based scenes count as *produced works* (attribution only) or as part of a *derivative database* (ODbL) is not settled for machine-learning datasets.
  - The OSMF attribution guidelines (<https://osmfoundation.org/wiki/Licence/Attribution_Guidelines>) treat training data that is a substantial extract of OSM as a derivative database.
  - If you publish a dataset, keep the ODbL notice with it, and check with your institution if in doubt.
- **The map backgrounds** shown in the app (OpenStreetMap tiles, EOX Sentinel-2 cloudless) are for display while choosing areas. They are not downloaded into scenes or datasets.

## Not used

Google Earth and Google Maps content (including Photorealistic 3D Tiles and the Elevation API) is not used anywhere in this project. Its terms forbid exporting it, building 3D models from it, and using it to train, test or validate machine-learning models.
