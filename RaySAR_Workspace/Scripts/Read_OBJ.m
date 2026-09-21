function [V, tri, info] = Read_OBJ(path, progress)
% Reads the geometry of a Wavefront .obj file of any size: the vertex
% positions, and every face cut into triangles.
%
% The file is read in blocks of about 16 MB, so the text of the whole file is
% never held in memory at once (only the vertex and triangle numbers are), and
% each block is parsed with a few vectorised calls, whatever the faces are:
% triangles, quads or larger polygons, with or without texture and normal
% indices, all mixed in one file. Larger polygons are fanned into triangles.
% Everything that is not a vertex position or a face (normals, texture
% coordinates, groups, materials) is skipped: a radar sees the shape only.
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

if nargin < 2 || isempty(progress), progress = @(s) []; end
d = dir(path);
if isempty(d), error('Read_OBJ:noFile', 'Could not find %s', path); end
fid = fopen(path, 'r');
if fid < 0, error('Read_OBJ:open', 'Could not open %s', path); end
closer = onCleanup(@() fclose(fid));

block_bytes = 16*2^20;
Vc = {};  n_v = 0;
Tc = {};  n_f = 0;  bad = 0;
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

    vl = lines(head == "v ");
    if ~isempty(vl)
        B = parse_vertices(vl);
        Vc{end+1} = B; %#ok<AGROW>
        n_v = n_v + size(B, 1);
    end

    fl = lines(head == "f ");
    if ~isempty(fl)
        n_f = n_f + numel(fl);
        [T, b] = parse_faces(fl, n_v);
        Tc{end+1} = T; %#ok<AGROW>
        bad = bad + b;
    end

    progress(sprintf('Reading the object: %.0f%%', 100*min(1, seen/max(1, d(1).bytes))));
    if last, break; end
end

if isempty(Vc), error('Read_OBJ:noVertices', 'No vertices found in %s. Is it a Wavefront .obj file?', path); end
V = vertcat(Vc{:});
if isempty(Tc), tri = zeros(0, 3, 'int32'); else, tri = vertcat(Tc{:}); end
clear Vc Tc

% Faces that point at vertices that do not exist, or that collapse to a line
ok = all(tri >= 1 & tri <= size(V, 1), 2);
ok = ok & tri(:, 1) ~= tri(:, 2) & tri(:, 2) ~= tri(:, 3) & tri(:, 1) ~= tri(:, 3);
bad = bad + sum(~ok);
tri = tri(ok, :);

info.header = cellstr(header);
info.n_faces = n_f;
info.skipped = bad;
info.bytes = d(1).bytes;
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


function [T, bad] = parse_faces(fl, n_v_so_far)
% Vertex indices of a block of face lines, cut into triangles
bad = 0;
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
    for k = 2:n-1
        T = [T; int32([F(:, 1), F(:, k), F(:, k+1)])]; %#ok<AGROW>
    end
end
end
