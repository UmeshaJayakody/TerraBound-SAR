function [finish, table] = Radar_Materials(name)
% The surface materials a scene can use, as POV-Ray finish{} strings the
% RaySAR engine understands. One place for them, so the converter, the SAR
% Dataset GUI and Earth Capture all use the same values.
%
% They are hand-set, not measured: they say how mirror-like or rough a surface
% is for the ray tracer, not what it is made of. In RaySAR, "diffuse" sends
% energy straight back to the radar (bright single bounce), "reflection" lets a
% ray carry on to the next surface (double and triple bounce, e.g. the bright
% line where a wall meets the ground), and "specular"/"roughness" shape the
% highlight around the mirror direction.
%
% finish = Radar_Materials(name)   the finish{} string for a material name
%                                  (not case sensitive), or '' if unknown
% [~, table] = Radar_Materials()   every material: name, label, finish, rgb
%                                  (a display colour, e.g. for Blender), source
%
% The names are what scene files use in their "usemtl" lines; see the
% 'materials' option of Convert_OBJ_to_POV.

t = struct('name', {}, 'label', {}, 'finish', {}, 'rgb', {}, 'source', {});

% Taken unchanged from the scenes and GUI presets of this project
t(end+1) = m('concrete',   'Buildings, concrete', ...
    'finish {reflection {0.4} ambient 0 diffuse 0.35 specular 0.5 roughness 0.01}', [0.62 0.62 0.60], 'preset');
t(end+1) = m('metal',      'Metal (roofs, ships, vehicles)', ...
    'finish {reflection {0.5} ambient 0 diffuse 0.2 specular 0.8 roughness 0.01}',  [0.55 0.62 0.72], 'preset');
t(end+1) = m('vegetation', 'Vegetation, trees, rough terrain', ...
    'finish {reflection {0.05} ambient 0 diffuse 0.6 specular 0.05 roughness 0.3}', [0.16 0.42 0.18], 'preset');
t(end+1) = m('sand',       'Sandy terrain (desert)', ...
    'finish {reflection {0.15} ambient 0 diffuse 0.55 specular 0.15 roughness 0.15}', [0.86 0.78 0.56], 'preset');
t(end+1) = m('soil',       'Soil, gravel, bare ground', ...
    'finish {reflection {0.2} ambient 0 diffuse 0.5 specular 0.2 roughness 0.1}',   [0.55 0.42 0.30], 'preset');
t(end+1) = m('land',       'Land (the default ground plane)', ...
    'finish {reflection {0.3} ambient 0 diffuse 0.15 specular 0}',                  [0.70 0.66 0.55], 'preset');
t(end+1) = m('water',      'Water, pond, river', ...
    'finish {reflection {0.35} ambient 0 diffuse 0.3 specular 0.5 roughness 0.05}', [0.25 0.50 0.80], 'preset');
t(end+1) = m('sea',        'Sea (near mirror, stylised)', ...
    'finish {reflection {0.6} ambient 0 diffuse 0.02 specular 0.9 roughness 0.001}', [0.10 0.25 0.55], 'preset');

% Added for real-world scenes. Derived from the presets above, not measured.
% Paved surfaces are smooth at X band, so they look dark in SAR images (little
% diffuse return) but still send rays on to walls (bright double bounce).
t(end+1) = m('asphalt',    'Roads, paved ground', ...
    'finish {reflection {0.4} ambient 0 diffuse 0.05 specular 0.3 roughness 0.01}', [0.30 0.30 0.32], 'derived');
% Halfway between vegetation and soil
t(end+1) = m('grass',      'Grass, crops, low vegetation', ...
    'finish {reflection {0.125} ambient 0 diffuse 0.55 specular 0.125 roughness 0.2}', [0.48 0.68 0.30], 'derived');

table = t;
if nargin < 1
    finish = '';
    return
end
k = find(strcmpi({t.name}, strtrim(char(name))), 1);
if isempty(k)
    finish = '';
else
    finish = t(k).finish;
end
end


function e = m(name, label, finish, rgb, source)
e = struct('name', name, 'label', label, 'finish', finish, 'rgb', rgb, 'source', source);
end
