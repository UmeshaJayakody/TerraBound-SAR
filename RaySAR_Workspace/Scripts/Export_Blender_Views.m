function json_path = Export_Blender_Views(blender_exe, handoff_dir)
% Reads the SAR cameras out of the .blend file that Blender saved in the
% hand-off folder, by running Blender in the background (no window), and
% writes sar_views.json and the exported model next to it. Waits for it.
%
% This is what lets SAR_Dataset_GUI's Capture button take the views straight
% from the file Blender saved (Ctrl+S), with nothing else to click in Blender.

blend = fullfile(handoff_dir, 'blender_scene.blend');
if ~isfile(blend)
    error('Export_Blender_Views:noBlend', 'Blender has not saved the scene yet (no %s). Press Ctrl+S in Blender.', blend);
end
if ~isfile(blender_exe)
    error('Export_Blender_Views:noBlender', 'Could not find Blender at %s', blender_exe);
end
script = fullfile(fileparts(fileparts(mfilename('fullpath'))), 'Blender', 'sar_blender_export.py');
sl = @(p) strrep(p, '\', '/');
cmd = sprintf('"%s" -b "%s" --python "%s" -- "%s"', sl(blender_exe), sl(blend), sl(script), sl(handoff_dir));
[status, out] = system(cmd);
json_path = fullfile(handoff_dir, 'sar_views.json');
if status ~= 0 || ~isfile(json_path)
    lines = strsplit(strtrim(out), newline);
    error('Export_Blender_Views:failed', 'Blender could not read the cameras: %s', strjoin(lines(max(1, end-2):end), ' '));
end
end
