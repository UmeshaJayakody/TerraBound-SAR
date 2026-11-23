% Makes the City_01 sample scene: five box buildings, [x z width depth height]
% in m, on an 80 m ground, seen through a 100 x 100 m view.
here = fileparts(mfilename('fullpath'));
addpath(fileparts(here));
buildings = [-30 10 18 18 25; 0 0 20 15 40; 30 15 16 16 20; -15 -20 14 14 15; 20 -15 18 18 30];
Make_Box_City_Scene(buildings, 80, [100 100], fullfile(fileparts(fileparts(here)), 'Scenes', 'City_01.pov'));
