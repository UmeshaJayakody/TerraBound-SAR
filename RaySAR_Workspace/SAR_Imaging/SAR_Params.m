function data = SAR_Params(opts)
% Builds a radar imaging geometry and every field the paper's imaging code
% needs (Table 1 of Gorham & Moore, 2010), from physical radar parameters.
% Also reports the four limits derived in Section 2 of the paper, which are
% what make an image physically meaningful rather than arbitrary:
%
%   Eq. (7)  Wr = c/(2*deltaF)        largest alias-free range extent
%   Eq. (8)  dr = c/(2*B)             range resolution
%   Eq. (9)  Wx = lambda_min/(2*dtheta)  largest alias-free cross-range extent
%   Eq. (10) dx = lambda_c/(2*theta_a)   cross-range resolution
%
% Coordinate frame (the "slant plane", matching RaySAR's output axes):
%   x = azimuth / cross-range, y = line of sight, z = elevation.
% The sensor sits at range R0 from the scene centre and sweeps a small
% angle in azimuth, i.e. a spotlight collection like the paper's Figure 1.
%
% opts fields (all optional):
%   fc       centre frequency [Hz]     default c/0.031 = 9.67 GHz, the X-band
%                                      wavelength RaySAR itself uses
%   bw       bandwidth [Hz]            default 500e6 -> 0.30 m range resolution
%   K        frequency samples/pulse   default 512
%   Np       pulses in the aperture    default 512
%   R0       slant range to centre [m] default 10e3
%   theta_a  integration angle [rad]   default gives cross-range = range resolution
%   scene    [range_extent azimuth_extent] in m, only used to warn about aliasing
%   quiet    suppress the printed summary

if nargin < 1, opts = struct(); end
c = 299792458;

data.fc     = get_opt(opts, 'fc', c/0.031);
data.lambda = c/data.fc;
data.bw     = get_opt(opts, 'bw', 500e6);
data.K      = get_opt(opts, 'K', 512);
data.Np     = get_opt(opts, 'Np', 512);
% Default slant range is spaceborne (X-band, like the TerraSAR-X imagery
% RaySAR was validated against). It is deliberately far: RaySAR's camera is
% orthographic, i.e. it assumes parallel rays, and at this range the
% wavefront curvature across a 150 m scene is under 2 cm, so the imaging
% geometry stays consistent with the scene RaySAR traced. Lower it for a
% genuinely airborne collection, at the cost of that consistency.
data.Rc     = get_opt(opts, 'R0', 500e3);

% By default make the cross-range resolution match the range resolution,
% which is what a well designed collection aims for.
dr_target    = c/(2*data.bw);
data.theta_a = get_opt(opts, 'theta_a', data.lambda/(2*dr_target));

% Frequency sampling. The paper defines B = (K-1)*deltaF (Section 2).
data.deltaF = data.bw/(data.K - 1);
f1          = data.fc - data.bw/2;
data.minF   = f1*ones(1, data.Np);

% Antenna track: a circular (spotlight) arc of total angle theta_a, centred
% broadside, at constant range from the scene centre.
phi       = linspace(-data.theta_a/2, data.theta_a/2, data.Np);
data.AntX =  data.Rc*sin(phi);
data.AntY = -data.Rc*cos(phi);
data.AntZ =  zeros(1, data.Np);
data.R0   =  sqrt(data.AntX.^2 + data.AntY.^2 + data.AntZ.^2);

% Length of the FFT used to form range profiles. The paper's rule of thumb
% is about 10x the data length, and a power of 2 for speed (Section 4.2).
data.Nfft = 2^nextpow2(10*data.K);

% The limits from Section 2
lambda_min = c/(f1 + data.bw);
dtheta     = data.theta_a/(data.Np - 1);
data.dr    = c/(2*data.bw);                 % Eq. (8)
data.dx    = data.lambda/(2*data.theta_a);  % Eq. (10)
data.maxWr = c/(2*data.deltaF);             % Eq. (7)
data.maxWx = lambda_min/(2*dtheta);         % Eq. (9)

if ~get_opt(opts, 'quiet', false)
    fprintf('Radar: fc %.3f GHz (lambda %.4f m), B %.0f MHz, K %d, Np %d, aperture %.3f deg, R0 %.1f km\n', ...
        data.fc/1e9, data.lambda, data.bw/1e6, data.K, data.Np, data.theta_a*180/pi, data.Rc/1e3);
    fprintf('Resolution  (Eq. 8, 10): %.3f m range, %.3f m cross-range\n', data.dr, data.dx);
    fprintf('Alias-free  (Eq. 7, 9): %.1f m range, %.1f m cross-range\n', data.maxWr, data.maxWx);
end

scene = get_opt(opts, 'scene', []);
if ~isempty(scene)
    if scene(1) > data.maxWr
        warning('SAR_Params:rangeAlias', ...
            'Scene range extent %.1f m exceeds the alias-free limit %.1f m. Increase K.', scene(1), data.maxWr);
    end
    if scene(2) > data.maxWx
        warning('SAR_Params:azimuthAlias', ...
            'Scene azimuth extent %.1f m exceeds the alias-free limit %.1f m. Increase Np.', scene(2), data.maxWx);
    end
end
end


function v = get_opt(o, n, d)
if isfield(o, n) && ~isempty(o.(n))
    v = o.(n);
else
    v = d;
end
end
