% End-to-end: a real SAR image of the Street_01 scene, formed the way a
% radar forms one, plus matching low-resolution versions.
%
%   RaySAR ray tracing  ->  Contributions.txt          (already done)
%   contributions       ->  point scatterers           Contributions_To_Scatterers
%   scatterers          ->  raw radar data             Synth_PhaseHistory   (Eq. 5)
%   raw data            ->  focused image              bpBasic              (Eq. 21, 22)
%   less raw data       ->  genuine LR images          Make_HR_LR_Pairs
%
% The chain itself lives in Run_SAR_From_Contributions, which the RaySAR GUI
% ("Realistic SAR image" panel of the 2D maps window) calls as well.
%
% Run time is a few minutes, dominated by backprojection.

here = fileparts(mfilename('fullpath'));
addpath(here);

% Render Scenes/Street_01.pov first (RaySAR GUI, Rendering); the engine writes
% Contributions.txt next to the scene.
contrib = fullfile(fileparts(here), 'Scenes', 'Contributions.txt');
out_dir = fullfile(here, 'results', 'Street_01');

% X-band at RaySAR's own 0.031 m wavelength, 500 MHz of bandwidth and an
% aperture chosen to give the same resolution in both directions. 0.15 m
% cells and pixels are half the resolution, so nothing the radar could
% resolve is merged away. The seed is fixed so the speckle is reproducible.
opts.bw = 500e6;
opts.bin = 0.15;
opts.pix = 0.15;
opts.seed = 1;
opts.factors = [2 4 8];    % 'mid', 'low', 'vlow'

Run_SAR_From_Contributions(contrib, out_dir, opts);
