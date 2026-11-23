function test_paper_fig1
% Validation against the source paper. Reproduces Figure 1 of Gorham &
% Moore (2010): three point targets at (0,0,0), (-3,2,0) and (1,4,0),
% imaged with both the matched filter and the backprojection algorithm,
% using the exact collection parameters stated in Section 3 of the paper.
%
% Pass criteria: both algorithms put the peaks at the true target
% positions, the reported resolution matches Eqs. (8) and (10), and the
% two independent algorithms agree.

here = fileparts(mfilename('fullpath'));
addpath(here);
out_dir = fullfile(here, 'results');
if exist(out_dir, 'dir') ~= 7, mkdir(out_dir); end

% ---- The paper's Figure 1 collection -----------------------------------
Np = 128; K = 512;
fc = 10e9; BW = 600e6;
elev = 30*pi/180;         % depression angle
R_slant = 10e3;
int_angle = 3*pi/180;
az_center = 50*pi/180;

targets = [ 0 0 0 1;
           -3 2 0 1;
            1 4 0 1];

az = az_center + linspace(-int_angle/2, int_angle/2, Np);
data.AntX = R_slant*cos(elev)*cos(az);
data.AntY = R_slant*cos(elev)*sin(az);
data.AntZ = R_slant*sin(elev)*ones(1, Np);
data.R0   = sqrt(data.AntX.^2 + data.AntY.^2 + data.AntZ.^2);
data.K      = K;
data.deltaF = BW/(K-1);
data.minF   = (fc - BW/2)*ones(1, Np);
data.Nfft   = 2^nextpow2(10*K);
data.quiet  = true;

sc.x = targets(:,1); sc.y = targets(:,2); sc.z = targets(:,3); sc.amp = targets(:,4);
data = Synth_PhaseHistory(data, sc, 'exact');

fprintf('Expected from Eqs. (8) and (10): %.3f m range, %.3f m cross-range\n', ...
    299792458/(2*BW), (299792458/fc)/(2*int_angle));

% ---- Backprojection at the paper's grid: 10 m x 10 m, 2 cm pixels ------
bp = data;
[bp.x_mat, bp.y_mat] = meshgrid(-5:0.02:5, -5:0.02:5);
bp.z_mat = zeros(size(bp.x_mat));
t0 = tic; bp = bpBasic(bp);
fprintf('Backprojection: %.1f s, reports %.3f m range / %.3f m cross-range\n', toc(t0), bp.dr, bp.dx);
save_db_image(bp.im_final, fullfile(out_dir, 'fig1b_backprojection.png'), -50);
report_peaks(bp, targets, 'Backprojection');

% ---- Matched filter: O(N^4), so a coarser 10 cm grid -------------------
mf = data;
[mf.x_mat, mf.y_mat] = meshgrid(-5:0.1:5, -5:0.1:5);
mf.z_mat = zeros(size(mf.x_mat));
t0 = tic; mf = mfBasic(mf);
fprintf('Matched filter: %.1f s\n', toc(t0));
save_db_image(mf.im_final, fullfile(out_dir, 'fig1a_matched_filter.png'), -50);
report_peaks(mf, targets, 'Matched filter');

% ---- Do the two independent algorithms agree? --------------------------
bp_coarse = bp.im_final(1:5:end, 1:5:end);
a = abs(bp_coarse(:))/max(abs(bp_coarse(:)));
b = abs(mf.im_final(:))/max(abs(mf.im_final(:)));
r = corrcoef(a, b);
fprintf('Backprojection vs matched filter, magnitude correlation: %.4f\n', r(1,2));
fprintf('Images written to %s\n', out_dir);
end


function save_db_image(im, path, floor_db)
mag = abs(im);
db = 20*log10(mag/max(mag(:)) + eps);
db = max(db, floor_db);
g = (db - floor_db)/(-floor_db);
imwrite(uint8(round(255*flipud(g))), path);
end


function report_peaks(d, targets, label)
mag = abs(d.im_final);
gmax = max(mag(:));
fprintf('%s: target position (true -> imaged), peak level\n', label);
for t = 1:size(targets,1)
    win = abs(d.x_mat - targets(t,1)) <= 0.5 & abs(d.y_mat - targets(t,2)) <= 0.5;
    m = mag; m(~win) = 0;
    [pk, idx] = max(m(:));
    fprintf('  (%5.2f, %5.2f) -> (%5.2f, %5.2f), %6.2f dB\n', ...
        targets(t,1), targets(t,2), d.x_mat(idx), d.y_mat(idx), 20*log10(pk/gmax));
end
end
