addpath('D:/FYP/RaySAR_Workspace/RaySAR');
addpath('D:/FYP/RaySAR_Workspace/Scripts');

opts.a_pix = 0.4;
opts.r_pix = 0.4;
opts.range_dir = 1;

Generate_Refl_Map_From_File( ...
    'D:/FYP/RaySAR_Workspace/POV_Ray/RaySAR/Contributions.txt', ...
    'D:/FYP/RaySAR_Workspace/Scenes/Urban_01_Results', ...
    opts);

hr_path = 'D:/FYP/RaySAR_Workspace/Scenes/Urban_01_Results/Maps/Figures/Ref_Maps/JPG/All Reflections.jpg';

tiers(1) = struct('name','mid',  'scale',2, 'looks',4, 'blur_sigma',0.6);
tiers(2) = struct('name','low',  'scale',4, 'looks',2, 'blur_sigma',1.2);
tiers(3) = struct('name','vlow', 'scale',8, 'looks',1, 'blur_sigma',2.0);

Degrade_To_LR(hr_path, 'D:/FYP/RaySAR_Workspace/Scenes/Urban_01_Results/LR_Pairs', tiers);

disp('Urban_01 pipeline complete.');
