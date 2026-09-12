function data = Synth_PhaseHistory(data, sc, method)
% Simulates the raw radar data (phase history) that a real SAR would collect
% from a set of point scatterers, using the signal model of Gorham & Moore
% (2010), Eq. (5):
%
%   S(f_k, tau_n) = sum_i  a_i * exp(-j*4*pi*f_k*dR_i(tau_n)/c)
%
% where dR_i(tau_n) = |r_a(tau_n) - r_i| - |r_a(tau_n)|  (Eqs. 4 and 6), so
% every pulse is motion compensated to the scene origin, exactly as the
% paper's imaging code assumes. This is the step RaySAR does not have: it
% turns a reflectivity map into something a radar receiver would actually
% measure, so that image formation (bpBasic) can then be done properly.
%
% data:   geometry struct from SAR_Params (AntX/AntY/AntZ, minF, deltaF, K, R0)
% sc:     scatterers, struct with column vectors x, y, z and complex amp
% method: 'exact' evaluates Eq. (5) directly. Faithful but costs
%                 O(Ns*Np*K); use it for validation and small scenes.
%         'fast'  (default) accumulates the same sum onto a fine range grid
%                 and takes one FFT per pulse, costing O(Ns*Np + Np*Ng*logNg).
%                 This is the exact inverse of the range-profile step that
%                 bpBasic performs, and agrees with 'exact' to ~1e-3 relative
%                 error (see test_forward_model.m).
%
% Adds data.phdata (K x Np, fast time in rows, slow time in columns).

if nargin < 3 || isempty(method), method = 'fast'; end
c = 299792458;

x = sc.x(:); y = sc.y(:); z = sc.z(:); a = sc.amp(:);
Ns = numel(x);
K = data.K; Np = numel(data.AntX);
f1 = data.minF(1);

data.phdata = zeros(K, Np);
t0 = tic;

switch lower(method)
    case 'exact'
        freq = (f1 + (0:(K-1))'*data.deltaF);   % K x 1
        chunk = max(1, floor(4e6/K));           % keep the K x chunk matrix modest
        for n = 1:Np
            acc = zeros(K, 1);
            for i0 = 1:chunk:Ns
                i1 = min(Ns, i0 + chunk - 1);
                dR = sqrt((data.AntX(n)-x(i0:i1)).^2 + ...
                          (data.AntY(n)-y(i0:i1)).^2 + ...
                          (data.AntZ(n)-z(i0:i1)).^2) - data.R0(n);
                acc = acc + exp(-1i*4*pi/c * (freq * dR.')) * a(i0:i1);
            end
            data.phdata(:, n) = acc;
        end

    case 'fast'
        Ng = data.Nfft;                 % fine range grid, zero-padding equivalent
        maxWr = c/(2*data.deltaF);      % Eq. (7)
        dropped = 0;

        % Deapodization factor for the linear-interpolation gridding below
        kk = (0:(K-1)).';
        apod = (sin(pi*kk/Ng)./(pi*kk/Ng)).^2;
        apod(1) = 1;
        for n = 1:Np
            dR = sqrt((data.AntX(n)-x).^2 + (data.AntY(n)-y).^2 + (data.AntZ(n)-z).^2) - data.R0(n);

            % Phase common to all frequencies, then position on the range grid.
            b = a .* exp(-1i*4*pi*f1*dR/c);
            u = -2*data.deltaF*dR/c;    % cycles per frequency step, must be in [-0.5, 0.5)

            keep = abs(u) < 0.5;
            dropped = dropped + sum(~keep);
            if ~all(keep)
                b = b(keep); u = u(keep);
            end

            % Linear interpolation onto the grid (the inverse of the interp1
            % step bpBasic uses when reading the range profile back out).
            pos = (u + 0.5)*Ng + 1;
            i0 = floor(pos);
            w1 = pos - i0;
            i1 = i0 + 1;
            i0(i0 < 1) = 1; i1(i1 > Ng) = Ng;
            g = complex(accumarray(i0, real(b).*(1-w1), [Ng 1]) + accumarray(i1, real(b).*w1, [Ng 1]), ...
                        accumarray(i0, imag(b).*(1-w1), [Ng 1]) + accumarray(i1, imag(b).*w1, [Ng 1]));

            % S(k) = sum_m g(m)*exp(j*2*pi*u_m*(k-1)) with u_m = -0.5 + (m-1)/Ng
            S = Ng * ifft(g);
            S = S(1:K) .* ((-1).^((0:(K-1)).'));

            % Spreading each scatterer over two grid points is a convolution
            % with a triangular kernel, which multiplies the result by that
            % kernel's transform, sinc^2. Divide it back out. (At k = 1 the
            % two weights sum to 1, so that sample is already exact, which
            % is why the correction is 1 there.)
            S = S ./ apod;
            data.phdata(:, n) = S;
        end
        if dropped > 0
            warning('Synth_PhaseHistory:outOfSwath', ...
                '%d scatterer-pulse pairs fell outside the %.1f m unambiguous range window and were dropped.', ...
                dropped, maxWr);
        end

    otherwise
        error('Synth_PhaseHistory:method', 'method must be ''exact'' or ''fast''.');
end

data.synth_method = lower(method);
data.synth_time = toc(t0);
data.n_scatterers = Ns;
fprintf('Phase history: %d scatterers, %d pulses x %d frequencies, %s model, %.1f s\n', ...
    Ns, Np, K, lower(method), data.synth_time);
end
