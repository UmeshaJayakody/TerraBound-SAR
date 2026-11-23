function [V, tri, info] = Read_OBJ(path, progress)
% Reads the geometry of a Wavefront .obj file of any size: the vertex
% positions, and every face cut into triangles.
%
% The file is read in blocks of about 16 MB, so the text of the whole file is
% never held in memory at once (only the vertex and triangle numbers are), and
% each block is parsed with a few vectorised calls, whatever the faces are:
% triangles, quads or larger polygons, with or without texture and normal
% indices, all mixed in one file. Larger polygons are fanned into triangles.
% Besides the shape, only the material name of each face is kept (the
% "usemtl" lines), so a scene can give buildings, ground and water different
% radar responses (see Convert_OBJ_to_POV's 'materials' option). Normals,
% texture coordinates and groups are skipped: a radar sees the shape only.
%
% The last file read is kept in memory, so reading the same unchanged file
% again (the SAR Dataset GUI analyses an object and then converts it) costs
% nothing. "clear Read_OBJ" lets go of it.
%
% path:     the .obj file
% progress: optional function handle f(text), told how far the reading is
%
% V:    n x 3 vertex positions, as saved in the file
% tri:  m x 3 triangles (int32), each a row of 1-based indices into V
% info: struct with
%         header    the comment lines at the top of the file (cell array of
%                   text), where exporters often say what units the file uses
%         n_faces   faces in the file, before cutting them into triangles
%         skipped   triangles left out because an index did not exist or two
%                   of their corners were the same vertex
%         bytes     size of the file
%         material  m x 1 (int32): the material of each triangle, an index
%                   into material_names, or 0 for faces before any "usemtl"
%         material_names  the material names in the order they first appear

persistent last
if nargin < 2 || isempty(progress), progress = @(s) []; end
d = dir(path);
if isempty(d), error('Read_OBJ:noFile', 'Could not find %s', path); end
key = {char(path), d(1).bytes, d(1).datenum};
if ~isempty(last) && isequal(last.key, key)
    V = last.V; tri = last.tri; info = last.info;
    progress('Reading the object: 100%');
    return
end
fid = fopen(path, 'r');
if fid < 0, error('Read_OBJ:open', 'Could not open %s', path); end
closer = onCleanup(@() fclose(fid));

block_bytes = 16*2^20;
Vc = {};  n_v = 0;
Tc = {};  n_f = 0;  bad = 0;
Mc = {};                    % material of each triangle, block by block
mat_names = strings(0, 1);
cur_mat = int32(0);         % material of the faces that follow; 0 = none yet
header = {};
carry = '';
seen = 0;

while true
    buf = fread(fid, block_bytes, '*char')';
    last = feof(fid) || isempty(buf);
    text = [carry buf];
    if ~last
        cut = find(text == newline, 1, 'last');
        if isempty(cut)
            carry = text; continue      % one very long line: read on
        end
        carry = text(cut+1:end);
        text = text(1:cut);
    else
        carry = '';
    end
    seen = seen + numel(buf);

    lines = splitlines(string(text));
    if isempty(header)
        header = comment_lines(lines);
    end
    head = extractBefore(lines + "  ", 3);   % the first two characters of each line
    head = replace(head, sprintf('\t'), " "); % "v<tab>x y z" counts as well as "v x y z"

    vl = lines(head == "v ");
    if ~isempty(vl)
        B = parse_vertices(vl);
        Vc{end+1} = B; %#ok<AGROW>
        n_v = n_v + size(B, 1);
    end

    is_f = head == "f ";
    fl = lines(is_f);
    % The material each face line is under: the latest "usemtl" before it,
    % in this block or an earlier one
    is_m = startsWith(lines, "usemtl");
    if any(is_m)
        ids = zeros(nnz(is_m), 1, 'int32');
        nm = strtrim(extractAfter(lines(is_m), 6));
        for j = 1:numel(nm)
            k = find(mat_names == nm(j), 1);
            if isempty(k)
                mat_names(end+1, 1) = nm(j); %#ok<AGROW>
                k = numel(mat_names);
            end
            ids(j) = k;
        end
        under = [cur_mat; ids];
        c = cumsum(is_m);
        fm = under(c(is_f) + 1);
        cur_mat = ids(end);
    else
        fm = repmat(cur_mat, numel(fl), 1);
    end

    if ~isempty(fl)
        n_f = n_f + numel(fl);
        [T, b, TM] = parse_faces(fl, n_v, fm);
        Tc{end+1} = T; %#ok<AGROW>
        Mc{end+1} = TM; %#ok<AGROW>
        bad = bad + b;
    end

    progress(sprintf('Reading the object: %.0f%%', 100*min(1, seen/max(1, d(1).bytes))));
    if last, break; end
end

if isempty(Vc), error('Read_OBJ:noVertices', 'No vertices found in %s. Is it a Wavefront .obj file?', path); end
V = vertcat(Vc{:});
if isempty(Tc)
    tri = zeros(0, 3, 'int32');
    tm = zeros(0, 1, 'int32');
else
    tri = vertcat(Tc{:});
    tm = vertcat(Mc{:});
end
clear Vc Tc Mc

% Faces that point at vertices that do not exist, or that collapse to a line
ok = all(tri >= 1 & tri <= size(V, 1), 2);
ok = ok & tri(:, 1) ~= tri(:, 2) & tri(:, 2) ~= tri(:, 3) & tri(:, 1) ~= tri(:, 3);
bad = bad + sum(~ok);
tri = tri(ok, :);
tm = tm(ok);

info.header = cellstr(header);
info.n_faces = n_f;
info.skipped = bad;
info.bytes = d(1).bytes;
info.material = tm;
info.material_names = cellstr(mat_names);
last = struct('key', {key}, 'V', V, 'tri', tri, 'info', info);
end


function h = comment_lines(lines)
% The comment lines at the top of the file, before the first real line
h = strings(0, 1);
for i = 1:min(numel(lines), 60)
    s = strtrim(lines(i));
    if startsWith(s, "#")
        h(end+1, 1) = extractAfter(s, 1); %#ok<AGROW>
    elseif strlength(s) > 0 && ~startsWith(s, "mtllib")
        break
    end
end
end


function B = parse_vertices(vl)
% "v x y z", or "v x y z r g b" / "v x y z w" with colours or a weight
txt = strjoin(vl, newline);
a = sscanf(txt, 'v %f %f %f ');     % the trailing space steps over each newline
if numel(a) == 3*numel(vl)
    B = reshape(a, 3, [])';
else
    C = textscan(txt, 'v %f %f %f %*[^\n]');
    B = [C{1} C{2} C{3}];
    if size(B, 1) ~= numel(vl)
        % Irregular spacing or a broken line: fall back to line by line for this block
        B = nan(numel(vl), 3);
        for i = 1:numel(vl)
            p = sscanf(char(extractAfter(vl(i), 1)), '%f', 3);
            if numel(p) == 3, B(i, :) = p'; end
        end
    end
end
end


function [T, bad, TM] = parse_faces(fl, n_v_so_far, fm)
% Vertex indices of a block of face lines, cut into triangles, and the
% material of each triangle (fm: the material of each face line)
bad = 0;
TM = zeros(0, 1, 'int32');
s = regexprep(fl, '/\S*', '');              % keep only the vertex index of "v/vt/vn"
s = regexprep(strtrim(s), '^f\s+', '');
s = regexprep(s, '\s+', ' ');
n_corners = strlength(s) - strlength(erase(s, " ")) + 1;
n_corners(strlength(s) == 0) = 0;

T = zeros(0, 3, 'int32');
for n = unique(n_corners)'
    if n < 3
        bad = bad + sum(n_corners == n);
        continue
    end
    sel = s(n_corners == n);
    idx = sscanf(strjoin(sel, ' '), '%d');
    if numel(idx) ~= n*numel(sel)
        bad = bad + numel(sel);            % a non-numeric token: skip these faces
        continue
    end
    F = reshape(idx, n, [])';
    F(F < 0) = F(F < 0) + n_v_so_far + 1;   % negative indices count back from the latest vertex
    sel_m = fm(n_corners == n);
    for k = 2:n-1
        T = [T; int32([F(:, 1), F(:, k), F(:, k+1)])]; %#ok<AGROW>
        TM = [TM; sel_m(:)]; %#ok<AGROW>
    end
end
end
