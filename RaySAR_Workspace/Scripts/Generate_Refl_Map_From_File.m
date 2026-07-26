function Generate_Refl_Map_From_File(contributions_path, output_path, opts)
% Drives Gen_Refl_Map directly from a Contributions.txt file, bypassing
% the interactive Maps GUI. Generalized version of run_step_reflectivity.m.
%
% contributions_path: path to Contributions.txt produced by the adapted POV-Ray engine
% output_path: folder where Maps/... results are written
% opts: struct of overrides (all optional, sensible defaults applied):
%   a_pix, r_pix        pixel spacing in azimuth/range [m]      (default 0.3)
%   a_min, a_max        azimuth bounds ('Min'/'Max' or number)  (default 'Min'/'Max' = auto-fit)
%   r_min, r_max        range bounds ('Min'/'Max' or number)    (default 'Min'/'Max' = auto-fit)
%   bounce_level        'Max' or 1-5                            (default 'Max')
%   db_min, db_max      dB display range                        (default '-20'/'Max')
%   r_geom              0 = slant range, 1 = ground range        (default 0)
%   range_dir           0 = bottom up, 1 = frontal view          (default 1, matches validated Step case)
%   coh                 0 = non-coherent, 1 = coherent sum        (default 0)

global Az Ra El Intens Tr_L Sp ang r_geom range_dir All_reflections Index_All az_min az_max ra_min ra_max bounce_rem Output_path;

if nargin < 3
    opts = struct();
end
get_opt = @(name,defaultval) get_opt_impl(opts,name,defaultval);

R = load(contributions_path);
Az = R(:,1);
Ra = R(:,2);
El = R(:,3);
Intens = R(:,4);
Tr_L = R(:,5);
Sp = R(:,6);

fprintf('Loaded %d signal contributions from %s\n', size(Az,1), contributions_path);

r_geom = get_opt('r_geom', 0);
range_dir = get_opt('range_dir', 1);
ang = -1;

Output_path = output_path;
if exist(Output_path,'dir') ~= 7
    mkdir(Output_path);
end

go.a_pix = get_opt('a_pix', 0.3);
go.r_pix = get_opt('r_pix', 0.3);
go.a_min = get_opt('a_min', 'Min');
go.a_max = get_opt('a_max', 'Max');
go.r_min = get_opt('r_min', 'Min');
go.r_max = get_opt('r_max', 'Max');
go.bounce_level = get_opt('bounce_level', 'Max');
go.dBnodB = 1;
go.db_min = get_opt('db_min', '-20');
go.db_max = get_opt('db_max', 'Max');
go.filt = 0;
go.coh = get_opt('coh', 0);
go.noise = 0;
go.store = get_opt('store', 1);
go.specular_flag = 0;
go.sinc_sim = 0;

Gen_Refl_Map(go);

fprintf('Done. Results written to %s\n', Output_path);

end

function v = get_opt_impl(opts, name, defaultval)
    if isfield(opts, name)
        v = opts.(name);
    else
        v = defaultval;
    end
end
