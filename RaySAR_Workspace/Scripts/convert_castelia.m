addpath('D:/FYP/RaySAR_Workspace/Scripts');

opts.finish = 'finish {reflection {0.4} ambient 0 diffuse 0.35 specular 0.5 roughness 0.01}';

% This is a huge scene (whole island + mountains); zoom the camera onto
% just the city + bridge district instead of the whole model. Center/extent
% derived from the X/Z spread of the tallest vertices (skyscrapers), with margin.
opts.look_at = [34268 0 -255];
opts.view_extent = [129542 70000];
opts.cam_height = 130000;

Convert_OBJ_to_POV( ...
    'D:/FYP/object files/Castelia City.obj', ...
    'D:/FYP/RaySAR_Workspace/Scenes/Castelia_01.pov', ...
    opts);
