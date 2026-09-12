function out = Form_SAR_Image(data, x_extent, y_extent, pix)
% Forms a SAR image from phase history by backprojection, on a regular grid
% in the slant plane (x = azimuth, y = range, imaged at z = 0).
%
% Imaging onto the z = 0 plane is what produces the layover that makes SAR
% images of buildings look the way they do: a scatterer high above the
% ground lands at the range it is measured at, not above its footprint.
%
% data:     geometry + data.phdata, from SAR_Params and Synth_PhaseHistory
% x_extent: [xmin xmax] azimuth limits in m
% y_extent: [ymin ymax] range limits in m
% pix:      pixel spacing in m (default: half the range resolution, as the
%           paper advises sampling finer than the resolution)

if nargin < 4 || isempty(pix)
    pix = data.dr/2;
end

[data.x_mat, data.y_mat] = meshgrid(x_extent(1):pix:x_extent(2), y_extent(1):pix:y_extent(2));
data.z_mat = zeros(size(data.x_mat));
data.quiet = true;

t0 = tic;
out = bpBasic(data);

% Two normalisations, so that an HR image and a coarser LR image of the
% same scene can share one brightness scale:
%
% 1) by the number of samples summed. Otherwise an LR image is dimmer than
%    its HR partner purely because fewer pulses and frequencies went into
%    it. The paper's matched filter, Eq. (11), carries the same 1/(Np*K).
% 2) by the square root of the resolution cell area. A coarser cell gathers
%    more scatterers, so distributed clutter grows as sqrt(area) while the
%    ground itself has not changed. Dividing it out expresses the image per
%    unit area, which is how real SAR brightness (sigma nought) is defined.
out.im_final = out.im_final/(out.K*out.Np)/sqrt(out.dr*out.dx);

out.pix = pix;
out.form_time = toc(t0);
fprintf('Backprojection: %d x %d pixels at %.2f m, %.1f s (resolution %.2f m range, %.2f m cross-range)\n', ...
    size(out.im_final,1), size(out.im_final,2), pix, out.form_time, out.dr, out.dx);
end
