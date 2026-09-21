function n = Views_For_Coverage(footprint_m2, window_m, coverage, n_min, n_max)
% How many partial views an object needs so that each part of it is seen
% about `coverage` times. A big object needs more views than a small one,
% because a view covers a fixed size of ground.
%
% footprint_m2: ground area of the object, in m^2 (its bounding box)
% window_m:     [min max] size of a window in m, the side of the square of
%               ground it covers; views are drawn between these
% coverage:     how many times each part of the object should appear on
%               average, over all the partial views
% n_min, n_max: never fewer or more views than this (default 10 and 2000)
%
% The mean window area is taken over sizes drawn evenly between the two
% ends, (a^2 + a*b + b^2)/3. Windows overlap and run over the edges, so this
% is a guide to the amount of data, not an exact cover.

if nargin < 4 || isempty(n_min), n_min = 10; end
if nargin < 5 || isempty(n_max), n_max = 2000; end

a = window_m(1);
b = window_m(end);
mean_area = (a^2 + a*b + b^2)/3;
n = round(coverage*footprint_m2/mean_area);
n = max(n_min, min(n_max, n));
end
