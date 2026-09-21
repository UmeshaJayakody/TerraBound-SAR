function view = Write_View_POV(dst_pov, body, bbox, bearing, incidence, center, fraction, extent_m)
% Writes one look at a converted scene: a new camera and light, with the
% model itself (body) left exactly as Convert_OBJ_to_POV wrote it.
%
% body:      the scene text from the ground plane / first mesh onwards, i.e.
%            everything after the header. Or, for a large scene, a struct with
%            fields pov (the scene file) and info (what Convert_OBJ_to_POV
%            returned): then only the parts of the scene that can matter to this
%            view are written (see Scene_Body), which is what keeps a view of a
%            small window on a huge scene fast.
% bbox:      [xmin xmax; ymin ymax; zmin zmax] of the model
% bearing:   look direction in degrees around the vertical axis
% incidence: angle from the vertical in degrees
% center:    [x z] ground point at the middle of the view (default: the
%            middle of the model's footprint)
% fraction:  how much of the full frame the view covers, 1 = the whole
%            model, 0.5 = a window half as wide and half as tall (default 1)
% extent_m:  [width height] of the window in m, if you want it exactly; this
%            replaces fraction (default: not given)
%
% A window is just a smaller frame put somewhere else. The rest of the scene
% is still there, so shadows fall into the window from objects outside it and
% tall buildings just outside can still lean into it, as in a real chip cut
% from a larger SAR scene.
%
% Returns the view actually written.

if nargin < 6 || isempty(center)
    center = [mean(bbox(1,:)) mean(bbox(3,:))];
end
if nargin < 7 || isempty(fraction), fraction = 1; end
if nargin < 8, extent_m = []; end

foot = [mean(bbox(1,:)) 0 mean(bbox(3,:))];
full = View_Frame(bbox, foot, bearing, incidence);   % the whole model from this direction
look_at = [center(1) 0 center(2)];
[~, dist] = View_Frame(bbox, look_at, bearing, incidence);
extent = fraction*full;
if ~isempty(extent_m), extent = extent_m(:)'; end

comment = sprintf('View: bearing %g deg, incidence %g deg, window %g at x=%.1f z=%.1f (Write_View_POV.m)', ...
    bearing, incidence, fraction, center(1), center(2));
header = POV_Header(comment, look_at, bearing, incidence, dist, extent);

view.kept = NaN; view.of = NaN;
if isstruct(body)
    [body, view.kept, view.of] = Scene_Body(body.pov, body.info, ...
        struct('bearing', bearing, 'incidence', incidence, 'look_at', look_at, 'extent', extent));
end

fid = fopen(dst_pov, 'w');
if fid < 0, error('Write_View_POV:open', 'Could not write %s', dst_pov); end
fwrite(fid, [header body], 'char');
fclose(fid);

view.bearing = bearing;
view.incidence = incidence;
view.look_at = look_at;
view.fraction = fraction;
view.extent = extent;
view.full_extent = full;
view.dist = dist;
end
