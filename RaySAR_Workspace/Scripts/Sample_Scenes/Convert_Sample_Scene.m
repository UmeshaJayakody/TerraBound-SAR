function info = Convert_Sample_Scene(name, obj_folder, scenes_folder)
% Converts one of the hand-made sample models into its RaySAR scene, with the
% exact settings that scene was originally made with. This replaces the nine
% convert_<scene>.m scripts, which differed only in these settings and in
% hard-coded absolute paths.
%
% name:          scene to make, e.g. 'Street_01'. Call with no arguments to
%                list them all.
% obj_folder:    folder with the source .obj models. They are not part of
%                the repository. Default: the TERRABOUND_OBJ_DIR environment
%                variable.
% scenes_folder: where the .pov scene is written
%                (default: RaySAR_Workspace/Scenes).
%
% Returns the info struct from Convert_OBJ_to_POV.
%
% Example:
%   Convert_Sample_Scene('Frigate_01', 'C:/models/sample objects')

here = fileparts(mfilename('fullpath'));
scripts = fileparts(here);
workspace = fileparts(scripts);
addpath(scripts);

table = sample_settings();
if nargin < 1 || isempty(name)
    fprintf('Sample scenes:\n');
    for k = 1:numel(table)
        fprintf('  %-14s from %s\n', table(k).name, table(k).obj);
    end
    info = [];
    return;
end

k = find(strcmpi({table.name}, name), 1);
if isempty(k)
    error('Convert_Sample_Scene:unknown', 'There is no sample scene called "%s". Call Convert_Sample_Scene() for the list.', name);
end
s = table(k);

if nargin < 2 || isempty(obj_folder), obj_folder = getenv('TERRABOUND_OBJ_DIR'); end
if isempty(obj_folder)
    error('Convert_Sample_Scene:noFolder', ['Say where the source .obj models are: pass the folder, ' ...
        'or set the TERRABOUND_OBJ_DIR environment variable.']);
end
if nargin < 3 || isempty(scenes_folder), scenes_folder = fullfile(workspace, 'Scenes'); end

obj = fullfile(obj_folder, s.obj);
if exist(obj, 'file') ~= 2
    error('Convert_Sample_Scene:noObj', 'Could not find %s', obj);
end
if ~isempty(s.note), fprintf('Note: %s\n', s.note); end

info = Convert_OBJ_to_POV(obj, fullfile(scenes_folder, [s.name '.pov']), s.opts);
end


function t = sample_settings()
% One entry per sample scene: the source model and the options it was
% converted with.

% Generic building concrete/masonry
concrete = 'finish {reflection {0.4} ambient 0 diffuse 0.35 specular 0.5 roughness 0.01}';
% Rough natural terrain
terrain = 'finish {reflection {0.2} ambient 0 diffuse 0.5 specular 0.2 roughness 0.1}';

t = struct('name', {}, 'obj', {}, 'opts', {}, 'note', {});

% This is a huge scene (whole island + mountains); zoom the camera onto
% just the city + bridge district instead of the whole model. Center/extent
% derived from the X/Z spread of the tallest vertices (skyscrapers), with margin.
t(end+1) = entry('Castelia_01', 'Castelia City.obj', ...
    struct('finish', concrete, 'look_at', [34268 0 -255], ...
    'view_extent', [129542 70000], 'cam_height', 130000));

% 3ds Max native export (Max2Obj) -- Z is up, not Y
t(end+1) = entry('CityBlock1_01', 'City1 Block 1.obj', ...
    struct('finish', concrete, 'up_axis', 'z'));

t(end+1) = entry('Desert_01', 'desert.obj', ...
    struct('finish', 'finish {reflection {0.15} ambient 0 diffuse 0.55 specular 0.15 roughness 0.15}'));

% Vegetation: highly diffuse, low coherent/specular return -- real trees
% scatter radar energy in many directions rather than reflecting it back
% cleanly, unlike hard man-made surfaces.
t(end+1) = entry('Forest_01', 'forest.obj', ...
    struct('finish', 'finish {reflection {0.05} ambient 0 diffuse 0.6 specular 0.05 roughness 0.3}'));

% Hull: metallic, strong specular/corner-reflector return (typical of real
% ship SAR signatures). Sea surface: mostly specular, near-zero diffuse --
% stylized approximation (RaySAR can't model real Bragg-scatter ocean clutter).
t(end+1) = entry('Frigate_01', 'frigate.obj', ...
    struct('finish', 'finish {reflection {0.5} ambient 0 diffuse 0.2 specular 0.8 roughness 0.01}', ...
    'ground_finish', 'finish {reflection {0.6} ambient 0 diffuse 0.02 specular 0.9 roughness 0.001}'));

t(end+1) = entry('Mountains_01', 'mountains.obj', ...
    struct('finish', terrain, 'max_verts_per_mesh', 500), ...
    ['Mountains_01 was set up with 500 vertices per mesh2 object, above the ~133 the ' ...
    'RaySAR engine handles (see Convert_OBJ_to_POV). Its scene was never made.']);

% The file bundles an oversized flat "Plane" reference object (4 verts
% spanning the full X/Z extent) alongside the much smaller actual terrain
% ("Landscape", ~6.5x8.4 units) -- override the auto-framing (which sizes
% to the whole bounding box, dominated by that Plane) to fit the terrain.
t(end+1) = entry('MountBlend_01', 'mount.blend1.obj', ...
    struct('finish', terrain, 'view_extent', [8.5 11], 'cam_height', 11));

% Mixed natural terrain/water surface -- more specular than dry desert
% ground (water patches) but not purely specular like open sea, since the
% mesh likely includes surrounding banks/terrain as well as the pond itself.
t(end+1) = entry('Pond_01', 'pond.obj', ...
    struct('finish', 'finish {reflection {0.35} ambient 0 diffuse 0.3 specular 0.5 roughness 0.05}'));

t(end+1) = entry('Street_01', 'Street environment_V01.obj', struct('finish', concrete));
end


function e = entry(name, obj, opts, note)
if nargin < 4, note = ''; end
e = struct('name', name, 'obj', obj, 'opts', opts, 'note', note);
end
