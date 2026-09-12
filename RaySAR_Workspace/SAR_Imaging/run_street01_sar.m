% End-to-end: a real SAR image of the Street_01 scene, formed the way a
% radar forms one, plus matching low-resolution versions.
%
%   RaySAR ray tracing  ->  Contributions.txt          (already done)
%   contributions       ->  point scatterers           Contributions_To_Scatterers
%   scatterers          ->  raw radar data             Synth_PhaseHistory   (Eq. 5)
%   raw data            ->  focused image              bpBasic              (Eq. 21, 22)
%   less raw data       ->  genuine LR images          Make_HR_LR_Pairs
%
% Run time is a few minutes, dominated by backprojection.

here = fileparts(mfilename('fullpath'));
addpath(here);

contrib = 'D:/FYP/RaySAR_Workspace/Scenes/Contributions.txt';
out_dir = fullfile(here, 'results', 'Street_01');

% 1) RaySAR's contributions become point scatterers. 0.15 m cells, half the
%    intended resolution, so nothing the radar could resolve is merged away.
sc_opts.bin = 0.15;
sc_opts.seed = 1;          % fixed, so the speckle is reproducible
sc_opts.phase = 'random';  % rough-surface phase: this is what makes speckle
sc = Contributions_To_Scatterers(contrib, sc_opts);

% 2) The radar collection. Defaults are X-band at RaySAR's own 0.031 m
%    wavelength, 500 MHz of bandwidth and an aperture chosen to give the
%    same resolution in both directions.
p.scene = [sc.extent(2) sc.extent(1)];   % [range azimuth] extent, for the alias checks
geom = SAR_Params(p);

% 3) Simulate what the receiver would measure.
data = Synth_PhaseHistory(geom, sc, 'fast');

% 4) Focus it, and make the LR versions from subsets of the same raw data.
hx = sc.extent(1)/2;
hy = sc.extent(2)/2;
tiers(1) = struct('name', 'mid',  'factor', 2);
tiers(2) = struct('name', 'low',  'factor', 4);
tiers(3) = struct('name', 'vlow', 'factor', 8);

out = Make_HR_LR_Pairs(data, [-hx hx], [-hy hy], 0.15, tiers, out_dir);

% Keep the complex images (single precision to stay small). The phase is
% what makes these SAR rather than photographs, and it is what multi-look
% processing or complex-valued training would need later.
hr = single(out.hr);
lr = cellfun(@single, out.lr, 'UniformOutput', false);
pix = 0.15;
extent = [-hx hx -hy hy];
resolution = [out.hr_res; out.lr_res];
save(fullfile(out_dir, 'sar_images.mat'), 'hr', 'lr', 'pix', 'extent', 'resolution', '-v7');
fprintf('Done.\n');
