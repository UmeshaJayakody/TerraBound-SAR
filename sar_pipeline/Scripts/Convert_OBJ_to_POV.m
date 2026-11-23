function info = Convert_OBJ_to_POV(obj_path, out_pov_path, opts)
% Converts a Wavefront .obj mesh into a RaySAR-ready .pov scene: parses
% vertices/faces from the OBJ, fan-triangulates any non-triangular faces,
% emits a POV-Ray mesh2{} block, and wraps it with the same
% camera/light/global_settings boilerplate every RaySAR scene needs.
%
% Only vertex positions and face connectivity are used -- OBJ materials
% (.mtl) describe visual appearance, not radar reflectivity, so they are
% intentionally ignored; a single finish{} representing the intended
% surface type is applied to the whole mesh instead (pass via opts.finish).
%
% obj_path: path to the .obj file
% out_pov_path: path to write the .pov scene to
% opts fields (all optional):
%   finish        POV finish{} string applied to the mesh material
%                 (default: generic building concrete/masonry)
%   cam_height    sensor/light height H -> location <0,H,-H> (45 deg incidence)
%                 (default: auto, covers the mesh's footprint with margin)
%   view_extent   [horizontal vertical] sensor view size [m] (default: auto)
%   ground        include a ground plane under the mesh (default: true)
%   ground_finish POV finish{} string for the ground plane (default: generic
%                 ground; pass a near-specular one for a "sea" scenario)
%   up_axis       'y' (default, most exporters), 'z' (3ds Max native
%                 export convention) -- swaps Y/Z columns so up is always Y --
%                 or 'auto', which finds it from the shape (see Analyze_Mesh)
%   scale         metres per unit of the file (default 1), or 'auto', which
%                 takes it from the file's own comments or, failing that, from
%                 the size (see Analyze_Mesh). Everything after this is in m.
%   progress      function handle f(text), told how far it has got
%   look_at       [x y z] world-space point (post ground-shift) to center
%                 the camera on (default: [0 0 0], i.e. the whole model) --
%                 use to zoom into one region of a large scene
%   center        true centres the camera on the middle of the model's
%                 footprint instead of on [0 0 0], for models that are not
%                 built around the origin (default: false). Ignored if
%                 look_at is given.
%
% Any size of file is accepted: it is read in blocks (see Read_OBJ), and the
% triangles are put in order by where they are before they are cut into the
% small mesh2 objects, so each object covers a small patch. info.chunks says
% where every object is, in the file and in space, which is what lets a view
% load only the objects it can see (see Scene_Chunks).
%
% Returns info with bbox ([xmin xmax; ymin ymax; zmin zmax] in m after the
% scale and the ground shift), look_at, the number of mesh2 objects written,
% the up axis and scale used, and chunks (start and stop byte of each object in
% the .pov file, and its bounding box [xmin ymin zmin xmax ymax zmax]).

if nargin < 3, opts = struct(); end
g = @(name,defv) get_opt(opts,name,defv);

progress = g('progress', @(t) []);
fprintf('Reading %s ...\n', obj_path);
[V, tri, rd] = Read_OBJ(obj_path, progress);
n_v = size(V, 1);
fprintf('Read %d vertices and %d triangles (%d faces in the file).\n', n_v, size(tri, 1), rd.n_faces);
if rd.skipped > 0
    fprintf('%d triangles were left out: they pointed at vertices that do not exist, or were not triangles.\n', rd.skipped);
end

% Which way is up, and what the units are: asked for outright, or worked out
up_axis = g('up_axis', 'y');
scale = g('scale', 1);
resolved = struct('up', lower(up_axis), 'scale', scale, 'findings', {{}}, 'warnings', {{}});
if strcmpi(up_axis, 'auto') || ischar(scale) || isstring(scale)
    progress('Working out what the object is ...');
    an = Analyze_Mesh(V, tri, rd.header, rd.bytes);
    resolved = Resolve_Model(an, up_axis, scale);
    for k = 1:numel(resolved.findings), fprintf('  %s\n', resolved.findings{k}); end
    for k = 1:numel(resolved.warnings), fprintf('  Note: %s\n', resolved.warnings{k}); end
end
up_axis = resolved.up;
scale = resolved.scale;

% Some exporters (notably 3ds Max's native OBJ export) write Z-up
% geometry instead of POV-Ray's Y-up convention. Swap columns so Y is
% always up before anything downstream (ground shift, framing) runs.
if strcmpi(up_axis, 'z')
    V = V(:, [1 3 2]);
end
if scale ~= 1
    V = V*scale;
end

finish_str = g('finish','finish {reflection {0.4} ambient 0 diffuse 0.35 specular 0.5 roughness 0.01}');

% Only vertices that a face uses and that are real numbers count towards the
% size: an unused or broken vertex must not stretch the frame
used = false(n_v, 1);
used(tri(:)) = true;
badv = ~all(isfinite(V), 2);
if any(badv & used)
    tri = tri(~any(badv(tri), 2), :);
    used = false(n_v, 1);
    used(tri(:)) = true;
end
if isempty(tri), error('Convert_OBJ_to_POV:noFaces', 'The file has no faces to build a scene from.'); end
Vu = V(used, :);
xr = [min(Vu(:,1)) max(Vu(:,1))];
yr = [min(Vu(:,2)) max(Vu(:,2))];
zr = [min(Vu(:,3)) max(Vu(:,3))];
clear Vu
fprintf('Bounding box: X [%g %g]  Y [%g %g]  Z [%g %g]\n', xr(1),xr(2), yr(1),yr(2), zr(1),zr(2));

% IMPORTANT: the RaySAR-adapted engine silently fails to produce any
% output (no render, no Contributions.txt) whenever the ground plane sits
% below world Y=0 -- found by bisection. Every official RaySAR test scene
% (Step.pov, Test_Building.pov) keeps ground at exactly Y=0 with all
% geometry at Y>=0, so shift the whole model up to match that convention
% instead of placing ground at a per-scene (possibly negative) offset.
V(:,2) = V(:,2) - yr(1);
yr = yr - yr(1);

% Frame each axis to its own extent (not a shared square sized to the
% longer one) -- fine for roughly-square scenes, but a shared square
% wastes almost the whole frame on an elongated object like a ship (the
% width ends up sized to the length, leaving the object a thin strip).
default_extent = [(xr(2)-xr(1))*1.3, (zr(2)-zr(1))*1.3];
view_extent = g('view_extent', default_extent);
cam_height = g('cam_height', max(view_extent));
ground = g('ground', true);

% Where the camera looks -- defaults to world origin (the whole model, as
% shifted/recentered above), but can be pointed at a sub-region of a large
% scene instead (e.g. one district of a big city model) by passing the
% world-space [x,y,z] of that region's center. Camera location keeps the
% same <0,H,-H>-relative-to-look_at offset that gives the 45 deg incidence,
% just translated to the new target.
if g('center', false)
    default_look = [mean(xr) 0 mean(zr)];
else
    default_look = [0 0 0];
end
look_at = g('look_at', default_look);

fid = fopen(out_pov_path,'w');
fprintf(fid, '%s', POV_Header(sprintf('Converted from %s (Convert_OBJ_to_POV.m)', obj_path), ...
    look_at, 0, 45, cam_height*sqrt(2), view_extent));

if ground
    ground_finish = g('ground_finish', 'finish {reflection {0.3} ambient 0 diffuse 0.15 specular 0}');
    fprintf(fid, 'plane {\n  <0,1,0>\n  0\n  pigment {color White}\n  %s\n}\n\n', ground_finish);
end

% IMPORTANT: the RaySAR-adapted POV-Ray engine silently fails to produce
% any output (no render, no Contributions.txt) once a single mesh2{}
% object's vertex count crosses somewhere around ~133 vertices -- found
% by bisection, since RaySAR's contribution-tracking patch appears to use
% a fixed-size per-object buffer that stock POV-Ray/mesh2 has no such
% limit for. The fix is to split the mesh into many small mesh2{} objects
% (well under the discovered threshold) rather than one big one -- this
% matches how the procedurally-generated scenes (many small box{} objects)
% already work fine.
max_verts = g('max_verts_per_mesh', 100);

% Which parts of the ground plan have structure on them, kept with the scene for
% planning views (see Occupied_Area)
progress('Mapping where the structure is ...');
plan_map = plan_grid(V, tri, xr, zr, yr);

% Triangles in order of where they are (a Morton curve over the ground plan), so
% that the objects cut from them are small patches, not pieces scattered over
% the whole scene. Views then only have to load the patches they can see.
progress('Ordering the triangles by position ...');
tri = tri(spatial_order(V, tri, xr, zr), :);

n_faces_total = size(tri,1);
localIdx = zeros(n_v,1);       % 0 = vertex not in current chunk, else its local 1-based index
chunkVertGlobal = zeros(max_verts,1);
chunkTris = zeros(max_verts*4,3); % upper bound on triangles before hitting max_verts; grown if a mesh needs more
nChunkVerts = 0;
nChunkTris = 0;
n_chunks = 0;
n_alloc = ceil(n_faces_total/30) + 100;
c_start = zeros(n_alloc, 1);
c_stop = zeros(n_alloc, 1);
c_box = zeros(n_alloc, 6);
next_report = 0;

for t = 1:n_faces_total
    g1 = tri(t,1); g2 = tri(t,2); g3 = tri(t,3);

    newCount = (localIdx(g1)==0) + (localIdx(g2)==0) + (localIdx(g3)==0);
    if nChunkVerts > 0 && nChunkVerts + newCount > max_verts
        n_chunks = n_chunks + 1;
        [c_start, c_stop, c_box] = grow(c_start, c_stop, c_box, n_chunks);
        c_start(n_chunks) = ftell(fid);
        c_box(n_chunks, :) = write_mesh_chunk(fid, V, chunkVertGlobal(1:nChunkVerts), chunkTris(1:nChunkTris,:), finish_str);
        c_stop(n_chunks) = ftell(fid);
        localIdx(chunkVertGlobal(1:nChunkVerts)) = 0;
        nChunkVerts = 0;
        nChunkTris = 0;
        if t >= next_report
            progress(sprintf('Writing the scene: %.0f%%', 100*t/n_faces_total));
            next_report = t + max(1, floor(n_faces_total/50));
        end
    end

    if localIdx(g1)==0
        nChunkVerts = nChunkVerts+1; chunkVertGlobal(nChunkVerts) = g1; localIdx(g1) = nChunkVerts;
    end
    if localIdx(g2)==0
        nChunkVerts = nChunkVerts+1; chunkVertGlobal(nChunkVerts) = g2; localIdx(g2) = nChunkVerts;
    end
    if localIdx(g3)==0
        nChunkVerts = nChunkVerts+1; chunkVertGlobal(nChunkVerts) = g3; localIdx(g3) = nChunkVerts;
    end

    nChunkTris = nChunkTris+1;
    if nChunkTris > size(chunkTris, 1), chunkTris(end+1:2*end, :) = 0; end
    chunkTris(nChunkTris,:) = [localIdx(g1), localIdx(g2), localIdx(g3)];
end

if nChunkVerts > 0
    n_chunks = n_chunks + 1;
    [c_start, c_stop, c_box] = grow(c_start, c_stop, c_box, n_chunks);
    c_start(n_chunks) = ftell(fid);
    c_box(n_chunks, :) = write_mesh_chunk(fid, V, chunkVertGlobal(1:nChunkVerts), chunkTris(1:nChunkTris,:), finish_str);
    c_stop(n_chunks) = ftell(fid);
end

fclose(fid);
fprintf('Wrote %s (%d mesh2 objects, max %d vertices each)\n', out_pov_path, n_chunks, max_verts);

info.bbox = [xr; yr; zr];
info.look_at = look_at;
info.n_meshes = n_chunks;
info.up_axis = up_axis;
info.scale = scale;
info.n_triangles = n_faces_total;
info.findings = resolved.findings;
info.warnings = resolved.warnings;
info.plan = plan_map;
info.chunks = struct('start', c_start(1:n_chunks), 'stop', c_stop(1:n_chunks), 'box', c_box(1:n_chunks, :));
end

function m = plan_grid(V, tri, xr, zr, yr)
% A map of the ground plan: which squares have structure on them. Structure is
% what a radar image is made of: walls and steep slopes (surfaces that are more
% than about 60 degrees from flat), which give layover, shadow and bright edges.
% Flat ground, roofs and gentle terrain are not, however high they lie, so a
% city on a plateau counts as the city, not as the whole plateau. Each such
% triangle marks the squares its bounding box covers. Squares are at least 1 m
% and at most about 1500 across the scene.
cell = max(1, max(xr(2) - xr(1), zr(2) - zr(1))/1500);
nx = max(1, ceil((xr(2) - xr(1))/cell));
nz = max(1, ceil((zr(2) - zr(1))/cell));
min_rise = min(1, 0.05*yr(2));       % ignore steep faces smaller than this, such as kerbs
D = zeros(nz + 1, nx + 1);
E = false(nz, nx);
n = size(tri, 1);
step = 2e6;
for i0 = 1:step:n
    t = tri(i0:min(n, i0 + step - 1), :);
    P1 = V(t(:,1), :); P2 = V(t(:,2), :); P3 = V(t(:,3), :);
    N = cross(P2 - P1, P3 - P1, 2);
    len = sqrt(sum(N.^2, 2));
    Y = [P1(:,2) P2(:,2) P3(:,2)];
    steep = len > 0 & abs(N(:,2)) < 0.5*len & (max(Y, [], 2) - min(Y, [], 2)) >= min_rise;
    X = [P1(steep,1) P2(steep,1) P3(steep,1)];
    Z = [P1(steep,3) P2(steep,3) P3(steep,3)];
    if isempty(X), continue; end
    ix0 = min(nx, floor((min(X, [], 2) - xr(1))/cell) + 1);
    ix1 = min(nx, floor((max(X, [], 2) - xr(1))/cell) + 1);
    iz0 = min(nz, floor((min(Z, [], 2) - zr(1))/cell) + 1);
    iz1 = min(nz, floor((max(Z, [], 2) - zr(1))/cell) + 1);

    % A small triangle marks its whole box. A large steep one (a cliff face, a
    % long wall) is thin seen from above but has a big box, so only its three
    % edges are traced.
    big = max(ix1 - ix0, iz1 - iz0) > 3;
    a0 = ix0(~big); a1 = ix1(~big); b0 = iz0(~big); b1 = iz1(~big);
    m1 = numel(a0);
    D = D + accumarray([b0 a0; b0 a1 + 1; b1 + 1 a0; b1 + 1 a1 + 1], [ones(m1, 1); -ones(m1, 1); -ones(m1, 1); ones(m1, 1)], [nz + 1, nx + 1]);
    Xb = X(big, :); Zb = Z(big, :);
    tt = linspace(0, 1, 128);
    for j0 = 1:20000:size(Xb, 1)
        r = j0:min(size(Xb, 1), j0 + 19999);
        for e = 1:3
            f = mod(e, 3) + 1;
            px = Xb(r, e) + (Xb(r, f) - Xb(r, e)).*tt;
            pz = Zb(r, e) + (Zb(r, f) - Zb(r, e)).*tt;
            qx = min(nx, floor((px(:) - xr(1))/cell) + 1);
            qz = min(nz, floor((pz(:) - zr(1))/cell) + 1);
            E(sub2ind([nz nx], qz, qx)) = true; %#ok<AGROW>
        end
    end
end
G = (cumsum(cumsum(D, 1), 2) > 0);
G = G(1:nz, 1:nx) | E;
m = struct('x0', xr(1), 'z0', zr(1), 'cell', cell, 'grid', G);
end

function [a, b, c] = grow(a, b, c, n)
% Room for chunk n
if n > numel(a)
    m = 2*numel(a);
    a(m) = 0; b(m) = 0; c(m, 6) = 0;
end
end

function ord = spatial_order(V, tri, xr, zr)
% The order that puts triangles that are near each other in the plan next to
% each other: a Morton (Z-order) key from the centre of each triangle, 16 bits
% for each of the two horizontal axes.
n = size(tri, 1);
key = zeros(n, 1, 'uint32');
sx = 65535/max(xr(2) - xr(1), eps);
sz = 65535/max(zr(2) - zr(1), eps);
step = 2e6;
for i0 = 1:step:n
    i1 = min(n, i0 + step - 1);
    t = tri(i0:i1, :);
    cx = (V(t(:,1),1) + V(t(:,2),1) + V(t(:,3),1))/3;
    cz = (V(t(:,1),3) + V(t(:,2),3) + V(t(:,3),3))/3;
    qx = uint32(min(65535, max(0, (cx - xr(1))*sx)));
    qz = uint32(min(65535, max(0, (cz - zr(1))*sz)));
    key(i0:i1) = bitor(spread_bits(qx), bitshift(spread_bits(qz), 1));
end
[~, ord] = sort(key);      % stable: triangles with the same key keep the file's order
end

function x = spread_bits(x)
% 16 bits with a zero between each
x = bitand(bitor(x, bitshift(x, 8)), uint32(hex2dec('00FF00FF')));
x = bitand(bitor(x, bitshift(x, 4)), uint32(hex2dec('0F0F0F0F')));
x = bitand(bitor(x, bitshift(x, 2)), uint32(hex2dec('33333333')));
x = bitand(bitor(x, bitshift(x, 1)), uint32(hex2dec('55555555')));
end

function box = write_mesh_chunk(fid, V, globalIdxList, localTris, finish_str)
    Vc = V(globalIdxList,:);
    box = [min(Vc, [], 1) max(Vc, [], 1)];
    tri0 = localTris - 1;
    fprintf(fid, 'mesh2 {\n  vertex_vectors {\n    %d,\n', size(Vc,1));
    if size(Vc,1) > 1
        fprintf(fid, '    <%.4f,%.4f,%.4f>,\n', Vc(1:end-1,:)');
    end
    fprintf(fid, '    <%.4f,%.4f,%.4f>\n', Vc(end,:)');
    fprintf(fid, '  }\n  face_indices {\n    %d,\n', size(tri0,1));
    if size(tri0,1) > 1
        fprintf(fid, '    <%d,%d,%d>,\n', tri0(1:end-1,:)');
    end
    fprintf(fid, '    <%d,%d,%d>\n', tri0(end,:)');
    fprintf(fid, '  }\n  pigment {color White}\n  %s\n}\n\n', finish_str);
end

function v = get_opt(opts,name,defv)
    if isfield(opts,name), v = opts.(name); else, v = defv; end
end
