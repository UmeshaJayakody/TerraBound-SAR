addpath('D:/FYP/RaySAR_Workspace/Scripts');

% Vegetation: highly diffuse, low coherent/specular return -- real trees
% scatter radar energy in many directions rather than reflecting it back
% cleanly, unlike hard man-made surfaces.
opts.finish = 'finish {reflection {0.05} ambient 0 diffuse 0.6 specular 0.05 roughness 0.3}';

Convert_OBJ_to_POV( ...
    'D:/FYP/object files/forest.obj', ...
    'D:/FYP/RaySAR_Workspace/Scenes/Forest_01.pov', ...
    opts);
