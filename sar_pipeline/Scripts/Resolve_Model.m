function r = Resolve_Model(a, up, scale)
% Turns what Analyze_Mesh found, and the user's own choices, into the up axis
% and scale to use, the size the model then has in metres, and a plain
% description of it all.
%
% a:      from Analyze_Mesh (or Analyze_OBJ)
% up:     'auto', 'y' or 'z'                                   (default 'auto')
% scale:  'auto', or metres per unit of the file, e.g. 0.01     (default 'auto')
%
% r fields:
%   up, scale, units    what will be used; units is a name ("centimetres")
%   size_m              [across height depth] in m after the scale
%   bulk_m              the same for the bulk of the model, without far-off points
%   pts                 a sample of the vertices [x height z] in m, for the map
%   structure           a sample of points [x z] in m on walls and steep slopes,
%                       to judge how much of the plan has structure on it
%   findings            cell array of sentences: what the model is
%   warnings            cell array of sentences: things to know or to check
%   auto_up, auto_scale whether each was worked out here (true) or chosen (false)

if nargin < 2 || isempty(up), up = 'auto'; end
if nargin < 3 || isempty(scale), scale = 'auto'; end

r.auto_up = strcmpi(up, 'auto');
if r.auto_up, r.up = a.up_auto; else, r.up = lower(up); end
if r.up == 'z'
    order = [1 3 2];       % across, height, depth
else
    order = [1 2 3];
end
raw = a.raw_ext(order);
bulk = a.bulk_ext(order);

r.auto_scale = ischar(scale) || isstring(scale);
unit_reason = '';
if r.auto_scale
    [r.scale, r.units, unit_reason] = guess_scale(raw, a.hint_scale, a.hint_name);
else
    r.scale = double(scale);
    r.units = unit_name(r.scale);
    unit_reason = 'as you chose';
end

r.size_m = raw*r.scale;
r.bulk_m = bulk*r.scale;
r.pts = a.pts_raw(:, order)*r.scale;

% Where the structure is: the centres of the sampled triangles that are steep
% (walls and steep slopes, see Convert_OBJ_to_POV), on the ground plan, in m
steep = a.tri_n(:, order(2)) < 0.5;
r.structure = double(a.tri_c(steep, [order(1) order(3)]))*r.scale;

f = {};
w = {};
f{end+1} = sprintf('%s triangles, %s vertices%s.', with_commas(a.n_triangles), with_commas(a.n_vertices), file_size(a.bytes));
f{end+1} = sprintf('As saved it measures %s x %s x %s units (across, up, deep).', num(raw(1)), num(raw(2)), num(raw(3)));
if r.auto_up
    f{end+1} = ['Up: ' ternary_up(r.up) '. ' a.up_reason];
else
    f{end+1} = ['Up: ' ternary_up(r.up) ', as you chose.'];
end
if r.scale == 1
    f{end+1} = sprintf('Units: %s (%s).', r.units, unit_reason);
else
    f{end+1} = sprintf('Units: %s, so every size is multiplied by %g (%s).', r.units, r.scale, unit_reason);
end
f{end+1} = sprintf('Size in metres: %s across, %s tall, %s deep.', length_text(r.size_m(1)), length_text(r.size_m(2)), length_text(r.size_m(3)));
r.findings = f;

if a.n_bad_vertices > 0
    w{end+1} = sprintf('%d vertices had no valid number and were ignored.', a.n_bad_vertices);
end
big = raw > 5*max(bulk, eps);
if any(big) && all(bulk > 0)
    w{end+1} = sprintf(['A few far-off parts make the model %.0f times wider than its main body (a large ground plane or a ' ...
        'stray point, usually). The size above includes them.'], max(raw(big)./bulk(big)));
end
if max(r.size_m([1 3])) > 20000
    w{end+1} = 'This is a very large scene. Images of the whole scene are coarse; the detailed images are windows on parts of it.';
end
if max(r.size_m([1 3])) < 3
    w{end+1} = 'The model is tiny for a radar (a few metres or less). Check Units.';
end
if r.size_m(2) > 9000
    w{end+1} = 'The model is taller than the highest mountain. Check Units.';
end
if a.n_triangles > 3e6
    w{end+1} = sprintf('%.1f million triangles: converting takes a few minutes, once. Views then use only the part of the model that is in them.', a.n_triangles/1e6);
end
r.warnings = w;
end


function [s, name, reason] = guess_scale(raw, hint_s, hint_name)
% Units from the file's own words if they give a believable size, else from the size
W = max(raw([1 3]));
H = raw(2);
believable = @(s) W*s >= 3 && W*s <= 60000 && H*s <= 9000;

if ~isnan(hint_s)
    if believable(hint_s)
        s = hint_s; name = hint_name;
        reason = sprintf('the file says so in its header');
        return
    end
    note = sprintf('the file says %s, but that would make it %s across and %s tall, which is not believable, so that is ignored; ', ...
        hint_name, length_text(W*hint_s), length_text(H*hint_s));
else
    note = '';
end

cand = {1, 'metres'; 0.01, 'centimetres'; 0.001, 'millimetres'; 0.0254, 'inches'; 0.3048, 'feet'};
for i = 1:size(cand, 1)
    if believable(cand{i, 1})
        s = cand{i, 1}; name = cand{i, 2};
        if i == 1
            reason = [note 'as saved, the size is believable'];
        else
            reason = sprintf('%sas metres it would be %s across and %s tall, which is too big; as %s it is believable', ...
                note, length_text(W), length_text(H), name);
        end
        return
    end
end
% Nothing fits: scale by a power of ten to a usable size
if W < 3
    s = 10^ceil(log10(30/W));
    name = 'scaled up';
    reason = sprintf('%sit is only %s across as saved, too small for a radar, so it is enlarged %g times', note, length_text(W), s);
else
    s = 10^-ceil(log10(W/3000));
    name = 'scaled down';
    reason = sprintf('%sit is %s across as saved, too large for any radar scene, so it is reduced to about 3 km', note, length_text(W));
end
end


function n = unit_name(s)
names = {1, 'metres'; 0.01, 'centimetres'; 0.001, 'millimetres'; 0.0254, 'inches'; 0.3048, 'feet'; 1000, 'kilometres'};
n = sprintf('custom (x%g)', s);
for i = 1:size(names, 1)
    if abs(s - names{i, 1}) < 1e-12, n = names{i, 2}; return; end
end
end


function s = ternary_up(u)
if u == 'z', s = 'Z'; else, s = 'Y'; end
end


function s = length_text(m)
if m >= 1000
    s = sprintf('%.1f km', m/1000);
elseif m >= 10
    s = sprintf('%.0f m', m);
else
    s = sprintf('%.1f m', m);
end
end


function s = num(x)
if x >= 100, s = sprintf('%.0f', x); else, s = sprintf('%.3g', x); end
end


function s = with_commas(n)
s = regexprep(sprintf('%d', round(n)), '(\d)(?=(\d{3})+$)', '$1,');
end


function s = file_size(b)
if isnan(b), s = ''; return; end
s = sprintf(' (%.1f MB file)', b/2^20);
end
