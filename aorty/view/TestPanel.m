classdef TestPanel < handle
    %TESTPANEL Test definition tabs, presets, and active-axis selection.

    properties (SetAccess = private)
        tabs
    end

    properties (Access = private)
        settings Settings
        parentFig
        callbacks = struct()
        controls = struct()
        uiState = struct()
        presetDrop
        axisModeDrop
        postButtons
        postSelection = 'Stay at unchanged position'
    end

    methods
        % TestPanel handles this operation.
        function panel = TestPanel(settings, parentFig, callbacks)
            panel.settings = settings;
            panel.parentFig = parentFig;
            panel.callbacks = callbacks;
        end

        % createToolbarControls handles this operation.
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
                'Items', {'Both', 'X only', 'Y only'}, ...
                'Value', 'Both', ...
                'ValueChangedFcn', @(~, ~) panel.onAxisModeChanged());
            panel.controls.system.axisMode = panel.axisModeDrop;
        end

        % create handles this operation.
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
        end

        % getConfiguration handles this operation.
        function config = getConfiguration(panel)
            config = panel.collectValues(panel.controls);
            config.post.afterTest = panel.postSelection;
        end

        % getAxisMode handles this operation.
        function mode = getAxisMode(panel)
            mode = char(panel.axisModeDrop.Value);
        end

        % getPostTestAction handles this operation.
        function action = getPostTestAction(panel)
            action = panel.postSelection;
        end

        % isAxisActive handles this operation.
        function enabled = isAxisActive(panel, axisName)
            mode = panel.getAxisMode();
            enabled = strcmp(mode, 'Both') || ...
                strcmp(mode, [upper(char(axisName)), ' only']);
        end
    end

    methods (Access = private)
        % createPreTestTab handles this operation.
        function createPreTestTab(panel, tab)
            grid = panel.createFormGrid(tab, 10);
            panel.controls.pre.rate = panel.addAxisRow(grid, 2, 'Pre-test rate', 1, '[mm/s]');
            panel.controls.pre.cyclic = panel.addCheckRow(grid, 3, 'Cyclic pre-conditioning', false);
            panel.controls.pre.cycles = panel.addNumericRow(grid, 4, 'Number of cycles', 1, '[cyc.]');
            panel.controls.pre.load = panel.addAxisRow(grid, 5, 'Load level', 0, '[N]');
            panel.controls.pre.unload = panel.addAxisRow(grid, 6, 'Unload level', 0, '[N]');
            panel.controls.pre.unloadToStart = panel.addCheckRow(grid, 7, 'Unload to start position', false);
            panel.controls.pre.preload = panel.addOptionalRow(grid, 8, 'Pre-load', 0, '[N]');
            panel.controls.pre.cameraPeriod = panel.addOptionalRow(grid, 9, 'Camera sampling period', 0.1, '[s]');
            panel.addRunButton(grid, 10, 'RUN PRE-TEST', panel.callbacks.runPre);
            panel.controls.pre.unloadToStart.ValueChangedFcn = ...
                @(~, ~) panel.refreshDependentControls();
        end

        % createSingleTestTab handles this operation.
        function createSingleTestTab(panel, tab)
            grid = panel.createFormGrid(tab, 12);
            panel.controls.single.includePre = panel.addCheckRow(grid, 2, 'Include pre-test', false);
            panel.controls.single.mode = panel.addDropRow(grid, 3, 'Test mode', ...
                {'Displacement controlled', 'Force controlled', 'Strain controlled'});
            panel.controls.single.rate = panel.addAxisRow(grid, 4, 'Test rate', 1, '[mode/s]');
            panel.controls.single.stop1Mode = panel.addDropRow(grid, 5, 'Stop criterion 1', ...
                {'Displacement', 'Force'});
            panel.controls.single.stop1 = panel.addAxisRow(grid, 6, 'Criterion 1 value', 0, '[mm/N]');
            panel.controls.single.stop2Mode = panel.addDropRow(grid, 7, 'Stop criterion 2 (or)', ...
                {'None', 'Displacement', 'Force'});
            panel.controls.single.stop2 = panel.addAxisRow(grid, 8, 'Criterion 2 value', 0, '[mm/N]');
            panel.controls.single.stopAtFailure = panel.addCheckRow(grid, 9, 'Stop at failure', false);
            panel.controls.single.forceDrop = panel.addNumericRow(grid, 10, 'Force drop', 10, '[%]');
            panel.controls.single.failureThreshold = panel.addAxisRow(grid, 11, 'Above threshold', 0, '[N]');
            panel.controls.single.cameraPeriod = panel.addOptionalRow(grid, 12, 'Camera sampling period', 0.1, '[s]');

            panel.uiState.singleRun = uibutton(grid, 'Text', 'RUN TEST', ...
                'FontWeight', 'bold', 'BackgroundColor', [0.72, 0.88, 0.72], ...
                'ButtonPushedFcn', panel.callbacks.runSingle);
            panel.uiState.singleRun.Layout.Row = 13;
            panel.uiState.singleRun.Layout.Column = [1, 5];
            grid.RowHeight{13} = 38;

            panel.controls.single.stopAtFailure.ValueChangedFcn = ...
                @(~, ~) panel.refreshDependentControls();
            panel.controls.single.stopAtFailure.Value = false;
            panel.controls.single.stopAtFailure.Enable = 'off';
            panel.controls.single.stopAtFailure.Tooltip = ...
                'Force-drop failure detection is not available yet.';
            panel.controls.single.mode.Tooltip = ...
                'Strain-controlled testing is not available yet.';
            panel.controls.single.stop2Mode.ValueChangedFcn = ...
                @(~, ~) panel.refreshDependentControls();
            panel.setFailureControlsEnabled(false);
            panel.setAxisEnabled(panel.controls.single.stop2, false);
        end

        % createCyclicTestTab handles this operation.
        function createCyclicTestTab(panel, tab)
            grid = panel.createFormGrid(tab, 9);
            panel.controls.cyclic.includePre = panel.addCheckRow(grid, 2, 'Include pre-test', false);
            panel.controls.cyclic.cycles = panel.addNumericRow(grid, 3, 'Number of cycles', 1, '[cyc.]');
            panel.controls.cyclic.rate = panel.addAxisRow(grid, 4, 'Test rate', 1, '[mode/s]');
            panel.controls.cyclic.loadMode = panel.addDropRow(grid, 5, 'Load level mode', ...
                {'Displacement', 'Force'});
            panel.controls.cyclic.load = panel.addAxisRow(grid, 6, 'Load level', 0, '[mm/N]');
            panel.controls.cyclic.unloadMode = panel.addDropRow(grid, 7, 'Unload level mode', ...
                {'Displacement', 'Force'});
            panel.controls.cyclic.unload = panel.addAxisRow(grid, 8, 'Unload level', 0, '[mm/N]');
            panel.controls.cyclic.cameraPeriod = panel.addOptionalRow(grid, 9, 'Camera sampling period', 0.1, '[s]');
            panel.addRunButton(grid, 10, 'RUN CYCLIC TEST', panel.callbacks.runCyclic);
        end

        % createGeneralTestTab handles this operation.
        function createGeneralTestTab(panel, tab)
            grid = panel.createFormGrid(tab, 6);
            panel.controls.general.includePre = panel.addCheckRow(grid, 2, 'Include pre-test', false);
            panel.controls.general.testFile = panel.addTextRow(grid, 3, 'Imported test file', 'No file selected');
            browse = uibutton(grid, 'Text', 'Browse', ...
                'ButtonPushedFcn', @(~, ~) panel.onBrowseGeneralTest());
            browse.Layout.Row = 3;
            browse.Layout.Column = 5;
            panel.controls.general.importCameraPeriod = panel.addOptionalRow(grid, 4, ...
                'Import camera sampling period', 0.1, '[s]');
            panel.controls.general.cameraPeriod = panel.addOptionalRow(grid, 5, ...
                'Camera sampling period', 0.1, '[s]');
            panel.uiState.generalRun = panel.addRunButton(grid, 6, ...
                'RUN GENERAL TEST', panel.callbacks.runGeneral);
            panel.uiState.generalRun.Enable = 'off';
            panel.uiState.generalRun.Tooltip = ...
                'General Test import is not available yet.';
        end

        % createPostTestTab handles this operation.
        function createPostTestTab(panel, tab)
            grid = uigridlayout(tab, [2, 1]);
            grid.RowHeight = {28, '1x'};
            grid.Padding = [12, 12, 12, 12];
            uilabel(grid, 'Text', 'After test:', 'FontWeight', 'bold');
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
                    'ValueChangedFcn', @(src, ~) panel.onPostTestSelected(src));
            end
            panel.selectPostTestAction('Stay at unchanged position');
        end

        % createFormGrid handles this operation.
        function grid = createFormGrid(~, tab, rows)
            grid = uigridlayout(tab, [rows + 1, 5]);
            grid.ColumnWidth = {170, '1x', '1x', 60, 48};
            grid.RowHeight = repmat({34}, 1, rows + 1);
            grid.Padding = [10, 10, 10, 10];
            grid.RowSpacing = 5;
            uilabel(grid, 'Text', 'Parameter', 'FontWeight', 'bold');
            uilabel(grid, 'Text', 'X', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
            uilabel(grid, 'Text', 'Y', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
            uilabel(grid, 'Text', 'Unit', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
            uilabel(grid, 'Text', 'Lock', 'FontWeight', 'bold', 'HorizontalAlignment', 'center');
        end

        % addAxisRow handles this operation.
        function controls = addAxisRow(panel, grid, row, text, value, unit)
            label = uilabel(grid, 'Text', text);
            label.Layout.Row = row; label.Layout.Column = 1;
            controls.x = uieditfield(grid, 'numeric', 'Value', value);
            controls.x.Layout.Row = row; controls.x.Layout.Column = 2;
            controls.y = uieditfield(grid, 'numeric', 'Value', value);
            controls.y.Layout.Row = row; controls.y.Layout.Column = 3;
            unitLabel = uilabel(grid, 'Text', unit, 'HorizontalAlignment', 'center');
            unitLabel.Layout.Row = row; unitLabel.Layout.Column = 4;
            controls.lock = uibutton(grid, 'state', 'Text', 'XY', 'Value', true);
            controls.lock.Layout.Row = row; controls.lock.Layout.Column = 5;
            controls.x.ValueChangedFcn = ...
                @(src, ~) panel.syncAxisPair(src, controls.y, controls.lock);
            controls.y.ValueChangedFcn = ...
                @(src, ~) panel.syncAxisPair(src, controls.x, controls.lock);
            controls.lock.ValueChangedFcn = ...
                @(src, ~) panel.onAxisLockChanged(src, controls.x, controls.y);
        end

        % addNumericRow handles this operation.
        function control = addNumericRow(~, grid, row, text, value, unit)
            label = uilabel(grid, 'Text', text);
            label.Layout.Row = row; label.Layout.Column = 1;
            control = uieditfield(grid, 'numeric', 'Value', value);
            control.Layout.Row = row; control.Layout.Column = [2, 3];
            unitLabel = uilabel(grid, 'Text', unit, 'HorizontalAlignment', 'center');
            unitLabel.Layout.Row = row; unitLabel.Layout.Column = 4;
        end

        % addCheckRow handles this operation.
        function control = addCheckRow(~, grid, row, text, value)
            control = uicheckbox(grid, 'Text', text, 'Value', value);
            control.Layout.Row = row; control.Layout.Column = [1, 4];
        end

        % addOptionalRow handles this operation.
        function controls = addOptionalRow(panel, grid, row, text, value, unit)
            controls.enabled = uicheckbox(grid, 'Text', text, 'Value', false);
            controls.enabled.Layout.Row = row; controls.enabled.Layout.Column = 1;
            controls.value = uieditfield(grid, 'numeric', ...
                'Value', value, 'Enable', 'off');
            controls.value.Layout.Row = row; controls.value.Layout.Column = [2, 3];
            unitLabel = uilabel(grid, 'Text', unit, 'HorizontalAlignment', 'center');
            unitLabel.Layout.Row = row; unitLabel.Layout.Column = 4;
            controls.enabled.ValueChangedFcn = ...
                @(src, ~) panel.setControlEnabled(controls.value, src.Value);
        end

        % addDropRow handles this operation.
        function control = addDropRow(~, grid, row, text, items)
            label = uilabel(grid, 'Text', text);
            label.Layout.Row = row; label.Layout.Column = 1;
            control = uidropdown(grid, 'Items', items);
            control.Layout.Row = row; control.Layout.Column = [2, 4];
        end

        % addTextRow handles this operation.
        function control = addTextRow(~, grid, row, text, value)
            label = uilabel(grid, 'Text', text);
            label.Layout.Row = row; label.Layout.Column = 1;
            control = uieditfield(grid, 'text', 'Value', value, 'Editable', 'off');
            control.Layout.Row = row; control.Layout.Column = [2, 4];
        end

        % addRunButton handles this operation.
        function button = addRunButton(~, grid, row, text, callback)
            button = uibutton(grid, 'Text', text, 'FontWeight', 'bold', ...
                'BackgroundColor', [0.72, 0.88, 0.72], ...
                'ButtonPushedFcn', callback);
            button.Layout.Row = row; button.Layout.Column = [1, 5];
        end

        % onPostTestSelected handles this operation.
        function onPostTestSelected(panel, selectedButton)
            if ~selectedButton.Value
                selectedButton.Value = true;
                return;
            end
            panel.selectPostTestAction(selectedButton.Text);
        end

        % selectPostTestAction handles this operation.
        function selectPostTestAction(panel, action)
            panel.postSelection = char(action);
            for index = 1:numel(panel.postButtons)
                selected = strcmp(panel.postButtons(index).Text, panel.postSelection);
                panel.postButtons(index).Value = selected;
                if selected
                    panel.postButtons(index).BackgroundColor = [0.55, 0.75, 0.95];
                    panel.postButtons(index).FontWeight = 'bold';
                else
                    panel.postButtons(index).BackgroundColor = [0.94, 0.94, 0.94];
                    panel.postButtons(index).FontWeight = 'normal';
                end
            end
        end

        % syncAxisPair handles this operation.
        function syncAxisPair(~, source, target, lock)
            if lock.Value, target.Value = source.Value; end
        end

        % onAxisLockChanged handles this operation.
        function onAxisLockChanged(~, lock, xField, yField)
            if lock.Value, yField.Value = xField.Value; end
        end

        % setAxisEnabled handles this operation.
        function setAxisEnabled(panel, controls, enabled)
            panel.setControlEnabled(controls.x, enabled);
            panel.setControlEnabled(controls.y, enabled);
            panel.setControlEnabled(controls.lock, enabled);
        end

        % setFailureControlsEnabled handles this operation.
        function setFailureControlsEnabled(panel, enabled)
            %#ok<INUSD> Force-drop detection is intentionally unavailable.
            panel.setControlEnabled(panel.controls.single.forceDrop, false);
            panel.setAxisEnabled(panel.controls.single.failureThreshold, false);
        end

        % setControlEnabled handles this operation.
        function setControlEnabled(~, control, enabled)
            if enabled, control.Enable = 'on'; else, control.Enable = 'off'; end
        end

        % onAxisModeChanged handles this operation.
        function onAxisModeChanged(panel)
            panel.refreshDependentControls();
            panel.callbacks.axisModeChanged();
        end

        % getAxisRows handles this operation.
        function rows = getAxisRows(panel)
            rows = {panel.controls.pre.rate, panel.controls.pre.load, ...
                panel.controls.pre.unload, panel.controls.single.rate, ...
                panel.controls.single.stop1, panel.controls.single.stop2, ...
                panel.controls.single.failureThreshold, panel.controls.cyclic.rate, ...
                panel.controls.cyclic.load, panel.controls.cyclic.unload};
        end

        % applyAxisMode handles this operation.
        function applyAxisMode(panel)
            mode = panel.getAxisMode();
            enableX = strcmp(mode, 'Both') || strcmp(mode, 'X only');
            enableY = strcmp(mode, 'Both') || strcmp(mode, 'Y only');
            rows = panel.getAxisRows();
            for index = 1:numel(rows)
                controls = rows{index};
                baseEnabled = strcmp(controls.x.Enable, 'on') && ...
                    strcmp(controls.y.Enable, 'on');
                panel.setControlEnabled(controls.x, baseEnabled && enableX);
                panel.setControlEnabled(controls.y, baseEnabled && enableY);
                panel.setControlEnabled(controls.lock, ...
                    baseEnabled && enableX && enableY);
            end
        end

        % loadPreset handles this operation.
        function loadPreset(panel)
            try
                panel.settings.loadAppConfig(panel.presetDrop.Value);
                cfg = panel.settings.appConfig;
                if ~isfield(cfg, 'system') || ~isfield(cfg.system, 'axisMode')
                    cfg.system.axisMode = 'Both';
                end
                panel.applyValues(panel.controls, cfg);
                panel.controls.single.stopAtFailure.Value = false;
                if strcmp(panel.controls.single.mode.Value, 'Strain controlled')
                    panel.controls.single.mode.Value = 'Displacement controlled';
                end
                if isfield(cfg, 'post') && isfield(cfg.post, 'afterTest')
                    panel.selectPostTestAction(cfg.post.afterTest);
                else
                    panel.selectPostTestAction('Stay at unchanged position');
                end
                panel.refreshDependentControls();
                panel.callbacks.axisModeChanged();
            catch exception
                uialert(panel.parentFig, exception.message, 'Cannot load test preset');
            end
        end

        % savePreset handles this operation.
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
                uialert(panel.parentFig, exception.message, 'Cannot save test preset');
            end
        end

        % collectValues handles this operation.
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

        % applyValues handles this operation.
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
                controls.Value = values;
            end
        end

        % refreshDependentControls handles this operation.
        function refreshDependentControls(panel)
            rows = panel.getAxisRows();
            for index = 1:numel(rows), panel.setAxisEnabled(rows{index}, true); end
            panel.setAxisEnabled(panel.controls.pre.unload, ...
                ~panel.controls.pre.unloadToStart.Value);
            panel.setFailureControlsEnabled(panel.controls.single.stopAtFailure.Value);
            panel.setAxisEnabled(panel.controls.single.stop2, ...
                ~strcmp(panel.controls.single.stop2Mode.Value, 'None'));
            panel.refreshOptionalGroup(panel.controls.pre.preload);
            panel.refreshOptionalGroup(panel.controls.pre.cameraPeriod);
            panel.refreshOptionalGroup(panel.controls.single.cameraPeriod);
            panel.refreshOptionalGroup(panel.controls.cyclic.cameraPeriod);
            panel.refreshOptionalGroup(panel.controls.general.importCameraPeriod);
            panel.refreshOptionalGroup(panel.controls.general.cameraPeriod);
            panel.applyAxisMode();
        end

        % refreshOptionalGroup handles this operation.
        function refreshOptionalGroup(panel, controls)
            panel.setControlEnabled(controls.value, controls.enabled.Value);
        end

        % onBrowseGeneralTest handles this operation.
        function onBrowseGeneralTest(panel)
            [file, folder] = uigetfile({'*.csv;*.txt;*.json', 'Test definition files'});
            if isequal(file, 0), return; end
            panel.controls.general.testFile.Value = fullfile(folder, file);
        end

        % nonEmptyItems handles this operation.
        function items = nonEmptyItems(~, items)
            if isempty(items), items = {'default'}; end
        end
    end
end


