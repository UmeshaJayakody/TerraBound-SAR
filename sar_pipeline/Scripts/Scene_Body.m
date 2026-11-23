function [body, n_kept, n_all] = Scene_Body(pov_path, info, view)
% The text of a converted scene for one view: the ground plane and only those of
% the scene's mesh objects that can affect what this view sees.
%
% A big scene (a city, an island) has millions of triangles, and a view of a
% small window needs almost none of them. Ray tracing time and memory go with
% what is loaded, so loading only what matters is what lets a scene of any
% size be used, at the same cost per view as a small one.
%
% The sensor is orthographic, so it sees a straight tube of space: the window,
% carried along the look direction. Rays that leave the sensor can only hit what
% is in that tube. Everything the window shows, and everything that can shade or
% hide it, is in the tube. The tube is widened by a margin, so that rays that
% bounce off a wall and travel on still find their surroundings: the height of
% the tallest thing in the scene, at least, and half the window.
%
% pov_path: the .pov scene written by Convert_OBJ_to_POV
% info:     what it returned (bbox and chunks)
% view:     struct with bearing, incidence (degrees), look_at ([x y z]) and
%           extent ([width height] of the window in m)
%
% body:     the scene text from the ground plane onwards, ready for Write_View_POV
% n_kept:   mesh objects loaded
% n_all:    mesh objects in the scene

ch = info.chunks;
n_all = numel(ch.start);

b = view.bearing*pi/180;
i = view.incidence*pi/180;
toward = [sin(i)*sin(b), cos(i), -sin(i)*cos(b)];   % from the scene to the sensor
d = -toward;                                        % the look direction
u = cross([0 1 0], d);  u = u/norm(u);              % across the view
v = cross(d, u);                                    % up the view

margin = max([info.bbox(2, 2), 0.5*max(view.extent), 20]);
lim_u = view.extent(1)/2 + margin;
lim_v = view.extent(2)/2 + margin;

lo = ch.box(:, 1:3) - view.look_at(:)';
hi = ch.box(:, 4:6) - view.look_at(:)';
[u_lo, u_hi] = project(lo, hi, u);
[v_lo, v_hi] = project(lo, hi, v);
keep = u_hi >= -lim_u & u_lo <= lim_u & v_hi >= -lim_v & v_lo <= lim_v;
sel = find(keep);
n_kept = numel(sel);

fid = fopen(pov_path, 'r');
if fid < 0, error('Scene_Body:open', 'Could not read %s', pov_path); end
closer = onCleanup(@() fclose(fid));

% Everything before the first mesh object: the header (dropped, the view has its
% own camera and light) and the ground plane, which stays
head = fread(fid, ch.start(1), '*char')';
k = regexp(head, '(?m)^(plane|mesh2)\s*\{', 'start', 'once');
if isempty(k), body_head = ''; else, body_head = head(k:end); end

% The chosen objects, read as few long pieces (neighbours are next to each
% other in the file)
parts = cell(1, 0);
if n_kept > 0
    breaks = [0; find(diff(sel) > 1); n_kept];
    for r = 1:numel(breaks) - 1
        first = sel(breaks(r) + 1);
        last = sel(breaks(r + 1));
        fseek(fid, ch.start(first), 'bof');
        parts{end+1} = fread(fid, ch.stop(last) - ch.start(first), '*char')'; %#ok<AGROW>
    end
end
body = [body_head parts{:}];
end


function [lo, hi] = project(lo_rel, hi_rel, dir)
% The range, along direction dir, of each box given by its corners relative to
% the point of view
a = lo_rel .* dir;
c = hi_rel .* dir;
lo = sum(min(a, c), 2);
hi = sum(max(a, c), 2);
end
