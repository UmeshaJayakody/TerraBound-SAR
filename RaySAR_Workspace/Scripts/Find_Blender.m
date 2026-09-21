function exe = Find_Blender()
% Where Blender is installed, or '' if it cannot be found. Looks at the
% BLENDER_PATH setting, the usual install folders, a portable copy in
% D:\Apps\Blender, and the PATH; the newest version wins.

candidates = {};
env = getenv('BLENDER_PATH');
if ~isempty(env), candidates{end+1} = env; end

patterns = { ...
    'C:\Program Files\Blender Foundation\Blender*\blender.exe', ...
    'C:\Program Files (x86)\Blender Foundation\Blender*\blender.exe', ...
    fullfile(getenv('LOCALAPPDATA'), 'Programs', 'Blender Foundation', 'Blender*', 'blender.exe'), ...
    'D:\Apps\Blender\blender.exe', ...
    'C:\Apps\Blender\blender.exe'};
for i = 1:numel(patterns)
    d = dir(patterns{i});
    if isempty(d), continue; end
    [~, order] = sort({d.folder});
    order = fliplr(order);                             % Blender 5.2 before Blender 4.2
    for k = order(:)'
        candidates{end+1} = fullfile(d(k).folder, d(k).name); %#ok<AGROW>
    end
end

[status, out] = system('where blender 2>NUL');
if status == 0
    lines = strtrim(strsplit(out, newline));
    candidates = [candidates, lines(~cellfun(@isempty, lines))];
end

exe = '';
for i = 1:numel(candidates)
    if isfile(candidates{i})
        exe = candidates{i};
        return
    end
end
end
