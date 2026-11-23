% Makes the Urban_01 sample scene: a seeded 4 x 4 grid of buildings.
here = fileparts(mfilename('fullpath'));
addpath(fileparts(here));
opts.seed = 7;
opts.grid_rows = 4;
opts.grid_cols = 4;
opts.spacing = 35;
opts.view_extent = [180 180];
opts.cam_height = 180;
Make_Urban_Scene(fullfile(fileparts(fileparts(here)), 'Scenes', 'Urban_01.pov'), opts);
