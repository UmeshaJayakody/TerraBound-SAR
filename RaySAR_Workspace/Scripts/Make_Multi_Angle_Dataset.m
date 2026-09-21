function [index, notes] = Make_Multi_Angle_Dataset(obj_path, out_root, opts)
% From one .obj file to many HR/LR SAR image pairs, each from a different
% look at the object.
%
%   .obj -> scene (.pov), converted once
%   for every view:
%       camera and light placed for that view -> ray trace ->
%       Contributions.txt -> radar signal chain -> HR.png and LR_*.png
%
% A view is a look direction (bearing), an incidence angle, and a window: a
% position over the object and a size. Windows can be the whole scene or any
% part of it, from any side, so one object gives whole-scene images, side
% views and small chips alike. Every view is a genuinely different image
% (different faces, shadow and layover, and its own speckle seed), not a
% crop or a rotation of another.
%
% Every view of an object uses the same radar bandwidth, so all its images
% have the same resolution and pixel size; a smaller window is simply a
% smaller image.
%
% obj_path: the .obj file
% out_root: folder for the dataset; this object's files go in out_root/<name>/
%
% opts fields (all optional). Two ways to choose the views:
%
%  Systematic (default): every combination of the following.
%   bearings     look directions in degrees around the object   (default 0:45:315)
%   incidences   angles from the vertical in degrees            (default 45)
%   window       fraction of the full frame each view covers,
%                1 = the whole scene                            (default 1)
%   grid         n puts windows at n x n positions tiled over
%                the object; 1 = one window in the middle       (default 1)
%
%  Whole scene as well: set full_bearings (e.g. [0 90 180 270], the four
%  sides) and those whole-scene views, at each of full_incidences (default 45),
%  come first. They can be followed by random views (n_random) or systematic
%  ones (bearings and the options above); with neither, they are all there is.
%   full_bearings    look directions of the whole-scene views
%   full_incidences  their incidence angles                     (default 45)
%
%  Random: set n_random, or coverage, and that many partial views are drawn,
%  each with its own bearing, incidence, window size and position. Repeatable
%  for a given seed.
%   n_random         number of views                            (default 0, off)
%   coverage         instead of n_random: enough views that each part of the
%                    object is seen about this many times, so a bigger object
%                    gets more views (see Views_For_Coverage). Needs window_m.
%   n_min, n_max     limits on that number                      (default 10, 2000)
%   bearing_range    [min max] degrees                          (default [0 360])
%   incidence_range  [min max] degrees from the vertical        (default [30 60])
%   side_fraction    share of the views taken from a low angle,
%                    so walls show, 0 to 1                      (default 0)
%   side_range       [min max] degrees for those side views     (default [65 85])
%   window_range     [min max] fraction of the full frame       (default [0.35 0.7])
%   window_m         instead of window_range: [min max] window size in
%                    metres, so windows cover the same ground on every object
%
%  Both:
%   bw           radar bandwidth in Hz, or 'auto', which picks one for the
%                object so its full scene is about target_px across  (default 'auto')
%   target_px    see bw                                         (default 800)
%   factors      how many times coarser each LR image is        (default [2 4 8])
%   seed         speckle seed of the first view; later views get seed+1, ...  (default 1)
%   rays_per_pixel  how finely the ray tracer samples: rays per image pixel,
%                per side. The same for every view, so a small window on a big
%                object is sampled as well as a whole small object   (default 1.25)
%   max_px       views whose image would be more than this many pixels
%                across are left out, and reported in notes          (default 2000)
%   up_axis, finish, ground, ground_finish
%                passed to Convert_OBJ_to_POV
%   overwrite    redo everything, including the conversion (default false).
%                Otherwise views that already have images with the same
%                settings are skipped, so an interrupted run carries on
%                where it stopped.
%   save_complex keep the complex images in sar_images.mat      (default true)
%   keep_files   keep each view's .pov and Contributions.txt, about 50 MB per
%                view and not needed once the images exist      (default false)
%   bounce_max   keep bounce levels up to this                  (default all)
%   top_down     orient the PNGs like RaySAR's top-down maps    (default true)
%   progress     function handle f(text), told what is happening
%   view_done    function handle f(i, n, row), called as each view finishes
%   should_stop  function handle returning true to stop before the next view
%
% Writes out_root/<name>/
%   scene/<name>.pov         the converted object
%   views/v001_whole_az045_inc45/  HR.png, LR_mid.png, LR_low.png, LR_vlow.png,
%                            sar_images.mat, view_info.mat
%   dataset_index.csv        one row per view
% and returns the same table as a struct array. notes lists anything that was
% left out, and why.

if nargin < 3, opts = struct(); end
g = @(n, d) get_opt(opts, n, d);

overwrite  = g('overwrite', false);
keep_files = g('keep_files', false);
report     = g('progress', @(s) []);
view_done  = g('view_done', @(i, n, row) []);
should_stop = g('should_stop', @() false);
seed0      = g('seed', 1);
rays_pp    = g('rays_per_pixel', 1.25);
max_px     = g('max_px', 2000);
notes      = {};
factors    = [2 4 8];
if isfield(opts, 'factors'), factors = opts.factors; end   % empty means HR images only

here = fileparts(mfilename('fullpath'));
addpath(here);
addpath(fullfile(fileparts(here), 'SAR_Imaging'));

[~, name] = fileparts(obj_path);
name = regexprep(name, '[^A-Za-z0-9_-]+', '_');
root = fullfile(out_root, name);
scene_dir = fullfile(root, 'scene');
views_dir = fullfile(root, 'views');
if exist(scene_dir, 'dir') ~= 7, mkdir(scene_dir); end
if exist(views_dir, 'dir') ~= 7, mkdir(views_dir); end

% 1) The object becomes a scene, once. Parsing a large mesh is the slow part
%    of converting, and it does not depend on the view.
base_pov = fullfile(scene_dir, [name '.pov']);
info_mat = fullfile(scene_dir, 'scene_info.mat');
if ~overwrite && exist(base_pov, 'file') == 2 && exist(info_mat, 'file') == 2
    fprintf('Using the scene already converted: %s\n', base_pov);
    load(info_mat, 'info');
else
    report('Converting the object ...');
    co = struct('center', true);   % objects are not all built around the origin
    for f = {'up_axis', 'finish', 'ground', 'ground_finish'}
        if isfield(opts, f{1}), co.(f{1}) = opts.(f{1}); end
    end
    info = Convert_OBJ_to_POV(obj_path, base_pov, co);
    save(info_mat, 'info');
end

% Everything from the ground plane or the first mesh onwards is the model.
% Only the camera and light above it change from view to view.
txt = fileread(base_pov);
k = regexp(txt, '(?m)^(plane|mesh2)\s*\{', 'start', 'once');
if isempty(k)
    error('Make_Multi_Angle_Dataset:noModel', 'No plane or mesh found in %s', base_pov);
end
body = txt(k:end);
clear txt

% 2) The views, and the one bandwidth they all share
plan = plan_views(opts, info.bbox, seed0);
n_views = numel(plan);

bw = g('bw', 'auto');
if ischar(bw) || isstring(bw)
    % From the largest the whole scene looks from any direction, not from
    % the views chosen, so the resolution belongs to the object and stays
    % the same however many views are taken
    foot = [mean(info.bbox(1,:)) 0 mean(info.bbox(3,:))];
    ext = 0;
    for b = 0:15:345
        ext = max(ext, max(View_Frame(info.bbox, foot, b, 45)));
    end
    bw = Auto_Bandwidth(ext, g('target_px', 800));
    fprintf('Bandwidth for every view: %.0f MHz (%.2f m resolution), so the whole scene is about %d px across\n', ...
        bw/1e6, 299792458/(2*bw), g('target_px', 800));
end

% 2b) How big each view's image will be, and how many rays it needs. The
%     image is as wide as the frame; at a low look angle the ground stretches
%     out along the range, by about tan(incidence) (checked against images made
%     at 45 to 85 degrees, within a few percent).
pix = 299792458/(2*bw)/2;
rays = cell(1, n_views);
too_big = false(1, n_views);
for i = 1:n_views
    [px, rays{i}] = view_size(info.bbox, plan(i), pix, rays_pp);
    too_big(i) = max(px) > max_px;
end
if any(too_big)
    notes{end+1} = sprintf(['%d of %d views were left out: at %.2f m resolution their images would be more than ' ...
        '%d px across. Choose smaller windows or a coarser resolution.'], sum(too_big), n_views, 2*pix, max_px);
    fprintf('%s\n', notes{end});
    plan = plan(~too_big);
    rays = rays(~too_big);
    n_views = numel(plan);
    if n_views == 0
        error('Make_Multi_Angle_Dataset:tooLarge', '%s', notes{end});
    end
end
fprintf('\n%d views of %s\n', n_views, name);

% 3) One image set per view
for i_view = 1:n_views
    if should_stop()
        fprintf('\nStopped before view %d of %d.\n', i_view, n_views);
        break
    end
    p = plan(i_view);
    if p.fraction >= 1, kind = 'whole'; else, kind = sprintf('win%02.0f', 100*p.fraction); end
    id = sprintf('v%03d_%s_az%03.0f_inc%02.0f', i_view, kind, mod(p.bearing, 360), p.incidence);
    vdir = fullfile(views_dir, id);
    label = sprintf('view %d of %d (%s)', i_view, n_views, id);

    row = view_row(id, p);
    row.seed = seed0 + i_view - 1;
    row.bandwidth_mhz = bw/1e6;
    row.factors = mat2str(factors);
    row.settings = sprintf('bounce%g_top%d_rays%g', g('bounce_max', inf), g('top_down', true), rays_pp);

    if ~overwrite && already_done(vdir, row)
        fprintf('\n%s already done, skipping\n', label);
        view_done(i_view, n_views, load_row(vdir));
        continue
    end
    fprintf('\n==== %s: bearing %g, incidence %g, window %.2f at x=%.1f z=%.1f ====\n', ...
        label, p.bearing, p.incidence, p.fraction, p.center(1), p.center(2));
    report([label ': ray tracing ...']);

    t0 = tic;
    pov = fullfile(vdir, 'view.pov');
    try
        if exist(vdir, 'dir') ~= 7, mkdir(vdir); end
        v = Write_View_POV(pov, body, info.bbox, p.bearing, p.incidence, p.center, p.fraction);
        row.window_m = sprintf('%.1f x %.1f', v.extent(1), v.extent(2));
        contrib = Render_POV(pov, vdir, rays{i_view});

        so.bw = bw;
        so.extent_from = 'single';   % the frame, not stray multi-bounce rays, sets the image
        so.bounce_max = g('bounce_max', inf);
        so.top_down = g('top_down', true);
        so.factors = factors;
        so.seed = row.seed;
        so.save_mat = g('save_complex', true);
        so.progress = @(s) report([label ': ' s]);
        res = Run_SAR_From_Contributions(contrib, vdir, so);

        row.status = 'done';
        row.hr_res_m = res.resolution(1, 1);
        row.image_px = res.image_size(2);
        row.image_py = res.image_size(1);
        row.lr = strjoin(res.files(2:end), ';');
    catch err
        row.status = 'failed';
        row.message = err.message;
        fprintf(2, 'FAILED %s: %s\n', label, err.message);
    end
    row.seconds = toc(t0);

    % The engine leaves a preview image, and Contributions.txt is big and
    % cheap to regenerate; the images are what the dataset is for.
    if ~keep_files
        for f = {pov, fullfile(vdir, 'Contributions.txt'), fullfile(vdir, 'view.png')}
            if exist(f{1}, 'file') == 2, delete(f{1}); end
        end
    end
    if exist(vdir, 'dir') == 7
        save(fullfile(vdir, 'view_info.mat'), 'row');
    end
    write_index(root);
    view_done(i_view, n_views, row);
end

index = write_index(root);
n_done = sum(strcmp({index.status}, 'done'));
fprintf('\n%d of %d views done. Index: %s\n', n_done, numel(index), fullfile(root, 'dataset_index.csv'));
if n_done < numel(index)
    fprintf('Views that failed are listed in the index with the reason; run again to retry them.\n');
end
end


function plan = plan_views(opts, bbox, seed0)
% The list of views: bearing, incidence, window centre [x z] and fraction.
% Whole-scene views come first, then either random or systematic partial views.
g = @(n, d) get_opt(opts, n, d);
plan = struct('bearing', {}, 'incidence', {}, 'center', {}, 'fraction', {});
x = bbox(1,:);
z = bbox(3,:);
middle = [mean(x) mean(z)];
foot = [middle(1) 0 middle(2)];

have_whole = isfield(opts, 'full_bearings') && ~isempty(opts.full_bearings);
if have_whole
    incidences = g('full_incidences', 45);
    for inc = incidences(:)'
        for b = opts.full_bearings(:)'
            plan(end+1) = struct('bearing', b, 'incidence', inc, 'center', middle, 'fraction', 1); %#ok<AGROW>
        end
    end
end

% How many random partial views: a fixed number, or enough that each part
% of the object appears about `coverage` times, so bigger objects get more
n_random = g('n_random', 0);
if n_random == 0 && isfield(opts, 'coverage') && ~isempty(opts.coverage)
    n_random = Views_For_Coverage((x(2) - x(1))*(z(2) - z(1)), g('window_m', [40 100]), ...
        opts.coverage, g('n_min', 10), g('n_max', 2000));
end
if n_random > 0
    br = g('bearing_range', [0 360]);
    ir = g('incidence_range', [30 60]);
    sr = g('side_range', [65 85]);
    wr = g('window_range', [0.35 0.7]);
    rs = RandStream('mt19937ar', 'Seed', seed0);
    u = @(r) r(1) + (r(2) - r(1))*rand(rs);

    % Side views look from a low angle, so walls show, instead of from above
    n_side = round(g('side_fraction', 0)*n_random);
    is_side = false(1, n_random);
    if n_side > 0, is_side(randperm(rs, n_random, n_side)) = true; end

    for i = 1:n_random
        b = round(u(br));
        if is_side(i), inc = round(u(sr)); else, inc = round(u(ir)); end
        if isfield(opts, 'window_m')
            % A window is a size in metres, so the same ground is covered
            % whatever the object; at most the whole scene
            full = View_Frame(bbox, foot, b, inc);
            frac = min(1, u(opts.window_m)/full(1));
        else
            frac = u(wr);
        end
        plan(end+1) = struct('bearing', b, 'incidence', inc, ...
            'center', [u(x) u(z)], ...   % anywhere over the object
            'fraction', round(100*frac)/100); %#ok<AGROW>
    end
    return
end
if have_whole && ~isfield(opts, 'bearings')
    return   % whole-scene views only
end

n = g('grid', 1);
if n == 1
    centers = middle;
else
    t = ((1:n) - 0.5)/n;
    [cx, cz] = meshgrid(x(1) + t*(x(2) - x(1)), z(1) + t*(z(2) - z(1)));
    centers = [cx(:) cz(:)];
end
incidences = g('incidences', 45);
bearings = g('bearings', 0:45:315);
for inc = incidences(:)'
    for b = bearings(:)'
        for c = 1:size(centers, 1)
            plan(end+1) = struct('bearing', b, 'incidence', inc, ...
                'center', centers(c,:), 'fraction', g('window', 1)); %#ok<AGROW>
        end
    end
end
end


function row = view_row(id, p)
row = struct('view', id, 'bearing_deg', p.bearing, 'incidence_deg', p.incidence, ...
    'center_x', p.center(1), 'center_z', p.center(2), 'window', p.fraction, 'window_m', '', ...
    'status', '', 'bandwidth_mhz', NaN, 'hr_res_m', NaN, 'image_px', NaN, 'image_py', NaN, ...
    'seed', NaN, 'seconds', NaN, 'factors', '', 'settings', '', 'lr', '', 'message', '');
end


function [px, rays] = view_size(bbox, p, pix, rays_pp)
% Predicted image size [columns rows] in pixels, and the rays [width height]
% the ray tracer needs to sample it at rays_pp rays per pixel
foot = [mean(bbox(1,:)) 0 mean(bbox(3,:))];
full = View_Frame(bbox, foot, p.bearing, p.incidence);
e = p.fraction*full;
phi = p.incidence*pi/180;
px = [e(1), max(e(2)*tan(phi), e(2))]/pix;
rays = min(4000, max(100, ceil(px*rays_pp)));
end


function row = load_row(vdir)
s = load(fullfile(vdir, 'view_info.mat'), 'row');
row = s.row;
end


function ok = already_done(vdir, row)
% True if this view was finished before with these very settings. A view
% folder left by a run with other settings is redone rather than trusted.
ok = false;
f = fullfile(vdir, 'view_info.mat');
if exist(fullfile(vdir, 'HR.png'), 'file') ~= 2 || exist(f, 'file') ~= 2, return; end
s = load(f, 'row');
old = s.row;
same = strcmp(old.status, 'done') && strcmp(old.factors, row.factors) && strcmp(old.settings, row.settings);
for n = {'bearing_deg', 'incidence_deg', 'center_x', 'center_z', 'window', 'seed', 'bandwidth_mhz'}
    same = same && abs(old.(n{1}) - row.(n{1})) < 1e-6*max(1, abs(row.(n{1})));
end
ok = same;
end


function index = write_index(root)
% dataset_index.csv from the view_info.mat of every view, so it is complete
% after an interrupted or resumed run too
d = dir(fullfile(root, 'views', '*', 'view_info.mat'));
index = [];
for i = 1:numel(d)
    s = load(fullfile(d(i).folder, d(i).name), 'row');
    index = [index s.row]; %#ok<AGROW>
end
if isempty(index)
    index = repmat(view_row('', struct('bearing', 0, 'incidence', 0, 'center', [0 0], 'fraction', 1)), 1, 0);
end

fid = fopen(fullfile(root, 'dataset_index.csv'), 'w');
fprintf(fid, ['view,bearing_deg,incidence_deg,center_x,center_z,window,window_m,status,bandwidth_mhz,' ...
    'hr_res_m,image_px,image_py,seed,seconds,hr,lr,message\n']);
for i = 1:numel(index)
    r = index(i);
    hr = ''; lr = '';
    if strcmp(r.status, 'done')
        hr = fullfile('views', r.view, 'HR.png');
        lr = strrep(r.lr, [root filesep], '');
    end
    msg = regexprep(r.message, '[,\r\n]+', ' ');
    fprintf(fid, '%s,%g,%g,%.2f,%.2f,%g,%s,%s,%g,%g,%g,%g,%g,%.0f,%s,%s,%s\n', r.view, r.bearing_deg, ...
        r.incidence_deg, r.center_x, r.center_z, r.window, r.window_m, r.status, r.bandwidth_mhz, ...
        r.hr_res_m, r.image_px, r.image_py, r.seed, r.seconds, hr, lr, msg);
end
fclose(fid);
end


function v = get_opt(o, n, d)
if isfield(o, n) && ~isempty(o.(n))
    v = o.(n);
else
    v = d;
end
end
