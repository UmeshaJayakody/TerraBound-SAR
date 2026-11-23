function Light_Theme(fig)
% Puts one of RaySAR's original windows in MATLAB's light theme.
%
% These windows were laid out in 2011 with the default light colours. Under
% a dark MATLAB theme their labels come out pale grey on pale boxes, and
% some parts cannot be read. Setting the window's own theme leaves the
% user's MATLAB theme alone and fixes only these windows. MATLAB releases
% before R2025a have no theme function, and there the windows already look
% as they were designed, so nothing is done.

if exist('theme', 'file') == 0 && exist('theme', 'builtin') == 0
    return
end
try
    theme(fig, 'light');
catch
end
