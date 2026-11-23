# Data sources

Earth Capture builds scenes only from open data that may be redistributed and used for machine learning. This page lists each source, how it is used, and the attribution it needs. The licence terms for what you share are in [DATA_LICENSE.md](../DATA_LICENSE.md).

## Elevation: Copernicus DEM GLO-30

- **What:** a global digital *surface* model at 1 arc-second (about 30 m), derived from TanDEM-X. Heights are above the EGM2008 geoid. It is a surface model: tops of buildings and tree canopy, not bare ground. See [earth_capture.md](earth_capture.md#what-it-builds-and-from-what) for how built-up areas are corrected.
- **Read from:**
  - the AWS Open Data registry, `s3://copernicus-dem-30m`, as cloud-optimised GeoTIFFs over HTTPS (<https://registry.opendata.aws/copernicus-dem/>);
  - if AWS cannot be reached, from Microsoft Planetary Computer, collection `cop-dem-glo-30`.
- **Account:** none needed for either.
- **Licence:** the Copernicus DEM licence allows reproduction, distribution, adaptation and combination with other data, free of charge.
- **Attribution:**
  > produced using Copernicus WorldDEM-30 © DLR e.V. 2010-2014 and © Airbus Defence and Space GmbH 2014-2018 provided under COPERNICUS by the European Union and ESA; all rights reserved
- **Citation:** doi:[10.5270/ESA-c5d3d65](https://doi.org/10.5270/ESA-c5d3d65).

## Land cover: ESA WorldCover 10 m 2021 v200

- **What:** 11 land-cover classes at 10 m from Sentinel-1 and Sentinel-2. Used to give each ground cell a radar material.
- **Read from:**
  - AWS, `s3://esa-worldcover` (<https://esa-worldcover.org/en/data-access>);
  - if AWS cannot be reached, Planetary Computer, collection `esa-worldcover`.
- **Licence:** CC BY 4.0.
- **Attribution:**
  > © ESA WorldCover project 2021 / Contains modified Copernicus Sentinel data (2021) processed by ESA WorldCover consortium
- **Citation:** Zanaga et al. (2022), doi:[10.5281/zenodo.7254221](https://doi.org/10.5281/zenodo.7254221).

## Buildings, water, roads: OpenStreetMap

- **What:**
  - building outlines and building parts with their `height`, `min_height`, `building:levels` and `roof:*` tags;
  - water areas (`natural=water`, `waterway=riverbank`, reservoirs and basins);
  - roads (`highway=*`, with their `width` or `lanes`).
- **Read from:** the Overpass API, from the first of `overpass-api.de`, `maps.mail.ru/osm/tools/overpass` and `overpass.kumi.systems` that answers, with retries. Each area's answer is cached.
- **Licence:** Open Database Licence (ODbL) 1.0.
- **Attribution:** © OpenStreetMap contributors (<https://www.openstreetmap.org/copyright>).
- **Building heights:** coverage varies a lot between countries. Each building records whether its height was tagged, derived from storeys, or a typical value for its type, and every view in the dataset metadata counts them.

## Place search: Nominatim

The search box sends the text you type to <https://nominatim.openstreetmap.org>, at most once a second, as its usage policy requires. Results are © OpenStreetMap contributors.

## Map backgrounds (display only)

These map backgrounds are shown while you choose areas. Nothing from them is saved into scenes or datasets.

| Background | Source | Terms |
|---|---|---|
| Satellite | Sentinel-2 cloudless 2023 by EOX IT Services GmbH (<https://s2maps.eu>), contains modified Copernicus Sentinel data 2023 | CC BY-NC-SA 4.0, non-commercial use |
| Streets | OpenStreetMap standard tiles | OSM tile usage policy; light, interactive use only |

## City list for "Suggest places"

Natural Earth *Populated Places*, cut down to the 3,089 places with 100,000 people or more (public domain, <https://www.naturalearthdata.com>). It is kept in `earth_capture/terrabound_earth/data/cities.csv`.

## Why not Google Earth

Google's Photorealistic 3D Tiles and Google Earth imagery would look sharper, but the Google Maps Platform Terms of Service do not allow this use:
- §3.2.3(a) and (b) forbid exporting or caching the content.
- §3.2.3(c) forbids creating content from it, including 3D models, and using it "to train, test, validate or fine-tune" machine-learning models.
- The Map Tiles API policies add that the tiles may only be used for visualisation, not "machine interpretation" or "offline uses".

The same holds when the tiles are reached through third-party tools. A SAR training dataset made from them could not be published or even kept.
