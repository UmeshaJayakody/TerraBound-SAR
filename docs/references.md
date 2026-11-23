# References

The papers, software and data this project builds on, grouped by what they are used for. Every DOI was checked against Crossref or DataCite in November 2026.

## RaySAR: the SAR simulator at the core of the pipeline

1. S. Auer, S. Hinz, R. Bamler (2010). Ray-tracing simulation techniques for understanding high-resolution SAR images. *IEEE Transactions on Geoscience and Remote Sensing* 48(3), 1445–1456. doi:[10.1109/TGRS.2009.2029339](https://doi.org/10.1109/TGRS.2009.2029339). **Required citation** (or no. 2) for any publication using RaySAR.
2. S. Auer (2011). *3D Synthetic Aperture Radar Simulation for Interpreting Complex Urban Reflection Scenarios.* Doctoral thesis, Technische Universität München, 126 p. <http://mediatum.ub.tum.de/doc/1003958/1003958.pdf>
3. S. Auer, R. Bamler, P. Reinartz (2016). RaySAR – 3D SAR simulator: now open source. *IEEE International Geoscience and Remote Sensing Symposium (IGARSS)*, 6730–6733. doi:[10.1109/IGARSS.2016.7730757](https://doi.org/10.1109/IGARSS.2016.7730757)
4. RaySAR software, release 1.2: <https://github.com/StefanJAuer/RaySAR>. POV-Ray 3.7: <https://www.povray.org>.

## SAR image formation (the signal chain in `sar_pipeline/SAR_Imaging`)

5. L. A. Gorham, L. Moore (2010). SAR image formation toolbox for MATLAB. *Proc. SPIE 7699, Algorithms for Synthetic Aperture Radar Imagery XVII*, 769906. doi:[10.1117/12.855375](https://doi.org/10.1117/12.855375). The source of the phase-history model (Eq. 5), the resolution relations (Eqs. 7–10) and the backprojection (Eqs. 21–22) used here, and of `bpBasic.m` / `mfBasic.m`.
6. A. Moreira, P. Prats-Iraola, M. Younis, G. Krieger, I. Hajnsek, K. Papathanassiou (2013). A tutorial on synthetic aperture radar. *IEEE Geoscience and Remote Sensing Magazine* 1(1), 6–43. doi:[10.1109/MGRS.2013.2248301](https://doi.org/10.1109/MGRS.2013.2248301)

## Speckle

7. J. W. Goodman (1976). Some fundamental properties of speckle. *Journal of the Optical Society of America* 66(11), 1145–1150. doi:[10.1364/JOSA.66.001145](https://doi.org/10.1364/JOSA.66.001145). Fully developed speckle, the basis of the random-phase scatterer model.
8. F. Argenti, A. Lapini, T. Bianchi, L. Alparone (2013). A tutorial on speckle reduction in synthetic aperture radar images. *IEEE Geoscience and Remote Sensing Magazine* 1(3), 6–35. doi:[10.1109/MGRS.2013.2277512](https://doi.org/10.1109/MGRS.2013.2277512). The multiplicative Gamma speckle model of `Degrade_To_LR`.

## SAR simulation from real-world scene models

9. T. Balz, U. Stilla (2009). Hybrid GPU-based single- and double-bounce SAR simulation. *IEEE Transactions on Geoscience and Remote Sensing* 47(10), 3519–3529. doi:[10.1109/TGRS.2009.2022326](https://doi.org/10.1109/TGRS.2009.2022326)
10. J. Tao, S. Auer, G. Palubinskas, P. Reinartz, R. Bamler (2014). Automatic SAR simulation technique for object identification in complex urban scenarios. *IEEE Journal of Selected Topics in Applied Earth Observations and Remote Sensing* 7(3), 994–1003. doi:[10.1109/JSTARS.2013.2275928](https://doi.org/10.1109/JSTARS.2013.2275928). RaySAR on a city-scale surface model.
11. T. Balz, H. Hammer, S. Auer (2015). Potentials and limitations of SAR image simulators – a comparative study of three simulation approaches. *ISPRS Journal of Photogrammetry and Remote Sensing* 101, 102–109. doi:[10.1016/j.isprsjprs.2014.12.008](https://doi.org/10.1016/j.isprsjprs.2014.12.008)
12. S. Auer, I. Hornig, M. Schmitt, P. Reinartz (2017). Simulation-based interpretation and alignment of high-resolution optical and SAR images. *IEEE Journal of Selected Topics in Applied Earth Observations and Remote Sensing* 10(11), 4779–4793. doi:[10.1109/JSTARS.2017.2723082](https://doi.org/10.1109/JSTARS.2017.2723082)
13. Y. Wang, X. X. Zhu (2018). The SARptical dataset for joint analysis of SAR and optical image in dense urban area. *IGARSS 2018*, 6840–6843. doi:[10.1109/IGARSS.2018.8518298](https://doi.org/10.1109/IGARSS.2018.8518298)
14. A. Sultanbekova, T. Balz (2024). Matching UAV-based simulated high-resolution SAR and real SAR images. *ISPRS Archives* XLVIII-1-2024, 613–618. doi:[10.5194/isprs-archives-XLVIII-1-2024-613-2024](https://doi.org/10.5194/isprs-archives-XLVIII-1-2024-613-2024)

## Simulated SAR data for deep learning

15. D. Malmgren-Hansen, A. Kusk, J. Dall, A. A. Nielsen, R. Engholm, H. Skriver (2017). Improving SAR automatic target recognition models with transfer learning from simulated data. *IEEE Geoscience and Remote Sensing Letters* 14(9), 1484–1488. doi:[10.1109/LGRS.2017.2717486](https://doi.org/10.1109/LGRS.2017.2717486)
16. B. Lewis, T. Scarnati, E. Sudkamp, J. Nehrbass, S. Rosencrantz, E. Zelnio (2019). A SAR dataset for ATR development: the Synthetic and Measured Paired Labeled Experiment (SAMPLE). *Proc. SPIE 10987, Algorithms for Synthetic Aperture Radar Imagery XXVI*. doi:[10.1117/12.2523460](https://doi.org/10.1117/12.2523460)

## Super-resolution

17. C. Ledig et al. (2017). Photo-realistic single image super-resolution using a generative adversarial network (SRGAN). *IEEE CVPR 2017*, 105–114. doi:[10.1109/CVPR.2017.19](https://doi.org/10.1109/CVPR.2017.19)
18. X. Wang et al. (2019). ESRGAN: enhanced super-resolution generative adversarial networks. *ECCV 2018 Workshops*, LNCS 11133, 63–79. doi:[10.1007/978-3-030-11021-5_5](https://doi.org/10.1007/978-3-030-11021-5_5)
19. X. Wang, L. Xie, C. Dong, Y. Shan (2021). Real-ESRGAN: training real-world blind super-resolution with pure synthetic data. *ICCV Workshops 2021*, 1905–1914. doi:[10.1109/ICCVW54120.2021.00217](https://doi.org/10.1109/ICCVW54120.2021.00217)
20. L. Wang, M. Zheng, W. Du, M. Wei, L. Li (2018). Super-resolution SAR image reconstruction via generative adversarial network. *12th International Symposium on Antennas, Propagation and EM Theory (ISAPE)*, 1–4. doi:[10.1109/ISAPE.2018.8634345](https://doi.org/10.1109/ISAPE.2018.8634345)
21. F. Gu, H. Zhang, C. Wang, F. Wu (2019). SAR image super-resolution based on noise-free generative adversarial network. *IGARSS 2019*, 2575–2578. doi:[10.1109/IGARSS.2019.8899202](https://doi.org/10.1109/IGARSS.2019.8899202)
22. P. Addabbo, M. L. Bernardi, F. Biondi, M. Cimitile, C. Clemente, N. Fiscante, G. Giunta, D. Orlando, L. Yan (2023). Super-resolution of synthetic aperture radar complex data by deep-learning. *IEEE Access* 11, 23647–23658. doi:[10.1109/ACCESS.2023.3251565](https://doi.org/10.1109/ACCESS.2023.3251565)

Most published SAR super-resolution work trains on real SAR that has been downsampled, or on optical images with simulated speckle. This project instead forms each low-resolution image from a sub-band and sub-aperture of the same simulated raw data as its high-resolution partner, so the pair differs the way a real radar's would.

## Real-world scene data (Earth Capture)

23. European Space Agency, Airbus (2022). *Copernicus DEM.* doi:[10.5270/ESA-c5d3d65](https://doi.org/10.5270/ESA-c5d3d65). GLO-30 read from the AWS Open Data registry (<https://registry.opendata.aws/copernicus-dem/>).
24. D. Zanaga, R. Van De Kerchove, D. Daems, W. De Keersmaecker, C. Brockmann, G. Kirches, J. Wevers, O. Cartus, M. Santoro, S. Fritz, M. Lesiv, M. Herold, N.-E. Tsendbazar, P. Xu, F. Ramoino, O. Arino (2022). *ESA WorldCover 10 m 2021 v200.* doi:[10.5281/zenodo.7254221](https://doi.org/10.5281/zenodo.7254221)
25. M. Haklay, P. Weber (2008). OpenStreetMap: user-generated street maps. *IEEE Pervasive Computing* 7(4), 12–18. doi:[10.1109/MPRV.2008.80](https://doi.org/10.1109/MPRV.2008.80). Data © OpenStreetMap contributors, ODbL: <https://www.openstreetmap.org/copyright>
26. T. G. Farr et al. (2007). The Shuttle Radar Topography Mission. *Reviews of Geophysics* 45(2), RG2004. doi:[10.1029/2005RG000183](https://doi.org/10.1029/2005RG000183). Background on radar-derived surface models such as the Copernicus DEM.
27. Natural Earth, *Populated Places* (public domain), <https://www.naturalearthdata.com>. Used for the "Suggest places" city list.

## Software used by the app

- Leaflet 1.9.4 (<https://leafletjs.com>)
- GDAL / rasterio (<https://rasterio.readthedocs.io>)
- PROJ / pyproj (<https://pyproj4.github.io/pyproj/>)
- GEOS / Shapely (<https://shapely.readthedocs.io>)
- mapbox earcut (<https://github.com/mapbox/earcut.hpp>)
- pywebview (<https://pywebview.flowrl.com>)
- Overpass API (<https://overpass-api.de>) and Nominatim (<https://nominatim.org>)
- Sentinel-2 cloudless by EOX IT Services GmbH (<https://s2maps.eu>)
