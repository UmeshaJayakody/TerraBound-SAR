function Save_SAR_Image(im, path, floor_db, ref)
% Writes a complex SAR image out as an 8-bit grayscale PNG on a dB scale,
% the standard way SAR amplitude imagery is displayed.
%
% im:       complex image from bpBasic
% path:     output .png path
% floor_db: dB below the peak to clip at (default -35)
% ref:      reference magnitude for 0 dB. Pass the HR image's peak when
%           saving LR versions, so a pair shares one brightness scale and
%           can be compared directly.

if nargin < 3 || isempty(floor_db), floor_db = -35; end
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

% Flip so range increases downward and azimuth left to right, matching how
% RaySAR's own reflectivity maps are displayed.
imwrite(uint8(round(255*g)), path);
end
