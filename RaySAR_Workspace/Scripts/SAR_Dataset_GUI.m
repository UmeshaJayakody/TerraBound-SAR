function SAR_Dataset_GUI
% SAR Dataset Studio: one window for the whole workflow, from a 3D object
% (.obj) to a folder of matching HR and lower-resolution SAR image pairs.
%
% Six steps, each explained on screen:
%   1 Object            the .obj file, where to save, how to treat the model
%   2 What to create    the complete set (whole scene from several sides plus many
%                       partial and side views), one full image, or views around
%                       the object
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
    'Custom (type it below)',        ''};
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
model_key = '';            % which file and up-axis model_size belongs to
planned_n = 0;             % how many views the run has said it will make
res_root = '';             % the dataset folder shown in Results
res_views = [];            % its views, one struct each
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

nav = uigridlayout(main, [1 6]);
at(nav, 3, 2);
nav.ColumnWidth = {130, 130, '1x', 100, 100, 4};
nav.Padding = [0 4 0 4];
save_btn = uibutton(nav, 'push', 'Text', 'Save settings...', 'ButtonPushedFcn', @(~, ~) do_save());
load_btn = uibutton(nav, 'push', 'Text', 'Load settings...', 'ButtonPushedFcn', @(~, ~) do_load());
uilabel(nav, 'Text', '');
back_btn = uibutton(nav, 'push', 'Text', '< Back', 'ButtonPushedFcn', @(~, ~) goto_step(step - 1));
next_btn = uibutton(nav, 'push', 'Text', 'Next >', 'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) do_next());
at(save_btn, 1, 1); at(load_btn, 1, 2); at(back_btn, 1, 4); at(next_btn, 1, 5);

% Each step is a grid in the same cell of the stack; only one is visible at a time
panels = gobjects(1, 6);

% ============================ Step 1: Object ==================================
g = step_grid(1, [10 4]);
g.ColumnWidth = {170, 250, '1x', 100};
g.RowHeight = {30, 30, 8, 30, 30, 30, 30, 30, 30, 60};
g.Padding = [8 8 8 8];
row_label(g, 1, 'Object file (.obj)');
obj_field = at(uieditfield(g, 'text', 'Editable', 'off', 'Tag', 'obj'), 1, [2 3]);
at(uibutton(g, 'push', 'Text', 'Browse...', 'ButtonPushedFcn', @(~, ~) browse_obj()), 1, 4);
row_label(g, 2, 'Save images in');
out_field = at(uieditfield(g, 'text', 'Tag', 'out', 'Value', fullfile(userpath_or_pwd(), 'SAR_Dataset')), 2, [2 3]);
at(uibutton(g, 'push', 'Text', 'Browse...', 'ButtonPushedFcn', @(~, ~) browse_out()), 2, 4);
row_label(g, 4, 'Which way is up');
up_drop = at(uidropdown(g, 'Items', {'Y is up (most files)', 'Z is up (3ds Max exports)'}, 'ItemsData', {'y', 'z'}, 'Value', 'y', 'Tag', 'up'), 4, 2);
row_hint(g, 4, 'If the object comes out lying on its side, switch this.');
row_label(g, 5, 'Object surface');
mat_drop = at(uidropdown(g, 'Items', OBJ_MATERIALS(:, 1), 'ItemsData', 1:size(OBJ_MATERIALS, 1), 'Value', 1, 'Tag', 'material', ...
    'ValueChangedFcn', @(~, ~) update_custom()), 5, 2);
row_hint(g, 5, 'How mirror-like or rough the object is to the radar.');
row_label(g, 6, 'Ground');
gnd_drop = at(uidropdown(g, 'Items', GROUNDS(:, 1), 'ItemsData', 1:size(GROUNDS, 1), 'Value', 1, 'Tag', 'ground', ...
    'ValueChangedFcn', @(~, ~) update_custom()), 6, 2);
row_hint(g, 6, 'The flat surface under the object. The sea is a stylised mirror, not real sea scattering.');
row_label(g, 7, 'Custom object surface');
cust_obj = at(uieditfield(g, 'text', 'Tag', 'custom_obj', 'Enable', 'off', 'Placeholder', 'finish {reflection {0.4} ambient 0 diffuse 0.35 specular 0.5 roughness 0.01}'), 7, [2 3]);
row_label(g, 8, 'Custom ground');
cust_gnd = at(uieditfield(g, 'text', 'Tag', 'custom_ground', 'Enable', 'off', 'Placeholder', 'finish {reflection {0.3} ambient 0 diffuse 0.15 specular 0}'), 8, [2 3]);
check_btn = at(uibutton(g, 'push', 'Text', 'Check model', 'Tag', 'check', 'ButtonPushedFcn', @(~, ~) check_model()), 9, 2);
row_hint(g, 9, 'Optional: reads the file and shows how big the object is.');
model_info = at(uilabel(g, 'Text', 'Use this to see whether "Which way is up" is right: the height it shows should be the object''s real height.', ...
    'WordWrap', 'on', 'VerticalAlignment', 'top'), 10, [2 4]);

% ============================ Step 2: What to create ==========================
g = step_grid(2, [3 1]);
g.RowHeight = {112, 64, '1x'};
g.Padding = [8 8 8 8];
mode_group = uibuttongroup(g, 'Title', '', 'BorderType', 'none', 'Tag', 'mode', 'SelectionChangedFcn', @(~, ~) mode_changed());
at(mode_group, 1, 1);
mode_btn(1) = uiradiobutton(mode_group, 'Text', 'Complete set (recommended)', 'Position', [10 82 300 22], 'Tag', 'mode1');
mode_btn(2) = uiradiobutton(mode_group, 'Text', 'One full image', 'Position', [10 47 300 22], 'Tag', 'mode2');
mode_btn(3) = uiradiobutton(mode_group, 'Text', 'Views around the object', 'Position', [10 12 300 22], 'Tag', 'mode3');
mode_text = at(uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment', 'top'), 2, 1);
at(uilabel(g, 'Text', ['A view is one image seen from one direction and angle. A window is the part of the scene ' ...
    'it covers, from the whole object down to a small piece. Side views and partial views are just views ' ...
    'with a different direction, angle or window.'], 'WordWrap', 'on', 'VerticalAlignment', 'top'), 3, 1);

% ============================ Step 3: Views ===================================
g = step_grid(3, [3 1]);
g.RowHeight = {380, 30, 44};
g.Padding = [8 8 8 8];
vstack = uigridlayout(g, [1 1]);
vstack.Padding = [0 0 0 0];
at(vstack, 1, 1);
views_summary = at(uilabel(g, 'Text', '', 'FontWeight', 'bold'), 2, 1);
views_time = at(uilabel(g, 'Text', '', 'WordWrap', 'on', 'VerticalAlignment', 'top'), 3, 1);

vp = gobjects(1, 3);

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
g.RowHeight = {34, '1x', 176};
g.Padding = [8 8 8 8];
g.RowSpacing = 6;

tb = uigridlayout(g, [1 6]);
at(tb, 1, 1);
tb.ColumnWidth = {'1x', 170, 200, 80, 150, 80};
tb.Padding = [0 0 0 0];
res_path = uilabel(tb, 'Text', 'No dataset loaded.', 'Tag', 'res_path');
uibutton(tb, 'push', 'Text', 'Open another dataset...', 'ButtonPushedFcn', @(~, ~) browse_dataset());
filter_drop = uidropdown(tb, 'Items', FILTERS, 'ItemsData', 1:numel(FILTERS), 'Value', 1, 'Tag', 'filter', ...
    'ValueChangedFcn', @(~, ~) apply_filter());
prev_btn = uibutton(tb, 'push', 'Text', '< Prev', 'ButtonPushedFcn', @(~, ~) change_page(-1));
page_lbl = uilabel(tb, 'Text', '', 'HorizontalAlignment', 'center', 'Tag', 'page');
nextp_btn = uibutton(tb, 'push', 'Text', 'Next >', 'ButtonPushedFcn', @(~, ~) change_page(1));

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
    inner.RowHeight = {'1x', 30};
    inner.Padding = [2 2 2 2];
    inner.RowSpacing = 2;
    cell_img(i) = uiimage(inner, 'ScaleMethod', 'fit', 'ImageClickedFcn', @(~, ~) select_cell(i));
    cell_cap(i) = uilabel(inner, 'Text', '', 'HorizontalAlignment', 'center', 'FontSize', 10, 'WordWrap', 'on');
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
    'stop', @do_stop, 'next', @do_next, 'validate', @validate_step, 'step', @get_step, ...
    'results_load', @load_dataset, 'results_filter', @apply_filter, 'results_select', @select_view, ...
    'export', @export_to, 'shown', @get_shown);
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
            model_info.Text = 'Click Check model to see how big it is.';
            say('info', '');
        end
    end

    function browse_out()
        d = uigetdir(out_field.Value, 'Folder for the images');
        if ~isequal(d, 0), out_field.Value = d; end
    end

    function update_custom()
        cust_obj.Enable = mat_drop.Value == size(OBJ_MATERIALS, 1);
        cust_gnd.Enable = gnd_drop.Value == size(GROUNDS, 1);
    end

    function check_model()
        p = obj_field.Value;
        if exist(p, 'file') ~= 2
            model_info.Text = 'Choose an .obj file first.';
            return
        end
        check_btn.Enable = 'off';
        model_info.Text = 'Reading the file ...';
        drawnow;
        try
            [sz, n] = read_model_size(p, up_drop.Value);
            model_size = sz; model_key = [p '|' up_drop.Value];
            model_info.Text = sprintf(['%d vertices. Size with this "up": %.1f m across (x), %.1f m tall, %.1f m deep (z). ' ...
                'If the height looks wrong, switch "Which way is up".'], n, sz(1), sz(2), sz(3));
            update_summary();
        catch err
            model_info.Text = ['Could not read the file: ' err.message];
        end
        check_btn.Enable = 'on';
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
             'at 3 angles is 24 views.']};
        mode_text.Text = texts{k};
        for j = 1:3, vp(j).Visible = j == k; end
    end

    function k = current_mode()
        k = find(arrayfun(@(b) b == mode_group.SelectedObject, mode_btn), 1);
        if isempty(k), k = 1; end
    end

% =============================== step 3 =======================================

    function show_view_settings()
        k = current_mode();
        for j = 1:3, vp(j).Visible = j == k; end
    end

    function n = count_views()
        switch current_mode()
            case 1, [nw, np] = complete_counts(); n = nw + max(0, np);
            case 2, n = 1;
            otherwise, n = around_n.Value*max(1, numel(unique(parse_list(around_inc.Value))))*around_grid.Value^2;
        end
    end

    function [nw, np] = complete_counts()
        % Whole-scene views, and partial views (NaN until the object has been read)
        nw = comp_whole_n.Value*numel(unique(parse_list(comp_whole_inc.Value)));
        if strcmp(comp_auto.Value, 'fixed')
            np = comp_n.Value;
        elseif ensure_model_size()
            np = Views_For_Coverage(model_size(1)*model_size(3), [comp_win{1}.Value comp_win{2}.Value], comp_cover.Value);
        else
            np = NaN;
        end
    end

    function ok = ensure_model_size()
        % Reads the object's size once per file and choice of up axis
        ok = false;
        if exist(obj_field.Value, 'file') ~= 2, return; end
        key = [obj_field.Value '|' up_drop.Value];
        if strcmp(key, model_key), ok = ~isempty(model_size); return; end
        say('info', 'Reading the object to work out how many views it needs ...');
        drawnow;
        try
            [model_size, ~] = read_model_size(obj_field.Value, up_drop.Value);
            model_key = key;
            ok = true;
            say('info', '');
        catch err
            model_size = []; model_key = '';
            say('error', ['Could not read the object: ' err.message]);
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
                s = sprintf('%s. The object is %.0f x %.0f m.', s, model_size(1), model_size(3));
            end
        else
            n = count_views();
            s = sprintf('%d view%s: %d HR image%s and %d lower-resolution image%s', ...
                n, plural(n), n, plural(n), n*nf, plural(n*nf));
        end
    end

    function update_summary()
        views_summary.Text = summary_text();
        views_time.Text = time_estimate(count_views());
    end

    function s = time_estimate(n)
        % Rough, from runs on Street_01: about 10 s for a small window and
        % a minute for the whole scene, most of it the radar processing
        switch current_mode()
            case 1
                [nw, np] = complete_counts();
                if isnan(np), np = 0; end
                f = 0.4;
                if ~isempty(model_size)
                    f = min(1, mean([comp_win{1}.Value comp_win{2}.Value])/max(model_size([1 3])));
                end
                t = nw*65 + np*(10 + 55*f^2);
            case 2, t = 65;
            otherwise, t = n*(10 + 55*(around_win.Value/100)^2);
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
        set_if(up_drop, 'up');
        set_if(mat_drop, 'material'); set_if(gnd_drop, 'ground');
        set_if(cust_obj, 'custom_obj'); cust_gnd.Value = pick(cfg, 'custom_ground', cust_gnd.Value);
        if isfield(cfg, 'mode') && cfg.mode >= 1 && cfg.mode <= 3, mode_group.SelectedObject = mode_btn(cfg.mode); end
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
        if isempty(res_root)
            [~, name] = fileparts(obj_field.Value);
            cand = fullfile(strtrim(out_field.Value), regexprep(name, '[^A-Za-z0-9_-]+', '_'));
            if ~isempty(name) && exist(fullfile(cand, 'views'), 'dir') == 7, res_root = cand; end
        end
        if isempty(res_root)
            res_views = []; res_shown = [];
            res_path.Text = 'No dataset yet. Make one in step 5, or open an earlier one.';
            show_page();
            return
        end
        load_dataset(res_root);
    end

    function load_dataset(folder)
        res_root = folder;
        res_views = read_views(folder);
        res_sel = 0;
        res_path.Text = sprintf('%s  (%d views)', folder, numel(res_views));
        res_path.Tooltip = folder;
        apply_filter();
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
                cell_cap(i).Text = {strjoin(tok(1:min(2, numel(tok))), ' '), sprintf('az %g   inc %g', v.bearing_deg, v.incidence_deg)};
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
                if mat_drop.Value == size(OBJ_MATERIALS, 1) && ~startsWith(strtrim(cust_obj.Value), 'finish')
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
            otherwise
                opts.bearings = mod(cfg.around_first + (0:cfg.around_n-1)*360/cfg.around_n, 360);
                opts.incidences = unique(parse_list(cfg.around_inc));
                opts.window = cfg.around_win/100;
                opts.grid = cfg.around_grid;
        end
        opts.up_axis = cfg.up;
        opts.finish = ternary(cfg.material == size(OBJ_MATERIALS, 1), cfg.custom_obj, OBJ_MATERIALS{cfg.material, 2});
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

    function refresh_review()
        cfg = collect();
        modes = {'Complete set', 'One full image', 'Views around the object'};
        lines = {sprintf('Object:   %s', cfg.obj), ...
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
        [~, name] = fileparts(cfg.obj);
        root_dir = fullfile(cfg.out, regexprep(name, '[^A-Za-z0-9_-]+', '_'));
        try
            if exist(cfg.out, 'dir') ~= 7, mkdir(cfg.out); end
            if exist(root_dir, 'dir') ~= 7, mkdir(root_dir); end
            write_text(fullfile(root_dir, 'settings.json'), jsonencode(cfg, 'PrettyPrint', true));
        catch err
            say('error', ['Could not write to the output folder: ' err.message]);
            return
        end

        opts = build_opts(cfg);
        opts.progress = @on_progress;
        opts.view_done = @on_view_done;
        opts.should_stop = @stop_wanted;   % a nested-function handle reads the live flag; @() stop_requested would freeze its value

        if cfg.mode == 1, ensure_model_size(); end
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
            [index, notes] = Make_Multi_Angle_Dataset(cfg.obj, cfg.out, opts);
            n_done = sum(strcmp({index.status}, 'done'));
            expected = ternary(planned_n > 0, planned_n, count_views());   % views the run set out to make
            left_out = '';
            if ~isempty(notes), left_out = [' Note: ' strjoin(notes, ' ')]; end
            if n_done == expected
                say('ok', sprintf('Finished: %d views in %.0f s. The images and dataset_index.csv are in %s.%s', n_done, toc(t0), root_dir, left_out));
                run_status.Text = 'Finished.';
                set_bar(1);
                finished_ok = true;
            elseif stop_requested
                say('info', sprintf('Stopped. %d of %d views are done; start again to carry on.', n_done, expected));
                run_status.Text = 'Stopped.';
            else
                say('error', sprintf('%d of %d views are done. The others failed: click their rows to see why, then Start again to retry them.', n_done, expected));
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
            res_root = root_dir;       % a finished run opens on its own results
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
    'image_px', {}, 'image_py', {}, 'status', {}, 'message', {}, 'seconds', {});
for i = 1:numel(d)
    try
        s = load(fullfile(d(i).folder, d(i).name), 'row');
        r = s.row;
        vs(end+1) = struct('view', r.view, 'bearing_deg', r.bearing_deg, 'incidence_deg', r.incidence_deg, ...
            'window', r.window, 'window_m', pick(r, 'window_m', ''), 'image_px', pick(r, 'image_px', NaN), ...
            'image_py', pick(r, 'image_py', NaN), 'status', r.status, 'message', pick(r, 'message', ''), ...
            'seconds', pick(r, 'seconds', NaN)); %#ok<AGROW>
    catch
    end
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

function [sz, n] = read_model_size(path, up)
% Size of an .obj model in m, [across height depth], from its vertices alone
lines = readlines(path);
v = lines(startsWith(lines, "v "));
n = numel(v);
a = sscanf(strjoin(v, newline), 'v %f %f %f ');   % the trailing space steps over each newline
if numel(a) == 3*n
    V = reshape(a, 3, n)';
else
    % Extra columns (vertex colours) or odd spacing: read the first three numbers of each line
    C = textscan(strjoin(v, newline), 'v %f %f %f %*[^\n]');
    V = [C{1} C{2} C{3}];
end
if isempty(V), error('No vertices found.'); end
if strcmp(up, 'z'), V = V(:, [1 3 2]); end
sz = max(V) - min(V);
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
