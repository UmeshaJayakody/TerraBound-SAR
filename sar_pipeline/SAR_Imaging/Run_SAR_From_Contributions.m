function res = Run_SAR_From_Contributions(contrib, out_dir, opts)
% One call from RaySAR's ray-tracing output to a realistic HR image and
% matching LR images. This is the whole chain in one place, used by the
% RaySAR GUI ("Realistic SAR image" panel of the 2D maps window) and by
% run_street01_sar:
%
%   contributions -> point scatterers  Contributions_To_Scatterers
%   scatterers    -> raw radar data    Synth_PhaseHistory   (Eq. 5)
%   raw data      -> focused images    Make_HR_LR_Pairs     (Eqs. 21, 22)
%
% contrib: path to Contributions.txt, or the matrix already loaded from it
%          (columns Az, Ra, El, Intens, Tr_L)
% out_dir: folder for HR.png, LR_<tier>.png and sar_images.mat
%
% opts fields (all optional):
%   bw          radar bandwidth [Hz]; sets the HR resolution c/(2B)  (default 500e6).
%               'auto' picks the bandwidth that makes the image about
%               target_px pixels across, so objects of any size fill a
%               similar frame; it is kept between 1 MHz and 2 GHz.
%   target_px   image size that bw = 'auto' aims for, in pixels        (default 800)
%   factors     how many times coarser each LR image is            (default [2 4 8])
%   seed        seed for the speckle phases                         (default 1)
%   bin         scatterer cell size [m]                     (default dr/2)
%   pix         image pixel size [m]                        (default dr/2)
%   bounce_max  keep bounce levels up to this               (default all)
%   extent_from 'all' or 'single': what sets the scene bounds, see
%               Contributions_To_Scatterers                  (default 'all')
%   top_down    orient the PNGs like RaySAR's top-down maps   (default true)
%   save_mat    also write the complex images to sar_images.mat (default true)
%   progress    function handle f(text), told which step is running
%   confirm     function handle f(text) -> logical, asked before an
%               unusually long run; returning false cancels it
%
% The collection is sized to the scene. K and Np start at 512 and are
% doubled until the alias-free extents of Eqs. (7) and (9) cover the scene,
% so a larger scene or a finer resolution does not alias silently.
%
% Returns res with the output files, the resolution actually achieved and
% the complex images. res.cancelled is true if confirm declined the run.

if nargin < 3, opts = struct(); end
c = 299792458;

bw         = get_opt(opts, 'bw', 500e6);
target_px  = get_opt(opts, 'target_px', 800);
factors    = [2 4 8];
if isfield(opts, 'factors'), factors = opts.factors; end   % empty means the HR image only
seed       = get_opt(opts, 'seed', 1);
bounce_max = get_opt(opts, 'bounce_max', inf);
top_down   = get_opt(opts, 'top_down', true);
save_mat   = get_opt(opts, 'save_mat', true);
report     = get_opt(opts, 'progress', @(s) []);
confirm    = get_opt(opts, 'confirm', @(s) true);

if ischar(bw) || isstring(bw)
    if ischar(contrib) || isstring(contrib)
        contrib = load(contrib);   % once, here, rather than again below
    end
    ext = robust_extent(contrib);
    bw = Auto_Bandwidth(ext, target_px);
    fprintf('Auto bandwidth: %.0f MHz for a %.0f m scene (%.2f m resolution)\n', bw/1e6, ext, c/(2*bw));
end

dr  = c/(2*bw);
bin = get_opt(opts, 'bin', dr/2);   % half a resolution cell, so nothing the radar
pix = get_opt(opts, 'pix', dr/2);   % could resolve is merged away or undersampled

res = struct('cancelled', false);
t0 = tic;

% 1) RaySAR's contributions become point scatterers. Random phase per cell
%    is what makes speckle (see Contributions_To_Scatterers).
report('1 of 4: turning contributions into point scatterers ...');
sc_opts.bin = bin;
sc_opts.seed = seed;
sc_opts.phase = 'random';
sc_opts.bounce_max = bounce_max;
sc_opts.extent_from = get_opt(opts, 'extent_from', 'all');
sc = Contributions_To_Scatterers(contrib, sc_opts);

% 2) The radar collection, sized to the scene.
K = 512; Np = 512;
while true
    g = SAR_Params(struct('bw', bw, 'K', K, 'Np', Np, 'quiet', true));
    ok_r = g.maxWr >= 1.1*sc.extent(2);
    ok_x = g.maxWx >= 1.1*sc.extent(1);
    if ok_r && ok_x, break; end
    if ~ok_r, K = 2*K; end
    if ~ok_x, Np = 2*Np; end
    if K > 16384 || Np > 16384
        error('Run_SAR_From_Contributions:tooLarge', ...
            'A %.0f x %.0f m scene at %.2f m resolution needs a collection larger than this code supports. Lower the bandwidth.', ...
            sc.extent(1), sc.extent(2), dr);
    end
end
p.bw = bw; p.K = K; p.Np = Np;
p.scene = [sc.extent(2) sc.extent(1)];   % [range azimuth], for the alias checks
geom = SAR_Params(p);

hx = sc.extent(1)/2;
hy = sc.extent(2)/2;
n_pix = numel(-hx:pix:hx) * numel(-hy:pix:hy);
n_sc = numel(sc.amp);

% Rough cost, measured on Street_01 (835k scatterers, 832 x 832 pixels,
% 512 pulses: 19 s for the raw data and 19 s per HR image). Backprojection
% runs once for the HR image and once per LR image, on fewer pulses each.
pulses_total = Np*(1 + sum(1./factors));
est_s = n_sc*Np/2.2e7 + n_pix*pulses_total/1.9e7;
if est_s > 90
    msg = sprintf(['This will simulate %d scatterers and form %d images of %d x %d pixels.\n' ...
                   'Estimated time: about %.0f minutes.\n\nContinue?'], ...
                   n_sc, 1 + numel(factors), numel(-hy:pix:hy), numel(-hx:pix:hx), est_s/60);
    if ~confirm(msg)
        res.cancelled = true;
        return
    end
end

% 3) Simulate what the receiver would measure.
report('2 of 4: simulating the raw radar data ...');
data = Synth_PhaseHistory(geom, sc, 'fast');

% 4) Focus it, and make the LR versions from subsets of the same raw data.
report('3 of 4: forming the HR image, then the LR images (the longest step) ...');
tiers = struct('name', {}, 'factor', {});
for f = factors(:)'
    tiers(end+1) = struct('name', tier_name(f), 'factor', f); %#ok<AGROW>
end
pair = Make_HR_LR_Pairs(data, [-hx hx], [-hy hy], pix, tiers, out_dir, top_down);

% Keep the complex images (single precision to stay small). The phase is
% what makes these SAR rather than photographs, and it is what multi-look
% processing or complex-valued training would need later.
report('4 of 4: saving ...');
if save_mat
    hr = single(pair.hr);
    lr = cellfun(@single, pair.lr, 'UniformOutput', false);
    extent = [-hx hx -hy hy];
    resolution = [pair.hr_res; pair.lr_res];
    save(fullfile(out_dir, 'sar_images.mat'), 'hr', 'lr', 'pix', 'extent', 'resolution', 'factors', '-v7');
end

res.out_dir = out_dir;
res.names = [{'HR'}, arrayfun(@(t) t.name, tiers, 'UniformOutput', false)];
res.files = [{fullfile(out_dir, 'HR.png')}, ...
             arrayfun(@(t) fullfile(out_dir, sprintf('LR_%s.png', t.name)), tiers, 'UniformOutput', false)];
res.bw = bw;
res.factors = factors;
res.resolution = [pair.hr_res; pair.lr_res];   % [range cross-range] per image, HR first
res.pix = pix;
res.image_size = size(pair.hr);
res.n_scatterers = n_sc;
res.hr = pair.hr;
res.lr = pair.lr;
res.seconds = toc(t0);
fprintf('Done in %.0f s.\n', res.seconds);
end


function ext = robust_extent(R)
% Larger side of the scene in m, trimmed the same way Contributions_To_Scatterers
% trims it, so a few stray rays do not stretch it
pct = @(v, p) v(max(1, min(numel(v), round(p/100*numel(v)))));
a = sort(R(:,1));
r = sort(R(:,2));
ext = max(pct(a, 99.5) - pct(a, 0.5), pct(r, 99.5) - pct(r, 0.5));
end


function n = tier_name(f)
% The tier names used so far for the usual factors
switch f
    case 2, n = 'mid';
    case 4, n = 'low';
    case 8, n = 'vlow';
    otherwise, n = sprintf('x%g', f);
end
end


function v = get_opt(o, n, d)
if isfield(o, n) && ~isempty(o.(n))
    v = o.(n);
else
    v = d;
end
end
