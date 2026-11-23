function test_forward_model
% Checks the fast forward model against the exact one.
%
% Synth_PhaseHistory('exact') evaluates Eq. (5) of the paper literally, one
% frequency and one scatterer at a time. That is the definition, but it
% costs O(Ns*Np*K), which is hopeless for a scene with tens of thousands of
% scatterers. The 'fast' path computes the same sum by accumulating the
% scatterers onto a fine range grid and taking one FFT per pulse.
%
% This test confirms the two agree, on a random scene small enough that the
% exact model is affordable, both in the raw data and in the formed image.

here = fileparts(mfilename('fullpath'));
addpath(here);

try
    rng(7);
catch
    rand('seed', 7);   %#ok<RAND>  (older Octave)
end

% A small, deliberately awkward scene: random positions, random complex
% amplitudes, spread over 40 m in each direction and 5 m in height.
Ns = 200;
sc.x = 40*(rand(Ns,1) - 0.5);
sc.y = 40*(rand(Ns,1) - 0.5);
sc.z = 5*rand(Ns,1);
sc.amp = (0.2 + rand(Ns,1)) .* exp(1i*2*pi*rand(Ns,1));

p.K = 256; p.Np = 64; p.quiet = true;
geom = SAR_Params(p);

ex = Synth_PhaseHistory(geom, sc, 'exact');
fa = Synth_PhaseHistory(geom, sc, 'fast');

A = ex.phdata(:); B = fa.phdata(:);
rel = norm(A - B)/norm(A);
r = corrcoef([real(A); imag(A)], [real(B); imag(B)]);
fprintf('\nRaw data: relative RMS difference %.3e, correlation %.6f, speedup %.1fx\n', ...
    rel, r(1,2), ex.synth_time/max(fa.synth_time, eps));

% And in the image, which is what actually matters
[xm, ym] = meshgrid(-20:0.25:20, -20:0.25:20);
im = cell(1,2);
both = {ex, fa};
for i = 1:2
    d = both{i};
    d.x_mat = xm; d.y_mat = ym; d.z_mat = zeros(size(xm));
    d.quiet = true;
    d = bpBasic(d);
    im{i} = d.im_final;
end
a = abs(im{1}(:)); b = abs(im{2}(:));
rel_im = norm(a - b)/norm(a);
r_im = corrcoef(a, b);
fprintf('Image:    relative RMS difference %.3e, correlation %.6f\n', rel_im, r_im(1,2));

if rel < 5e-3 && r_im(1,2) > 0.999
    fprintf('RESULT: the fast forward model matches the exact Eq. (5) sum.\n');
else
    fprintf('RESULT: MISMATCH - do not trust the fast path.\n');
end
end
