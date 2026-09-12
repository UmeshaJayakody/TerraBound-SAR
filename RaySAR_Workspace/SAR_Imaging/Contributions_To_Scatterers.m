function sc = Contributions_To_Scatterers(contrib_path, opts)
% Turns RaySAR's Contributions.txt into point scatterers that the radar
% forward model can illuminate. This is the missing link between RaySAR and
% real SAR imaging: RaySAR says where energy comes from and how much, this
% hands that over to a model of an actual radar collection.
%
% RaySAR's columns are: Az, Ra, El, Intens, Tr_L (bounce level), Sp
% (specular flag). Az, Ra and El are the contribution's azimuth,
% slant-range and elevation coordinates in the sensor frame, which is the
% same frame the imaging code uses (x = azimuth, y = line of sight,
% z = elevation), so this is a re-centring rather than a projection.
%
% Amplitude: RaySAR's own Gen_Refl_Map.m treats Intens as an amplitude
% (Signal = Intens*exp(1i*Phi)), so amplitudes are summed per cell here to
% keep the brightness identical to RaySAR's reflectivity map.
%
% Phase: deliberately NOT taken from RaySAR. RaySAR folds the propagation
% phase -4*pi*Ra/lambda into its coherent sum because it has no propagation
% model of its own. Here the forward model derives that phase from the
% geometry, so reusing RaySAR's would count it twice. Each cell instead
% gets a random phase, the standard model of a surface that is rough at the
% wavelength scale. That phase diversity is what produces real speckle,
% rather than the noise that gets multiplied on afterwards in Degrade_To_LR.
%
% opts fields (all optional):
%   bin         cell size in m for merging contributions     (default 0.15)
%   bounce_max  keep only bounce levels up to this           (default: all)
%   trim_pct    percentile trim for stray outlying rays      (default 0.5)
%   phase       'random' (default) or 'none' for no speckle
%   seed        seed for the random phases, for repeatability (default 0)
%   max_scatterers  warn above this many cells              (default 5e5)
%
% Returns sc with fields x, y, z, amp (column vectors, scene-centred),
% plus sc.centre = [az0 ra0 el0] and sc.extent = [azimuth range] in m.

if nargin < 2, opts = struct(); end
bin        = get_opt(opts, 'bin', 0.15);
bounce_max = get_opt(opts, 'bounce_max', inf);
trim_pct   = get_opt(opts, 'trim_pct', 0.5);
phase_mode = get_opt(opts, 'phase', 'random');
seed       = get_opt(opts, 'seed', 0);
max_sc     = get_opt(opts, 'max_scatterers', 5e5);

R = load(contrib_path);
fprintf('Loaded %d signal contributions from %s\n', size(R,1), contrib_path);
Az = R(:,1); Ra = R(:,2); El = R(:,3); Intens = R(:,4); Tr_L = R(:,5);
clear R

if isfinite(bounce_max)
    keep = Tr_L <= bounce_max;
    fprintf('Keeping bounce levels <= %d: %d of %d contributions\n', bounce_max, sum(keep), numel(keep));
    Az = Az(keep); Ra = Ra(keep); El = El(keep); Intens = Intens(keep);
end

% Large imported meshes throw off a few stray rays that would otherwise
% stretch the scene over hundreds of metres. Same robust trim the existing
% pipeline uses before building a reflectivity map.
pct = @(v, p) v(max(1, min(numel(v), round(p/100*numel(v)))));
as = sort(Az); rs = sort(Ra);
a_lo = pct(as, trim_pct); a_hi = pct(as, 100 - trim_pct);
r_lo = pct(rs, trim_pct); r_hi = pct(rs, 100 - trim_pct);
clear as rs
inside = Az >= a_lo & Az <= a_hi & Ra >= r_lo & Ra <= r_hi;
Az = Az(inside); Ra = Ra(inside); El = El(inside); Intens = Intens(inside);
fprintf('Robust bounds: azimuth [%.2f %.2f] m, range [%.2f %.2f] m (%d contributions kept)\n', ...
    a_lo, a_hi, r_lo, r_hi, numel(Az));

% Merge contributions that share a cell. Anything finer than a resolution
% cell is indistinguishable to the radar anyway, and this is what keeps the
% forward model affordable.
e_lo = min(El);
ix = floor((Az - a_lo)/bin) + 1;
iy = floor((Ra - r_lo)/bin) + 1;
iz = floor((El - e_lo)/bin) + 1;
nx = max(ix); ny = max(iy);
key = (iz - 1)*nx*ny + (iy - 1)*nx + ix;
[ukey, ~, j] = unique(key);
amp = accumarray(j, Intens);
Ns = numel(ukey);
fprintf('Merged into %d scatterer cells of %.2f m\n', Ns, bin);
if Ns > max_sc
    warning('Contributions_To_Scatterers:manyScatterers', ...
        '%d scatterers is a lot; the forward model will be slow. Increase opts.bin to merge more.', Ns);
end

iz_u = floor((ukey - 1)/(nx*ny)) + 1;
rest = mod(ukey - 1, nx*ny);
iy_u = floor(rest/nx) + 1;
ix_u = mod(rest, nx) + 1;

az0 = (a_lo + a_hi)/2;
ra0 = (r_lo + r_hi)/2;
el0 = e_lo;

sc.x = a_lo + (ix_u - 0.5)*bin - az0;
sc.y = r_lo + (iy_u - 0.5)*bin - ra0;
sc.z = e_lo + (iz_u - 0.5)*bin - el0;

switch lower(phase_mode)
    case 'random'
        try
            rng(seed);
        catch
            rand('seed', seed);   %#ok<RAND>  (older Octave)
        end
        sc.amp = amp .* exp(1i*2*pi*rand(Ns, 1));
    case 'none'
        sc.amp = amp;
    otherwise
        error('Contributions_To_Scatterers:phase', 'opts.phase must be ''random'' or ''none''.');
end

sc.centre = [az0 ra0 el0];
sc.extent = [a_hi - a_lo, r_hi - r_lo];
sc.bin = bin;
fprintf('Scene extent: %.1f m azimuth x %.1f m range, phases: %s\n', sc.extent(1), sc.extent(2), lower(phase_mode));
end


function v = get_opt(o, n, d)
if isfield(o, n) && ~isempty(o.(n))
    v = o.(n);
else
    v = d;
end
end
