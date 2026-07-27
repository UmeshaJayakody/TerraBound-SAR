addpath('D:/FYP/RaySAR_Workspace/Scripts');

% Mixed natural terrain/water surface -- more specular than dry desert
% ground (water patches) but not purely specular like open sea, since the
% mesh likely includes surrounding banks/terrain as well as the pond itself.
opts.finish = 'finish {reflection {0.35} ambient 0 diffuse 0.3 specular 0.5 roughness 0.05}';

Convert_OBJ_to_POV( ...
    'D:/FYP/object files/pond.obj', ...
    'D:/FYP/RaySAR_Workspace/Scenes/Pond_01.pov', ...
    opts);
