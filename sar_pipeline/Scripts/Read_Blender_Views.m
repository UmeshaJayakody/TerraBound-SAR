function [picks, names, obj, when] = Read_Blender_Views(json_path)
% Reads the views file that the Blender add-on writes ("Send views to the SAR
% window"), for SAR_Dataset_GUI.
%
% picks: one row per camera, [direction angle centre_x centre_z width height]
% names: the cameras' names
% obj:   the model Blender exported, which the views are relative to
% when:  when the file was written (datenum)

if ~isfile(json_path)
    error('Read_Blender_Views:noFile', 'Blender has not sent any views yet (no %s).', json_path);
end
S = jsondecode(fileread(json_path));
if ~isfield(S, 'views') || isempty(S.views)
    problems = {};
    if isfield(S, 'problems') && ~isempty(S.problems), problems = cellstr(S.problems); end
    if isempty(problems)
        error('Read_Blender_Views:noViews', 'Blender has no SAR window box yet. Click "Add the yellow window box" in Blender.');
    end
    error('Read_Blender_Views:problems', '%s', strjoin(problems(:)', ' '));
end
vs = S.views;
if iscell(vs), vs = [vs{:}]; end
n = numel(vs);
picks = zeros(n, 6);
names = cell(n, 1);
for i = 1:n
    v = vs(i);
    h = v.width_m*0.75;
    if isfield(v, 'height_m') && ~isempty(v.height_m), h = v.height_m; end
    picks(i, :) = [v.bearing_deg v.incidence_deg v.center_x v.center_z v.width_m h];
    names{i} = char(v.name);
end
obj = char(S.obj);
d = dir(json_path);
when = d(1).datenum;
end
