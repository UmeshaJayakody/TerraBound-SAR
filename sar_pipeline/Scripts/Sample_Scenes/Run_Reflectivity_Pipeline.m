function Run_Reflectivity_Pipeline(name, contrib_file, out_folder)
% The reflectivity-map route for the sample scenes: RaySAR's own map
% (Gen_Refl_Map, through Generate_Refl_Map_From_File), then Degrade_To_LR for
% the low-resolution tiers. This replaces the eleven run_<scene>_pipeline.m
% scripts, which differed only in the settings below and in hard-coded
% absolute paths. Every setting is the one that scene was run with.
%
% name:         scene, e.g. 'Street_01' or 'Street_01_Coherent'. Call with
%               no arguments to list them all.
% contrib_file: Contributions.txt from rendering that scene
%               (default: sar_pipeline/Scenes/Contributions.txt, where
%               the RaySAR GUI's Rendering button writes it).
% out_folder:   results folder (default: sar_pipeline/Scenes/<name>_Results).
%
% For realistic SAR images formed from raw radar data, use
% SAR_Imaging/Run_SAR_From_Contributions instead.

here = fileparts(mfilename('fullpath'));
scripts = fileparts(here);
workspace = fileparts(scripts);
addpath(fullfile(workspace, 'RaySAR'));
addpath(scripts);

table = run_settings();
if nargin < 1 || isempty(name)
    fprintf('Scenes:\n');
    for k = 1:numel(table)
        fprintf('  %-20s pixel %g m\n', table(k).name, table(k).pix);
    end
    return;
end
k = find(strcmpi({table.name}, name), 1);
if isempty(k)
    error('Run_Reflectivity_Pipeline:unknown', 'There is no scene called "%s". Call Run_Reflectivity_Pipeline() for the list.', name);
end
s = table(k);

if nargin < 2 || isempty(contrib_file), contrib_file = fullfile(workspace, 'Scenes', 'Contributions.txt'); end
if nargin < 3 || isempty(out_folder), out_folder = fullfile(workspace, 'Scenes', [s.name '_Results']); end
if exist(contrib_file, 'file') ~= 2
    error('Run_Reflectivity_Pipeline:noContributions', 'Could not find %s. Render the scene first.', contrib_file);
end

opts.a_pix = s.pix;
opts.r_pix = s.pix;
opts.range_dir = 1;

if ~isempty(s.pct)
    % A handful of stray/degenerate ray contributions (common with large
    % imported meshes) can blow out plain min/max auto-fit bounds, leaving
    % almost the whole image empty. Use robust percentile bounds instead so a
    % few outliers don't dictate the whole canvas size.
    R = load(contrib_file);
    az = sort(R(:,1)); ra = sort(R(:,2));
    pct = @(v,p) v(max(1, min(numel(v), round(p/100*numel(v)))));
    a_lo = pct(az, s.pct(1)); a_hi = pct(az, s.pct(2));
    r_lo = pct(ra, s.pct(1)); r_hi = pct(ra, s.pct(2));
    fprintf('Robust bounds -> azimuth [%.2f %.2f]  range [%.2f %.2f]\n', a_lo,a_hi,r_lo,r_hi);
    clear R az ra
    opts.a_min = num2str(a_lo);
    opts.a_max = num2str(a_hi);
    opts.r_min = num2str(r_lo);
    opts.r_max = num2str(r_hi);
end
if s.coh
    % RaySAR's documented "coherent summation" (RaySAR_documentation.pdf,
    % Section 2.2.2): contributions are summed as complex values, using the
    % phase from range and wavelength, instead of plain amplitudes. Meant for
    % highly detailed 3D models such as Street_01.
    opts.coh = 1;
end

Generate_Refl_Map_From_File(contrib_file, out_folder, opts);

hr_path = fullfile(out_folder, 'Maps', 'Figures', 'Ref_Maps', 'JPG', 'All Reflections.jpg');

tiers(1) = struct('name','mid',  'scale',2, 'looks',4, 'blur_sigma',0.6);
tiers(2) = struct('name','low',  'scale',4, 'looks',2, 'blur_sigma',1.2);
tiers(3) = struct('name','vlow', 'scale',8, 'looks',1, 'blur_sigma',2.0);

Degrade_To_LR(hr_path, fullfile(out_folder, 'LR_Pairs'), tiers);

fprintf('%s pipeline complete.\n', s.name);
end


function t = run_settings()
% pix: reflectivity-map pixel size in m (azimuth and range)
% pct: [low high] percentiles for robust image bounds, or [] for RaySAR's own
% coh: coherent summation
t = struct('name', {}, 'pix', {}, 'pct', {}, 'coh', {});
t(end+1) = struct('name', 'Castelia_01',        'pix', 100,   'pct', [5 95],     'coh', false);
t(end+1) = struct('name', 'City_01',            'pix', 0.3,   'pct', [],         'coh', false);
t(end+1) = struct('name', 'CityBlock1_01',      'pix', 0.2,   'pct', [5 95],     'coh', false);
t(end+1) = struct('name', 'Desert_01',          'pix', 0.03,  'pct', [0.5 99.5], 'coh', false);
t(end+1) = struct('name', 'Forest_01',          'pix', 0.002, 'pct', [5 95],     'coh', false);
t(end+1) = struct('name', 'Frigate_01',         'pix', 0.15,  'pct', [0.5 99.5], 'coh', false);
t(end+1) = struct('name', 'MountBlend_01',      'pix', 0.01,  'pct', [5 95],     'coh', false);
t(end+1) = struct('name', 'Pond_01',            'pix', 0.06,  'pct', [5 95],     'coh', false);
t(end+1) = struct('name', 'Street_01',          'pix', 0.3,   'pct', [0.5 99.5], 'coh', false);
t(end+1) = struct('name', 'Street_01_Coherent', 'pix', 0.3,   'pct', [0.5 99.5], 'coh', true);
t(end+1) = struct('name', 'Urban_01',           'pix', 0.4,   'pct', [],         'coh', false);
end
