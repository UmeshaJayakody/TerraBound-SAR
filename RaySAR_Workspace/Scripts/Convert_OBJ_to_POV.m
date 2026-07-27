function Convert_OBJ_to_POV(obj_path, out_pov_path, opts)
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
%   up_axis       'y' (default, most exporters) or 'z' (3ds Max native
%                 export convention) -- swaps Y/Z columns so up is always Y
%   look_at       [x y z] world-space point (post ground-shift) to center
%                 the camera on (default: [0 0 0], i.e. the whole model) --
%                 use to zoom into one region of a large scene

if nargin < 3, opts = struct(); end
g = @(name,defv) get_opt(opts,name,defv);

fprintf('Reading %s ...\n', obj_path);
lines = readlines(obj_path);

v_lines = lines(startsWith(lines,"v "));
f_lines = lines(startsWith(lines,"f "));

n_v = numel(v_lines);
fprintf('Parsing %d vertices...\n', n_v);

% Fast path: every vertex line is "v x y z" -- parse the whole block in one
% vectorized sscanf call instead of a per-line loop (essential for large,
% imported meshes with hundreds of thousands of vertices; a per-line loop
% that's fine for a few thousand vertices becomes impractically slow here).
vvals = sscanf(strjoin(v_lines, newline), 'v %f %f %f');
if numel(vvals) == 3*n_v
    V = reshape(vvals, 3, n_v)';
else
    % Fallback for malformed/irregular vertex lines the fast path can't parse
    V = zeros(n_v,3);
    for i = 1:n_v
        parts = strsplit(strtrim(v_lines(i)));
        V(i,:) = [str2double(parts(2)), str2double(parts(3)), str2double(parts(4))];
    end
end
fprintf('Parsed %d vertices.\n', n_v);

% Parse faces, keep only the vertex index (before the first '/'), and
% fan-triangulate faces with more than 3 vertices.
n_f = numel(f_lines);
fprintf('Parsing %d faces...\n', n_f);

% Fast path: if every face is already a plain triangle "f a/x/y b/x/y c/x/y",
% parse the whole block in one vectorized sscanf call (no per-line loop).
fvals = sscanf(strjoin(f_lines, newline), 'f %d/%d/%d %d/%d/%d %d/%d/%d');
if numel(fvals) == 9*n_f
    M = reshape(fvals, 9, n_f)';
    tri = double(M(:, [1 4 7]));
    n_tri = n_f;
else
    % General fallback: variable-length faces (quads/pentagons/mixed),
    % fan-triangulated one line at a time.
    tri = zeros(n_f*2, 3); % over-allocate (n-gons split into >=1 triangles)
    n_tri = 0;
    for i = 1:n_f
        tokens = strsplit(strtrim(f_lines(i)));
        tokens = tokens(2:end); % drop leading "f"
        idx = zeros(1,numel(tokens));
        for k = 1:numel(tokens)
            vpart = strsplit(tokens{k}, '/');
            idx(k) = str2double(vpart{1});
        end
        idx = idx(~isnan(idx));
        for k = 2:numel(idx)-1
            n_tri = n_tri + 1;
            tri(n_tri,:) = [idx(1), idx(k), idx(k+1)];
        end
    end
    tri = tri(1:n_tri,:);
end
fprintf('Parsed %d faces -> %d triangles.\n', n_f, n_tri);

% OBJ indices are 1-based already, matching POV mesh2's 0-based
% face_indices after subtracting 1.
tri0 = tri - 1;

% Some exporters (notably 3ds Max's native OBJ export) write Z-up
% geometry instead of POV-Ray's Y-up convention. A tell: the two
% horizontal axes are large and roughly symmetric about 0 while the true
% "up" axis is a smaller, mostly-positive range. Swap columns so Y is
% always up before anything downstream (ground shift, framing) runs.
up_axis = g('up_axis', 'y');
if strcmpi(up_axis, 'z')
    V = V(:, [1 3 2]);
end

finish_str = g('finish','finish {reflection {0.4} ambient 0 diffuse 0.35 specular 0.5 roughness 0.01}');

xr = [min(V(:,1)) max(V(:,1))];
yr = [min(V(:,2)) max(V(:,2))];
zr = [min(V(:,3)) max(V(:,3))];
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
look_at = g('look_at', [0 0 0]);
Lx = look_at(1); Ly = look_at(2); Lz = look_at(3);

fid = fopen(out_pov_path,'w');
fprintf(fid, '#version 3.5;\n\n#include "colors.inc"\n#include "finish.inc"\n\n');
fprintf(fid, 'global_settings{SAR_Output_Data 1 SAR_Intersection 0}\n\n');
fprintf(fid, '// Converted from %s (Convert_OBJ_to_POV.m)\n\n', obj_path);

fprintf(fid, '#declare Cam = camera {\n  orthographic\n  location <%g,%g,%g>\n  look_at <%g,%g,%g>\n  right %g*x\n  up %g*y\n}\n\ncamera{Cam}\n\n', ...
    Lx, Ly+cam_height, Lz-cam_height, Lx, Ly, Lz, view_extent(1), view_extent(2));
fprintf(fid, 'light_source {\n  <%g,%g,%g>\n  color rgb <1,1,1>\n  parallel\n  point_at <%g,%g,%g>\n}\n\n', ...
    Lx, Ly+cam_height, Lz-cam_height, Lx, Ly, Lz);

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

n_faces_total = size(tri,1);
localIdx = zeros(n_v,1);       % 0 = vertex not in current chunk, else its local 1-based index
chunkVertGlobal = zeros(max_verts,1);
chunkTris = zeros(max_verts*4,3); % generous upper bound on triangles before hitting max_verts
nChunkVerts = 0;
nChunkTris = 0;
n_chunks = 0;

for t = 1:n_faces_total
    g1 = tri(t,1); g2 = tri(t,2); g3 = tri(t,3);

    newCount = (localIdx(g1)==0) + (localIdx(g2)==0) + (localIdx(g3)==0);
    if nChunkVerts > 0 && nChunkVerts + newCount > max_verts
        write_mesh_chunk(fid, V, chunkVertGlobal(1:nChunkVerts), chunkTris(1:nChunkTris,:), finish_str);
        n_chunks = n_chunks + 1;
        localIdx(chunkVertGlobal(1:nChunkVerts)) = 0;
        nChunkVerts = 0;
        nChunkTris = 0;
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
    chunkTris(nChunkTris,:) = [localIdx(g1), localIdx(g2), localIdx(g3)];
end

if nChunkVerts > 0
    write_mesh_chunk(fid, V, chunkVertGlobal(1:nChunkVerts), chunkTris(1:nChunkTris,:), finish_str);
    n_chunks = n_chunks + 1;
end

fclose(fid);
fprintf('Wrote %s (%d mesh2 objects, max %d vertices each)\n', out_pov_path, n_chunks, max_verts);

end

function write_mesh_chunk(fid, V, globalIdxList, localTris, finish_str)
    Vc = V(globalIdxList,:);
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
