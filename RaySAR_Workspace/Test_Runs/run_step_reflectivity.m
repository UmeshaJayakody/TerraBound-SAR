% Drives Gen_Refl_Map directly for the Step test model, using the exact
% parameters documented in Step_Simulation_Documentation.pdf, bypassing
% the interactive Maps GUI.

addpath('D:/FYP/RaySAR_Workspace/RaySAR');

global Az Ra El Intens Tr_L Sp ang r_geom range_dir All_reflections Index_All az_min az_max ra_min ra_max bounce_rem Output_path;

% --- Load ray tracing contributions ---
R = load('D:/FYP/RaySAR_Workspace/POV_Ray/RaySAR/Contributions.txt');

Az = R(:,1);     % azimuth [m]
Ra = R(:,2);     % slant range [m]
El = R(:,3);     % elevation [m]
Intens = R(:,4); % intensity
Tr_L = R(:,5);   % bounce level
Sp = R(:,6);     % specular flag

fprintf('Loaded %d signal contributions.\n', size(Az,1));

% --- Imaging geometry (per Step_Simulation_Documentation.pdf) ---
r_geom = 0;      % slant range
range_dir = 1;   % frontal view (matches orientation of reference results)
ang = -1;        % unused in slant-range geometry

Output_path = 'D:/FYP/RaySAR_Workspace/Test_Runs/Step_Results';
if exist(Output_path,'dir') ~= 7
    mkdir(Output_path);
end

% --- Reflectivity map parameters ---
go.a_pix = 0.2;
go.r_pix = 0.2;
go.a_min = '-15';
go.a_max = '15';
go.r_min = '62';
go.r_max = '137';
go.bounce_level = 'Max';
go.dBnodB = 1;
go.db_min = '-20';
go.db_max = 'Max';
go.filt = 0;
go.coh = 0;
go.noise = 0;
go.store = 0;
go.specular_flag = 0;
go.sinc_sim = 0;

Gen_Refl_Map(go);

fprintf('Done. Results written to %s\n', Output_path);
