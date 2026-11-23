function result_file = Run_Earth_Views(job_path)
% Makes the SAR images of a real-world scene built by Earth Capture
% (earth_capture/ in this repository). Reads the job file the app writes,
% runs every view through Make_Multi_Angle_Dataset, and reports progress in
% a file the app reads while MATLAB works:
%
%   matlab -batch "addpath('<repo>/sar_pipeline/Scripts/Earth'); Run_Earth_Views('<job.json>')"
%
% Nothing about how the images are made is different from any other run:
% the scene is converted, ray-traced and imaged exactly as a hand-made model
% would be. The only settings that differ are the ones a real-world scene
% needs: it is already in metres with y up, its own terrain is the ground
% (no ground plane), and each surface keeps its radar material.
%
% job_path: JSON with
%   obj            the scene (.obj in metres, y up, a usemtl line per surface)
%   out_folder     where the images go (a folder per scene inside it)
%   bandwidth_mhz  radar bandwidth, sets the resolution (500 MHz = 0.30 m)
%   factors        how many times coarser each lower-resolution image is
%   materials      'auto': each surface's material name picks its radar finish
%                  (see Radar_Materials); leave out for one finish everywhere
%   seed           speckle seed of the first view (the next view gets seed+1, ...)
%   keep_files     keep each view's .pov and Contributions.txt (default false)
%   progress_file  JSON lines appended as the run goes: progress, view, done, error
%   result_file    JSON written at the end, one entry per view
%   stop_file      if this file exists, the run stops before the next view
%   views          name, bearing_deg, incidence_deg, center_x, center_z,
%                  width_m, height_m (other fields are ignored)
%
% Views already made with the same settings are skipped, so a stopped run
% carries on where it stopped.

here = fileparts(mfilename('fullpath'));
scripts = fileparts(here);
addpath(scripts);
addpath(fullfile(fileparts(scripts), 'SAR_Imaging'));

S = jsondecode(fileread(job_path));
progress_file = char(field(S, 'progress_file', [tempname '.jsonl']));
result_file = char(field(S, 'result_file', fullfile(fileparts(job_path), 'result.json')));
stop_file = char(field(S, 'stop_file', ''));
emit = @(s) append_line(progress_file, s);

try
    vs = S.views;
    if iscell(vs), vs = [vs{:}]; end
    views = struct('name', {}, 'bearing', {}, 'incidence', {}, 'center', {}, 'width_m', {}, 'height_m', {});
    for i = 1:numel(vs)
        v = vs(i);
        views(end+1) = struct('name', char(v.name), 'bearing', v.bearing_deg, 'incidence', v.incidence_deg, ...
            'center', [v.center_x v.center_z], 'width_m', v.width_m, 'height_m', v.height_m); %#ok<AGROW>
    end

    o = struct('views', views, 'up_axis', 'y', 'scale', 1, 'ground', false, ...
        'bw', 1e6*field(S, 'bandwidth_mhz', 500), 'seed', field(S, 'seed', 1), ...
        'keep_files', logical(field(S, 'keep_files', false)));
    o.factors = reshape(field(S, 'factors', [2 4 8]), 1, []);
    m = field(S, 'materials', '');
    if ~isempty(m), o.materials = m; end
    o.progress = @(s) emit(struct('event', 'progress', 'text', s));
    o.view_done = @(i, n, row) emit(struct('event', 'view', 'i', i, 'n', n, 'view', row.view, ...
        'status', row.status, 'message', row.message, 'seconds', row.seconds));
    if ~isempty(stop_file)
        o.should_stop = @() isfile(stop_file);
    end

    emit(struct('event', 'start', 'views', numel(views)));
    [~, notes, run] = Make_Multi_Angle_Dataset(char(S.obj), char(S.out_folder), o);

    [~, name] = fileparts(char(S.obj));
    root = fullfile(char(S.out_folder), regexprep(name, '[^A-Za-z0-9_-]+', '_'));
    ok = ~isempty(run) && all(strcmp({run.status}, 'done'));
    write_json(result_file, struct('ok', ok, 'root', root, 'notes', {notes}, 'views', {num2cell(run)}));
    emit(struct('event', 'done', 'ok', ok, 'root', root));
catch err
    emit(struct('event', 'error', 'message', err.message));
    write_json(result_file, struct('ok', false, 'error', err.message));
    rethrow(err);
end
end


function v = field(s, name, default)
if isfield(s, name) && ~isempty(s.(name)), v = s.(name); else, v = default; end
end


function append_line(path, s)
s.time = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
fid = fopen(path, 'a');
if fid < 0, return; end
fprintf(fid, '%s\n', jsonencode(s));
fclose(fid);
end


function write_json(path, s)
fid = fopen(path, 'w');
if fid < 0, return; end
fwrite(fid, jsonencode(s, 'PrettyPrint', true), 'char');
fclose(fid);
end
