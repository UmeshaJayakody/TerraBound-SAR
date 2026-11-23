function contrib_path = Render_POV(pov_path, work_dir, render_px)
% Ray-traces a .pov scene with the RaySAR engine, with no GUI and nothing
% appearing on screen, and returns the path of the Contributions.txt it
% wrote. The same engine call the RaySAR GUI's Rendering button makes, except
% that it runs in work_dir, so several scenes can be rendered one after
% another without their outputs overwriting each other.
%
% pov_path:  scene to render
% work_dir:  folder the engine writes into (created if missing). The
%            engine writes Contributions.txt, and a preview image, here.
% render_px: rays across the view, [width height], or one number for both
%            (default 1000, what the GUI uses); more rays means more
%            contributions and a longer render
%
% Only one engine can run at a time, and a render is finished when this
% returns.
%
% Two things keep the engine quiet, both in the engine itself, not in this
% code's own windows:
%  - Its "Use Editor" setting is turned off. This build has no editor
%    component, so with the setting on it asks "Could not load internal
%    editor - download it?" at the start of every run.
%  - Run_POV_Engine.ps1 hides the engine's main and render windows as they
%    appear. Cmd.exe does not wait for a GUI program, so that script is also
%    what waits for the render to end.

if nargin < 3 || isempty(render_px), render_px = 1000; end
if isscalar(render_px), render_px = [render_px render_px]; end
render_px = round(render_px);

here = fileparts(mfilename('fullpath'));
root = fileparts(here);
exe = fullfile(root, 'POV_Ray', 'RaySAR', 'pvengine.exe');
inc = fullfile(root, 'POV_Ray', 'include');
runner = fullfile(here, 'Run_POV_Engine.ps1');
if exist(exe, 'file') ~= 2
    error('Render_POV:noEngine', 'Could not find the ray-tracing engine at %s', exe);
end

[~, running] = system('tasklist /FI "IMAGENAME eq pvengine.exe" 2>NUL');
if contains(running, 'pvengine.exe')
    error('Render_POV:busy', 'A POV-Ray window is already open. Close it first; only one can run at a time.');
end

turn_off_editor_prompt();

if exist(work_dir, 'dir') ~= 7, mkdir(work_dir); end
work_dir = char(java.io.File(work_dir).getAbsolutePath());
pov_path = char(java.io.File(pov_path).getAbsolutePath());
contrib_path = fullfile(work_dir, 'Contributions.txt');
if exist(contrib_path, 'file') == 2, delete(contrib_path); end

cmd = sprintf(['powershell -NoProfile -ExecutionPolicy Bypass -File "%s" -Exe "%s" -WorkDir "%s" ' ...
    '-PovFile "%s" -Wpx %d -Hpx %d -IncludeDir "%s"'], runner, exe, work_dir, pov_path, render_px(1), render_px(2), inc);
[status, out] = system(cmd);

if status ~= 0 || exist(contrib_path, 'file') ~= 2
    error('Render_POV:failed', 'The render produced no Contributions.txt (status %d). %s', status, strtrim(out));
end
end


function turn_off_editor_prompt()
% Sets UseEditors=0 under [General] in the engine's pvengine.ini, which the
% engine reads at start-up (windows/pvmisc.cpp in the POV-Ray source). Done
% before every render, so it holds even if the setting is changed or the
% file is restored by a sync. Only an existing file is touched: the engine
% creates it on its first run, so that one run can still show the prompt.
try
    doc = winqueryreg('HKEY_CURRENT_USER', 'Software\POV-Ray\v3.7\Windows', 'DocPath');
catch
    return
end
ini = fullfile(doc, 'ini', 'pvengine.ini');
if exist(ini, 'file') ~= 2, return; end

txt = fileread(ini);
if ~isempty(regexp(txt, '(?m)^UseEditors=0[ \t]*\r?$', 'once')), return; end
if ~isempty(regexp(txt, '(?m)^UseEditors=', 'once'))
    txt = regexprep(txt, '(?m)^UseEditors=[^\r\n]*', 'UseEditors=0');
else
    txt = regexprep(txt, '(?m)^(\[General\][ \t]*)(\r?\n)', '$1$2UseEditors=0$2', 'once');
end
fid = fopen(ini, 'w');
if fid < 0, return; end
fwrite(fid, txt, 'char');
fclose(fid);
end
