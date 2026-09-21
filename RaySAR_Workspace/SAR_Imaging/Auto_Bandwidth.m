function bw = Auto_Bandwidth(extent, target_px)
% The radar bandwidth that makes a scene of the given size come out about
% target_px pixels across. Pixels are half a resolution cell (the paper
% advises sampling finer than the resolution), so the cell is
% 2*extent/target_px and the bandwidth is c over twice that. Street_01
% (125 m, 800 px) comes out at about 500 MHz. Kept between 1 MHz (150 m resolution,
% for scenes of tens of kilometres) and 2 GHz.
%
% extent:    larger side of the scene in m
% target_px: image size to aim for

c = 299792458;
bw = min(2e9, max(1e6, c/(2*(2*extent/target_px))));
end
