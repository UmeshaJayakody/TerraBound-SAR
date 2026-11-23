# RaySAR SAR Super-Resolution Dataset Pipeline

Final Year Project: enhance low-resolution Synthetic Aperture Radar (SAR) images to high resolution using a GAN (SRGAN/ESRGAN-style generator/discriminator).

Real matched HR/LR SAR image pairs of the same scene essentially don't exist publicly — high-resolution SAR archives are mostly restricted/commercial, and no two captures of one place at both high and low resolution under identical conditions are freely available. This project works around that by generating its own paired dataset with [RaySAR](https://github.com/StefanJAuer/RaySAR.git), a ray-tracing-based 3D SAR simulator: render a scene once for a clean "HR" image, then synthetically degrade it (blur + downsample + realistic speckle noise) to produce the matching "LR" image. Both images originate from the same simulation, so they're pixel-aligned by construction — exactly what supervised training needs.

## Start here

**→ [`sar_pipeline/README.md`](sar_pipeline/README.md) — the actual pipeline: theory and how to run each GUI.**

`sar_pipeline/` is fully self-contained (the ray-tracing engine, its support library, and RaySAR's MATLAB code are all bundled inside it) and is the only folder published to this project's GitHub repo.

## What happens in each stage, theoretically

1. **Build a 3D scene** — a `.pov` file (or a `.obj` 3D model converted to one) describing camera, light, ground, and objects.
2. **Ray-trace it (RaySAR)** — the engine simulates radar signal bounces off every surface (direct hits, ground bounces, multi-bounce reflections) and records every contribution's position, intensity, and bounce count.

![Pipeline overview: 3D scene -> RaySAR ray tracing -> Contributions.txt -> reflectivity map (HR image) -> degraded LR versions](docs/pipeline_overview.png)

3. **Build the HR image** — every recorded signal contribution is binned into pixels by position and summed, producing the grayscale SAR "ground truth" image.
4. **Degrade to LR** — the HR image is blurred, downsampled, and given realistic multiplicative speckle noise at several severity tiers, producing matching low-resolution versions.

Building real geometry instead of hand-placed boxes — converting a `.obj` 3D model into a RaySAR-ready scene:

![OBJ to POV conversion process: parse geometry, triangulate faces, fix ground height to Y=0, split into small mesh chunks, write the .pov scene file](docs/obj_to_pov_conversion.png)

See `sar_pipeline/README.md` for exactly how to run each of these stages through its GUI.
