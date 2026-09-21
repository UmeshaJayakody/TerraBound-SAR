function occ = Occupied_Area(B, cell, thr)
% (A second form, Occupied_Area(plan, cell), takes the map that Convert_OBJ_to_POV
% keeps with a scene, info.plan, instead of a list of pieces.)
%
% Which parts of a scene's ground plan have something on them, and how much
% ground that is. A model's bounding box says little about this: a city on an
% island in a wide bay has a box that is mostly empty, and a window placed at
% random in it would mostly show bare ground.
%
% B:     one row per piece of the model, [xmin zmin xmax zmax height]: the
%        ground it covers and how high it reaches, in m. A single point is a
%        piece with xmin = xmax and zmin = zmax.
% cell:  side of the squares the plan is divided into, in m
% thr:   pieces that do not rise above this are ground, not structure, in m
%          (default: 2 m, or a third of the model's height if that is less,
%          so that a low model such as dunes still counts as having structure)
%
% occ fields:
%   area_m2    ground covered by the squares that have structure on them
%   centres    their centres, n x 2 ([x z] in m)
%   cell       side used (larger than asked if the plan would need too many)
%   fraction   share of all squares of the model's plan that have structure
%   usable     true if there is any structure to plan by

if isstruct(B)
    occ = from_map(B, cell);
    return
end
if nargin < 3 || isempty(thr), thr = min(2, 0.3*max(B(:, 5))); end

occ = struct('area_m2', 0, 'centres', zeros(0, 2), 'cell', cell, 'fraction', 0, 'usable', false);
B = B(all(isfinite(B), 2), :);
if isempty(B), return; end
x0 = min(B(:, 1)); z0 = min(B(:, 2));
wx = max(B(:, 3)) - x0;
wz = max(B(:, 4)) - z0;
nx = max(1, ceil(wx/cell));
nz = max(1, ceil(wz/cell));
while nx*nz > 4e6                       % keep the grid to a sensible size
    cell = 2*cell;
    nx = max(1, ceil(wx/cell));
    nz = max(1, ceil(wz/cell));
end
occ.cell = cell;

B = B(B(:, 5) > thr, :);
if isempty(B), return; end
ix0 = min(nx, floor((B(:, 1) - x0)/cell) + 1);
ix1 = min(nx, floor((B(:, 3) - x0)/cell) + 1);
iz0 = min(nz, floor((B(:, 2) - z0)/cell) + 1);
iz1 = min(nz, floor((B(:, 4) - z0)/cell) + 1);

% Every square that any piece covers: add each piece's rectangle to a
% difference grid, then sum along both directions
n = numel(ix0);
D = accumarray([iz0 ix0; iz0 ix1 + 1; iz1 + 1 ix0; iz1 + 1 ix1 + 1], [ones(n, 1); -ones(n, 1); -ones(n, 1); ones(n, 1)], [nz + 1, nx + 1]);
G = cumsum(cumsum(D, 1), 2) > 0;
G = G(1:nz, 1:nx);
[rz, rx] = find(G);

occ.centres = [x0 + (rx - 0.5)*cell, z0 + (rz - 0.5)*cell];
occ.area_m2 = numel(rx)*cell^2;
occ.fraction = numel(rx)/(nx*nz);
occ.usable = numel(rx) >= 4;
end


function occ = from_map(m, cell)
% The map of a scene, at planning squares of about the given size (whole
% multiples of the map's own squares)
k = max(1, round(cell/m.cell));
G = m.grid;
[nz, nx] = size(G);
nz2 = ceil(nz/k); nx2 = ceil(nx/k);
P = false(nz2*k, nx2*k);
P(1:nz, 1:nx) = G;
C = reshape(P, k, nz2, k, nx2);
C = squeeze(any(any(C, 1), 3));
if nz2 == 1 || nx2 == 1, C = reshape(C, nz2, nx2); end
[rz, rx] = find(C);
c = k*m.cell;
occ.cell = c;
occ.centres = [m.x0 + (rx - 0.5)*c, m.z0 + (rz - 0.5)*c];
occ.area_m2 = numel(rx)*c^2;
occ.fraction = numel(rx)/(nz2*nx2);
occ.usable = numel(rx) >= 4;
end
