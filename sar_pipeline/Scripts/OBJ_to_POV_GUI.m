function OBJ_to_POV_GUI
% Standalone GUI for Convert_OBJ_to_POV.m: pick a .obj file and a folder
% to save the converted .pov scene into, then click Convert. Separate
% from RaySAR's own Simulation_Data GUI -- this only does the OBJ->POV
% conversion step (Part 6 of the README), nothing else.

addpath(fileparts(mfilename('fullpath')));

fig = uifigure('Name', 'OBJ to POV Converter', 'Position', [100 100 520 230]);

uilabel(fig, 'Position', [20 180 100 22], 'Text', '.obj file:');
objField = uieditfield(fig, 'text', 'Position', [110 180 300 22], 'Editable', 'off');
uibutton(fig, 'push', 'Text', 'Browse...', 'Position', [420 180 80 22], ...
    'ButtonPushedFcn', @(btn,event) browse_obj());

uilabel(fig, 'Position', [20 140 100 22], 'Text', 'Result folder:');
outField = uieditfield(fig, 'text', 'Position', [110 140 300 22], 'Editable', 'off');
uibutton(fig, 'push', 'Text', 'Browse...', 'Position', [420 140 80 22], ...
    'ButtonPushedFcn', @(btn,event) browse_out());

statusLabel = uilabel(fig, 'Position', [20 80 480 45], 'Text', '', ...
    'FontColor', [0 0 0], 'WordWrap', 'on');

convertBtn = uibutton(fig, 'push', 'Text', 'Convert', 'Position', [210 30 100 30], ...
    'ButtonPushedFcn', @(btn,event) do_convert());

    function browse_obj()
        [f, p] = uigetfile('*.obj', 'Select .obj file');
        if ~isequal(f, 0)
            objField.Value = fullfile(p, f);
        end
    end

    function browse_out()
        d = uigetdir(pwd, 'Select folder to save the .pov result into');
        if ~isequal(d, 0)
            outField.Value = d;
        end
    end

    function do_convert()
        obj_path = objField.Value;
        out_dir = outField.Value;

        if isempty(obj_path) || isempty(out_dir)
            statusLabel.FontColor = [0.6 0 0];
            statusLabel.Text = 'Please select both a .obj file and a result folder.';
            return;
        end

        if exist(out_dir, 'dir') ~= 7
            mkdir(out_dir);
        end

        [~, base_name] = fileparts(obj_path);
        out_pov = fullfile(out_dir, [base_name, '.pov']);

        convertBtn.Enable = 'off';
        statusLabel.FontColor = [0 0 0];
        statusLabel.Text = 'Converting... this can take a while for large meshes.';
        drawnow;

        try
            Convert_OBJ_to_POV(obj_path, out_pov);
            statusLabel.FontColor = [0 0.5 0];
            statusLabel.Text = ['Done. Wrote ', out_pov];
        catch ME
            statusLabel.FontColor = [0.6 0 0];
            statusLabel.Text = ['Conversion failed: ', ME.message];
        end

        convertBtn.Enable = 'on';
    end

end
