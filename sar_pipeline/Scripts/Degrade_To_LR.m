function Degrade_To_LR(hr_image_path, out_dir, tiers)
% Produces paired LR images from a RaySAR HR reflectivity map, following
% the project's documented degradation model: mild Gaussian blur +
% downsampling + multiplicative speckle noise (L-look intensity model).
%
% Deliberately uses only base MATLAB (no Image Processing / Statistics
% toolboxes), since this machine only has core MATLAB licensed.
%
% hr_image_path: path to the HR grayscale image (e.g. "All Reflections.jpg")
% out_dir: folder to write LR tier images into
% tiers: struct array, one entry per resolution tier, fields:
%   name         tier label, e.g. 'low','mid','high'
%   scale        downsampling factor (e.g. 4 = quarter resolution)
%   looks        number of looks L for speckle (lower L = noisier; 1 = single-look)
%   blur_sigma   Gaussian blur sigma in HR pixels before downsampling
%
% Each LR tier is saved at its native (downsampled) size AND upsampled
% back to HR size (bicubic) for pixel-aligned side-by-side comparison,
% since supervised SR training needs LR/HR pairs at a known, fixed
% pixel correspondence.

if exist(out_dir,'dir') ~= 7
    mkdir(out_dir);
end

HR = double(imread(hr_image_path));
if size(HR,3) > 1
    HR = 0.2989*HR(:,:,1) + 0.5870*HR(:,:,2) + 0.1140*HR(:,:,3);
end
HR = HR / 255;

[hr_rows, hr_cols] = size(HR);
imwrite(HR, fullfile(out_dir, 'HR.png'));

for i = 1:numel(tiers)
    t = tiers(i);

    % 1) Mild blur (sensor/optics-like softening) before downsampling
    Img = local_gaussblur(HR, t.blur_sigma);

    % 2) Downsample to simulate lower resolution acquisition
    lr_rows = round(hr_rows / t.scale);
    lr_cols = round(hr_cols / t.scale);
    Img = local_resize(Img, lr_rows, lr_cols);
    Img = min(max(Img,0),1);

    % 3) Multiplicative speckle noise: average of L independent
    %    Exponential(1) samples = Gamma(L,1/L), the standard L-look
    %    SAR intensity speckle model (mean 1).
    speckle = zeros(size(Img));
    for k = 1:t.looks
        speckle = speckle + (-log(rand(size(Img))));
    end
    speckle = speckle / t.looks;
    Img = Img .* speckle;
    Img = min(max(Img,0),1);

    imwrite(Img, fullfile(out_dir, sprintf('LR_%s_native.png', t.name)));

    % Upsampled back to HR pixel grid for aligned pairing
    Img_aligned = local_resize(Img, hr_rows, hr_cols);
    Img_aligned = min(max(Img_aligned,0),1);
    imwrite(Img_aligned, fullfile(out_dir, sprintf('LR_%s_aligned.png', t.name)));

    fprintf('Tier "%s": scale 1/%g, %d looks, blur sigma %g -> %s\n', ...
        t.name, t.scale, t.looks, t.blur_sigma, out_dir);
end

end

function Img = local_gaussblur(Img, sigma)
    if sigma <= 0
        return;
    end
    r = ceil(3*sigma);
    x = -r:r;
    k1 = exp(-(x.^2)/(2*sigma^2));
    k1 = k1 / sum(k1);

    [rows, cols] = size(Img);
    ridx = [ones(1,r), 1:rows, rows*ones(1,r)];
    cidx = [ones(1,r), 1:cols, cols*ones(1,r)];
    Img_p = Img(ridx, cidx);

    Img = conv2(k1, k1, Img_p, 'valid');
end

function Out = local_resize(Img, out_rows, out_cols)
    [Xq, Yq] = meshgrid(linspace(1, size(Img,2), out_cols), linspace(1, size(Img,1), out_rows));
    Out = interp2(Img, Xq, Yq, 'cubic');
end
