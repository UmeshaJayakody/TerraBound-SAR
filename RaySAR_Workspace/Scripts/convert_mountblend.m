addpath('D:/FYP/RaySAR_Workspace/Scripts');

opts.finish = 'finish {reflection {0.2} ambient 0 diffuse 0.5 specular 0.2 roughness 0.1}';
% The file bundles an oversized flat "Plane" reference object (4 verts
% spanning the full X/Z extent) alongside the much smaller actual terrain
% ("Landscape", ~6.5x8.4 units) -- override the auto-framing (which sizes
% to the whole bounding box, dominated by that Plane) to fit the terrain.
opts.view_extent = [8.5 11];
opts.cam_height = 11;

Convert_OBJ_to_POV( ...
    'D:/FYP/object files/mount.blend1.obj', ...
    'D:/FYP/RaySAR_Workspace/Scenes/MountBlend_01.pov', ...
    opts);
