function out = Make_HR_LR_Pairs(data, x_extent, y_extent, pix, tiers, out_dir)
% Produces an HR image and matching LR images the way a radar actually
% produces them: by collecting less data.
%
% This is the part that matters most for a super-resolution dataset. The
% existing Degrade_To_LR.m fakes low resolution after the fact, by blurring
% a finished image and multiplying noise onto it. Here the HR image is
% formed from the full phase history, and each LR image is formed from a
% centred SUBSET of that same raw data:
%
%   less bandwidth      -> coarser range resolution      (Eq. 8:  dr = c/2B)
%   shorter aperture    -> coarser cross-range resolution (Eq. 10: dx = lambda/2*theta_a)
%
% So the degradation is the real one: the point spread function broadens
% correctly, the sidelobes move, and the speckle changes on its own. Every
% image is formed on the same pixel grid, so HR and LR are pixel-aligned by
% construction, which is what supervised training needs.
%
% tiers: struct array with fields
%   name    label for the output file
%   factor  how much coarser, e.g. 2 = half the bandwidth and half the
%           aperture, so twice the resolution cell in both directions
%
% Returns out.hr (complex HR image) and out.lr{i}, plus the grids.

if exist(out_dir, 'dir') ~= 7, mkdir(out_dir); end

K = size(data.phdata, 1);
Np = size(data.phdata, 2);

% ---- HR: everything we collected ---------------------------------------
fprintf('\nHR image (full %d MHz bandwidth, full %.3f deg aperture)\n', ...
    round(data.bw/1e6), data.theta_a*180/pi);
hr = Form_SAR_Image(data, x_extent, y_extent, pix);

% One brightness reference shared by every image in the set, taken from the
% HR image, so an HR/LR pair can be compared pixel for pixel. A high
% percentile rather than the peak, for the reason given in Save_SAR_Image.
v = sort(abs(hr.im_final(:)));
ref = v(max(1, round(0.995*numel(v))));
Save_SAR_Image(hr.im_final, fullfile(out_dir, 'HR.png'), -35, ref);
out.hr = hr.im_final;
out.x_mat = hr.x_mat;
out.y_mat = hr.y_mat;
out.hr_res = [hr.dr hr.dx];
out.lr = cell(1, numel(tiers));
out.lr_res = zeros(numel(tiers), 2);

% ---- LR: the same data, less of it -------------------------------------
for i = 1:numel(tiers)
    t = tiers(i);

    K_lr = max(2, round(K/t.factor));
    Np_lr = max(2, round(Np/t.factor));
    k0 = floor((K - K_lr)/2) + 1;
    n0 = floor((Np - Np_lr)/2) + 1;
    ks = k0:(k0 + K_lr - 1);
    ns = n0:(n0 + Np_lr - 1);

    d = data;
    d.phdata = data.phdata(ks, ns);
    d.minF   = data.minF(ns) + (k0 - 1)*data.deltaF;   % the subset starts higher up the band
    d.AntX   = data.AntX(ns);
    d.AntY   = data.AntY(ns);
    d.AntZ   = data.AntZ(ns);
    d.R0     = data.R0(ns);
    d.K      = K_lr;
    d.Np     = Np_lr;

    fprintf('LR "%s": %d of %d frequencies (%.0f MHz), %d of %d pulses (%.3f deg)\n', ...
        t.name, K_lr, K, (K_lr - 1)*data.deltaF/1e6, Np_lr, Np, ...
        (data.theta_a*(Np_lr - 1)/(Np - 1))*180/pi);

    lr = Form_SAR_Image(d, x_extent, y_extent, pix);
    Save_SAR_Image(lr.im_final, fullfile(out_dir, sprintf('LR_%s.png', t.name)), -35, ref);
    out.lr{i} = lr.im_final;
    out.lr_res(i, :) = [lr.dr lr.dx];
end

fprintf('\nResolution actually achieved:\n');
fprintf('  HR            %.2f m range, %.2f m cross-range\n', out.hr_res(1), out.hr_res(2));
for i = 1:numel(tiers)
    fprintf('  LR %-8s   %.2f m range, %.2f m cross-range\n', tiers(i).name, out.lr_res(i,1), out.lr_res(i,2));
end
fprintf('Images written to %s\n', out_dir);
end
