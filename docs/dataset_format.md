# Dataset format

What **Export dataset** in Earth Capture (or `python -m terrabound_earth export`) writes, for whoever trains a model on it.

```
sar_dataset_<time>/
  train/  HR/<id>.png   LR_x2/<id>.png   LR_x4/<id>.png   LR_x8/<id>.png
  val/    (same layout)
  test/   (same layout)
  metadata.csv          one row per image pair
  metadata.jsonl        the same rows, one JSON object per line
  dataset_info.json     totals, settings, data sources
  README.md, ATTRIBUTION.md, DATA_LICENSE.md
```

## Image pairs

- **`id`** is `<area id>__<view>`. For example, `colombo_fort_6.9355N_79.8430E_400x400m__v003_r003_az260_inc37` is the third view of that area, with the radar at compass bearing 260° and 37° incidence. Views placed by hand in Blender end in `_blender`.
- **HR**: the SAR image formed from the full simulated raw data.
  - 8-bit grey levels in decibels: 0 is −35 dB, 255 is the HR image's 99.5th-percentile brightness.
  - Rows are range, with near range at the top. Columns are azimuth.
  - Flipped left-right on export, so that it matches the map (see [earth_capture.md](earth_capture.md#views-and-orientation)).
- **LR_x*f***: the same scene imaged with 1/*f* of the bandwidth and 1/*f* of the synthetic aperture, so the resolution is *f* times coarser in both directions. This is the degradation a real radar has: the point spread function widens and the speckle changes. It is not blur and noise added to the HR image.
  - The LR images share the HR's brightness scale, so a pair can be compared pixel for pixel.
  - **aligned** layout (default): each LR image is on the HR pixel grid, the same size.
  - **native** layout: each LR image is shrunk by *f* (Lanczos), the usual input size of super-resolution networks.
- **Speckle** comes from a random phase for every scattering cell, seeded per view (the `seed` column), so a dataset can be made again exactly.

## Splits

Splits are by **area**: every view of one place is in the same split, so a model is never tested on a place it was trained on. Areas are assigned 80/10/10 in a fixed order (by a hash of the area id), and the same set of areas always gives the same split. With fewer than three areas, everything is in `train`.

## metadata.csv columns

| Column | Meaning |
|---|---|
| `id`, `split`, `area_id`, `place`, `view` | Which pair, where it is in the dataset, and the area's name. |
| `lat`, `lon` | The ground point at the centre of the view (WGS84, degrees). |
| `footprint_wkt` | The ground window as a WKT polygon (lon lat). |
| `bearing_deg` | Compass direction from the scene to the radar (0 = radar north of the scene, looking south). |
| `incidence_deg` | Angle of the radar's look from the vertical. |
| `window_m` | Side of the ground window in metres. |
| `bandwidth_mhz`, `hr_resolution_m` | Radar bandwidth and the HR resolution it gives (c/2B; 500 MHz = 0.30 m). |
| `lr_factors`, `hr_size`, `lr_size` | The LR factors and the image sizes in pixels. |
| `buildings` | Buildings whose outline meets the window. |
| `heights_tagged`, `heights_from_levels`, `heights_default` | How many of those have a measured height, a height from their number of storeys, or a typical height for their type. |
| `landcover` | Share of each ESA WorldCover class in the window (JSON). |
| `seed` | Speckle seed of the view. |
| `mirror_fixed`, `lr_layout`, `views_from` | Orientation fix applied, LR layout, and whether the view was planned by the app or placed in Blender. |
| `hr_path`, `lr_x*_path` | The files, relative to the dataset folder. |

## Loading it

```python
import csv
from PIL import Image

rows = list(csv.DictReader(open("sar_dataset_xxx/metadata.csv", encoding="utf-8")))
train = [r for r in rows if r["split"] == "train"]
hr = Image.open("sar_dataset_xxx/" + train[0]["hr_path"])
lr = Image.open("sar_dataset_xxx/" + train[0]["lr_x4_path"])
```

The complex images (before conversion to dB) are in each view's `sar_images.mat` under `runs/<area>/sar/…`, if you need them.

## Licence

See `DATA_LICENSE.md` and `ATTRIBUTION.md` in the dataset folder, and [DATA_LICENSE.md](../DATA_LICENSE.md) here. In short:
- The images are offered under CC BY 4.0, with the data-source attributions and the RaySAR citation.
- The scenes they were rendered from contain OpenStreetMap data (ODbL).
