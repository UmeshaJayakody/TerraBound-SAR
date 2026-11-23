function Save_SAR_Image(im, path, floor_db, ref, top_down)
% Writes a complex SAR image out as an 8-bit grayscale PNG on a dB scale,
% the standard way SAR amplitude imagery is displayed.
%
% im:       complex image from bpBasic
% path:     output .png path
% floor_db: dB below the peak to clip at (default -35)
% ref:      reference magnitude for 0 dB. Pass the HR image's peak when
%           saving LR versions, so a pair shares one brightness scale and
%           can be compared directly.
% top_down: true (default) orients the image like RaySAR's "Top Down" maps,
%           false like its "Bottom Up" maps

if nargin < 3 || isempty(floor_db), floor_db = -35; end
if nargin < 5 || isempty(top_down), top_down = true; end
mag = abs(im);

% Reference for 0 dB. Deliberately a high percentile rather than the single
% brightest pixel: a SAR scene contains a few specular returns from flat
% walls that are tens of dB above everything else, and scaling to those
% would push the entire scene below the display floor. Real SAR imagery is
% displayed the same way, with the brightest few percent saturated.
if nargin < 4 || isempty(ref)
    v = sort(mag(:));
    ref = v(max(1, round(0.995*numel(v))));
end

db = 20*log10(mag/ref + eps);
db = max(min(db, 0), floor_db);
g = (db - floor_db)/(-floor_db);

% Rows are range (near range at the top) and columns azimuth, the same
% layout as RaySAR's map matrix. RaySAR's top-down display flips that
% matrix left-right (R_Map.m, range_dir = 1) and its bottom-up display flips
% it up-down (range_dir = 0), so do the same here to make the images
% directly comparable. Only the PNG is flipped; the complex image keeps the
% grid orientation of x_extent/y_extent.
if top_down
    g = fliplr(g);
else
    g = flipud(g);
end
imwrite(uint8(round(255*g)), path);
end
