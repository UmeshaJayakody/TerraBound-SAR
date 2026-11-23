function SAR_Dataset_GUI
% SAR Dataset Studio: one window for the whole workflow, from a 3D object
% (.obj) to a folder of matching HR and lower-resolution SAR image pairs.
%
% Six steps, each explained on screen:
%   1 Object            the .obj file, where to save, how to treat the model
%   2 What to create    the complete set (whole scene from several sides plus many
%                       partial and side views), one full image, views around the
%                       object, views you pick by eye on a map of the object, or
%                       views chosen in Blender (Open Blender, then Capture)
%   3 Views             directions, incidence angles, and how much of the
%                       scene each image covers
%   4 Radar and images  resolution, lower-resolution versions, other options
%   5 Run               review, start, watch the images appear
%   6 Results           see every image that was made, and download them to any folder
%                       (or a .zip file) you choose
%
% Everything is reported inside the window. Nothing pops up, and the ray
% tracer's own windows are hidden while it works. The work itself is done by
% Make_Multi_Angle_Dataset, which can also be called directly, e.g. on a
% server: Make_Multi_Angle_Dataset(obj, out_folder, opts).
%
% Settings can be saved to a file and loaded again (buttons at the bottom),
% and every run also writes them next to the images as settings.json.

here = fileparts(mfilename('fullpath'));
addpath(here);
addpath(fullfile(fileparts(here), 'SAR_Imaging'));

STEPS = {'Object', 'What to create', 'Views', 'Radar and images', 'Run', 'Results'};
SUBTITLE = { ...
    'Choose the 3D object, where to save the images, and how the object should be treated.', ...
    'Choose what kind of data set to make.', ...
    'Choose where the radar looks from, and how much of the scene each image covers.', ...
    'Choose the resolution, the lower-resolution versions and a few other options.', ...
    'Check the settings, then start. Finished views appear below as they are made.', ...
    'See every image that was made, and download them to any place you choose.'};

% Surface responses the ray tracer understands, taken from the scenes already
% made here. They are hand-set, not measured: they say how mirror-like or
% rough a surface is, not what it is made of.
OBJ_MATERIALS = { ...
    'Buildings, concrete (default)', 'finish {reflection {0.4} ambient 0 diffuse 0.35 specular 0.5 roughness 0.01}'
    'Metal (ship, vehicles)',        'finish {reflection {0.5} ambient 0 diffuse 0.2 specular 0.8 roughness 0.01}'
    'Vegetation, rough terrain',     'finish {reflection {0.05} ambient 0 diffuse 0.6 specular 0.05 roughness 0.3}'
    'Sandy terrain (desert)',        'finish {reflection {0.15} ambient 0 diffuse 0.55 specular 0.15 roughness 0.15}'
    'Soil, gravel terrain',          'finish {reflection {0.2} ambient 0 diffuse 0.5 specular 0.2 roughness 0.1}'
    'Custom (type it below)',        ''
    'By material name in the file',  'materials:auto'};   % each usemtl name picks its finish (Radar_Materials)
MAT_CUSTOM = find(strcmp(OBJ_MATERIALS(:, 1), 'Custom (type it below)'));
GROUNDS = { ...
    'Land (default)',                'finish {reflection {0.3} ambient 0 diffuse 0.15 specular 0}'
    'Water, pond',                   'finish {reflection {0.35} ambient 0 diffuse 0.3 specular 0.5 roughness 0.05}'
    'Sea (near mirror, stylised)',   'finish {reflection {0.6} ambient 0 diffuse 0.02 specular 0.9 roughness 0.001}'
    'No ground plane',               ''
    'Custom (type it below)',        ''};
BOUNCES = {'All', '1', '2', '3', '4', '5'};

% ---- state -----------------------------------------------------------------
step = 1;
running = false;
stop_requested = false;
root_dir = '';
view_rows = {};            % the info of every view, for the results table
frozen = [];               % controls switched off while a run is going
model_size = [];           % [width height depth] of the chosen object in m, once read
model_key = '';            % which file, up axis and units model_size belongs to
analysis = [];             % what Analyze_OBJ found in the chosen file (kept, so a change of choice costs nothing)
analysis_file = '';        % the file it belongs to, and when that file was written
analysis_stamp = [];
resolved = [];             % the up axis and units in use, from Resolve_Model, and what they make of the file
planned_n = 0;             % how many views the run has said it will make
model_pts = [];            % a sample of the object's vertices [x height z], for the map
map_key = '';              % which object the map was last set up for
picks = zeros(0, 6);       % views picked on the map: [direction angle centre_x centre_z width height]
pick_sel = 0;              % the selected row of the list of picked views
bl_picks = zeros(0, 6);    % views captured from Blender: [direction angle centre_x centre_z width height]
bl_names = {};             % the cameras they came from
blender_obj = '';          % the model Blender exported, which those views are relative to
res_root = '';             % the dataset folder shown in Results
res_all = [];              % every view in that folder, one struct each, newest first
res_views = [];            % the ones shown: the latest render, or all of them (history)
res_scope = 'run';         % 'run': only the latest render; 'all': the history too
res_loaded = '';           % the folder res_all was read from
last_run = struct('root', '', 'ids', {{}});   % the views the last run in this window handled
res_shown = [];            % indices into res_views that the filter lets through
res_page = 1;
res_sel = 0;               % index into res_views of the selected view
last_dest = '';            % where the last download went
PAGE = 12;                 % thumbnails per page
FILTERS = {'All views', 'Whole-scene views', 'Partial views', 'Side views (60 deg or more)', 'Views from above (under 60 deg)', 'Failed views'};

% ---- window ----------------------------------------------------------------
fig = uifigure('Name', 'SAR Dataset Studio', 'Position', [40 30 1120 780], 'Tag', 'studio');

main = uigridlayout(fig, [3 2]);
main.ColumnWidth = {190, '1x'};
main.RowHeight = {'1x', 34, 40};
main.Padding = [10 10 10 10];

% Left: the steps
side = uipanel(main, 'Title', '');
at(side, [1 3], 1);
sg = uigridlayout(side, [10 1]);
sg.RowHeight = {30, 8, 38, 38, 38, 38, 38, 38, '1x', 60};
sg.Padding = [8 8 8 8];
uilabel(sg, 'Text', 'Steps', 'FontWeight', 'bold', 'FontSize', 15);
step_btn = gobjects(1, 6);
for k = 1:6
    step_btn(k) = uibutton(sg, 'push', 'Text', sprintf('%d   %s', k, STEPS{k}), ...
        'HorizontalAlignment', 'left', 'ButtonPushedFcn', @(~, ~) goto_step(k));
    at(step_btn(k), 2 + k, 1);
end
side_note = uilabel(sg, 'Text', 'Every setting has a default, so you can click Next through the steps.', ...
    'WordWrap', 'on', 'VerticalAlignment', 'top');
at(side_note, 10, 1);

% Right: heading, the current step, message line, buttons
content = uipanel(main, 'BorderType', 'none');
at(content, 1, 2);
cg = uigridlayout(content, [2 1]);
cg.RowHeight = {60, '1x'};
cg.Padding = [0 0 0 0];
head = uigridlayout(cg, [2 1]);
head.RowHeight = {28, 26};
head.Padding = [4 0 0 0];
head.RowSpacing = 2;
title_lbl = uilabel(head, 'Text', '', 'FontWeight', 'bold', 'FontSize', 18);
sub_lbl = uilabel(head, 'Text', '', 'WordWrap', 'on');
stack = uigridlayout(cg, [1 1]);
stack.Padding = [0 0 0 0];

msg = uilabel(main, 'Text', '', 'WordWrap', 'on', 'FontWeight', 'bold', 'Tag', 'message');
at(msg, 2, 2);

nav = uigridlayout(main, [1 7]);
at(nav, 3, 2);
nav.ColumnWidth = {130, 130, '1x', 150, 100, 100, 4};
nav.Padding = [0 4 0 4];
save_btn = uibutton(nav, 'push', 'Text', 'Save settings...', 'ButtonPushedFcn', @(~, ~) do_save());
load_btn = uibutton(nav, 'push', 'Text', 'Load settings...', 'ButtonPushedFcn', @(~, ~) do_load());
uilabel(nav, 'Text', '');
earth_btn = uibutton(nav, 'push', 'Text', 'Real world (map)...', 'Tag', 'earth', ...
    'Tooltip', 'Pick real places on a world map and make their SAR images (Earth Capture)', ...
    'ButtonPushedFcn', @(~, ~) open_earth_capture());
back_btn = uibutton(nav, 'push', 'Text', '< Back', 'ButtonPushedFcn', @(~, ~) goto_step(step - 1));
next_btn = uibutton(nav, 'push', 'Text', 'Next >', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) do_next());
at(save_btn, 1, 1); at(load_btn, 1, 2); at(earth_btn, 1, 4); at(back_btn, 1, 5); at(next_btn, 1, 6);

% Each step is a grid in the same cell of the stack; only one is visible at a time
panels = gobjects(1, 6);

% ============================ Step 1: Object ==================================
g = step_grid(1, [12 4]);
g.ColumnWidth = {170, 250, '1x', 100};
g.RowHeight = {30, 30, 8, 30, 30, 30, 30, 30, 30, 30, 30, 150};
g.Padding = [8 8 8 8];
row_label(g, 1, 'Object file (.obj)');
obj_field = at(uieditfield(g, 'text', 'Editable', 'off', 'Tag', 'obj'), 1, [2 3]);
at(uibutton(g, 'push', 'Text', 'Browse...', 'ButtonPushedFcn', @(~, ~) browse_obj()), 1, 4);
row_label(g, 2, 'Save images in');
out_field = at(uieditfield(g, 'text', 'Tag', 'out', 'Value', fullfile(userpath_or_pwd(), 'SAR_Dataset')), 2, [2 3]);
at(uibutton(g, 'push', 'Text', 'Browse...', 'ButtonPushedFcn', @(~, ~) browse_out()), 2, 4);
row_label(g, 4, 'Which way is up');
up_drop = at(uidropdown(g, 'Items', {'Automatic (recommended)', 'Y is up (most files)', 'Z is up (3ds Max exports)'}, ...
    'ItemsData', {'auto', 'y', 'z'}, 'Value', 'auto', 'Tag', 'up', 'ValueChangedFcn', @(~, ~) model_choice_changed()), 4, 2);
row_hint(g, 4, 'Found from the shape of the object. Change it only if the object comes out lying on its side.');
row_label(g, 5, 'Units of the file');
units_drop = at(uidropdown(g, 'Items', {'Automatic (recommended)', 'Metres', 'Centimetres', 'Millimetres', 'Inches', 'Feet', 'Kilometres', 'Other...'}, ...
    'ItemsData', {'auto', '1', '0.01', '0.001', '0.0254', '0.3048', '1000', 'custom'}, 'Value', 'auto', 'Tag', 'units', ...
    'ValueChangedFcn', @(~, ~) model_choice_changed()), 5, 2);
row_hint(g, 5, 'Read from the file or judged from its size, so that it comes out at its real size in metres.');
row_label(g, 6, 'Metres per unit (Other)');
units_custom = at(uieditfield(g, 'numeric', 'Value', 1, 'Limits', [1e-9 1e9], 'LowerLimitInclusive', 'on', 'Tag', 'units_custom', ...
    'Enable', 'off', 'ValueChangedFcn', @(~, ~) model_choice_changed()), 6, 2);
row_label(g, 7, 'Object surface');
mat_drop = at(uidropdown(g, 'Items', OBJ_MATERIALS(:, 1), 'ItemsData', 1:size(OBJ_MATERIALS, 1), 'Value', 1, 'Tag', 'material', ...
    'ValueChangedFcn', @(~, ~) update_custom()), 7, 2);
row_hint(g, 7, 'How mirror-like or rough the object is to the radar.');
row_label(g, 8, 'Ground');
gnd_drop = at(uidropdown(g, 'Items', GROUNDS(:, 1), 'ItemsData', 1:size(GROUNDS, 1), 'Value', 1, 'Tag', 'ground', ...
    'ValueChangedFcn', @(~, ~) update_custom()), 8, 2);
row_hint(g, 8, 'The flat surface under the object. The sea is a stylised mirror, not real sea scattering.');
row_label(g, 9, 'Custom object surface');
cust_obj = at(uieditfield(g, 'text', 'Tag', 'custom_obj', 'Enable', 'off', 'Placeholder', 'finish {reflection {0.4} ambient 0 diffuse 0.35 specular 0.5 roughness 0.01}'), 9, [2 3]);
row_label(g, 10, 'Custom ground');
cust_gnd = at(uieditfield(g, 'text', 'Tag', 'custom_ground', 'Enable', 'off', 'Placeholder', 'finish {reflection {0.3} ambient 0 diffuse 0.15 specular 0}'), 10, [2 3]);
check_btn = at(uibutton(g, 'push', 'Text', 'Check model', 'Tag', 'check', 'ButtonPushedFcn', @(~, ~) check_model(true)), 11, 2);
row_hint(g, 11, 'Reads the file again and shows what was found. This happens by itself when you choose a file.');
model_info = at(uilabel(g, 'Text', {'Choose an object file. Any size of .obj file works: its up direction, its units and its size are worked out for you, and shown here.'}, ...
    'WordWrap', 'on', 'VerticalAlignment', 'top', 'Tag', 'model_info'), 12, [2 4]);

% ============================ Step 2: What to create ==========================
g = step_grid(2, [3 1]);
g.RowHeight = {172, 64, '1x'};
g.Padding = [8 8 8 8];
mode_group = uibuttongroup(g, 'Title', '', 'BorderType', 'none', 'Tag', 'mode', 'SelectionChangedFcn', @(~, ~) mode_changed());
at(mode_group, 1, 1);
mode_btn(1) = uiradiobutton(mode_group, 'Text', 'Complete set (recommended)', 'Position', [10 142 300 22], 'Tag', 'mode1');
mode_btn(2) = uiradiobutton(mode_group, 'Text', 'One full image', 'Position', [10 110 300 22], 'Tag', 'mode2');
mode_btn(3) = uiradiobutton(mode_group, 'Text', 'Views around the object', 'Position', [10 78 300 22], 'Tag', 'mode3');
mode_btn(4) = uiradiobutton(mode_group, 'Text', 'Choose views on a map', 'Position', [10 46 300 22], 'Tag', 'mode4');
mode_btn(5) = uiradiobutton(mode_group, 'Text', 'Choose views in Blender', 'Position', [10 14 300 22], 'Tag', 'mode5');
mode_text = at(uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment', 'top'), 2, 1);
at(uilabel(g, 'Text', ['A view is one image seen from one direction and angle. A window is the part of the scene ' ...
    'it covers, from the whole object down to a small piece. Side views and partial views are just views ' ...
    'with a different direction, angle or window.'], 'WordWrap', 'on', 'VerticalAlignment', 'top'), 3, 1);

% ============================ Step 3: Views ===================================
g = step_grid(3, [3 1]);
g.RowHeight = {400, 66, 44};
g.Padding = [8 8 8 8];
vstack = uigridlayout(g, [1 1]);
vstack.Padding = [0 0 0 0];
at(vstack, 1, 1);
views_summary = at(uilabel(g, 'Text', '', 'FontWeight', 'bold', 'WordWrap', 'on', 'VerticalAlignment', 'top', 'Tag', 'views_summary'), 2, 1);
views_time = at(uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment', 'top'), 3, 1);

vp = gobjects(1, 5);

% one full image
g = view_grid(vstack, 3);
vp(2) = g;
row_label(g, 1, 'Direction [deg]');
full_bearing = at(uieditfield(g, 'numeric', 'Value', 0, 'Limits', [0 360], 'LowerLimitInclusive', 'on', 'UpperLimitInclusive', 'off', 'Tag', 'full_bearing', ...
    'ValueChangedFcn', @(~, ~) update_summary()), 1, 2);
row_hint(g, 1, '0 is the default view. Larger values turn the radar round the object; 90 looks from the side.');
row_label(g, 2, 'Incidence angle [deg]');
full_inc = at(uieditfield(g, 'numeric', 'Value', 45, 'Limits', [10 85], 'Tag', 'full_inc', ...
    'ValueChangedFcn', @(~, ~) update_summary()), 2, 2);
row_hint(g, 2, 'Angle from straight down. 45 is typical; 70 or more looks from the side, with long shadows and walls showing.');

% views around the object
g = view_grid(vstack, 5);
vp(3) = g;
row_label(g, 1, 'Number of directions');
around_n = at(uieditfield(g, 'numeric', 'Value', 8, 'Limits', [1 72], 'RoundFractionalValues', 'on', 'Tag', 'around_n', ...
    'ValueChangedFcn', @(~, ~) update_summary()), 1, 2);
row_hint(g, 1, 'Spread evenly all the way round: 8 gives every 45 degrees.');
row_label(g, 2, 'First direction [deg]');
around_first = at(uieditfield(g, 'numeric', 'Value', 0, 'Limits', [0 360], 'UpperLimitInclusive', 'off', 'Tag', 'around_first'), 2, 2);
row_hint(g, 2, 'Where to start; turns every direction by this much.');
row_label(g, 3, 'Incidence angles [deg]');
around_inc = at(uieditfield(g, 'text', 'Value', '45', 'Tag', 'around_inc', 'ValueChangedFcn', @(~, ~) update_summary()), 3, 2);
row_hint(g, 3, 'One or several, e.g. 35 45 55. Every direction is taken at each angle.');
row_label(g, 4, 'Window size [% of scene]');
around_win = at(uieditfield(g, 'numeric', 'Value', 100, 'Limits', [10 100], 'RoundFractionalValues', 'on', 'Tag', 'around_win'), 4, 2);
row_hint(g, 4, '100 is the whole object. Less makes each image a part of the scene.');
row_label(g, 5, 'Windows per side');
around_grid = at(uieditfield(g, 'numeric', 'Value', 1, 'Limits', [1 10], 'RoundFractionalValues', 'on', 'Tag', 'around_grid', ...
    'ValueChangedFcn', @(~, ~) update_summary()), 5, 2);
row_hint(g, 5, '1 is one window in the middle; 2 places windows at 2 x 2 spots over the object; and so on.');

% complete set: whole-scene views from several sides, and many partial views
g = view_grid(vstack, 9);
vp(1) = g;
row_label(g, 1, 'Whole-scene directions');
comp_whole_n = at(uieditfield(g, 'numeric', 'Value', 4, 'Limits', [0 72], 'RoundFractionalValues', 'on', 'Tag', 'comp_whole_n', ...
    'ValueChangedFcn', @(~, ~) update_summary()), 1, 2);
row_hint(g, 1, 'Images of the whole object, spread evenly round it: 4 is one from each side. 0 for none.');
row_label(g, 2, 'Whole-scene angles [deg]');
comp_whole_inc = at(uieditfield(g, 'text', 'Value', '40 65', 'Tag', 'comp_whole_inc', ...
    'ValueChangedFcn', @(~, ~) update_summary()), 2, 2);
row_hint(g, 2, 'From straight down, one or several. 40 is fairly from above, 65 from a low side angle.');
row_label(g, 3, 'Partial views');
comp_auto = at(uidropdown(g, 'Items', {'Automatic (from object size)', 'A fixed number'}, 'ItemsData', {'auto', 'fixed'}, ...
    'Value', 'auto', 'Tag', 'comp_auto', 'ValueChangedFcn', @(~, ~) update_comp()), 3, 2);
row_hint(g, 3, 'Windows on parts of the object, from random directions and places. A bigger object gets more.');
row_label(g, 4, 'Each part seen about [times]');
comp_cover = at(uieditfield(g, 'numeric', 'Value', 3, 'Limits', [0.5 50], 'Tag', 'comp_cover'), 4, 2);
row_hint(g, 4, 'Automatic: how often each part of the object should appear over all the partial views.');
row_label(g, 5, 'Number of partial views');
comp_n = at(uieditfield(g, 'numeric', 'Value', 50, 'Limits', [0 5000], 'RoundFractionalValues', 'on', 'Tag', 'comp_n', 'Enable', 'off'), 5, 2);
row_hint(g, 5, 'Only for "A fixed number".');
row_label(g, 6, 'Window size [m]');
comp_win = range_fields(g, 6, [40 100], [5 2000], 'comp_win');
row_hint(g, 6, 'From ... to: the width of ground a partial view covers. The same on every object.');
row_label(g, 7, 'Partial-view angles [deg]');
comp_inc = range_fields(g, 7, [25 60], [10 85], 'comp_inc');
row_hint(g, 7, 'From ... to, from straight down. Small numbers look from above.');
row_label(g, 8, 'Share of side views [%]');
comp_side = at(uieditfield(g, 'numeric', 'Value', 35, 'Limits', [0 100], 'Tag', 'comp_side'), 8, 2);
row_hint(g, 8, 'How many of the partial views look from a low angle instead, so walls and sides show.');
row_label(g, 9, 'Side-view angles [deg]');
comp_side_r = range_fields(g, 9, [62 80], [40 85], 'comp_side_r');
row_hint(g, 9, 'From ... to. Near 85 is almost level with the ground: long shadows, dark ground.');

% choose views on a map
g = uigridlayout(vstack, [1 2]);
g.Layout.Row = 1;
g.Layout.Column = 1;
g.Visible = 'off';
g.ColumnWidth = {'1.6x', '1x'};
g.Padding = [0 0 0 0];
g.ColumnSpacing = 12;
vp(4) = g;

lc = uigridlayout(g, [2 1]);
lc.RowHeight = {'1x', 112};
lc.Padding = [0 0 0 0];
lc.RowSpacing = 6;
map_ax = uiaxes(lc);
map_ax.Layout.Row = 1;
map_ax.Toolbar.Visible = 'off';
disableDefaultInteractivity(map_ax);
title(map_ax, 'Top view of the object (north is up)');
xlabel(map_ax, 'x [m]');
ylabel(map_ax, 'north [m]');
map_ax.ButtonDownFcn = @(~, ev) map_click(ev);
pick_tbl = uitable(lc, 'ColumnName', {'View', 'Direction', 'Angle', 'Centre x', 'Centre z', 'Window'}, ...
    'ColumnWidth', {60, 70, 60, 80, 80, '1x'}, 'RowName', {}, 'Data', cell(0, 6), 'Tag', 'picks', ...
    'CellSelectionCallback', @(~, ev) pick_selected(ev));
pick_tbl.Layout.Row = 2;

rc = uigridlayout(g, [11 2]);
rc.ColumnWidth = {110, '1x'};
rc.RowHeight = {56, 26, 26, 26, 26, 26, 26, 26, 30, 26, '1x'};
rc.Padding = [0 0 0 0];
rc.RowSpacing = 4;
inst = uilabel(rc, 'Text', ['Click the map to put the window there, then choose the direction, angle and size. ' ...
    'The blue frame is the ground the picture will cover and the triangle is where the radar sits. ' ...
    'Then click Add this view, and do it again for more.'], 'WordWrap', 'on', 'VerticalAlignment', 'top');
at(inst, 1, [1 2]);
row_label(rc, 2, 'A click sets');
pick_click = at(uidropdown(rc, 'Items', {'The window centre', 'Where the radar sits'}, 'ItemsData', {'center', 'radar'}, ...
    'Value', 'center', 'Tag', 'pick_click'), 2, 2);
row_label(rc, 3, 'Direction [deg]');
pick_dir = at(uieditfield(rc, 'numeric', 'Value', 0, 'Limits', [0 360], 'UpperLimitInclusive', 'off', 'Tag', 'pick_dir', ...
    'ValueChangedFcn', @(~, ~) draw_overlay()), 3, 2);
row_label(rc, 4, 'Angle [deg]');
pick_inc = at(uieditfield(rc, 'numeric', 'Value', 50, 'Limits', [10 85], 'Tag', 'pick_inc', ...
    'ValueChangedFcn', @(~, ~) draw_overlay()), 4, 2);
row_label(rc, 5, 'Window width [m]');
pick_w = at(uieditfield(rc, 'numeric', 'Value', 60, 'Limits', [5 3000], 'Tag', 'pick_w', ...
    'ValueChangedFcn', @(~, ~) draw_overlay()), 5, 2);
row_label(rc, 6, 'Window height [m]');
pick_h = at(uieditfield(rc, 'numeric', 'Value', 45, 'Limits', [5 3000], 'Tag', 'pick_h', ...
    'ValueChangedFcn', @(~, ~) draw_overlay()), 6, 2);
row_label(rc, 7, 'Centre x [m]');
pick_cx = at(uieditfield(rc, 'numeric', 'Value', 0, 'Tag', 'pick_cx', 'ValueChangedFcn', @(~, ~) draw_overlay()), 7, 2);
row_label(rc, 8, 'Centre z [m]');
pick_cz = at(uieditfield(rc, 'numeric', 'Value', 0, 'Tag', 'pick_cz', 'ValueChangedFcn', @(~, ~) draw_overlay()), 8, 2);
pick_add = at(uibutton(rc, 'push', 'Text', 'Add this view', 'FontWeight', 'bold', 'Tag', 'pick_add', ...
    'ButtonPushedFcn', @(~, ~) add_pick()), 9, [1 2]);
bg2 = uigridlayout(rc, [1 2]);
at(bg2, 10, [1 2]);
bg2.Padding = [0 0 0 0];
uibutton(bg2, 'push', 'Text', 'Remove selected', 'Tag', 'pick_remove', 'ButtonPushedFcn', @(~, ~) remove_pick());
uibutton(bg2, 'push', 'Text', 'Clear all', 'Tag', 'pick_clear', 'ButtonPushedFcn', @(~, ~) clear_picks());
pick_info = at(uilabel(rc, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment', 'top'), 11, [1 2]);

% views chosen in Blender
g = uigridlayout(vstack, [7 3]);
g.Layout.Row = 1;
g.Layout.Column = 1;
g.Visible = 'off';
g.ColumnWidth = {170, '1x', 110};
g.RowHeight = {66, 30, 36, 50, 36, 24, '1x'};
g.Padding = [8 8 8 8];
g.RowSpacing = 8;
vp(5) = g;
at(uilabel(g, 'Text', ['Choose each SAR image by eye in Blender: a yellow box on your object marks the window. Move it, ' ...
    'turn it and resize it, and set the look angle. Blender opens with your object already loaded. Two buttons do ' ...
    'the rest, and nothing runs in the background.'], ...
    'WordWrap', 'on', 'VerticalAlignment', 'top'), 1, [1 3]);
row_label(g, 2, 'Blender program');
blender_field = at(uieditfield(g, 'text', 'Value', Find_Blender(), 'Tag', 'blender_exe', 'Placeholder', 'Browse to blender.exe'), 2, 2);
at(uibutton(g, 'push', 'Text', 'Browse...', 'ButtonPushedFcn', @(~, ~) browse_blender()), 2, 3);
at(uibutton(g, 'push', 'Text', 'Open Blender', 'FontWeight', 'bold', 'Tag', 'open_blender', ...
    'ButtonPushedFcn', @(~, ~) open_blender()), 3, [1 2]);
at(uilabel(g, 'Text', ['In Blender a yellow box lies on your object: it is the window. Click it, then G moves it, R turns it ' ...
    '(the small triangle is the side the radar is on) and S resizes it; set the Angle in the panel under Transform. ' ...
    'Add more boxes with "Add the yellow window box". There is nothing to save: click Capture here and it takes the ' ...
    'boxes where they are now.'], ...
    'WordWrap', 'on', 'VerticalAlignment', 'top'), 4, [1 3]);
capture_btn = at(uibutton(g, 'push', 'Text', 'Capture', 'FontWeight', 'bold', 'FontSize', 15, 'Tag', 'capture_blender', ...
    'ButtonPushedFcn', @(~, ~) capture_button()), 5, 2);
bl_now = at(uicheckbox(g, 'Text', 'Make the images right away', 'Value', true, 'Tag', 'bl_now'), 5, 3);
bl_info = at(uilabel(g, 'Text', 'Nothing captured yet.', 'Tag', 'bl_info', 'WordWrap', 'on'), 6, [1 3]);
bl_tbl = at(uitable(g, 'ColumnName', {'Camera', 'Direction', 'Angle', 'Centre x', 'Centre z', 'Window'}, ...
    'ColumnWidth', {110, 70, 60, 80, 80, '1x'}, 'RowName', {}, 'Data', cell(0, 6), 'Tag', 'bl_views'), 7, [1 3]);

% ============================ Step 4: Radar and images ========================
g = step_grid(4, [11 3]);
g.ColumnWidth = {200, 250, '1x'};
g.RowHeight = repmat({30}, 1, 11);
g.Padding = [8 8 8 8];
row_label(g, 1, 'Resolution');
res_drop = at(uidropdown(g, 'Items', {'Fixed (same for every object)', 'Automatic (from object size)'}, 'ItemsData', {'manual', 'auto'}, 'Value', 'manual', 'Tag', 'res', ...
    'ValueChangedFcn', @(~, ~) update_radar()), 1, 2);
row_hint(g, 1, 'Fixed keeps every image at the same resolution, so all your data is comparable. Automatic sizes it from the object.');
row_label(g, 2, 'Image size [px]');
px_field = at(uieditfield(g, 'numeric', 'Value', 800, 'Limits', [200 4000], 'RoundFractionalValues', 'on', 'Tag', 'px', 'Enable', 'off'), 2, 2);
row_hint(g, 2, 'Automatic only: how wide the whole scene comes out. Windows come out smaller.');
row_label(g, 3, 'Bandwidth [MHz]');
bw_field = at(uieditfield(g, 'numeric', 'Value', 500, 'Limits', [10 5000], 'Tag', 'bw', ...
    'ValueChangedFcn', @(~, ~) update_radar()), 3, 2);
bw_hint = at(uilabel(g, 'Text', '', 'FontAngle', 'italic', 'WordWrap', 'on'), 3, 3);
row_label(g, 4, 'Lower-resolution versions');
fac_field = at(uieditfield(g, 'text', 'Value', '2 4 8', 'Tag', 'factors', 'ValueChangedFcn', @(~, ~) update_radar()), 4, 2);
fac_hint = at(uilabel(g, 'Text', '', 'FontAngle', 'italic', 'WordWrap', 'on'), 4, 3);
row_label(g, 5, 'Speckle seed');
seed_field = at(uieditfield(g, 'numeric', 'Value', 1, 'Limits', [0 1e6], 'RoundFractionalValues', 'on', 'Tag', 'seed'), 5, 2);
row_hint(g, 5, 'Same seed, same speckle. Each view then uses the next number.');
row_label(g, 6, 'Highest bounce level');
bounce_drop = at(uidropdown(g, 'Items', BOUNCES, 'ItemsData', 1:6, 'Value', 1, 'Tag', 'bounce'), 6, 2);
row_hint(g, 6, 'All keeps every return. 1 keeps only direct returns, without corner and multi-bounce ones.');
row_label(g, 7, 'Rays per image pixel');
rays_field = at(uieditfield(g, 'numeric', 'Value', 1.25, 'Limits', [0.5 4], 'Tag', 'rays'), 7, 2);
row_hint(g, 7, 'How finely the ray tracer samples, per side. The same for every view. More is smoother but slower.');
top_box = at(uicheckbox(g, 'Text', 'Orient images like RaySAR (top down)', 'Value', true, 'Tag', 'topdown'), 8, [1 2]);
row_hint(g, 8, 'Range increases downward, as in RaySAR''s own maps.');
cplx_box = at(uicheckbox(g, 'Text', 'Also save complex images (with phase)', 'Value', true, 'Tag', 'complex'), 9, [1 2]);
row_hint(g, 9, 'A .mat file per view, about 17 MB for a full scene. The PNGs do not need it.');
keep_box = at(uicheckbox(g, 'Text', 'Keep the ray tracer''s files', 'Value', false, 'Tag', 'keep'), 10, [1 2]);
row_hint(g, 10, 'The view''s .pov scene and Contributions.txt, about 50 MB per view. Off saves disk space.');
redo_box = at(uicheckbox(g, 'Text', 'Redo views that are already done', 'Value', false, 'Tag', 'redo'), 11, [1 2]);
row_hint(g, 11, 'Off: a run that was stopped carries on where it stopped.');

% ============================ Step 5: Run =====================================
g = step_grid(5, [7 1]);
g.RowHeight = {92, 34, 16, 22, 130, 20, '1x'};
g.Padding = [8 8 8 8];
g.RowSpacing = 6;
review = at(uitextarea(g, 'Editable', 'off', 'Tag', 'review'), 1, 1);
btn_row = uigridlayout(g, [1 5]);
at(btn_row, 2, 1);
btn_row.ColumnWidth = {130, 100, 130, '1x', 0};
btn_row.Padding = [0 0 0 0];
start_btn = at(uibutton(btn_row, 'push', 'Text', 'Start', 'FontWeight', 'bold', 'Tag', 'start', 'ButtonPushedFcn', @(~, ~) do_start()), 1, 1);
stop_btn = at(uibutton(btn_row, 'push', 'Text', 'Stop', 'Enable', 'off', 'Tag', 'stop', 'ButtonPushedFcn', @(~, ~) do_stop()), 1, 2);
open_btn = at(uibutton(btn_row, 'push', 'Text', 'Open folder', 'Enable', 'off', 'Tag', 'open', 'ButtonPushedFcn', @(~, ~) open_folder()), 1, 3);
bar_bg = uipanel(g, 'BorderType', 'line');
at(bar_bg, 3, 1);
bar_fill = uipanel(bar_bg, 'Units', 'pixels', 'Position', [0 0 0 14], 'BorderType', 'none', 'BackgroundColor', [0.2 0.55 0.85]);
run_status = at(uilabel(g, 'Text', 'Ready.', 'Tag', 'run_status'), 4, 1);
tbl = at(uitable(g, 'Tag', 'views', 'ColumnName', {'View', 'Direction', 'Incidence', 'Window', 'Size (px)', 'Status', 'Seconds'}, ...
    'ColumnWidth', {170, 80, 80, 90, 100, 100, '1x'}, 'RowName', {}, 'Data', cell(0, 7), ...
    'CellSelectionCallback', @(~, ev) table_selected(ev)), 5, 1);
detail = at(uilabel(g, 'Text', 'Click a row to see its images.', 'Tag', 'detail'), 6, 1);
pv = uigridlayout(g, [1 5]);
at(pv, 7, 1);
pv.Padding = [0 0 0 0];
pv_ax = gobjects(1, 5);
for k = 1:5
    pv_ax(k) = uiaxes(pv);
    pv_ax(k).XTick = []; pv_ax(k).YTick = [];
    pv_ax(k).Box = 'on';
    pv_ax(k).Toolbar.Visible = 'off';
    disableDefaultInteractivity(pv_ax(k));
    title(pv_ax(k), '');
end

% ============================ Step 6: Results =================================
g = step_grid(6, [3 1]);
g.RowHeight = {62, '1x', 176};
g.Padding = [8 8 8 8];
g.RowSpacing = 6;

tb = uigridlayout(g, [2 6]);
at(tb, 1, 1);
tb.RowHeight = {26, 28};
tb.ColumnWidth = {140, 170, '1x', 70, 90, 70};
tb.Padding = [0 0 0 0];
tb.RowSpacing = 4;
res_path = at(uilabel(tb, 'Text', 'No dataset loaded.', 'Tag', 'res_path'), 1, [1 6]);
hist_btn = at(uibutton(tb, 'push', 'Text', 'History', 'Tag', 'history', 'ButtonPushedFcn', @(~, ~) toggle_history(), ...
    'Tooltip', 'Show the older images in this folder as well as the latest render, or go back to the latest render only.'), 2, 1);
at(uibutton(tb, 'push', 'Text', 'Open another dataset...', 'ButtonPushedFcn', @(~, ~) browse_dataset()), 2, 2);
filter_drop = at(uidropdown(tb, 'Items', FILTERS, 'ItemsData', 1:numel(FILTERS), 'Value', 1, 'Tag', 'filter', ...
    'ValueChangedFcn', @(~, ~) apply_filter()), 2, 3);
prev_btn = at(uibutton(tb, 'push', 'Text', '< Prev', 'ButtonPushedFcn', @(~, ~) change_page(-1)), 2, 4);
page_lbl = at(uilabel(tb, 'Text', '', 'HorizontalAlignment', 'center', 'Tag', 'page'), 2, 5);
nextp_btn = at(uibutton(tb, 'push', 'Text', 'Next >', 'ButtonPushedFcn', @(~, ~) change_page(1)), 2, 6);

mainp = uigridlayout(g, [1 2]);
at(mainp, 2, 1);
mainp.ColumnWidth = {'1.15x', '1x'};
mainp.Padding = [0 0 0 0];
mainp.ColumnSpacing = 10;

gal = uigridlayout(mainp, [3 4]);
gal.Padding = [0 0 0 0];
gal.RowSpacing = 6;
gal.ColumnSpacing = 6;
% Each thumbnail sits in a panel whose border marks the selected one. Background
% colours are left alone, so the window follows MATLAB's light or dark theme.
cell_grid = gobjects(1, PAGE); cell_img = gobjects(1, PAGE); cell_cap = gobjects(1, PAGE);
for i = 1:PAGE
    cell_grid(i) = uipanel(gal, 'BorderType', 'none', 'BorderWidth', 3, 'HighlightColor', [0.2 0.55 0.85]);
    cell_grid(i).Layout.Row = ceil(i/4);
    cell_grid(i).Layout.Column = mod(i - 1, 4) + 1;
    inner = uigridlayout(cell_grid(i), [2 1]);
    inner.RowHeight = {'1x', 44};
    inner.Padding = [2 2 2 2];
    inner.RowSpacing = 2;
    cell_img(i) = uiimage(inner, 'ScaleMethod', 'fit', 'ImageClickedFcn', @(~, ~) select_cell(i));
    cell_cap(i) = uilabel(inner, 'Text', '', 'HorizontalAlignment', 'center', 'VerticalAlignment', 'top', 'FontSize', 10, 'WordWrap', 'on');
end

vw = uigridlayout(mainp, [3 2]);
vw.RowHeight = {44, '1x', '1x'};
vw.Padding = [0 0 0 0];
vw.RowSpacing = 6;
vw.ColumnSpacing = 6;
view_info = uilabel(vw, 'Text', 'Click an image on the left to see it, and its lower-resolution versions, larger.', ...
    'WordWrap', 'on', 'VerticalAlignment', 'top', 'Tag', 'view_info');
at(view_info, 1, [1 2]);
vcell_grid = gobjects(1, 4); vcell_img = gobjects(1, 4); vcell_cap = gobjects(1, 4);
for i = 1:4
    vcell_grid(i) = uigridlayout(vw, [2 1]);
    vcell_grid(i).Layout.Row = 1 + ceil(i/2);
    vcell_grid(i).Layout.Column = mod(i - 1, 2) + 1;
    vcell_grid(i).RowHeight = {'1x', 18};
    vcell_grid(i).Padding = [0 0 0 0];
    vcell_grid(i).RowSpacing = 2;
    vcell_img(i) = uiimage(vcell_grid(i), 'ScaleMethod', 'fit');
    vcell_cap(i) = uilabel(vcell_grid(i), 'Text', '', 'HorizontalAlignment', 'center', 'FontWeight', 'bold');
end

ex = uipanel(g, 'Title', 'Download');
at(ex, 3, 1);
eg = uigridlayout(ex, [4 5]);
eg.ColumnWidth = {110, 170, 170, 150, '1x'};
eg.RowHeight = {28, 28, 28, 30};
eg.Padding = [8 6 8 6];
eg.RowSpacing = 6;
row_label(eg, 1, 'Which views');
scope_drop = at(uidropdown(eg, 'Items', {'Every view in the list above', 'Only the selected view'}, 'ItemsData', {'list', 'selected'}, ...
    'Value', 'list', 'Tag', 'scope'), 1, [2 3]);
uilabel(eg, 'Text', 'Save as', 'HorizontalAlignment', 'right', 'Layout', matlab.ui.layout.GridLayoutOptions('Row', 1, 'Column', 4));
saveas_drop = at(uidropdown(eg, 'Items', {'A folder', 'One .zip file'}, 'ItemsData', {'folder', 'zip'}, 'Value', 'folder', 'Tag', 'saveas'), 1, 5);
row_label(eg, 2, 'Arrange as');
layout_drop = at(uidropdown(eg, 'Items', {'Training layout: HR and LR folders, matching file names', 'One folder per view, as they were made'}, ...
    'ItemsData', {'training', 'perview'}, 'Value', 'training', 'Tag', 'layout'), 2, [2 5]);
row_label(eg, 3, 'Include');
inc_hr = at(uicheckbox(eg, 'Text', 'HR images', 'Value', true, 'Tag', 'inc_hr'), 3, 2);
inc_lr = at(uicheckbox(eg, 'Text', 'Lower-resolution images', 'Value', true, 'Tag', 'inc_lr'), 3, 3);
inc_mat = at(uicheckbox(eg, 'Text', 'Complex images (.mat)', 'Value', false, 'Tag', 'inc_mat'), 3, 4);
inc_idx = at(uicheckbox(eg, 'Text', 'Index and settings', 'Value', true, 'Tag', 'inc_idx'), 3, 5);
dl_btn = at(uibutton(eg, 'push', 'Text', 'Download...', 'FontWeight', 'bold', 'Tag', 'download', 'ButtonPushedFcn', @(~, ~) do_download()), 4, 2);
opendest_btn = at(uibutton(eg, 'push', 'Text', 'Open the place', 'Enable', 'off', 'Tag', 'opendest', 'ButtonPushedFcn', @(~, ~) open_dest()), 4, 3);
at(uilabel(eg, 'Text', 'You choose where in the next step. Files with the same names are replaced.', 'FontAngle', 'italic', 'WordWrap', 'on'), 4, [4 5]);


% ---- start -----------------------------------------------------------------
fig.UserData = struct('collect', @collect, 'apply', @apply_cfg, 'goto', @goto_step, 'start', @do_start, ...
    'stop', @do_stop, 'next', @do_next, 'validate', @validate_step, 'step', @get_step, 'map_click', @map_click, 'picks', @get_picks, 'blender_capture', @capture_from_blender, 'blender_open', @open_blender, 'bl_picks', @get_bl_picks, ...
    'results_load', @load_dataset, 'results_filter', @apply_filter, 'results_select', @select_view, ...
    'export', @export_to, 'shown', @get_shown, 'history', @toggle_history, 'results_views', @get_res_views);
fig.CloseRequestFcn = @(~, ~) close_window();
% Anything that changes the number of views or the time refreshes the summary
for c = [comp_win, comp_inc, comp_side_r, {around_win, full_bearing, comp_cover, comp_n, comp_side}]
    c{1}.ValueChangedFcn = @(~, ~) update_summary();
end
update_custom();
update_radar();
mode_changed();
goto_step(1);


% =============================== navigation ===================================

    function g = step_grid(k, dims)
        g = uigridlayout(stack, dims);
        g.Layout.Row = 1;
        g.Layout.Column = 1;
        g.Visible = 'off';
        panels(k) = g;
    end

    function s = get_step()
        s = step;
    end

    function v = get_res_views()
        v = {res_views.view};
    end

    function s = get_shown()
        s = res_shown;   % a handle to this function reads the live value; @() res_shown would freeze it
    end

    function goto_step(k)
        if running || k < 1 || k > 6, return; end
        % You can always go back; going forward needs the steps before to be complete.
        for j = 1:k-1
            m = validate_step(j);
            if ~isempty(m)
                step = j; show_step(); say('error', m);
                return
            end
        end
        step = k;
        show_step();
        say('info', '');
    end

    function do_next()
        m = validate_step(step);
        if ~isempty(m)
            say('error', m);
            return
        end
        goto_step(step + 1);
    end

    function show_step()
        for j = 1:6
            panels(j).Visible = j == step;
            step_btn(j).FontWeight = 'normal';
        end
        step_btn(step).FontWeight = 'bold';
        title_lbl.Text = sprintf('Step %d of 6: %s', step, STEPS{step});
        sub_lbl.Text = SUBTITLE{step};
        back_btn.Enable = step > 1;
        next_btn.Visible = step < 6;
        if step == 3, show_view_settings(); update_summary(); end
        if step == 5, refresh_review(); end
        if step == 6, refresh_results(); end
    end

    function say(kind, text)
        dark = false;
        try dark = strcmp(char(fig.Theme.BaseColorStyle), 'dark'); catch, end
        switch kind
            case 'error', c = ternary(dark, [1 0.55 0.5], [0.72 0.1 0.1]);
            case 'ok',    c = ternary(dark, [0.5 0.9 0.55], [0.1 0.5 0.15]);
            otherwise,    c = ternary(dark, [0.85 0.85 0.85], [0.25 0.25 0.25]);
        end
        msg.FontColor = c;
        msg.Text = text;
    end

    function set_busy(busy)
        if busy
            ctrls = [];
            for j = 1:4, ctrls = [ctrls; findall(panels(j), '-property', 'Enable')]; end %#ok<AGROW>
            ctrls = ctrls(~arrayfun(@(c) isa(c, 'matlab.ui.container.GridLayout'), ctrls));
            was_enabled = arrayfun(@(c) strcmp(char(c.Enable), 'on'), ctrls);
            for c = ctrls(was_enabled)', c.Enable = 'off'; end
            frozen = ctrls(was_enabled);
        else
            for c = frozen', if isvalid(c), c.Enable = 'on'; end, end
            frozen = [];
        end
        for j = 1:6, step_btn(j).Enable = ~busy; end
        back_btn.Enable = ~busy && step > 1;
        next_btn.Enable = ~busy;
        save_btn.Enable = ~busy;
        load_btn.Enable = ~busy;
        start_btn.Enable = ~busy;
        stop_btn.Enable = busy;
        drawnow;
    end

% =============================== step 1 =======================================

    function browse_obj()
        [f, p] = uigetfile('*.obj', 'Select the .obj file', obj_field.Value);
        if ~isequal(f, 0)
            obj_field.Value = fullfile(p, f);
            say('info', '');
            check_model(false);
        end
    end

    function browse_out()
        d = uigetdir(out_field.Value, 'Folder for the images');
        if ~isequal(d, 0), out_field.Value = d; end
    end

    function update_custom()
        cust_obj.Enable = mat_drop.Value == MAT_CUSTOM;
        cust_gnd.Enable = gnd_drop.Value == size(GROUNDS, 1);
    end

    function check_model(force)
        % Reads the chosen file (once per file, unless forced) and shows what it is
        p = obj_field.Value;
        if exist(p, 'file') ~= 2
            model_info.Text = 'Choose an .obj file first.';
            return
        end
        if force, analysis = []; end
        check_btn.Enable = 'off';
        ok = ensure_model_size();
        check_btn.Enable = 'on';
        if ok, update_summary(); end
    end

    function model_choice_changed()
        % Up axis or units changed: applies the choice to what was already read
        units_custom.Enable = strcmp(units_drop.Value, 'custom');
        if ~isempty(analysis)
            resolve_model();
            update_summary();
            if current_mode() == 4 && step == 3, refresh_map(); end
        end
    end

    function u = units_choice()
        % The units in use as Resolve_Model wants them: 'auto', or metres per unit
        switch units_drop.Value
            case 'auto', u = 'auto';
            case 'custom', u = units_custom.Value;
            otherwise, u = str2double(units_drop.Value);
        end
    end

    function ok = ensure_model_size()
        % Reads the object once per file and works out what it is; then applies the choices of up axis and units
        ok = false;
        p = obj_field.Value;
        if exist(p, 'file') ~= 2, return; end
        d = dir(p);
        stamp = [d(1).bytes d(1).datenum];
        if isempty(analysis) || ~strcmp(analysis_file, p) || ~isequal(analysis_stamp, stamp)
            say('info', 'Reading the object ...');
            model_info.Text = {'Reading the file ...'};
            drawnow;
            try
                analysis = Analyze_OBJ(p, @read_progress);
                analysis_file = p;
                analysis_stamp = stamp;
            catch err
                analysis = []; resolved = []; model_size = []; model_pts = []; model_key = '';
                say('error', ['Could not read the object: ' err.message]);
                model_info.Text = {['Could not read the file: ' err.message]};
                return
            end
            say('info', '');
        end
        resolve_model();
        ok = true;
    end

    function read_progress(text)
        model_info.Text = {text};
        drawnow limitrate;
    end

    function resolve_model()
        % What the file is under the current choices, and the text that says so
        resolved = Resolve_Model(analysis, up_drop.Value, units_choice());
        model_size = resolved.size_m;
        model_pts = resolved.pts;
        model_key = sprintf('%s|%s|%s', analysis_file, up_drop.Value, units_drop.Value);
        if strcmp(units_drop.Value, 'custom'), model_key = sprintf('%s|%g', model_key, units_custom.Value); end
        lines = resolved.findings;
        for q = 1:numel(resolved.warnings), lines{end+1} = ['Note: ' resolved.warnings{q}]; end %#ok<AGROW>
        if resolved.auto_up && ~isnan(analysis.facing(2)) && resolved.size_m(2) > max(resolved.size_m([1 3])) && resolved.size_m(2) > 100
            lines{end+1} = 'Note: it is taller than it is wide. If it is lying on its side, change "Which way is up".';
        end
        if isfield(analysis.info, 'material_names') && ~isempty(analysis.info.material_names)
            names = analysis.info.material_names;
            known = names(cellfun(@(n) ~isempty(Radar_Materials(regexprep(n, '\.\d{3}$', ''))), names));
            lines{end+1} = sprintf('Materials named in the file: %s.', strjoin(names(1:min(end, 12)), ', '));
            if ~isempty(known)
                lines{end+1} = sprintf(['%d of them are radar materials (%s). Choose "By material name in the file" ' ...
                    'under Object surface to give each its own response.'], numel(known), strjoin(known(1:min(end, 8)), ', '));
            end
        end
        model_info.Text = lines;
    end

% =============================== step 2 =======================================

    function mode_changed()
        k = current_mode();
        texts = { ...
            ['The recommended set. Images of the whole object from several sides and angles, plus many partial ' ...
             'views: windows on parts of the object, from random directions, angles and places, with some looking ' ...
             'from a low side angle so walls show. How many partial views you get depends on the size of the ' ...
             'object: a bigger object gets more.'], ...
            ['The whole object from one direction. Gives one HR image and its lower-resolution versions. ' ...
             'A good first test, and the quickest way to see what a view looks like.'], ...
            ['A systematic set: several directions round the object, optionally at several incidence angles, ' ...
             'and optionally as windows tiled over the object. Even and repeatable. For example 8 directions ' ...
             'at 3 angles is 24 views.'], ...
            ['You choose every view yourself, by eye. A top view of the object is shown: click where you want the ' ...
             'window, choose which side the radar looks from, the angle and how much to cover, and see the ground ' ...
             'the picture will cover before you add it. No other program is needed.'], ...
            ['Choose the views in Blender, by eye, with cameras. Click Open Blender: it opens with your object loaded and ' ...
             'a panel for the SAR views. Place a camera, click Send views in Blender, then click Capture here to take those ' ...
             'views. Needs Blender installed; the other ways of choosing views do not.']};
        mode_text.Text = texts{k};
        for j = 1:5, vp(j).Visible = j == k; end
    end

    function k = current_mode()
        k = find(arrayfun(@(b) b == mode_group.SelectedObject, mode_btn), 1);
        if isempty(k), k = 1; end
    end

% =============================== step 3 =======================================

    function show_view_settings()
        k = current_mode();
        for j = 1:5, vp(j).Visible = j == k; end
        if k == 4, refresh_map(); end
    end

    function refresh_map()
        % Draws the object from above and, over it, the views picked so far
        cla(map_ax);
        if ~ensure_model_size() || isempty(model_pts)
            text(map_ax, 0.5, 0.5, 'Choose the object in step 1 to see it here.', 'Units', 'normalized', 'HorizontalAlignment', 'center');
            return
        end
        scatter(map_ax, model_pts(:, 1), -model_pts(:, 3), 4, model_pts(:, 2), 'filled', 'PickableParts', 'none');
        hold(map_ax, 'on');
        colormap(map_ax, 'parula');
        axis(map_ax, 'equal');
        pad = 0.2*max(model_size([1 3]));
        xlim(map_ax, [min(model_pts(:, 1)) - pad, max(model_pts(:, 1)) + pad]);
        ylim(map_ax, [min(-model_pts(:, 3)) - pad, max(-model_pts(:, 3)) + pad]);
        map_ax.ButtonDownFcn = @(~, ev) map_click(ev);
        if ~strcmp(map_key, model_key)
            % a new object: start the draft in the middle of it, about half its size
            map_key = model_key;
            pick_cx.Value = (min(model_pts(:, 1)) + max(model_pts(:, 1)))/2;
            pick_cz.Value = (min(model_pts(:, 3)) + max(model_pts(:, 3)))/2;
            w = max(5, min(300, round(0.5*max(model_size([1 3])))));
            pick_w.Value = w;
            pick_h.Value = max(5, round(0.75*w));
        end
        draw_overlay();
    end

    function draw_overlay()
        % The picked views in orange, and the draft in blue with the radar's place
        if isempty(model_pts), return; end
        delete(findobj(map_ax, 'Tag', 'overlay'));
        hold(map_ax, 'on');
        orange = [0.95 0.6 0.1]; blue = [0.2 0.55 0.85];
        for q = 1:size(picks, 1)
            r = picks(q, :);
            P = footprint(r(1), r(2), r(3), r(4), r(5), r(6));
            plot(map_ax, P(:, 1), P(:, 2), '-', 'Color', orange, 'LineWidth', 1.5, 'Tag', 'overlay', 'PickableParts', 'none');
            text(map_ax, r(3), -r(4), sprintf('%d', q), 'Color', orange, 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center', 'Tag', 'overlay', 'PickableParts', 'none');
        end
        b = pick_dir.Value; i = pick_inc.Value; cx = pick_cx.Value; cz = pick_cz.Value; w = pick_w.Value; h = pick_h.Value;
        P = footprint(b, i, cx, cz, w, h);
        plot(map_ax, P(:, 1), P(:, 2), '-', 'Color', blue, 'LineWidth', 2.5, 'Tag', 'overlay', 'PickableParts', 'none');
        d = h/cosd(i);                                   % the frame's height, laid out along the ground
        k = d/2 + 0.12*max(w, d);
        rx = cx + k*sind(b); ry = -cz + k*cosd(b);       % the radar sits on the side the direction names
        plot(map_ax, [rx cx], [ry -cz], '-', 'Color', blue, 'LineWidth', 1.5, 'Tag', 'overlay', 'PickableParts', 'none');
        plot(map_ax, rx, ry, '^', 'MarkerSize', 11, 'MarkerFaceColor', blue, 'MarkerEdgeColor', blue, 'Tag', 'overlay', 'PickableParts', 'none');
        if strcmp(res_drop.Value, 'manual')
            pix = 299792458/(2*bw_field.Value*1e6)/2;
            res_text = sprintf('%.2f m resolution', 2*pix);
        else
            pix = 0.15;
            res_text = '0.30 m resolution (the automatic resolution depends on the object)';
        end
        pick_info.Text = sprintf('This view covers %.0f m across and %.0f m along the ground, about %.0f x %.0f pixels at %s.', ...
            w, d, w/pix, max(d, h)/pix, res_text);
    end

    function map_click(ev)
        if isempty(model_pts), return; end
        p = ev.IntersectionPoint;
        x = p(1); z = -p(2);                              % the map shows north up, and north is -z
        if strcmp(pick_click.Value, 'center')
            pick_cx.Value = x;
            pick_cz.Value = z;
        else
            dx = x - pick_cx.Value; dz = z - pick_cz.Value;
            if hypot(dx, dz) > 0
                pick_dir.Value = mod(atan2(dx, -dz)*180/pi, 360);   % the radar is the way the click points
            end
        end
        draw_overlay();
    end

    function add_pick()
        picks(end+1, :) = [pick_dir.Value, pick_inc.Value, pick_cx.Value, pick_cz.Value, pick_w.Value, pick_h.Value];
        update_pick_table();
        draw_overlay();
        update_summary();
        say('ok', sprintf('Added view %d. Click the map for the next one, or go on with Next.', size(picks, 1)));
    end

    function remove_pick()
        if pick_sel >= 1 && pick_sel <= size(picks, 1)
            picks(pick_sel, :) = [];
            pick_sel = 0;
            update_pick_table();
            draw_overlay();
            update_summary();
        else
            say('error', 'Click a row of the list first, then Remove selected.');
        end
    end

    function clear_picks()
        picks = zeros(0, 6);
        pick_sel = 0;
        update_pick_table();
        draw_overlay();
        update_summary();
    end

    function pick_selected(ev)
        if ~isempty(ev.Indices), pick_sel = ev.Indices(1); end
    end

    function update_pick_table()
        d = cell(size(picks, 1), 6);
        for q = 1:size(picks, 1)
            r = picks(q, :);
            d(q, :) = {sprintf('Pick%d', q), sprintf('%.0f', r(1)), sprintf('%.0f', r(2)), sprintf('%.1f', r(3)), ...
                sprintf('%.1f', r(4)), sprintf('%.0f x %.0f m', r(5), r(6))};
        end
        pick_tbl.Data = d;
    end

    function p = get_picks()
        p = picks;
    end

    function p = get_bl_picks()
        p = bl_picks;
    end

    function browse_blender()
        [f, p] = uigetfile('blender*.exe', 'Find blender.exe', blender_field.Value);
        if ~isequal(f, 0), blender_field.Value = fullfile(p, f); end
    end

    function d = blender_dir()
        % Where Blender and this window hand things to each other
        d = fullfile(strtrim(out_field.Value), 'blender_handoff');
    end

    function open_earth_capture()
        % Earth Capture (earth_capture/ next to sar_pipeline/) builds real-world
        % scenes from open map data and runs them through this same pipeline
        earth = fullfile(fileparts(fileparts(fileparts(mfilename('fullpath')))), 'earth_capture');
        pyw = fullfile(earth, '.venv', 'Scripts', 'pythonw.exe');
        if ~isfile(pyw)
            say('error', sprintf(['Earth Capture is not installed yet. In a terminal, run:  ' ...
                'powershell -ExecutionPolicy Bypass -File "%s"'], fullfile(earth, 'install.ps1')));
            return
        end
        [status, out] = system(sprintf('cd /d "%s" && start "" "%s" -m terrabound_earth', earth, pyw));
        if status ~= 0
            say('error', ['Could not start Earth Capture: ' strtrim(out)]);
        else
            say('info', 'Earth Capture is opening in its own window.');
        end
    end

    function open_blender()
        m = validate_step(1);
        if ~isempty(m), say('error', m); return; end
        exe = strtrim(blender_field.Value);
        if isempty(exe) || ~isfile(exe)
            exe = Find_Blender();
            if isempty(exe)
                say('error', 'Blender was not found. Install it, or click Browse... and choose blender.exe.');
                return
            end
            blender_field.Value = exe;
        end
        try
            if ~ensure_model_size(), return; end
            Launch_Blender(exe, obj_field.Value, resolved.up, blender_dir(), ...
                struct('bandwidth_mhz', bw_field.Value, 'factors', unique(parse_list(fac_field.Value)), 'scale', resolved.scale));
            say('info', ['Blender is opening with your object. Place a SAR camera, click "Send views to the SAR window" ' ...
                '(SAR tab, press N), then come back here and click Capture.']);
        catch err
            say('error', ['Could not open Blender: ' err.message]);
        end
    end

    function ok = capture_from_blender(run_now)
        % Takes the views from Blender: where the boxes are now (sar_live.json), or from "Send views to the
        % SAR window", whichever is newer. A button, not a watcher: nothing runs in the background.
        if nargin < 1, run_now = false; end
        ok = false;
        js = fullfile(blender_dir(), 'sar_views.json');
        blend = fullfile(blender_dir(), 'blender_scene.blend');
        live = fullfile(blender_dir(), 'sar_live.json');
        source = 'the views Blender sent';
        try
            % Three places hold the views: sar_live.json (kept up to date by Blender whenever the scene changes),
            % what "Send views" wrote, and the scene Blender saved. Take whichever is newest.
            t_sent = 0; if isfile(js), t_sent = dir_time(js); end
            t_live = 0; if isfile(live), t_live = dir_time(live); end
            t_blend = 0; if isfile(blend), t_blend = dir_time(blend); end
            slack = 10/86400;                                   % a save and the live file land within seconds of each other
            if t_live > 0 && t_live >= max(t_sent, t_blend) - slack
                js = live;
                source = sprintf('where the box is in Blender now (as of %s)', datestr(t_live, 'HH:MM:SS'));
            elseif t_blend > t_sent
                source = sprintf('the scene Blender saved at %s', datestr(t_blend, 'HH:MM:SS'));
                exe = strtrim(blender_field.Value);
                if isempty(exe) || ~isfile(exe), exe = Find_Blender(); end
                say('info', 'Reading the boxes from the file Blender saved ...');
                drawnow;
                Export_Blender_Views(exe, blender_dir());
            end
            [pk, nm, ob, when] = Read_Blender_Views(js);
        catch err
            say('error', [err.message ' Open Blender from this window, place the yellow box, and click Capture again.']);
            return
        end
        if ~isfile(ob)
            say('error', ['The model Blender exported is missing: ' ob]);
            return
        end
        bl_picks = pk; bl_names = nm; blender_obj = ob;
        update_bl_table();
        bl_info.Text = sprintf('%d view%s captured, read from %s.', size(pk, 1), plural(size(pk, 1)), source);
        update_summary();
        % A window has to be small enough for the radar's resolution. If not, say so here, in plain words,
        % instead of leaving it to fail later.
        if strcmp(res_drop.Value, 'manual')
            pix = 299792458/(2*bw_field.Value*1e6)/2;
            for q = 1:size(pk, 1)
                w = pk(q, 5); h = pk(q, 6);
                px = max(w, max(h*tan(pk(q, 2)*pi/180), h))/pix;
                if px > 2000
                    say('error', sprintf(['%s: its window is %.0f m wide, which would be an image about %.0f pixels across at %.2f m ' ...
                        'resolution (the limit is 2000). In Blender make the yellow box smaller (about %.0f m across or less), ' ...
                        'and click Capture again.'], nm{q}, w, px, 2*pix, 2000*pix*min(1, w/max(w, h*max(tan(pk(q, 2)*pi/180), 1)))));
                    return
                end
            end
        end
        ok = true;
        say('ok', sprintf('Captured %d view%s from Blender.', size(pk, 1), plural(size(pk, 1))));
        if run_now
            goto_step(5);
            do_start();
        end
    end

    function capture_button()
        capture_from_blender(bl_now.Value);   % the tick box is read when the button is pressed
    end

    function t = dir_time(path)
        d = dir(path);
        t = d(1).datenum;
    end

    function update_bl_table()
        d = cell(size(bl_picks, 1), 6);
        for q = 1:size(bl_picks, 1)
            r = bl_picks(q, :);
            d(q, :) = {bl_names{q}, sprintf('%.0f', r(1)), sprintf('%.0f', r(2)), sprintf('%.1f', r(3)), ...
                sprintf('%.1f', r(4)), sprintf('%.0f x %.0f m', r(5), r(6))};
        end
        bl_tbl.Data = d;
    end


    function n = count_views()
        switch current_mode()
            case 1, [nw, np] = complete_counts(); n = nw + max(0, np);
            case 2, n = 1;
            case 3, n = around_n.Value*max(1, numel(unique(parse_list(around_inc.Value))))*around_grid.Value^2;
            case 4, n = size(picks, 1);
            otherwise, n = size(bl_picks, 1);
        end
    end

    function a = structure_area()
        % Ground in m^2 that has structure on it, from the sample of the object; the box's area if there is none
        a = model_size(1)*model_size(3);
        if isempty(resolved) || size(resolved.structure, 1) < 50, return; end
        c = max(2, 0.4*comp_win{1}.Value);
        P = resolved.structure;
        o = Occupied_Area([P(:, 1) - c/2, P(:, 2) - c/2, P(:, 1) + c/2, P(:, 2) + c/2, ones(size(P, 1), 1)], c);
        if o.usable, a = o.area_m2; end
    end

    function [nw, np] = complete_counts()
        % Whole-scene views, and partial views (NaN until the object has been read)
        nw = comp_whole_n.Value*numel(unique(parse_list(comp_whole_inc.Value)));
        if strcmp(res_drop.Value, 'manual') && whole_scene_px() > 2000, nw = 0; end   % too big at this resolution: left out (see the note)
        if strcmp(comp_auto.Value, 'fixed')
            np = comp_n.Value;
        elseif ensure_model_size()
            np = Views_For_Coverage(structure_area(), [comp_win{1}.Value comp_win{2}.Value], comp_cover.Value);
        else
            np = NaN;
        end
    end

    function update_comp()
        auto = strcmp(comp_auto.Value, 'auto');
        comp_cover.Enable = auto;
        comp_n.Enable = ~auto;
        update_summary();
    end

    function s = summary_text()
        nf = numel(parse_list(fac_field.Value));
        if current_mode() == 1
            [nw, np] = complete_counts();
            if isnan(np)
                s = sprintf(['%d whole-scene view%s, plus partial views: how many depends on the size of the ' ...
                    'object, so choose the object in step 1'], nw, plural(nw));
                return
            end
            n = nw + np;
            s = sprintf('%d views (%d whole scene, %d partial): %d HR images and %d lower-resolution images', ...
                n, nw, np, n, n*nf);
            if strcmp(comp_auto.Value, 'auto') && ~isempty(model_size)
                s = sprintf('%s. The object is %s x %s, and the parts with structure on them are about %s.', s, ...
                    length_text(model_size(1)), length_text(model_size(3)), area_text(structure_area()));
            end
        else
            n = count_views();
            s = sprintf('%d view%s: %d HR image%s and %d lower-resolution image%s', ...
                n, plural(n), n, plural(n), n*nf, plural(n*nf));
        end
    end

    function px = whole_scene_px()
        % About how many pixels across the whole scene would be at the chosen resolution (NaN if the object is not read yet)
        px = NaN;
        if isempty(model_size), return; end
        if strcmp(res_drop.Value, 'manual')
            px = 1.15*hypot(model_size(1), model_size(3))/(299792458/(2*bw_field.Value*1e6)/2);
        else
            px = px_field.Value;
        end
    end

    function t = view_seconds(w)
        % Seconds for one view of a window w m wide. Street_01: about 10 s of set-up and a radar
        % part that grows with the image's area (65 s for its whole 125 m scene at 500 MHz). Tall
        % structures stretch the image along the range (layover), which makes it longer.
        if isempty(model_size), t = 10 + 55*0.16; return; end
        if strcmp(res_drop.Value, 'manual')
            pix = 299792458/(2*bw_field.Value*1e6)/2;
        else
            pix = 1.15*hypot(model_size(1), model_size(3))/max(px_field.Value, 1);
        end
        k = (w/125)*(0.15/pix);
        lift = 1 + min(2, 0.5*model_size(2)/max(w, 1));
        t = 10 + 55*k^2*lift;
    end

    function t = whole_scene_note()
        % A warning if whole-scene images would be too big at the fixed resolution, for the modes that make them
        t = '';
        if isempty(model_size) || ~strcmp(res_drop.Value, 'manual'), return; end
        m = current_mode();
        makes_whole = (m == 1 && comp_whole_n.Value > 0) || m == 2 || (m == 3 && around_win.Value >= 100 && around_grid.Value == 1);
        if ~makes_whole, return; end
        px = whole_scene_px();
        if px > 2000
            t = sprintf([' Note: at %g MHz the whole scene would be about %s pixels across, more than the 2,000 this can make, ' ...
                'so the whole-scene views are left out and only windows are made. For the whole scene, choose Automatic resolution in step 4.'], ...
                bw_field.Value, regexprep(sprintf('%d', round(px)), '(\d)(?=(\d{3})+$)', '$1,'));
        end
    end

    function update_summary()
        views_summary.Text = [summary_text() whole_scene_note()];
        views_time.Text = time_estimate(count_views());
    end

    function s = time_estimate(n)
        % Rough, from runs on Street_01: about 10 s for a small window and
        % a minute for the whole scene, most of it the radar processing
        switch current_mode()
            case 1
                [nw, np] = complete_counts();
                if isnan(np), np = 0; end
                w1 = comp_win{1}.Value; w2 = comp_win{2}.Value;
                if whole_scene_px() > 2000 && strcmp(res_drop.Value, 'manual'), nw = 0; end   % those are left out
                t = nw*65 + np*mean([view_seconds(w1), view_seconds((w1 + w2)/2), view_seconds(w2)]);
            case 2, t = 65;
            case 3, t = n*(10 + 55*(around_win.Value/100)^2);
            case 4, t = size(picks, 1)*(10 + 55*0.25);
            otherwise, t = size(bl_picks, 1)*(10 + 55*0.25);
        end
        if t < 90, s = sprintf('Roughly %.0f seconds in all.', t);
        elseif t < 5400, s = sprintf('Roughly %.0f minutes in all.', t/60);
        else, s = sprintf('Roughly %.1f hours in all.', t/3600);
        end
        s = [s ' A guide only: it depends on the object and the computer. Stopping is safe, and starting again carries on.'];
    end

% =============================== step 4 =======================================

    function update_radar()
        manual = strcmp(res_drop.Value, 'manual');
        px_field.Enable = ~manual;
        bw_field.Enable = manual;
        if manual
            bw_hint.Text = sprintf('= %.2f m resolution.', 299792458/(2*bw_field.Value*1e6));
        else
            bw_hint.Text = 'Set from the image size above.';
        end
        f = parse_list(fac_field.Value);
        if isempty(f)
            fac_hint.Text = 'EMPTY: only HR images will be made, with no lower-resolution ones. Type 2 4 8 for the usual three.';
        else
            names = arrayfun(@(x) sprintf('%gx', x), f, 'UniformOutput', false);
            fac_hint.Text = ['Coarser than HR by ' strjoin(names, ', ') '. Leave empty for HR only.'];
        end
        update_summary();
    end

% =============================== settings =====================================

    function cfg = collect()
        cfg.obj = obj_field.Value;
        cfg.out = strtrim(out_field.Value);
        cfg.up = up_drop.Value;
        cfg.units = units_drop.Value;
        cfg.units_custom = units_custom.Value;
        cfg.material = mat_drop.Value;
        cfg.ground = gnd_drop.Value;
        cfg.custom_obj = strtrim(cust_obj.Value);
        cfg.custom_ground = strtrim(cust_gnd.Value);
        cfg.mode = current_mode();
        cfg.full_bearing = full_bearing.Value;
        cfg.full_inc = full_inc.Value;
        cfg.around_n = around_n.Value;
        cfg.around_first = around_first.Value;
        cfg.around_inc = around_inc.Value;
        cfg.around_win = around_win.Value;
        cfg.around_grid = around_grid.Value;
        cfg.comp_whole_n = comp_whole_n.Value;
        cfg.comp_whole_inc = comp_whole_inc.Value;
        cfg.comp_auto = comp_auto.Value;
        cfg.comp_cover = comp_cover.Value;
        cfg.comp_n = comp_n.Value;
        cfg.comp_win = [comp_win{1}.Value comp_win{2}.Value];
        cfg.comp_inc = [comp_inc{1}.Value comp_inc{2}.Value];
        cfg.comp_side = comp_side.Value;
        cfg.comp_side_r = [comp_side_r{1}.Value comp_side_r{2}.Value];
        cfg.picks = picks;
        cfg.blender_exe = blender_field.Value;
        cfg.blender_obj = blender_obj;
        cfg.bl_picks = bl_picks;
        cfg.bl_names = bl_names;
        cfg.res = res_drop.Value;
        cfg.px = px_field.Value;
        cfg.bw = bw_field.Value;
        cfg.factors = fac_field.Value;
        cfg.seed = seed_field.Value;
        cfg.bounce = bounce_drop.Value;
        cfg.rays = rays_field.Value;
        cfg.topdown = top_box.Value;
        cfg.complex = cplx_box.Value;
        cfg.keep = keep_box.Value;
        cfg.redo = redo_box.Value;
    end

    function apply_cfg(cfg)
        set_if = @(c, name) assign(c, cfg, name);
        obj_field.Value = pick(cfg, 'obj', obj_field.Value);
        out_field.Value = pick(cfg, 'out', out_field.Value);
        set_if(up_drop, 'up'); set_if(units_drop, 'units'); set_if(units_custom, 'units_custom');
        units_custom.Enable = strcmp(units_drop.Value, 'custom');
        set_if(mat_drop, 'material'); set_if(gnd_drop, 'ground');
        set_if(cust_obj, 'custom_obj'); cust_gnd.Value = pick(cfg, 'custom_ground', cust_gnd.Value);
        if isfield(cfg, 'mode') && cfg.mode >= 1 && cfg.mode <= 5, mode_group.SelectedObject = mode_btn(cfg.mode); end
        if isfield(cfg, 'picks'), picks = to_picks(cfg.picks); pick_sel = 0; update_pick_table(); end
        if isfield(cfg, 'bl_picks')
            bl_picks = to_picks(cfg.bl_picks);
            bl_names = cellstr(cfg.bl_names(:))';
            if numel(bl_names) ~= size(bl_picks, 1), bl_names = arrayfun(@(q) sprintf('SAR%d', q), 1:size(bl_picks, 1), 'UniformOutput', false); end
            bl_names = bl_names(:);
        end
        blender_obj = pick(cfg, 'blender_obj', blender_obj);
        if isfield(cfg, 'blender_exe') && ~isempty(cfg.blender_exe), blender_field.Value = cfg.blender_exe; end
        update_bl_table();
        set_if(full_bearing, 'full_bearing'); set_if(full_inc, 'full_inc');
        set_if(around_n, 'around_n'); set_if(around_first, 'around_first'); set_if(around_inc, 'around_inc');
        set_if(around_win, 'around_win'); set_if(around_grid, 'around_grid');
        set_if(comp_whole_n, 'comp_whole_n'); set_if(comp_whole_inc, 'comp_whole_inc'); set_if(comp_auto, 'comp_auto');
        set_if(comp_cover, 'comp_cover'); set_if(comp_n, 'comp_n'); set_if(comp_side, 'comp_side');
        pairs = {comp_win, 'comp_win'; comp_inc, 'comp_inc'; comp_side_r, 'comp_side_r'};
        for q = 1:size(pairs, 1)
            if isfield(cfg, pairs{q, 2}) && numel(cfg.(pairs{q, 2})) == 2
                pairs{q, 1}{1}.Value = cfg.(pairs{q, 2})(1);
                pairs{q, 1}{2}.Value = cfg.(pairs{q, 2})(2);
            end
        end
        set_if(res_drop, 'res'); set_if(px_field, 'px'); set_if(bw_field, 'bw');
        set_if(fac_field, 'factors'); set_if(seed_field, 'seed'); set_if(bounce_drop, 'bounce');
        set_if(rays_field, 'rays'); set_if(top_box, 'topdown'); set_if(cplx_box, 'complex');
        set_if(keep_box, 'keep'); set_if(redo_box, 'redo');
        update_custom(); update_radar(); update_comp(); mode_changed(); update_summary();
    end

    function do_save()
        [f, p] = uiputfile('*.json', 'Save settings', 'sar_dataset_settings.json');
        if isequal(f, 0), return; end
        write_text(fullfile(p, f), jsonencode(collect(), 'PrettyPrint', true));
        say('ok', ['Settings saved to ' fullfile(p, f)]);
    end

    function do_load()
        [f, p] = uigetfile('*.json', 'Load settings');
        if isequal(f, 0), return; end
        try
            apply_cfg(jsondecode(fileread(fullfile(p, f))));
            say('ok', ['Settings loaded from ' fullfile(p, f)]);
        catch err
            say('error', ['Could not load those settings: ' err.message]);
        end
    end

% =============================== step 6: results ==============================

    function refresh_results()
        % Show the dataset this session made, or the one the settings point at
        % Candidates: the one already shown, the one the settings point at, and the ones made from Blender
        % (by this window, or by Blender's own Capture button). The newest wins.
        [~, name] = fileparts(obj_field.Value);
        out = strtrim(out_field.Value);
        cands = {res_root, fullfile(out, regexprep(name, '[^A-Za-z0-9_-]+', '_')), fullfile(out, 'blender_scene'), ...
            fullfile(out, 'blender_handoff', 'blender_scene')};
        best = ''; best_t = 0;
        for q = 1:numel(cands)
            if ~isempty(cands{q}) && exist(fullfile(cands{q}, 'views'), 'dir') == 7
                dd = dir(fullfile(cands{q}, 'views', '*', 'view_info.mat'));
                if ~isempty(dd) && max([dd.datenum]) > best_t, best = cands{q}; best_t = max([dd.datenum]); end
            end
        end
        if ~isempty(best), res_root = best; end
        if isempty(res_root)
            res_all = []; res_views = []; res_shown = []; res_loaded = '';
            hist_btn.Enable = 'off'; hist_btn.Text = 'History (none)';
            res_path.Text = 'No dataset yet. Make one in step 5, or open an earlier one.';
            show_page();
            return
        end
        load_dataset(res_root);
    end

    function load_dataset(folder)
        % Reads the folder. It opens on the latest render only, and the older views are behind History, so
        % that a folder that has grown over many runs does not show old and new images mixed together.
        same = strcmp(folder, res_loaded);
        res_root = folder;
        res_loaded = folder;
        res_all = read_views(folder);
        if ~same, res_scope = 'run'; end
        res_sel = 0;
        apply_scope();
    end

    function ids = latest_ids()
        % The views of the latest render: from this window's last run, or from the note the run leaves in the folder
        if strcmp(last_run.root, res_root)
            ids = last_run.ids;
        else
            ids = read_last_run(res_root);
        end
        if ~isempty(res_all), ids = ids(ismember(ids, {res_all.view})); end
        if isempty(ids) && ~isempty(res_all), ids = newest_group(res_all); end   % a folder from before runs were recorded
    end

    function apply_scope()
        ids = latest_ids();
        n_all = numel(res_all);
        if isempty(ids) || numel(ids) == n_all
            % a dataset from before runs were recorded, or one run made everything: nothing older to hide
            res_scope = 'run';
            res_views = res_all;
            if isempty(ids), res_views = sort_newest(res_all); end
            older = 0;
        elseif strcmp(res_scope, 'run')
            [~, at_i] = ismember(ids, {res_all.view});
            res_views = res_all(at_i);
            older = n_all - numel(ids);
        else
            res_views = sort_newest(res_all);
            older = n_all - numel(ids);
        end
        if older > 0
            hist_btn.Enable = 'on';
            hist_btn.Text = ternary(strcmp(res_scope, 'run'), sprintf('History (%d older)', older), 'Latest render only');
        else
            hist_btn.Enable = 'off';
            hist_btn.Text = 'History (none)';
        end
        n = numel(res_views);
        if strcmp(res_scope, 'run') && older > 0
            res_path.Text = sprintf('Latest render: %d view%s in %s. History has %d older.', n, plural(n), res_root, older);
        elseif strcmp(res_scope, 'all')
            res_path.Text = sprintf('History: all %d views in %s, newest first.', n, res_root);
        else
            res_path.Text = sprintf('%s  (%d view%s)', res_root, n, plural(n));
        end
        res_path.Tooltip = res_root;
        res_sel = 0;
        apply_filter();
    end

    function toggle_history()
        if isempty(res_all), return; end
        res_scope = ternary(strcmp(res_scope, 'run'), 'all', 'run');
        apply_scope();
    end

    function browse_dataset()
        d = uigetdir(pwd, 'Choose a dataset folder (the one that contains "views")');
        if isequal(d, 0), return; end
        if exist(fullfile(d, 'views'), 'dir') ~= 7
            say('error', 'That folder has no "views" folder inside. Choose the folder named after the object.');
            return
        end
        load_dataset(d);
        say('info', '');
    end

    function apply_filter()
        n = numel(res_views);
        keep = false(1, n);
        for i = 1:n
            v = res_views(i);
            done = strcmp(v.status, 'done');
            switch filter_drop.Value
                case 1, keep(i) = done;
                case 2, keep(i) = done && v.window >= 1;
                case 3, keep(i) = done && v.window < 1;
                case 4, keep(i) = done && v.incidence_deg >= 60;
                case 5, keep(i) = done && v.incidence_deg < 60;
                otherwise, keep(i) = ~done;
            end
        end
        res_shown = find(keep);
        res_page = 1;
        if ~ismember(res_sel, res_shown), res_sel = 0; end
        show_page();
    end

    function change_page(d)
        pages = max(1, ceil(numel(res_shown)/PAGE));
        res_page = max(1, min(pages, res_page + d));
        show_page();
    end

    function show_page()
        n = numel(res_shown);
        pages = max(1, ceil(n/PAGE));
        res_page = min(res_page, pages);
        for i = 1:PAGE
            j = (res_page - 1)*PAGE + i;
            if j <= n
                v = res_views(res_shown(j));
                f = fullfile(res_root, 'views', v.view, 'HR.png');
                if exist(f, 'file') == 2, cell_img(i).ImageSource = f; else, cell_img(i).ImageSource = ''; end
                tok = strsplit(v.view, '_');
                cap = {strjoin(tok(1:min(2, numel(tok))), ' '), sprintf('az %g   inc %g', v.bearing_deg, v.incidence_deg)};
                if strcmp(res_scope, 'all') && ~isnan(v.made), cap{3} = datestr(v.made, 'dd mmm HH:MM'); end   % history: when it was made
                cell_cap(i).Text = cap;
                cell_grid(i).Visible = 'on';
            else
                cell_grid(i).Visible = 'off';
            end
        end
        page_lbl.Text = sprintf('Page %d of %d', res_page, pages);
        prev_btn.Enable = res_page > 1;
        nextp_btn.Enable = res_page < pages;
        dl_btn.Enable = n > 0;
        if n > 0 && res_sel == 0, res_sel = res_shown(1); end
        highlight();
        show_viewer();
    end

    function highlight()
        for i = 1:PAGE
            j = (res_page - 1)*PAGE + i;
            if j <= numel(res_shown) && res_shown(j) == res_sel
                cell_grid(i).BorderType = 'line';
            else
                cell_grid(i).BorderType = 'none';
            end
        end
    end

    function select_cell(i)
        j = (res_page - 1)*PAGE + i;
        if j <= numel(res_shown), select_view(res_shown(j)); end
    end

    function select_view(k)
        res_sel = k;
        highlight();
        show_viewer();
    end

    function show_viewer()
        if res_sel == 0 || res_sel > numel(res_views)
            for i = 1:4, vcell_grid(i).Visible = 'off'; end
            view_info.Text = ternary(isempty(res_views), 'Nothing to show yet.', 'No view matches this filter.');
            return
        end
        v = res_views(res_sel);
        src = fullfile(res_root, 'views', v.view);
        lr = dir(fullfile(src, 'LR_*.png'));
        files = [{fullfile(src, 'HR.png')}, arrayfun(@(d) fullfile(d.folder, d.name), lr, 'UniformOutput', false)'];
        names = [{'HR'}, arrayfun(@(d) strrep(d.name(1:end-4), '_', ' '), lr, 'UniformOutput', false)'];
        view_info.Text = sprintf('%s: direction %g deg, incidence %g deg, window %.0f%% (%s m), %d x %d px, made in %.0f s', ...
            v.view, v.bearing_deg, v.incidence_deg, 100*v.window, v.window_m, v.image_px, v.image_py, v.seconds);
        for i = 1:4
            if i <= numel(files) && exist(files{i}, 'file') == 2
                vcell_img(i).ImageSource = files{i};
                vcell_cap(i).Text = names{i};
                vcell_grid(i).Visible = 'on';
            else
                vcell_grid(i).Visible = 'off';
            end
        end
    end

    function vs = export_views()
        % The views a download would contain
        if strcmp(scope_drop.Value, 'selected')
            vs = res_views(res_sel(res_sel > 0));
        else
            vs = res_views(res_shown);
        end
    end

    function do_download()
        vs = export_views();
        if isempty(vs), say('error', 'There is nothing to download: no view is shown or selected.'); return; end
        if ~inc_hr.Value && ~inc_lr.Value && ~inc_mat.Value
            say('error', 'Tick at least one of HR images, lower-resolution images or complex images.'); return
        end
        [~, obj] = fileparts(res_root);
        if strcmp(saveas_drop.Value, 'zip')
            [f, p] = uiputfile('*.zip', 'Save the images as', [obj '_images.zip']);
            if isequal(f, 0), return; end
            export_to(fullfile(p, f), true);
        else
            start = ternary(isempty(last_dest) || exist(last_dest, 'dir') ~= 7, pwd, last_dest);
            d = uigetdir(start, 'Choose the folder to save the images in');
            if isequal(d, 0), return; end
            export_to(d, false);
        end
    end

    function n_files = export_to(dest, as_zip)
        % Copies the chosen views to dest, a folder, or a .zip file if as_zip
        n_files = 0;
        vs = export_views();
        if isempty(vs), say('error', 'There is nothing to download.'); return; end
        stage = dest;
        if as_zip, stage = tempname; end
        try
            n_files = copy_out(vs, stage);
            if as_zip
                zip(dest, '*', stage);
                rmdir(stage, 's');
            end
            last_dest = ternary(as_zip, fileparts(dest), dest);
            opendest_btn.Enable = 'on';
            say('ok', sprintf('Saved %d files (%d view%s) to %s', n_files, numel(vs), plural(numel(vs)), dest));
        catch err
            if as_zip && exist(stage, 'dir') == 7, rmdir(stage, 's'); end
            say('error', ['Could not save the images: ' err.message]);
        end
    end

    function n = copy_out(vs, dest)
        [~, obj] = fileparts(res_root);
        training = strcmp(layout_drop.Value, 'training');
        n = 0;
        for i = 1:numel(vs)
            v = vs(i);
            src = fullfile(res_root, 'views', v.view);
            lr = dir(fullfile(src, 'LR_*.png'));
            if training
                name = [obj '_' v.view];
                if inc_hr.Value, n = n + put(fullfile(src, 'HR.png'), fullfile(dest, 'HR', [name '.png'])); end
                if inc_lr.Value
                    for q = 1:numel(lr)
                        n = n + put(fullfile(src, lr(q).name), fullfile(dest, lr(q).name(1:end-4), [name '.png']));
                    end
                end
                if inc_mat.Value, n = n + put(fullfile(src, 'sar_images.mat'), fullfile(dest, 'complex', [name '.mat'])); end
            else
                out = fullfile(dest, 'views', v.view);
                if inc_hr.Value, n = n + put(fullfile(src, 'HR.png'), fullfile(out, 'HR.png')); end
                if inc_lr.Value
                    for q = 1:numel(lr), n = n + put(fullfile(src, lr(q).name), fullfile(out, lr(q).name)); end
                end
                if inc_mat.Value, n = n + put(fullfile(src, 'sar_images.mat'), fullfile(out, 'sar_images.mat')); end
            end
            if mod(i, 5) == 0 || i == numel(vs)
                say('info', sprintf('Copying view %d of %d ...', i, numel(vs)));
                drawnow;
            end
        end
        if inc_idx.Value
            write_export_index(vs, res_root, dest, training);
            n = n + 1;
            if exist(fullfile(res_root, 'settings.json'), 'file') == 2
                n = n + put(fullfile(res_root, 'settings.json'), fullfile(dest, 'settings.json'));
            end
        end
    end

    function open_dest()
        if exist(last_dest, 'dir') == 7, winopen(last_dest); end
    end


% =============================== validation ===================================

    function m = validate_step(k)
        m = '';
        switch k
            case 1
                if isempty(obj_field.Value) || exist(obj_field.Value, 'file') ~= 2
                    m = 'Choose an .obj file (Browse...).'; return
                end
                if isempty(strtrim(out_field.Value))
                    m = 'Choose a folder to save the images in.'; return
                end
                if mat_drop.Value == MAT_CUSTOM && ~startsWith(strtrim(cust_obj.Value), 'finish')
                    m = 'The custom object surface must be a POV-Ray finish, starting with "finish {".'; return
                end
                if gnd_drop.Value == size(GROUNDS, 1) && ~startsWith(strtrim(cust_gnd.Value), 'finish')
                    m = 'The custom ground must be a POV-Ray finish, starting with "finish {".'; return
                end
            case 3
                switch current_mode()
                    case 1
                        inc = parse_list(comp_whole_inc.Value);
                        if comp_whole_n.Value > 0 && (isempty(inc) || any(inc < 10) || any(inc > 85))
                            m = 'Whole-scene angles must be numbers between 10 and 85, e.g. 40 65.'; return
                        end
                        if comp_win{1}.Value > comp_win{2}.Value || comp_inc{1}.Value > comp_inc{2}.Value || ...
                                comp_side_r{1}.Value > comp_side_r{2}.Value
                            m = 'In each "from ... to" pair, the first number must not be larger than the second.'; return
                        end
                        if comp_whole_n.Value == 0 && strcmp(comp_auto.Value, 'fixed') && comp_n.Value == 0
                            m = 'Nothing to make: choose some whole-scene directions or some partial views.'; return
                        end
                    case 3
                        inc = parse_list(around_inc.Value);
                        if isempty(inc) || any(inc < 10) || any(inc > 85)
                            m = 'Incidence angles must be numbers between 10 and 85, e.g. 45 or 35 45 55.'; return
                        end
                    case 4
                        if isempty(picks)
                            m = 'Add at least one view: click the map to place the window, then click Add this view.'; return
                        end
                    case 5
                        if isempty(bl_picks)
                            m = 'No views captured yet: choose them in Blender, click "Send views to the SAR window" there, then click Capture here.'; return
                        end
                end
            case 4
                f = parse_list(fac_field.Value);
                if any(f <= 1) || any(f > 32) || (~isempty(strtrim(fac_field.Value)) && isempty(f))
                    m = 'Lower-resolution versions must be numbers above 1 and up to 32, e.g. 2 4 8. Leave empty for HR only.'; return
                end
        end
    end

% =============================== run ==========================================

    function opts = build_opts(cfg)
        opts = struct();
        switch cfg.mode
            case 1
                if cfg.comp_whole_n > 0
                    opts.full_bearings = (0:cfg.comp_whole_n-1)*360/cfg.comp_whole_n;
                    opts.full_incidences = unique(parse_list(cfg.comp_whole_inc));
                end
                if strcmp(cfg.comp_auto, 'fixed')
                    opts.n_random = cfg.comp_n;
                else
                    opts.coverage = cfg.comp_cover;
                end
                opts.window_m = cfg.comp_win;
                opts.incidence_range = cfg.comp_inc;
                opts.side_fraction = cfg.comp_side/100;
                opts.side_range = cfg.comp_side_r;
            case 2
                opts.bearings = cfg.full_bearing;
                opts.incidences = cfg.full_inc;
            case 4
                vs = struct('name', {}, 'bearing', {}, 'incidence', {}, 'center', {}, 'width_m', {}, 'height_m', {});
                for q = 1:size(cfg.picks, 1)
                    r = cfg.picks(q, :);
                    vs(end+1) = struct('name', sprintf('Pick%d', q), 'bearing', r(1), 'incidence', r(2), ...
                        'center', [r(3) r(4)], 'width_m', r(5), 'height_m', r(6)); %#ok<AGROW>
                end
                opts.views = vs;
            case 5
                vs = struct('name', {}, 'bearing', {}, 'incidence', {}, 'center', {}, 'width_m', {}, 'height_m', {});
                for q = 1:size(cfg.bl_picks, 1)
                    r = cfg.bl_picks(q, :);
                    vs(end+1) = struct('name', cfg.bl_names{q}, 'bearing', r(1), 'incidence', r(2), ...
                        'center', [r(3) r(4)], 'width_m', r(5), 'height_m', r(6)); %#ok<AGROW>
                end
                opts.views = vs;
            otherwise
                opts.bearings = mod(cfg.around_first + (0:cfg.around_n-1)*360/cfg.around_n, 360);
                opts.incidences = unique(parse_list(cfg.around_inc));
                opts.window = cfg.around_win/100;
                opts.grid = cfg.around_grid;
        end
        if cfg.mode == 5
            opts.up_axis = 'y';       % Blender exports its model with Y up, in metres
            opts.scale = 1;
        elseif ~isempty(resolved) && strcmp(analysis_file, cfg.obj)
            opts.up_axis = resolved.up;       % what the user saw in step 1
            opts.scale = resolved.scale;
        else
            opts.up_axis = cfg.up;
            opts.scale = ternary(strcmp(cfg.units, 'auto'), 'auto', ternary(strcmp(cfg.units, 'custom'), cfg.units_custom, str2double(cfg.units)));
        end
        if strcmp(OBJ_MATERIALS{cfg.material, 2}, 'materials:auto')
            % Each material name of the file picks its finish; faces without a
            % known name get the default (concrete)
            opts.materials = 'auto';
            opts.finish = OBJ_MATERIALS{1, 2};
        else
            opts.finish = ternary(cfg.material == MAT_CUSTOM, cfg.custom_obj, OBJ_MATERIALS{cfg.material, 2});
        end
        if cfg.ground == 4
            opts.ground = false;
        else
            opts.ground_finish = ternary(cfg.ground == size(GROUNDS, 1), cfg.custom_ground, GROUNDS{cfg.ground, 2});
        end
        if strcmp(cfg.res, 'manual'), opts.bw = cfg.bw*1e6; else, opts.target_px = cfg.px; end
        opts.factors = unique(parse_list(cfg.factors));
        opts.seed = cfg.seed;
        if cfg.bounce > 1, opts.bounce_max = str2double(BOUNCES{cfg.bounce}); end
        opts.rays_per_pixel = cfg.rays;
        opts.top_down = cfg.topdown;
        opts.save_complex = cfg.complex;
        opts.keep_files = cfg.keep;
        opts.overwrite = cfg.redo;
    end

    function t = model_line(cfg)
        if cfg.mode == 5
            t = 'the model as Blender shows it (metres)';
        elseif ~isempty(resolved) && strcmp(analysis_file, cfg.obj)
            t = sprintf('%s up, %s%s: %s across, %s tall, %s deep', upper(resolved.up), resolved.units, ...
                ternary(resolved.scale == 1, '', sprintf(' (x%g)', resolved.scale)), ...
                length_text(resolved.size_m(1)), length_text(resolved.size_m(2)), length_text(resolved.size_m(3)));
        else
            t = 'worked out when the run starts';
        end
    end

    function refresh_review()
        cfg = collect();
        modes = {'Complete set', 'One full image', 'Views around the object', 'Views picked on a map', 'Views chosen in Blender'};
        lines = {sprintf('Object:   %s', ternary(cfg.mode == 5 && ~isempty(cfg.blender_obj), cfg.blender_obj, cfg.obj)), ...
                 sprintf('Model:    %s', model_line(cfg)), ...
                 sprintf('Save in:  %s', cfg.out), ...
                 sprintf('Create:   %s, %s', modes{cfg.mode}, summary_text()), ...
                 sprintf('Radar:    %s; lower-resolution versions: %s', ...
                    ternary(strcmp(cfg.res, 'manual'), sprintf('%g MHz bandwidth', cfg.bw), sprintf('automatic, whole scene about %d px', cfg.px)), ...
                    ternary(isempty(parse_list(cfg.factors)), 'NONE, so only HR images will be made', strtrim(cfg.factors))), ...
                 time_estimate(count_views())};
        if cfg.mode == 1
            lines = [lines(1:3), {sprintf('Partial:  windows %g to %g m, angles %g to %g deg, %g%% of them side views at %g to %g deg', ...
                cfg.comp_win, cfg.comp_inc, cfg.comp_side, cfg.comp_side_r)}, lines(4:end)];
        end
        review.Value = lines;
        run_status.Text = 'Ready.';
        set_bar(0);
    end

    function do_start()
        if running, return; end
        for j = 1:4
            m = validate_step(j);
            if ~isempty(m), step = j; show_step(); say('error', m); return; end
        end
        cfg = collect();
        obj_run = ternary(cfg.mode == 5, cfg.blender_obj, cfg.obj);   % in Blender mode the views belong to Blender's model
        [~, name] = fileparts(obj_run);
        root_dir = fullfile(cfg.out, regexprep(name, '[^A-Za-z0-9_-]+', '_'));
        try
            if exist(cfg.out, 'dir') ~= 7, mkdir(cfg.out); end
            if exist(root_dir, 'dir') ~= 7, mkdir(root_dir); end
            write_text(fullfile(root_dir, 'settings.json'), jsonencode(cfg, 'PrettyPrint', true));
        catch err
            say('error', ['Could not write to the output folder: ' err.message]);
            return
        end

        if cfg.mode ~= 5, ensure_model_size(); end   % what the object is, so the run uses what step 1 showed
        opts = build_opts(cfg);
        opts.progress = @on_progress;
        opts.view_done = @on_view_done;
        opts.should_stop = @stop_wanted;   % a nested-function handle reads the live flag; @() stop_requested would freeze its value

        planned_n = 0;
        running = true; stop_requested = false; view_rows = {};
        tbl.Data = cell(0, 7);
        for a = pv_ax, cla(a); title(a, ''); end
        set_busy(true);
        open_btn.Enable = 'off';
        say('info', 'Running. The first view includes converting the object, which can take a little while for a large file.');
        set_bar(0);
        t0 = tic;
        finished_ok = false;
        try
            [~, notes, run_rows] = Make_Multi_Angle_Dataset(obj_run, cfg.out, opts);
            last_run = struct('root', root_dir, 'ids', {{run_rows.view}});   % Results shows these, and keeps the rest as history
            % Count only the views of this run. The dataset folder also holds the views of earlier
            % runs (every earlier Blender capture, for one), and those are not this run's to judge.
            states = {run_rows.status};
            n_done = sum(strcmp(states, 'done'));
            n_failed = sum(strcmp(states, 'failed'));
            expected = ternary(planned_n > 0, planned_n, count_views());   % views the run set out to make
            left_out = '';
            if ~isempty(notes), left_out = [' Note: ' strjoin(notes, ' ')]; end
            if n_failed == 0 && n_done == expected
                say('ok', sprintf('Finished: %d views in %.0f s. The images and dataset_index.csv are in %s.%s', n_done, toc(t0), root_dir, left_out));
                run_status.Text = 'Finished.';
                set_bar(1);
                finished_ok = true;
            elseif n_failed == 0 && stop_requested
                say('info', sprintf('Stopped. %d of %d views are done; start again to carry on.', n_done, expected));
                run_status.Text = 'Stopped.';
            else
                say('error', sprintf('%d of %d views are done, %d failed. Click a failed row to see why, then Start again to retry it.%s', n_done, expected, n_failed, left_out));
                run_status.Text = 'Finished with errors.';
            end
        catch err
            say('error', ['Stopped by an error: ' err.message]);
            run_status.Text = 'Stopped by an error.';
        end
        running = false;
        set_busy(false);
        open_btn.Enable = exist(root_dir, 'dir') == 7;
        if finished_ok
            res_root = root_dir;       % a finished run opens on its own results, without the older ones
            res_scope = 'run';
            res_loaded = root_dir;
            res_sel = 0;
            goto_step(6);
            say('ok', sprintf('Finished: %d views in %.0f s. All of them are below; use Download to save them anywhere you like.%s', n_done, toc(t0), left_out));
        end
    end

    function do_stop()
        stop_requested = true;
        stop_btn.Enable = 'off';
        say('info', 'Stopping after the view that is running now ...');
    end

    function s = stop_wanted()
        s = stop_requested;
    end

    function on_progress(text)
        run_status.Text = text;
        tok = regexp(text, '^view (\d+) of (\d+)', 'tokens', 'once');
        if ~isempty(tok)
            i = str2double(tok{1}); n = str2double(tok{2});
            set_bar((i - 1)/n);
            ensure_rows(n);
            if size(tbl.Data, 1) >= i && ~strcmp(tbl.Data{i, 6}, 'done'), tbl.Data{i, 6} = 'working'; end
        end
        drawnow;
    end

    function ensure_rows(n)
        planned_n = n;
        if size(tbl.Data, 1) ~= n
            d = cell(n, 7);
            d(:, 6) = {'waiting'};
            for r = 1:min(n, size(tbl.Data, 1)), d(r, :) = tbl.Data(r, :); end
            tbl.Data = d;
            view_rows = [view_rows, cell(1, n - numel(view_rows))];
        end
    end

    function on_view_done(i, n, row)
        ensure_rows(n);
        view_rows{i} = row;
        size_txt = '';
        if strcmp(row.status, 'done'), size_txt = sprintf('%d x %d', row.image_px, row.image_py); end
        tbl.Data(i, :) = {row.view, sprintf('%g deg', row.bearing_deg), sprintf('%g deg', row.incidence_deg), ...
            sprintf('%.0f%%', 100*row.window), size_txt, row.status, sprintf('%.0f', row.seconds)};
        set_bar(i/n);
        if strcmp(row.status, 'done'), show_view(i); end
        drawnow;
    end

    function table_selected(ev)
        if ~isempty(ev.Indices), show_view(ev.Indices(1)); end
    end

    function show_view(i)
        if i > numel(view_rows) || isempty(view_rows{i}), detail.Text = 'This view has not been made yet.'; return; end
        r = view_rows{i};
        if strcmp(r.status, 'failed')
            detail.Text = ['Failed: ' r.message];
            return
        end
        if ~strcmp(r.status, 'done'), return; end
        files = [{fullfile(root_dir, 'views', r.view, 'HR.png')}, strsplit(r.lr, ';')];
        files = files(~cellfun(@isempty, files));
        names = cell(size(files));
        for k = 1:numel(files)
            [~, base] = fileparts(files{k});
            names{k} = strrep(base, '_', ' ');   % HR, LR mid, LR low, ...
        end
        detail.Text = sprintf('%s: direction %g, incidence %g, window %.0f%% (%s m)', r.view, r.bearing_deg, r.incidence_deg, 100*r.window, r.window_m);
        for k = 1:5
            if k <= numel(files) && exist(files{k}, 'file') == 2
                image(pv_ax(k), imread(files{k}));
                colormap(pv_ax(k), gray(256));
                axis(pv_ax(k), 'image');
                pv_ax(k).XTick = []; pv_ax(k).YTick = [];
                title(pv_ax(k), names{k});
                pv_ax(k).Visible = 'on';
            else
                cla(pv_ax(k)); title(pv_ax(k), '');
                pv_ax(k).Visible = 'off';
            end
        end
    end

    function set_bar(frac)
        w = bar_bg.InnerPosition(3);
        bar_fill.Position = [0 0 max(0, min(1, frac))*w 14];
    end

    function open_folder()
        if exist(root_dir, 'dir') == 7, winopen(root_dir); end
    end

    function close_window()
        if running
            stop_requested = true;
            say('info', 'A run is in progress. It will stop after the current view, then the window can be closed.');
            return
        end
        delete(fig);
    end

end


% =============================== helpers ======================================

function vs = read_views(folder)
% Every view of a dataset folder, from the view_info.mat each one keeps. Only
% the fields the Results step needs are taken, so datasets made by earlier
% versions still open.
d = dir(fullfile(folder, 'views', '*', 'view_info.mat'));
vs = struct('view', {}, 'bearing_deg', {}, 'incidence_deg', {}, 'window', {}, 'window_m', {}, ...
    'image_px', {}, 'image_py', {}, 'status', {}, 'message', {}, 'seconds', {}, 'made', {});
for i = 1:numel(d)
    try
        s = load(fullfile(d(i).folder, d(i).name), 'row');
        r = s.row;
        vs(end+1) = struct('view', r.view, 'bearing_deg', r.bearing_deg, 'incidence_deg', r.incidence_deg, ...
            'window', r.window, 'window_m', pick(r, 'window_m', ''), 'image_px', pick(r, 'image_px', NaN), ...
            'image_py', pick(r, 'image_py', NaN), 'status', r.status, 'message', pick(r, 'message', ''), ...
            'seconds', pick(r, 'seconds', NaN), 'made', d(i).datenum); %#ok<AGROW>
    catch
    end
end
end

function vs = sort_newest(vs)
% Newest first
if numel(vs) > 1
    [~, o] = sort([vs.made], 'descend');
    vs = vs(o);
end
end

function ids = newest_group(vs)
% For a folder that does not say which views its latest run made: the newest views that were made one after
% another (each less than 15 minutes after the one before), the way a run makes them
[t, o] = sort([vs.made], 'descend');
k = 1;
while k < numel(t) && t(k) - t(k + 1) <= 15/1440
    k = k + 1;
end
ids = {vs(o(1:k)).view};
end

function ids = read_last_run(folder)
% The views the latest run of a dataset folder handled, from the note the run leaves (last_run.json)
ids = {};
f = fullfile(folder, 'last_run.json');
if exist(f, 'file') ~= 2, return; end
try
    S = jsondecode(fileread(f));
    if isfield(S, 'views') && ~isempty(S.views), ids = cellstr(S.views); end
    ids = ids(:)';
catch
end
end

function write_export_index(vs, root, dest, training)
% index.csv for what was downloaded: one row per view, with where its files went
[~, obj] = fileparts(root);
if ~exist(dest, 'dir'), mkdir(dest); end
fid = fopen(fullfile(dest, 'index.csv'), 'w');
fprintf(fid, 'view,bearing_deg,incidence_deg,window,window_m,image_px,image_py,file_name\n');
for i = 1:numel(vs)
    v = vs(i);
    if training, fn = [obj '_' v.view '.png']; else, fn = fullfile('views', v.view); end
    fprintf(fid, '%s,%g,%g,%g,%s,%g,%g,%s\n', v.view, v.bearing_deg, v.incidence_deg, v.window, v.window_m, ...
        v.image_px, v.image_py, fn);
end
fclose(fid);
end

function n = put(src, dst)
% Copies one file if it exists, making the folder first. Returns how many were copied.
n = 0;
if exist(src, 'file') ~= 2, return; end
folder = fileparts(dst);
if exist(folder, 'dir') ~= 7, mkdir(folder); end
copyfile(src, dst, 'f');
n = 1;
end

function s = length_text(m)
% A length in m as people say it: 830 m, 6.9 km
if m >= 1000
    s = sprintf('%.1f km', m/1000);
elseif m >= 10
    s = sprintf('%.0f m', m);
else
    s = sprintf('%.1f m', m);
end
end

function s = area_text(m2)
if m2 >= 1e5
    s = sprintf('%.1f km^2', m2/1e6);
else
    s = sprintf('%.0f m^2', m2);
end
end

function P = footprint(bearing, incidence, cx, cz, w, h)
% The ground a view covers, as a closed outline in map coordinates (x, north).
% The frame's width lies across the look direction, and its height, seen on
% the ground, is stretched by 1/cos(incidence) along it.
b = bearing*pi/180;
a = [cos(b) sin(b)];              % across, in (x, z)
s = [sin(b) -cos(b)];             % towards the radar, in (x, z)
d = h/cos(incidence*pi/180);
c = [cx cz];
Q = [c + (w/2)*a + (d/2)*s; c - (w/2)*a + (d/2)*s; c - (w/2)*a - (d/2)*s; c + (w/2)*a - (d/2)*s; c + (w/2)*a + (d/2)*s];
P = [Q(:, 1), -Q(:, 2)];
end

function p = to_picks(x)
% Views picked on the map, from settings that were saved as JSON (one view comes back flat)
if isempty(x), p = zeros(0, 6); elseif size(x, 2) == 6, p = x; else, p = reshape(x(:), 6, [])'; end
end

function c = at(c, row, col)
% Puts a component at a row and column of its grid
c.Layout.Row = row;
c.Layout.Column = col;
end

function row_label(g, r, text)
uilabel(g, 'Text', text, 'HorizontalAlignment', 'right', 'Layout', matlab.ui.layout.GridLayoutOptions('Row', r, 'Column', 1));
end

function row_hint(g, r, text)
% Third column, to the right of the control: what it means
uilabel(g, 'Text', text, 'FontAngle', 'italic', 'WordWrap', 'on', 'VerticalAlignment', 'center', ...
    'Layout', matlab.ui.layout.GridLayoutOptions('Row', r, 'Column', 3));
end

function g = view_grid(parent, rows)
% A grid for one kind of view, sharing the one cell of its parent
g = uigridlayout(parent, [rows 3]);
g.Layout.Row = 1;
g.Layout.Column = 1;
g.Visible = 'off';
g.ColumnWidth = {200, 250, '1x'};
g.RowHeight = repmat({30}, 1, rows);
g.Padding = [8 8 8 8];
end

function pair = range_fields(g, r, vals, lim, tag)
% Two number fields for a "from ... to" range
p = uigridlayout(g, [1 2]);
p.Layout.Row = r; p.Layout.Column = 2;
p.Padding = [0 0 0 0];
p.ColumnSpacing = 6;
pair = {uieditfield(p, 'numeric', 'Value', vals(1), 'Limits', lim, 'Tag', [tag '_min']), ...
        uieditfield(p, 'numeric', 'Value', vals(2), 'Limits', lim, 'Tag', [tag '_max'])};
end

function v = parse_list(s)
% "35, 45 55" -> [35 45 55]
v = sscanf(strrep(s, ',', ' '), '%f')';
v = v(:)';
end

function s = plural(n)
if n == 1, s = ''; else, s = 's'; end
end

function v = ternary(c, a, b)
if c, v = a; else, v = b; end
end

function v = pick(cfg, name, default)
if isfield(cfg, name) && ~isempty(cfg.(name)), v = cfg.(name); else, v = default; end
end

function assign(ctrl, cfg, name)
if isfield(cfg, name), ctrl.Value = cfg.(name); end
end

function write_text(path, text)
fid = fopen(path, 'w');
if fid < 0, error('Could not write %s', path); end
fwrite(fid, text, 'char');
fclose(fid);
end

function p = userpath_or_pwd()
p = pwd;
try
    u = userpath;
    if ~isempty(u), p = u; end
catch
end
end
