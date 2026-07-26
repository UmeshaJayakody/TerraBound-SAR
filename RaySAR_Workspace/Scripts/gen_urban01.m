addpath('D:/FYP/RaySAR_Workspace/Scripts');
opts.seed = 7;
opts.grid_rows = 4;
opts.grid_cols = 4;
opts.spacing = 35;
opts.view_extent = [180 180];
opts.cam_height = 180;
Make_Urban_Scene('D:/FYP/RaySAR_Workspace/Scenes/Urban_01.pov', opts);
