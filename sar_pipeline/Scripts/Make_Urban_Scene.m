function Make_Urban_Scene(out_pov_path, opts)
% Generates a denser, more varied RaySAR urban scene than Make_Box_City_Scene:
% a jittered grid of buildings (some L-shaped, all randomly rotated), with
% streets running along the grid lines and cars scattered on the streets.
%
% opts fields (all optional, defaults shown):
%   seed              random seed for reproducibility        (1)
%   grid_rows         number of building rows                (4)
%   grid_cols         number of building columns              (4)
%   spacing           center-to-center block spacing [m]      (35)
%   footprint_range   [min max] building footprint side [m]   [12 22]
%   height_range      [min max] building height [m]           [10 45]
%   rotation_max_deg  max random rotation about Y axis [deg]  (35)
%   l_shape_prob      probability a building gets an L-wing   (0.4)
%   street_width      width of streets between blocks [m]     (6)
%   cars_per_street    approx cars placed per street segment   (3)
%   cam_height        sensor/light height H -> <0,H,-H>       (auto: covers full grid at 45 deg)
%   view_extent       [horizontal vertical] sensor view [m]   (auto: grid extent + margin)

if nargin < 2, opts = struct(); end
g = @(name,defv) get_opt(opts,name,defv);

rng(g('seed',1));

grid_rows = g('grid_rows',4);
grid_cols = g('grid_cols',4);
spacing   = g('spacing',35);
fp_range  = g('footprint_range',[12 22]);
ht_range  = g('height_range',[10 45]);
rot_max   = g('rotation_max_deg',35);
l_prob    = g('l_shape_prob',0.4);
street_w  = g('street_width',6);
cars_per_street = g('cars_per_street',3);

grid_w = (grid_cols-1)*spacing;
grid_d = (grid_rows-1)*spacing;

default_extent = [grid_w + 4*spacing, grid_d + 4*spacing];
view_extent = g('view_extent', default_extent);
cam_height  = g('cam_height', max(view_extent));

fid = fopen(out_pov_path,'w');
fprintf(fid, '#version 3.5;\n\n#include "colors.inc"\n#include "finish.inc"\n\n');
fprintf(fid, 'global_settings{SAR_Output_Data 1 SAR_Intersection 0}\n\n');
fprintf(fid, '// Auto-generated urban scene (Make_Urban_Scene.m, seed=%d)\n\n', g('seed',1));

fprintf(fid, '#declare Cam = camera {\n  orthographic\n  location <0,%g,-%g>\n  look_at <0,0,0>\n  right %g*x\n  up %g*y\n}\n\ncamera{Cam}\n\n', ...
    cam_height, cam_height, view_extent(1), view_extent(2));
fprintf(fid, 'light_source {\n  <0,%g,-%g>\n  color rgb <1,1,1>\n  parallel\n  point_at <0,0,0>\n}\n\n', cam_height, cam_height);

fprintf(fid, 'plane {\n  <0,1,0>\n  0\n  pigment {color White}\n  finish {reflection {0.3} ambient 0 diffuse 0.15 specular 0}\n}\n\n');

asphalt_finish = 'finish {reflection {0.1} ambient 0 diffuse 0.05 specular 0.1}';
building_finish = 'finish {reflection {0.5} ambient 0 diffuse 0.3 specular 0.7 roughness 0.005}';
car_finish = 'finish {reflection {0.4} ambient 0 diffuse 0.2 specular 0.9 roughness 0.001}';

% --- Streets: horizontal and vertical strips along the grid lines ---
x0 = -grid_w/2; z0 = -grid_d/2;

fprintf(fid, '// Streets\n');
for r = 1:grid_rows
    zc = z0 + (r-1)*spacing;
    fprintf(fid, 'box{<%g,0,%g> <%g,0.02,%g> pigment{color Gray30} %s}\n', ...
        x0-spacing/2, zc-street_w/2, x0+grid_w+spacing/2, zc+street_w/2, asphalt_finish);
end
for c = 1:grid_cols
    xc = x0 + (c-1)*spacing;
    fprintf(fid, 'box{<%g,0,%g> <%g,0.02,%g> pigment{color Gray30} %s}\n', ...
        xc-street_w/2, z0-spacing/2, xc+street_w/2, z0+grid_d+spacing/2, asphalt_finish);
end
fprintf(fid, '\n// Buildings\n');

for r = 1:grid_rows
    for c = 1:grid_cols
        cx = x0 + (c-1)*spacing + (rand()-0.5)*spacing*0.25;
        cz = z0 + (r-1)*spacing + (rand()-0.5)*spacing*0.25;

        w = fp_range(1) + rand()*(fp_range(2)-fp_range(1));
        d = fp_range(1) + rand()*(fp_range(2)-fp_range(1));
        h = ht_range(1) + rand()*(ht_range(2)-ht_range(1));
        rot = (rand()-0.5)*2*rot_max;

        fprintf(fid, 'union{\n');
        fprintf(fid, '  box{<%g,0,%g> <%g,%g,%g>}\n', -w/2, -d/2, w/2, h, d/2);

        if rand() < l_prob
            % Attach an L-wing on a random corner, overlapping slightly
            % to avoid coincident-surface render artifacts.
            wing_w = w*0.5; wing_d = d*0.5; wing_h = h*(0.6+0.4*rand());
            side = randi(4);
            switch side
                case 1, wx = w/2 - 0.5; wz = -d/2 - wing_d + 0.5;
                case 2, wx = w/2 - 0.5; wz = d/2 - 0.5;
                case 3, wx = -w/2 - wing_w + 0.5; wz = -d/2 - wing_d + 0.5;
                otherwise, wx = -w/2 - wing_w + 0.5; wz = d/2 - 0.5;
            end
            fprintf(fid, '  box{<%g,0,%g> <%g,%g,%g>}\n', wx, wz, wx+wing_w, wing_h, wz+wing_d);
        end

        fprintf(fid, '  rotate <0,%g,0>\n', rot);
        fprintf(fid, '  translate <%g,0,%g>\n', cx, cz);
        fprintf(fid, '  pigment {color White} %s\n', building_finish);
        fprintf(fid, '}\n\n');
    end
end

% --- Cars: small boxes scattered along the horizontal streets ---
fprintf(fid, '// Cars\n');
for r = 1:grid_rows
    zc = z0 + (r-1)*spacing;
    for k = 1:cars_per_street
        cx = x0 - spacing/2 + rand()*(grid_w+spacing);
        cz = zc + (rand()-0.5)*(street_w-2);
        car_w = 1.8; car_d = 4.2; car_h = 1.5;
        car_rot = (rand()<0.5)*90 + (rand()-0.5)*10;
        fprintf(fid, 'box{<%g,0,%g> <%g,%g,%g> rotate<0,%g,0> translate<%g,0,%g> pigment{color White} %s}\n', ...
            -car_w/2,-car_d/2, car_w/2,car_h,car_d/2, car_rot, cx, cz, car_finish);
    end
end

fclose(fid);
fprintf('Urban scene written to %s (%dx%d buildings, seed=%d)\n', out_pov_path, grid_rows, grid_cols, g('seed',1));

end

function v = get_opt(opts,name,defv)
    if isfield(opts,name), v = opts.(name); else, v = defv; end
end
