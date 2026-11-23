function [index, notes, result_file] = Make_SAR_From_Blender(json_path, opts)
% Makes the SAR images for views that were chosen in Blender: read the views
% file the Blender add-on (Blender/sar_view_picker.py) writes, run every view
% through the same pipeline as the rest of this project, and write
% blender_result.json so the add-on can show the pictures.
%
% json_path: the views file. It holds
%   obj            the model the add-on exported, in the object's own coordinates
%   out_folder     where to write the dataset (default: sar_out next to the file)
%   bandwidth_mhz  radar bandwidth, sets the resolution (default 500, 0.30 m)
%   factors        how many times coarser each lower-resolution image is (default [2 4 8])
%   views          one entry per camera, each with name, bearing_deg,
%                  incidence_deg, center_x, center_z (the ground point at the
%                  middle of the window), width_m and height_m
% opts (optional) overrides any option of Make_Multi_Angle_Dataset, e.g.
%   opts.seed, opts.keep_files, opts.progress.
%
% Views that are already done with the same settings are skipped, so adding a
% camera in Blender only makes that camera's image. The images go to
% <out_folder>/<object name>/views/v001_<camera name>_az..._inc.../ like any
% other dataset, and can be viewed and downloaded in the Results step of
% SAR_Dataset_GUI (Open another dataset...).
%
% Returns the index of the views, notes about anything left out, and the path
% of blender_result.json.

if nargin < 2, opts = struct(); end
here = fileparts(mfilename('fullpath'));
addpath(here);
addpath(fullfile(fileparts(here), 'SAR_Imaging'));

S = jsondecode(fileread(json_path));
if ~isfield(S, 'views') || isempty(S.views)
    error('Make_SAR_From_Blender:noViews', 'The views file has no views.');
end
folder = fileparts(json_path);
obj = char(S.obj);
if ~isfile(obj) && isfile(fullfile(folder, obj)), obj = fullfile(folder, obj); end
out = fieldget(S, 'out_folder', fullfile(folder, 'sar_out'));
if ~isfolder(out), out = fullfile(folder, out); end

% The views, as the driver wants them
vs = S.views;
if iscell(vs), vs = [vs{:}]; end
views = struct('name', {}, 'bearing', {}, 'incidence', {}, 'center', {}, 'width_m', {}, 'height_m', {});
for i = 1:numel(vs)
    v = vs(i);
    views(end+1) = struct('name', char(fieldget(v, 'name', sprintf('view%d', i))), ...
        'bearing', v.bearing_deg, 'incidence', v.incidence_deg, ...
        'center', [v.center_x v.center_z], 'width_m', v.width_m, ...
        'height_m', fieldget(v, 'height_m', [])); %#ok<AGROW>
end

o = struct('views', views, 'up_axis', 'y', 'scale', 1, 'bw', 1e6*fieldget(S, 'bandwidth_mhz', 500));
if isfield(S, 'factors'), o.factors = S.factors(:)'; end
if isfield(S, 'finish') && ~isempty(S.finish), o.finish = char(S.finish); end
if isfield(S, 'ground_finish') && ~isempty(S.ground_finish), o.ground_finish = char(S.ground_finish); end
names = fieldnames(opts);
for k = 1:numel(names), o.(names{k}) = opts.(names{k}); end

[~, notes, index] = Make_Multi_Angle_Dataset(obj, out, o);   % index: the views of this send, not older ones in the folder

% What the add-on should show. A camera's name is the second part of its view
% folder name (v001_<camera>_az..._inc...).
[~, name] = fileparts(obj);
root = fullfile(out, regexprep(name, '[^A-Za-z0-9_-]+', '_'));
res = struct('view', {}, 'camera', {}, 'status', {}, 'message', {}, 'hr', {}, 'lr', {}, 'image_px', {}, 'image_py', {});
for i = 1:numel(index)
    r = index(i);
    tok = strsplit(r.view, '_');
    vdir = fullfile(root, 'views', r.view);
    lr = dir(fullfile(vdir, 'LR_*.png'));
    res(end+1) = struct('view', r.view, 'camera', tok{min(2, numel(tok))}, 'status', r.status, ...
        'message', r.message, 'hr', fullfile(vdir, 'HR.png'), ...
        'lr', {arrayfun(@(d) fullfile(d.folder, d.name), lr, 'UniformOutput', false)'}, ...
        'image_px', r.image_px, 'image_py', r.image_py); %#ok<AGROW>
end
result_file = fullfile(root, 'blender_result.json');
fid = fopen(result_file, 'w');
% views as a cell array of structs, so one view is still written as a list of one
fwrite(fid, jsonencode(struct('ok', all(strcmp({index.status}, 'done')), 'root', root, 'views', {num2cell(res)}, 'notes', {notes}), 'PrettyPrint', true), 'char');
fclose(fid);
fprintf('Result for Blender: %s\n', result_file);
end


function v = fieldget(s, name, default)
if isfield(s, name) && ~isempty(s.(name)), v = s.(name); else, v = default; end
end
