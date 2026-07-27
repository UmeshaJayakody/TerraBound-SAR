addpath('D:/FYP/RaySAR_Workspace/Scripts');

% Hull: metallic, strong specular/corner-reflector return (typical of real ship SAR signatures)
opts.finish = 'finish {reflection {0.5} ambient 0 diffuse 0.2 specular 0.8 roughness 0.01}';
% Sea surface: mostly specular, near-zero diffuse -- stylized approximation
% (RaySAR can't model real Bragg-scatter ocean clutter; see README caveat)
opts.ground_finish = 'finish {reflection {0.6} ambient 0 diffuse 0.02 specular 0.9 roughness 0.001}';

Convert_OBJ_to_POV( ...
    'D:/FYP/object files/frigate.obj', ...
    'D:/FYP/RaySAR_Workspace/Scenes/Frigate_01.pov', ...
    opts);
