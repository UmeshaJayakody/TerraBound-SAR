addpath('D:/FYP/RaySAR_Workspace/RaySAR');
addpath('D:/FYP/RaySAR_Workspace/Scripts');

R = load('D:/FYP/RaySAR_Workspace/POV_Ray/RaySAR/Contributions.txt');
az = sort(R(:,1)); ra = sort(R(:,2));
pct = @(v,p) v(max(1, min(numel(v), round(p/100*numel(v)))));
a_lo = pct(az, 5); a_hi = pct(az, 95);
r_lo = pct(ra, 5); r_hi = pct(ra, 95);
fprintf('Robust bounds -> azimuth [%.2f %.2f]  range [%.2f %.2f]\n', a_lo,a_hi,r_lo,r_hi);
clear R az ra

opts.a_pix = 0.01;
opts.r_pix = 0.01;
opts.range_dir = 1;
opts.a_min = num2str(a_lo);
opts.a_max = num2str(a_hi);
opts.r_min = num2str(r_lo);
opts.r_max = num2str(r_hi);

Generate_Refl_Map_From_File( ...
    'D:/FYP/RaySAR_Workspace/POV_Ray/RaySAR/Contributions.txt', ...
    'D:/FYP/RaySAR_Workspace/Scenes/MountBlend_01_Results', ...
    opts);

hr_path = 'D:/FYP/RaySAR_Workspace/Scenes/MountBlend_01_Results/Maps/Figures/Ref_Maps/JPG/All Reflections.jpg';

tiers(1) = struct('name','mid',  'scale',2, 'looks',4, 'blur_sigma',0.6);
tiers(2) = struct('name','low',  'scale',4, 'looks',2, 'blur_sigma',1.2);
tiers(3) = struct('name','vlow', 'scale',8, 'looks',1, 'blur_sigma',2.0);

Degrade_To_LR(hr_path, 'D:/FYP/RaySAR_Workspace/Scenes/MountBlend_01_Results/LR_Pairs', tiers);

disp('MountBlend_01 pipeline complete.');
