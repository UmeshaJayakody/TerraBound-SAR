function Launch_Blender(blender_exe, obj, up, handoff_dir, opts)
% Opens Blender with an object already loaded and the SAR View Picker ready, so
% the angle and window of every SAR image can be chosen there by eye. Returns
% straight away; Blender stays open on its own.
%
% blender_exe: path of blender.exe (see Find_Blender)
% obj:         the .obj file to open
% up:          'y' or 'z', which way is up in that file
% handoff_dir: where Blender writes the views (sar_views.json) and the model it
%              exports; SAR_Dataset_GUI reads them from here
% opts:        bandwidth_mhz and factors, handed to Blender's own "Create SAR
%              images" button, and scale, metres per unit of the file (default
%              1), so a model in inches or centimetres opens at its real size,
%              and materials ('auto' for a scene whose material names are
%              radar materials, e.g. from Earth Capture; Blender then keeps
%              them when it sends the model back) (all optional)
%
% In Blender: move the camera, or add more (Add SAR view camera), then click
% "Send views to the SAR window" in the SAR tab of the sidebar (press N).

if nargin < 5, opts = struct(); end
if nargin < 3 || isempty(up), up = 'y'; end
if ~isfile(blender_exe), error('Launch_Blender:noBlender', 'Could not find Blender at %s', blender_exe); end
if ~isfile(obj), error('Launch_Blender:noObject', 'Could not find the object file %s', obj); end

here = fileparts(mfilename('fullpath'));
root = fileparts(here);
addon_dir = fullfile(root, 'Blender');
if exist(handoff_dir, 'dir') ~= 7, mkdir(handoff_dir); end

cfg = struct('addon_dir', slashes(addon_dir), 'obj', slashes(obj), 'up', up, ...
    'workspace', slashes(root), 'matlab', slashes(fullfile(matlabroot, 'bin', 'matlab.exe')), ...
    'out_dir', slashes(handoff_dir), 'bandwidth_mhz', getopt(opts, 'bandwidth_mhz', 500), ...
    'factors', getopt(opts, 'factors', [2 4 8]), 'scale', getopt(opts, 'scale', 1));
if isfield(opts, 'materials') && ~isempty(opts.materials), cfg.materials = opts.materials; end
cfg_path = fullfile(handoff_dir, 'blender_setup.json');
fid = fopen(cfg_path, 'w');
fwrite(fid, jsonencode(cfg, 'PrettyPrint', true), 'char');
fclose(fid);

% Start Blender and do not wait for it
ps1 = fullfile(handoff_dir, 'start_blender.ps1');
q = @(s) strrep(s, '''', '''''');
fid = fopen(ps1, 'w');
fprintf(fid, 'Start-Process -FilePath ''%s'' -ArgumentList @(''--python'', ''"%s"'', ''--'', ''"%s"'')\r\n', ...
    q(blender_exe), q(fullfile(addon_dir, 'sar_blender_startup.py')), q(cfg_path));
fclose(fid);
[status, out] = system(['powershell -NoProfile -ExecutionPolicy Bypass -File "' ps1 '"']);
if status ~= 0
    error('Launch_Blender:failed', 'Blender did not start: %s', strtrim(out));
end
end


function s = slashes(p)
s = strrep(p, '\', '/');
end

function v = getopt(o, n, d)
if isfield(o, n) && ~isempty(o.(n)), v = o.(n); else, v = d; end
end
