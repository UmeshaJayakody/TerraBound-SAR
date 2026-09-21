function [extent, dist] = View_Frame(bbox, look_at, bearing, incidence)
% How big the sensor's view has to be to take in a whole model from one
% direction, and how far out the sensor has to sit to be clear of it.
%
% bbox:      [xmin xmax; ymin ymax; zmin zmax] of the model
% look_at:   [x y z] the sensor looks at
% bearing:   look direction in degrees around the vertical axis
% incidence: angle from the vertical in degrees
%
% The sensor is orthographic, so the frame is the model's bounding box
% projected onto the view. A square footprint is wider seen along its
% diagonal than along its side, so the answer depends on the direction.
% extent is [width height] in m, centred on look_at.

corners = [bbox(1,[1 2 1 2 1 2 1 2]); bbox(2,[1 1 2 2 1 1 2 2]); bbox(3,[1 1 1 1 2 2 2 2])]';
rel = corners - look_at(:)';

b = bearing*pi/180;
i = incidence*pi/180;
toward = [sin(i)*sin(b), cos(i), -sin(i)*cos(b)];   % from the scene to the sensor
d = -toward;                                        % viewing direction
u = cross([0 1 0], d);  u = u/norm(u);              % across the view
v = cross(d, u);                                    % up the view

margin = 1.15;
extent = 2*margin*[max(abs(rel*u')), max(abs(rel*v'))];
dist = 2*max(sqrt(sum(rel.^2, 2)));
end
