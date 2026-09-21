function s = POV_Header(comment, look_at, bearing, incidence, dist, extent)
% The text every RaySAR scene starts with: engine settings, an orthographic
% camera and a parallel light at the same place (a monostatic radar).
% Shared by Convert_OBJ_to_POV and Write_View_POV so a scene converted once
% and the same scene seen from another direction use one template.
%
% comment:   one line written as a // comment
% look_at:   [x y z] point the sensor looks at
% bearing:   look direction around the vertical axis in degrees. 0 puts the
%            sensor on the -z side looking toward +z, the layout every
%            RaySAR scene here has; positive values swing it toward +x.
% incidence: angle from the vertical in degrees (45 = the usual 45 deg)
% dist:      distance from look_at to the sensor. The camera is
%            orthographic, so this only has to place the sensor clear of
%            the scene.
% extent:    [width height] of the view in m

b = bearing*pi/180;
i = incidence*pi/180;
loc = look_at(:)' + dist*[sin(i)*sin(b), cos(i), -sin(i)*cos(b)];

s = sprintf('#version 3.5;\n\n#include "colors.inc"\n#include "finish.inc"\n\n');
s = [s sprintf('global_settings{SAR_Output_Data 1 SAR_Intersection 0}\n\n')];
s = [s sprintf('// %s\n\n', comment)];
s = [s sprintf('#declare Cam = camera {\n  orthographic\n  location <%g,%g,%g>\n  look_at <%g,%g,%g>\n  right %g*x\n  up %g*y\n}\n\ncamera{Cam}\n\n', ...
    loc(1), loc(2), loc(3), look_at(1), look_at(2), look_at(3), extent(1), extent(2))];
s = [s sprintf('light_source {\n  <%g,%g,%g>\n  color rgb <1,1,1>\n  parallel\n  point_at <%g,%g,%g>\n}\n\n', ...
    loc(1), loc(2), loc(3), look_at(1), look_at(2), look_at(3))];
end
