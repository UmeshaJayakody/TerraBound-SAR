function a = Analyze_Mesh(V, tri, header, n_bytes)
% Works out what a mesh is, from its numbers alone (and the comment lines at the
% top of the .obj file, when there are any), so that any model can be used
% without being told which way is up or what its units are.
%
% V:        n x 3 vertex positions as saved in the file
% tri:      m x 3 triangles, rows of indices into V
% header:   the comment lines at the top of the file (cell array of text)
% n_bytes:  size of the file (only reported)
%
% The result holds what was found; Resolve_Model turns it, together with the
% user's own choices of up axis and units where there are any, into the
% orientation and scale to use. Kept apart so that changing a choice in the
% window does not mean reading the file again.
%
% What is worked out:
%  up          Which of Y and Z points up. The surfaces of most scenes that face
%              up (ground, roofs, decks) outweigh those that face either
%              sideways, so the axis most surface area faces is taken as up.
%  units       Exporters often say it in the file's comments ("File units =
%              inches"). When they do not, the size decides: the units chosen
%              are the first of metres, centimetres, millimetres, inches, feet
%              that make the model a believable size for a radar scene (from
%              a few metres to some tens of kilometres, and not taller than the
%              highest mountain).

if nargin < 3, header = {}; end
if nargin < 4, n_bytes = NaN; end

a = struct();
a.n_vertices = size(V, 1);
a.n_triangles = size(tri, 1);
a.bytes = n_bytes;
a.header = header;

used = false(size(V, 1), 1);
used(tri(:)) = true;            % a vertex no face uses is not part of the model
ok = all(isfinite(V), 2);
a.n_bad_vertices = sum(~ok & used);
Vf = V(ok & used, :);
if isempty(Vf), error('Analyze_Mesh:empty', 'The model has no usable vertices.'); end
a.raw_ext = max(Vf) - min(Vf);          % [x y z] as saved
a.raw_min = min(Vf);

% The bulk of the model, leaving out the few far-off points (a big ground
% plane, a stray vertex) that can make its bounding box much larger than it is
n = size(Vf, 1);
S = Vf(1:max(1, floor(n/200000)):end, :);
S = sort(S);
k1 = max(1, round(0.005*size(S, 1)));
k2 = min(size(S, 1), round(0.995*size(S, 1)));
a.bulk_ext = S(k2, :) - S(k1, :);

% A sample of the vertices, for the map in the window
a.pts_raw = Vf(1:max(1, ceil(n/30000)):end, :);

% Which way is up: the axis that most surface area faces
% (the sample of triangles it looks at is kept: their centres and which way
% they face, for judging where the structure is once the up axis is known)
[a.up_auto, a.up_reason, a.facing, a.tri_c, a.tri_n] = guess_up(V, tri, a.bulk_ext);

% What the file says about its units
[a.hint_scale, a.hint_name] = units_from_header(header);
end


function [up, reason, share, tri_c, tri_n] = guess_up(V, tri, ext)
share = [NaN NaN NaN];
tri_c = zeros(0, 3, 'single');
tri_n = zeros(0, 3, 'single');
up = 'y';
reason = 'Could not tell from the shape, so Y is taken as up, which is how most exporters save.';
nt = size(tri, 1);
if nt == 0, return; end
t = double(tri(1:max(1, floor(nt/300000)):end, :));
P1 = V(t(:, 1), :); P2 = V(t(:, 2), :); P3 = V(t(:, 3), :);
N = cross(P2 - P1, P3 - P1, 2);
A = sqrt(sum(N.^2, 2));
good = A > 0 & isfinite(A) & all(isfinite(P1 + P2 + P3), 2);
if ~any(good), return; end
N = N(good, :); A = A(good);
u = abs(N)./A;
w = A/sum(A);
tri_c = single((P1(good, :) + P2(good, :) + P3(good, :))/3);
tri_n = single(u);
share = [sum(w.*(u(:, 1) > 0.8)), sum(w.*(u(:, 2) > 0.8)), sum(w.*(u(:, 3) > 0.8))];
sy = share(2); sz = share(3);
% A flat scene (a city, terrain, the sea) is far wider than it is tall: the axis
% that is much shorter than the other two is up. That is a stronger sign than
% which way the surfaces face, because tall buildings have far more wall than roof.
z_flat = ext(3) <= 0.5*min(ext(1), ext(2));
y_flat = ext(2) <= 0.5*min(ext(1), ext(3));
if z_flat && ~y_flat
    up = 'z';
    reason = sprintf('With Z up it is %.0f times wider than tall, and with Y up it would not be, so Z is up.', min(ext(1), ext(2))/max(ext(3), eps));
elseif y_flat && ~z_flat
    up = 'y';
    reason = sprintf('With Y up it is %.0f times wider than tall, and with Z up it would not be, so Y is up.', min(ext(1), ext(3))/max(ext(2), eps));
elseif sy >= 1.25*sz
    up = 'y';
    reason = sprintf('%.0f%% of the surface faces Y and %.0f%% faces Z, so Y is up.', 100*sy, 100*sz);
elseif sz >= 1.25*sy
    up = 'z';
    reason = sprintf('%.0f%% of the surface faces Z and %.0f%% faces Y, so Z is up.', 100*sz, 100*sy);
else
    reason = sprintf('Y and Z are faced about equally (%.0f%% and %.0f%%), so Y is taken as up, which is how most exporters save.', 100*sy, 100*sz);
end
end


function [scale, name] = units_from_header(header)
% "File units = inches", "This file uses centimeters as units", "units: mm" ...
scale = NaN; name = '';
words = {'inch', 0.0254, 'inches'; 'centimet', 0.01, 'centimetres'; 'millimet', 0.001, 'millimetres'; ...
         'kilomet', 1000, 'kilometres'; 'feet', 0.3048, 'feet'; 'foot', 0.3048, 'feet'; ...
         'meter', 1, 'metres'; 'metre', 1, 'metres'};
for i = 1:numel(header)
    s = lower(char(header{i}));
    if ~contains(s, 'unit'), continue; end
    for j = 1:size(words, 1)
        if contains(s, words{j, 1})
            scale = words{j, 2}; name = words{j, 3};
            return
        end
    end
end
end
