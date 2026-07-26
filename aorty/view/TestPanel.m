classdef TestPanel < handle
    % Test definition tabs, presets, General JSON import, and axis selection.

    properties (SetAccess = private)
        tabs
    end

    properties (Access = private)
        settings Settings
        parentFig
        callbacks = struct()
        controls = struct()
        presetDrop
        axisModeDrop
        postButtons
        postSelection = 'Stay at unchanged position'
        runButtons = gobjects(0)
        preRun
        generalRun
        generalSummary
        generalDefinition = []
        machineRunAllowed = false
        generalMachineAllowed = false
    end

    methods
        function panel = TestPanel(settings, parentFig, callbacks)
            panel.settings = settings;
            panel.parentFig = parentFig;
            panel.callbacks = callbacks;
        end

        function createToolbarControls(panel, grid)
            uilabel(grid, 'Text', 'Preset:');
            panel.presetDrop = uidropdown(grid, ...
                'Items', panel.nonEmptyItems(panel.settings.listAppConfigs()), ...
                'ValueChangedFcn', @(~, ~) panel.loadPreset());
            uibutton(grid, 'Text', 'Save', ...
                'ButtonPushedFcn', @(~, ~) panel.savePreset(false));
            uibutton(grid, 'Text', 'Save as', ...
                'ButtonPushedFcn', @(~, ~) panel.savePreset(true));
            axisPanel = uipanel(grid, 'Title', 'Active axes');
            axisGrid = uigridlayout(axisPanel, [1, 1]);
            axisGrid.Padding = [4, 0, 4, 0];
            panel.axisModeDrop = uidropdown(axisGrid, ...
                'Items', {'Both', 'X only', 'Y only'}, 'Value', 'Both', ...
                'ValueChangedFcn', @(~, ~) panel.onAxisModeChanged());
            panel.controls.system.axisMode = panel.axisModeDrop;
        end

        function create(panel, parent)
            container = uipanel(parent, 'Title', 'Test definition');
            container.Layout.Row = 2;
            container.Layout.Column = 1;
            layout = uigridlayout(container, [1, 1]);
            layout.Padding = [4, 4, 4, 4];
            panel.tabs = uitabgroup(layout);
            panel.createPreTestTab(uitab(panel.tabs, 'Title', 'Pre-test'));
            panel.createSingleTestTab(uitab(panel.tabs, 'Title', 'Single test'));
            panel.createCyclicTestTab(uitab(panel.tabs, 'Title', 'Cyclic test'));
            panel.createGeneralTestTab(uitab(panel.tabs, 'Title', 'General test'));
            panel.createPostTestTab(uitab(panel.tabs, 'Title', 'Post-test'));
            panel.refreshDependentControls();
            panel.refreshRunButtons();
        end

        function config = getConfiguration(panel)
            config = panel.collectValues(panel.controls);
            config.post.afterTest = panel.postSelection;
        end

        function mode = getAxisMode(panel)
            mode = char(panel.axisModeDrop.Value);
        end

        function action = getPostTestAction(panel)
            action = panel.postSelection;
        end

        function definition = getGeneralDefinition(panel)
            if isempty(panel.generalDefinition)
                error('GeneralTest:NoValidFile', ...
                    'Browse to a valid General Test JSON file first.');
            end
            definition = panel.generalDefinition;
        end

        function enabled = isAxisActive(panel, axisName)
            mode = panel.getAxisMode();
            enabled = strcmp(mode, 'Both') || ...
                strcmp(mode, [upper(char(axisName)), ' only']);
        end

        function setMachineAvailability(panel, connected, statuses)
            allowed = logical(connected);
            if allowed && ~isempty(statuses)
                axes = panel.activeAxes();
                for index = 1:numel(axes)
                    state = statuses.(axes{index});
                    allowed = allowed && ~state.working && ~state.error;
                end
            end
            panel.machineRunAllowed = allowed;
            generalAllowed = logical(connected);
            if generalAllowed && ~isempty(statuses) && ...
                    ~isempty(panel.generalDefinition)
                switch lower(char(panel.generalDefinition.axisMode))
                    case 'x'
                        generalAxes = {'X'};
                    case 'y'
                        generalAxes = {'Y'};
                    otherwise
                        generalAxes = {'X', 'Y'};
                end
                for index = 1:numel(generalAxes)
                    state = statuses.(generalAxes{index});
                    generalAllowed = generalAllowed && ...
                        ~state.working && ~state.error;
                end
            end
            panel.generalMachineAllowed = generalAllowed;
            panel.refreshRunButtons();
        end
    end

    methods (Access = private)
        function createPreTestTab(panel, tab)
            grid = panel.createFormGrid(tab, 11);
            panel.controls.pre.rate = panel.addAxisRow(grid, 2, ...
                'Movement speed', 1, '[mm/s]');
            panel.controls.pre.holdTime = panel.addAxisRow(grid, 3, ...
                'Time after force reached', 0, '[s]');
            panel.controls.pre.cyclic = panel.addCheckRow(grid, 4, ...
                'Cyclic pre-conditioning', false);
            panel.controls.pre.cycles = panel.addNumericRow(grid, 5, ...
                'Number of cycles', 1, '[cyc.]');
            panel.controls.pre.load = panel.addAxisRow(grid, 6, ...
                'Load force', 0, '[N]');
            panel.controls.pre.unload = panel.addAxisRow(grid, 7, ...
                'Unload force', 0, '[N]');
            panel.controls.pre.unloadToStart = panel.addCheckRow(grid, 8, ...
                'Unload to captured start position', false);
            panel.controls.pre.preload = panel.addOptionalAxisRow(grid, 9, ...
                'Initial preload', 0, '[N]');
            panel.controls.pre.cameraPeriod = panel.addOptionalRow(grid, 10, ...
                'Camera sampling period', 0.1, '[s]');
            button = panel.addRunButton(grid, 11, 'RUN PRE-TEST', ...
                panel.callbacks.runPre);
            panel.preRun = button;
            panel.runButtons(end + 1) = button;
            panel.controls.pre.cyclic.ValueChangedFcn = ...
                @(~, ~) panel.refreshDependentControls();
            panel.controls.pre.unloadToStart.ValueChangedFcn = ...
                @(~, ~) panel.refreshDependentControls();
            panel.controls.pre.preload.enabled.ValueChangedFcn = ...
                @(~, ~) panel.refreshDependentControls();
        end

        function createSingleTestTab(panel, tab)
            grid = panel.createFormGrid(tab, 11);
            panel.controls.single.includePre = panel.addCheckRow(grid, 2, ...
                'Include force pre-test', false);
            panel.controls.single.primaryMode = panel.addDropRow(grid, 3, ...
                'Primary endpoint mode', {'Displacement', 'Force'});
            panel.controls.single.primary = panel.addAxisRow(grid, 4, ...
                'Primary endpoint value', 0, '[mm / N]');
            panel.controls.single.secondaryMode = panel.addDropRow(grid, 5, ...
                'Optional OR endpoint', {'None', 'Displacement', 'Force'});
            panel.controls.single.secondary = panel.addAxisRow(grid, 6, ...
                'OR endpoint value', 0, '[mm / N]');
            panel.controls.single.rate = panel.addAxisRow(grid, 7, ...
                'Movement speed', 1, '[mm/s]');
            panel.controls.single.holdTime = panel.addAxisRow(grid, 8, ...
                'Wait after force reached', 0, '[s]');
            panel.controls.single.forceDrop = panel.addNumericRow(grid, 9, ...
                'Force drop', 10, '[%]');
            panel.controls.single.failureThreshold = panel.addAxisRow(grid, 10, ...
                'Arm above force', 0, '[N]');
            panel.controls.single.cameraPeriod = panel.addOptionalRow(grid, 11, ...
                'Camera sampling period', 0.1, '[s]');
            button = panel.addRunButton(grid, 12, 'RUN SINGLE TEST', ...
                panel.callbacks.runSingle);
            panel.runButtons(end + 1) = button;

            panel.controls.single.secondaryMode.ValueChangedFcn = ...
                @(~, ~) panel.refreshDependentControls();
            panel.controls.single.primaryMode.ValueChangedFcn = ...
                @(~, ~) panel.refreshDependentControls();
        end

        function createCyclicTestTab(panel, tab)
            grid = panel.createFormGrid(tab, 12);
            panel.controls.cyclic.includePre = panel.addCheckRow(grid, 2, ...
                'Include force pre-test', false);
            panel.controls.cyclic.cycles = panel.addNumericRow(grid, 3, ...
                'Number of cycles', 1, '[cyc.]');
            panel.controls.cyclic.loadMode = panel.addDropRow(grid, 4, ...
                'Load mode', {'Displacement', 'Force'});
            panel.controls.cyclic.load = panel.addAxisRow(grid, 5, ...
                'Constant load value', 0, '[mm / N]');
            panel.controls.cyclic.unloadMode = panel.addDropRow(grid, 6, ...
                'Unload mode', {'Displacement', 'Force'});
            panel.controls.cyclic.unload = panel.addAxisRow(grid, 7, ...
                'Constant unload value', 0, '[mm / N]');
            panel.controls.cyclic.rate = panel.addAxisRow(grid, 8, ...
                'Movement speed', 1, '[mm/s]');
            panel.controls.cyclic.holdTime = panel.addAxisRow(grid, 9, ...
                'Wait after force reached', 0, '[s]');
            panel.controls.cyclic.forceDrop = panel.addNumericRow(grid, 10, ...
                'Force drop', 0, '[%]');
            panel.controls.cyclic.failureThreshold = panel.addAxisRow(grid, 11, ...
                'Arm above force', 0, '[N]');
            panel.controls.cyclic.cameraPeriod = panel.addOptionalRow(grid, 12, ...
                'Camera sampling period', 0.1, '[s]');
            button = panel.addRunButton(grid, 13, 'RUN CYCLIC TEST', ...
                panel.callbacks.runCyclic);
            panel.runButtons(end + 1) = button;
            panel.controls.cyclic.loadMode.ValueChangedFcn = ...
                @(~, ~) panel.refreshDependentControls();
            panel.controls.cyclic.unloadMode.ValueChangedFcn = ...
                @(~, ~) panel.refreshDependentControls();
        end

        function createGeneralTestTab(panel, tab)
            grid = panel.createFormGrid(tab, 6);
            panel.controls.general.testFile = panel.addTextRow(grid, 2, ...
                'Complete JSON definition', 'No file selected');
            browse = uibutton(grid, 'Text', 'Browse JSON', ...
                'ButtonPushedFcn', @(~, ~) panel.onBrowseGeneralTest());
            browse.Layout.Row = 2;
            browse.Layout.Column = 5;
            label = uilabel(grid, 'Text', 'Imported test summary');
            label.Layout.Row = 3;
            label.Layout.Column = 1;
            panel.generalSummary = uitextarea(grid, 'Editable', 'off', ...
                'Value', {'No valid General Test has been imported.'});
            panel.generalSummary.Layout.Row = [3, 5];
            panel.generalSummary.Layout.Column = [2, 5];
            panel.generalRun = panel.addRunButton(grid, 6, ...
                'RUN IMPORTED TEST', panel.callbacks.runGeneral);
            panel.generalRun.Enable = 'off';
            panel.generalRun.Tooltip = ...
                'Run is enabled after a complete schemaVersion 1 JSON file validates.';
        end

        function createPostTestTab(panel, tab)
            grid = uigridlayout(tab, [2, 1]);
            grid.RowHeight = {28, '1x'};
            grid.Padding = [12, 12, 12, 12];
            uilabel(grid, 'Text', 'PLC action after successful test:', ...
                'FontWeight', 'bold');
            buttonGrid = uigridlayout(grid, [5, 1]);
            buttonGrid.RowHeight = repmat({40}, 1, 5);
            buttonGrid.Padding = [4, 4, 4, 4];
            buttonGrid.RowSpacing = 6;
            labels = {'Return to saved position', 'Return to start position', ...
                'Return to pre-test final position', 'Unload (force)', ...
                'Stay at unchanged position'};
            panel.postButtons = gobjects(numel(labels), 1);
            for index = 1:numel(labels)
                panel.postButtons(index) = uibutton(buttonGrid, 'state', ...
                    'Text', labels{index}, ...
                    'ValueChangedFcn', ...
                    @(src, ~) panel.onPostTestSelected(src));
            end
            panel.selectPostTestAction('Stay at unchanged position');
        end

        function grid = createFormGrid(~, tab, rows)
            grid = uigridlayout(tab, [rows + 1, 5]);
            grid.ColumnWidth = {190, '1x', '1x', 80, 72};
            grid.RowHeight = repmat({34}, 1, rows + 1);
            grid.Padding = [10, 10, 10, 10];
            grid.RowSpacing = 5;
            uilabel(grid, 'Text', 'Parameter', 'FontWeight', 'bold');
            uilabel(grid, 'Text', 'X', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            uilabel(grid, 'Text', 'Y', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            uilabel(grid, 'Text', 'Unit', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            uilabel(grid, 'Text', 'Lock', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
        end

        function controls = addAxisRow(panel, grid, row, text, value, unit)
            label = uilabel(grid, 'Text', text);
            label.Layout.Row = row;
            label.Layout.Column = 1;
            controls.x = uieditfield(grid, 'numeric', 'Value', value);
            controls.x.Layout.Row = row;
            controls.x.Layout.Column = 2;
            controls.y = uieditfield(grid, 'numeric', 'Value', value);
            controls.y.Layout.Row = row;
            controls.y.Layout.Column = 3;
            unitLabel = uilabel(grid, 'Text', unit, ...
                'HorizontalAlignment', 'center');
            unitLabel.Layout.Row = row;
            unitLabel.Layout.Column = 4;
            controls.lock = uibutton(grid, 'state', 'Text', 'XY', ...
                'Value', true);
            controls.lock.Layout.Row = row;
            controls.lock.Layout.Column = 5;
            controls.x.ValueChangedFcn = ...
                @(src, ~) panel.syncAxisPair(src, controls.y, controls.lock);
            controls.y.ValueChangedFcn = ...
                @(src, ~) panel.syncAxisPair(src, controls.x, controls.lock);
            controls.lock.ValueChangedFcn = ...
                @(src, ~) panel.onAxisLockChanged(src, controls.x, controls.y);
        end

        function control = addNumericRow(~, grid, row, text, value, unit)
            label = uilabel(grid, 'Text', text);
            label.Layout.Row = row;
            label.Layout.Column = 1;
            control = uieditfield(grid, 'numeric', 'Value', value);
            control.Layout.Row = row;
            control.Layout.Column = [2, 3];
            unitLabel = uilabel(grid, 'Text', unit, ...
                'HorizontalAlignment', 'center');
            unitLabel.Layout.Row = row;
            unitLabel.Layout.Column = 4;
        end

        function control = addCheckRow(~, grid, row, text, value)
            control = uicheckbox(grid, 'Text', text, 'Value', value);
            control.Layout.Row = row;
            control.Layout.Column = [1, 4];
        end

        function controls = addOptionalRow(panel, grid, row, text, value, unit)
            controls.enabled = uicheckbox(grid, 'Text', text, 'Value', false);
            controls.enabled.Layout.Row = row;
            controls.enabled.Layout.Column = 1;
            controls.value = uieditfield(grid, 'numeric', ...
                'Value', value, 'Enable', 'off');
            controls.value.Layout.Row = row;
            controls.value.Layout.Column = [2, 3];
            unitLabel = uilabel(grid, 'Text', unit, ...
                'HorizontalAlignment', 'center');
            unitLabel.Layout.Row = row;
            unitLabel.Layout.Column = 4;
            controls.enabled.ValueChangedFcn = ...
                @(~, ~) panel.refreshDependentControls();
        end

        function controls = addOptionalAxisRow(panel, grid, row, text, value, unit)
            controls.enabled = uicheckbox(grid, 'Text', text, 'Value', false);
            controls.enabled.Layout.Row = row;
            controls.enabled.Layout.Column = 1;
            controls.value.x = uieditfield(grid, 'numeric', 'Value', value);
            controls.value.x.Layout.Row = row;
            controls.value.x.Layout.Column = 2;
            controls.value.y = uieditfield(grid, 'numeric', 'Value', value);
            controls.value.y.Layout.Row = row;
            controls.value.y.Layout.Column = 3;
            unitLabel = uilabel(grid, 'Text', unit, ...
                'HorizontalAlignment', 'center');
            unitLabel.Layout.Row = row;
            unitLabel.Layout.Column = 4;
            controls.value.lock = uibutton(grid, 'state', 'Text', 'XY', ...
                'Value', true);
            controls.value.lock.Layout.Row = row;
            controls.value.lock.Layout.Column = 5;
            controls.value.x.ValueChangedFcn = @(src, ~) ...
                panel.syncAxisPair(src, controls.value.y, controls.value.lock);
            controls.value.y.ValueChangedFcn = @(src, ~) ...
                panel.syncAxisPair(src, controls.value.x, controls.value.lock);
            controls.value.lock.ValueChangedFcn = @(src, ~) ...
                panel.onAxisLockChanged(src, controls.value.x, controls.value.y);
        end

        function control = addDropRow(~, grid, row, text, items)
            label = uilabel(grid, 'Text', text);
            label.Layout.Row = row;
            label.Layout.Column = 1;
            control = uidropdown(grid, 'Items', items);
            control.Layout.Row = row;
            control.Layout.Column = [2, 4];
        end

        function control = addTextRow(~, grid, row, text, value)
            label = uilabel(grid, 'Text', text);
            label.Layout.Row = row;
            label.Layout.Column = 1;
            control = uieditfield(grid, 'text', 'Value', value, ...
                'Editable', 'off');
            control.Layout.Row = row;
            control.Layout.Column = [2, 4];
        end

        function button = addRunButton(~, grid, row, text, callback)
            button = uibutton(grid, 'Text', text, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.72, 0.88, 0.72], ...
                'ButtonPushedFcn', callback);
            button.Layout.Row = row;
            button.Layout.Column = [1, 5];
        end

        function onPostTestSelected(panel, selectedButton)
            if ~selectedButton.Value
                selectedButton.Value = true;
                return;
            end
            panel.selectPostTestAction(selectedButton.Text);
        end

        function selectPostTestAction(panel, action)
            panel.postSelection = char(action);
            for index = 1:numel(panel.postButtons)
                selected = strcmp(panel.postButtons(index).Text, ...
                    panel.postSelection);
                panel.postButtons(index).Value = selected;
                if selected
                    panel.postButtons(index).BackgroundColor = ...
                        [0.55, 0.75, 0.95];
                    panel.postButtons(index).FontWeight = 'bold';
                else
                    panel.postButtons(index).BackgroundColor = ...
                        [0.94, 0.94, 0.94];
                    panel.postButtons(index).FontWeight = 'normal';
                end
            end
        end

        function syncAxisPair(~, source, target, lock)
            if lock.Value, target.Value = source.Value; end
        end

        function onAxisLockChanged(~, lock, xField, yField)
            if lock.Value, yField.Value = xField.Value; end
        end

        function setAxisEnabled(panel, controls, enabled)
            panel.setControlEnabled(controls.x, enabled);
            panel.setControlEnabled(controls.y, enabled);
            panel.setControlEnabled(controls.lock, enabled);
        end

        function setAxisByMode(panel, controls, baseEnabled)
            mode = panel.getAxisMode();
            enableX = baseEnabled && ...
                (strcmp(mode, 'Both') || strcmp(mode, 'X only'));
            enableY = baseEnabled && ...
                (strcmp(mode, 'Both') || strcmp(mode, 'Y only'));
            panel.setControlEnabled(controls.x, enableX);
            panel.setControlEnabled(controls.y, enableY);
            panel.setControlEnabled(controls.lock, enableX && enableY);
        end

        function setControlEnabled(~, control, enabled)
            if enabled
                control.Enable = 'on';
            else
                control.Enable = 'off';
            end
        end

        function onAxisModeChanged(panel)
            panel.refreshDependentControls();
            panel.callbacks.axisModeChanged();
            panel.refreshRunButtons();
        end

        function axes = activeAxes(panel)
            switch panel.getAxisMode()
                case 'X only'
                    axes = {'X'};
                case 'Y only'
                    axes = {'Y'};
                otherwise
                    axes = {'X', 'Y'};
            end
        end

        function rows = ordinaryAxisRows(panel)
            rows = {panel.controls.single.primary, ...
                panel.controls.single.rate, panel.controls.single.holdTime, ...
                panel.controls.cyclic.load, panel.controls.cyclic.unload, ...
                panel.controls.cyclic.rate, panel.controls.cyclic.holdTime};
        end

        function loadPreset(panel)
            try
                panel.settings.loadAppConfig(panel.presetDrop.Value);
                cfg = panel.migratePreset(panel.settings.appConfig);
                panel.applyValues(panel.controls, cfg);
                if isfield(cfg, 'post') && isfield(cfg.post, 'afterTest')
                    panel.selectPostTestAction(cfg.post.afterTest);
                else
                    panel.selectPostTestAction( ...
                        'Stay at unchanged position');
                end
                panel.refreshDependentControls();
                panel.callbacks.axisModeChanged();
            catch exception
                uialert(panel.parentFig, exception.message, ...
                    'Cannot load test preset');
            end
        end

        function savePreset(panel, saveAs)
            filename = panel.presetDrop.Value;
            if saveAs
                answer = inputdlg('Preset name:', 'Save test preset', ...
                    [1, 45], {'new_test'});
                if isempty(answer) || isempty(strtrim(answer{1})), return; end
                filename = strtrim(answer{1});
            end
            try
                panel.settings.appConfig = panel.getConfiguration();
                panel.settings.saveAppConfig(filename);
                panel.presetDrop.Items = panel.nonEmptyItems( ...
                    panel.settings.listAppConfigs());
                panel.presetDrop.Value = filename;
            catch exception
                uialert(panel.parentFig, exception.message, ...
                    'Cannot save test preset');
            end
        end

        function cfg = migratePreset(~, cfg)
            if ~isfield(cfg, 'system') || ~isfield(cfg.system, 'axisMode')
                cfg.system.axisMode = 'Both';
            end
            if ~isfield(cfg.pre, 'holdTime')
                cfg.pre.holdTime = struct('x', 0, 'y', 0, 'lock', true);
            end
            if isfield(cfg.pre, 'preload') && ...
                    isfield(cfg.pre.preload, 'value') && ...
                    isnumeric(cfg.pre.preload.value)
                value = cfg.pre.preload.value;
                cfg.pre.preload.value = ...
                    struct('x', value, 'y', value, 'lock', true);
            end
            if isfield(cfg.single, 'stop1Mode')
                cfg.single.primaryMode = cfg.single.stop1Mode;
                cfg.single.primary = cfg.single.stop1;
            end
            if isfield(cfg.single, 'stop2Mode')
                cfg.single.secondaryMode = cfg.single.stop2Mode;
                cfg.single.secondary = cfg.single.stop2;
            end
            if ~isfield(cfg.single, 'primaryMode')
                cfg.single.primaryMode = 'Displacement';
            end
            if ~isfield(cfg.single, 'secondaryMode')
                cfg.single.secondaryMode = 'None';
            end
            if ~isfield(cfg.single, 'holdTime')
                cfg.single.holdTime = ...
                    struct('x', 0, 'y', 0, 'lock', true);
            end
            if ~isfield(cfg.single, 'forceDrop')
                cfg.single.forceDrop = 0;
            end
            if ~isfield(cfg.single, 'failureThreshold')
                cfg.single.failureThreshold = ...
                    struct('x', 0, 'y', 0, 'lock', true);
            end
            if ~isfield(cfg.cyclic, 'holdTime')
                cfg.cyclic.holdTime = ...
                    struct('x', 0, 'y', 0, 'lock', true);
            end
            if ~isfield(cfg.cyclic, 'forceDrop')
                cfg.cyclic.forceDrop = 0;
            end
            if ~isfield(cfg.cyclic, 'failureThreshold')
                cfg.cyclic.failureThreshold = ...
                    struct('x', 0, 'y', 0, 'lock', true);
            end
        end

        function values = collectValues(panel, controls)
            if isstruct(controls)
                values = struct();
                names = fieldnames(controls);
                for index = 1:numel(names)
                    name = names{index};
                    values.(name) = panel.collectValues(controls.(name));
                end
            elseif isprop(controls, 'Value')
                values = controls.Value;
            else
                values = [];
            end
        end

        function applyValues(panel, controls, values)
            if isstruct(controls)
                names = fieldnames(controls);
                for index = 1:numel(names)
                    name = names{index};
                    if isstruct(values) && isfield(values, name)
                        panel.applyValues(controls.(name), values.(name));
                    end
                end
            elseif isprop(controls, 'Value')
                try
                    controls.Value = values;
                catch
                    % Ignore obsolete preset values that are not selectable.
                end
            end
        end

        function refreshDependentControls(panel)
            rows = panel.ordinaryAxisRows();
            for index = 1:numel(rows)
                panel.setAxisByMode(rows{index}, true);
            end
            preCyclic = panel.controls.pre.cyclic.Value;
            preAny = preCyclic || panel.controls.pre.preload.enabled.Value;
            panel.setAxisByMode(panel.controls.pre.rate, preAny);
            panel.setAxisByMode(panel.controls.pre.holdTime, preAny);
            panel.setControlEnabled(panel.controls.pre.cycles, preCyclic);
            panel.setAxisByMode(panel.controls.pre.load, preCyclic);
            panel.setAxisByMode(panel.controls.pre.unload, ...
                preCyclic && ~panel.controls.pre.unloadToStart.Value);
            panel.setControlEnabled(panel.controls.pre.unloadToStart, preCyclic);
            panel.setAxisByMode(panel.controls.pre.preload.value, ...
                panel.controls.pre.preload.enabled.Value);
            panel.setAxisByMode(panel.controls.single.secondary, ...
                ~strcmp(panel.controls.single.secondaryMode.Value, 'None'));
            singleForce = strcmp(panel.controls.single.primaryMode.Value, 'Force');
            panel.setControlEnabled(panel.controls.single.forceDrop, singleForce);
            panel.setAxisByMode(panel.controls.single.failureThreshold, singleForce);
            cyclicForce = strcmp(panel.controls.cyclic.loadMode.Value, 'Force') || ...
                strcmp(panel.controls.cyclic.unloadMode.Value, 'Force');
            panel.setControlEnabled(panel.controls.cyclic.forceDrop, cyclicForce);
            panel.setAxisByMode(panel.controls.cyclic.failureThreshold, cyclicForce);
            panel.setControlEnabled(panel.controls.pre.cameraPeriod.value, ...
                panel.controls.pre.cameraPeriod.enabled.Value);
            panel.setControlEnabled(panel.controls.single.cameraPeriod.value, ...
                panel.controls.single.cameraPeriod.enabled.Value);
            panel.setControlEnabled(panel.controls.cyclic.cameraPeriod.value, ...
                panel.controls.cyclic.cameraPeriod.enabled.Value);
            panel.refreshRunButtons();
        end

        function onBrowseGeneralTest(panel)
            [file, folder] = uigetfile({'*.json', ...
                'General Test JSON (*.json)'});
            if isequal(file, 0), return; end
            filename = fullfile(folder, file);
            try
                definition = GeneralTestDefinition.load(filename);
                panel.generalDefinition = definition;
                panel.controls.general.testFile.Value = filename;
                panel.generalSummary.Value = ...
                    {GeneralTestDefinition.summary(definition)};
                switch lower(char(definition.axisMode))
                    case 'x'
                        panel.axisModeDrop.Value = 'X only';
                    case 'y'
                        panel.axisModeDrop.Value = 'Y only';
                    otherwise
                        panel.axisModeDrop.Value = 'Both';
                end
                panel.callbacks.axisModeChanged();
                panel.generalRun.Tooltip = ...
                    'The imported definition is complete and authoritative.';
            catch exception
                panel.generalDefinition = [];
                panel.controls.general.testFile.Value = filename;
                panel.generalSummary.Value = ...
                    {['Invalid file: ', exception.message]};
                panel.generalRun.Tooltip = exception.message;
                uialert(panel.parentFig, exception.message, ...
                    'Invalid General Test');
            end
            panel.refreshRunButtons();
        end

        function refreshRunButtons(panel)
            for index = 1:numel(panel.runButtons)
                panel.setControlEnabled(panel.runButtons(index), ...
                    panel.machineRunAllowed);
            end
            if ~isempty(panel.preRun) && isvalid(panel.preRun)
                preSelected = panel.controls.pre.cyclic.Value || ...
                    panel.controls.pre.preload.enabled.Value;
                panel.setControlEnabled(panel.preRun, ...
                    panel.machineRunAllowed && preSelected);
            end
            if ~isempty(panel.generalRun) && isvalid(panel.generalRun)
                panel.setControlEnabled(panel.generalRun, ...
                    panel.generalMachineAllowed && ...
                    ~isempty(panel.generalDefinition));
            end
        end

        function items = nonEmptyItems(~, items)
            if isempty(items), items = {'default'}; end
        end
    end
end
