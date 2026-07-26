function Make_Box_City_Scene(buildings, cam_height, view_extent, out_pov_path)
% Generates a RaySAR-ready POV-Ray scene file containing a ground plane
% and a set of box-shaped buildings, viewed by an orthographic sensor at
% 45 degrees incidence (camera location <0,H,-H>), following the same
% pattern as the bundled Step.pov / Test_Building.pov reference scenes.
%
% buildings: Nx5 matrix, one row per building: [center_x, center_z, width, depth, height]
% cam_height: camera/light height H -> location <0,H,-H>, look_at <0,0,0> (45 deg incidence)
% view_extent: [horizontal, vertical] size of the sensor's view window in meters
% out_pov_path: file path to write the .pov scene to

fid = fopen(out_pov_path,'w');

fprintf(fid, '#version 3.5;\n\n');
fprintf(fid, '#include "colors.inc"\n#include "finish.inc"\n\n');
fprintf(fid, 'global_settings{SAR_Output_Data 1 SAR_Intersection 0}\n\n');
fprintf(fid, '// Auto-generated box-city scene (Make_Box_City_Scene.m)\n\n');

fprintf(fid, '#declare Cam = camera {\n');
fprintf(fid, '  orthographic\n');
fprintf(fid, '  location <0,%g,-%g>\n', cam_height, cam_height);
fprintf(fid, '  look_at <0,0,0>\n');
fprintf(fid, '  right %g*x\n', view_extent(1));
fprintf(fid, '  up %g*y\n', view_extent(2));
fprintf(fid, '}\n\ncamera{Cam}\n\n');

fprintf(fid, 'light_source {\n  <0,%g,-%g>\n  color rgb <1,1,1>\n  parallel\n  point_at <0,0,0>\n}\n\n', cam_height, cam_height);

fprintf(fid, 'plane {\n  <0,1,0>\n  0\n  pigment {color White}\n  finish {reflection {0.5} ambient 0 diffuse 0.1 specular 0}\n}\n\n');

for i = 1:size(buildings,1)
    cx = buildings(i,1); cz = buildings(i,2);
    w  = buildings(i,3); d  = buildings(i,4); h = buildings(i,5);

    fprintf(fid, 'box{\n');
    fprintf(fid, '  <%g,0,%g>\n', -w/2, -d/2);
    fprintf(fid, '  <%g,%g,%g>\n', w/2, h, d/2);
    fprintf(fid, '  translate <%g,0,%g>\n', cx, cz);
    fprintf(fid, '  pigment {color White}\n');
    fprintf(fid, '  finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}\n');
    fprintf(fid, '}\n\n');
end

fclose(fid);
fprintf('Scene written to %s (%d buildings)\n', out_pov_path, size(buildings,1));
