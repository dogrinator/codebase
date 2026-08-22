classdef SettingsWindow < handle
    %SETTINGSWINDOW Edits and applies the fixed stand hardware configuration.
    % The window binds numeric UI fields to the Settings hardware schema.

    properties (SetAccess = private)
        % Settings dependency and window ownership
        settings Settings
        parentFig
        fig
        settingsChanged
    end

    properties (Access = private)
        % Controls bound to camera and per-axis configuration fields
        configDrop
        camUI = struct()
        plcXUI = struct()
        plcYUI = struct()
        applyButton
        editControls = gobjects(0)
        machineIdle = true
    end

    methods
        %% Window lifecycle and machine-idle interlock
        function window = SettingsWindow(settings, parentFig, settingsChanged)
            window.settings = settings;
            window.parentFig = parentFig;
            if nargin < 3
                settingsChanged = [];
            end
            window.settingsChanged = settingsChanged;
        end

        function show(window)
            % Reuse the existing figure so repeated opens preserve user input.
            if window.isOpen()
                figure(window.fig);
                return;
            end

            window.ensureConfigLoaded();
            window.fig = uifigure( ...
                'Name', 'Hardware configuration', ...
                'Position', [350, 150, 700, 660], ...
                'CloseRequestFcn', @(~, ~) window.close());

            root = uigridlayout(window.fig, [3, 1]);
            root.RowHeight = {48, '1x', 48};
            root.Padding = [10, 10, 10, 10];
            root.RowSpacing = 8;

            top = uigridlayout(root, [1, 3]);
            top.ColumnWidth = {'1x', 70, 85};
            top.Padding = 0;
            window.configDrop = uidropdown(top, ...
                'Items', window.nonEmptyItems(window.settings.listHwConfigs()), ...
                'ValueChangedFcn', @(~, ~) window.loadConfig());
            selected = window.settings.activeHwConfigName;
            if isempty(selected) && ismember('default', window.configDrop.Items)
                selected = 'default';
            end
            if ~isempty(selected) && ismember(selected, window.configDrop.Items)
                window.configDrop.Value = selected;
            end
            saveButton = uibutton(top, 'Text', 'Save', ...
                'ButtonPushedFcn', @(~, ~) window.saveConfig(false));
            saveAsButton = uibutton(top, 'Text', 'Save as', ...
                'ButtonPushedFcn', @(~, ~) window.saveConfig(true));

            tabs = uitabgroup(root);
            cameraTab = uitab(tabs, 'Title', 'Camera');
            xTab = uitab(tabs, 'Title', 'X Axis');
            yTab = uitab(tabs, 'Title', 'Y Axis');

            cfg = window.settings.hwConfig;
            window.camUI = window.createConfigFields(cameraTab, cfg.camera, ...
                {'exposureTimeAbs', 'gainRaw', 'acquisitionFrameRateAbs'});
            window.plcXUI = window.createAxisConfigFields(xTab, cfg.plc.xAxis);
            window.plcYUI = window.createAxisConfigFields(yTab, cfg.plc.yAxis);

            bottom = uigridlayout(root, [1, 1]);
            bottom.ColumnWidth = {'1x'};
            bottom.Padding = 0;
            window.applyButton = uibutton(bottom, 'Text', 'Apply settings', ...
                'FontWeight', 'bold', 'BackgroundColor', [0.72, 0.9, 0.72], ...
                'ButtonPushedFcn', @(~, ~) window.applySettings());
            window.editControls = [window.configDrop, saveButton, ...
                saveAsButton, window.applyButton, ...
                window.configFieldHandles(window.camUI), ...
                window.configFieldHandles(window.plcXUI), ...
                window.configFieldHandles(window.plcYUI)];
            window.refreshUI();
            window.setMachineIdle(window.machineIdle);
        end

        function close(window)
            if window.isOpen()
                window.fig.CloseRequestFcn = '';
                delete(window.fig);
            end
            window.fig = [];
            window.configDrop = [];
            window.camUI = struct();
            window.plcXUI = struct();
            window.plcYUI = struct();
            window.applyButton = [];
            window.editControls = gobjects(0);
            restoreFigureFocus(window.parentFig);
        end

        function value = isOpen(window)
            value = ~isempty(window.fig) && isvalid(window.fig);
        end

        function setMachineIdle(window, idle)
            % Hardware configuration is immutable while either axis is active.
            window.machineIdle = logical(idle);
            for index = 1:numel(window.editControls)
                if isvalid(window.editControls(index))
                    if window.machineIdle
                        window.editControls(index).Enable = 'on';
                    else
                        window.editControls(index).Enable = 'off';
                    end
                end
            end
        end
    end

    methods (Access = private)
        %% Configuration field construction and synchronization
        function ensureConfigLoaded(window)
            if ~isempty(window.settings.hwConfig)
                return;
            end
            try
                window.settings.loadHwConfig('default');
            catch exception
                uialert(window.parentFig, exception.message, ...
                    'Cannot load hardware configuration');
                error('SettingsWindow:MissingHardwareConfig', '%s', exception.message);
            end
        end

        function fields = createAxisConfigFields(window, tab, config)
            layout = uigridlayout(tab, [2, 1]);
            layout.RowHeight = {125, '1x'};
            layout.Padding = [8, 8, 8, 8];
            layout.RowSpacing = 8;

            tenzoPanel = uipanel(layout, 'Title', 'Tenzo settings');
            motorPanel = uipanel(layout, 'Title', 'Motor settings');
            tenzoNames = {'fTenzoOffset', 'fTenzoCons'};
            hiddenNames = {'fKi', 'fIntegralLimit'};
            motorOrder = {'fKp', 'fForceTolerance', ...
                'fMaxVelocity', 'fMaxForce', 'fForceReliefDistance', ...
                'fForceReliefVelocity'};
            allNames = fieldnames(config)';
            motorNames = [motorOrder, setdiff(allNames, ...
                [tenzoNames, motorOrder, hiddenNames], 'stable')];

            fields = window.createConfigFields(tenzoPanel, config, tenzoNames);
            motorFields = window.createConfigFields(motorPanel, config, motorNames);
            names = fieldnames(motorFields);
            for index = 1:numel(names)
                fields.(names{index}) = motorFields.(names{index});
            end
        end

        function fields = createConfigFields(window, parent, config, preferredOrder)
            availableNames = fieldnames(config);
            names = preferredOrder(ismember(preferredOrder, availableNames));
            grid = uigridlayout(parent, [numel(names), 3]);
            grid.ColumnWidth = {220, '1x', 90};
            grid.RowHeight = repmat({34}, 1, numel(names));
            grid.Padding = [12, 12, 12, 12];
            grid.Scrollable = 'on';
            fields = struct();
            for index = 1:numel(names)
                name = names{index};
                [label, unit] = window.fieldPresentation(name);
                uilabel(grid, 'Text', label, ...
                    'HorizontalAlignment', 'right');
                fields.(name) = uieditfield(grid, 'numeric', ...
                    'Value', config.(name));
                uilabel(grid, 'Text', unit, ...
                    'HorizontalAlignment', 'left');
                window.configureVisibleLimit(fields.(name), name);
            end
        end

        function refreshUI(window)
            cfg = window.settings.hwConfig;
            window.pushFields(window.camUI, cfg.camera);
            window.pushFields(window.plcXUI, cfg.plc.xAxis);
            window.pushFields(window.plcYUI, cfg.plc.yAxis);
        end

        function pushFields(~, fields, config)
            names = fieldnames(fields);
            for index = 1:numel(names)
                name = names{index};
                if isfield(config, name)
                    fields.(name).Value = config.(name);
                end
            end
        end

        function config = pullFields(~, fields, config)
            names = fieldnames(fields);
            for index = 1:numel(names)
                name = names{index};
                config.(name) = fields.(name).Value;
            end
        end

        %% Configuration persistence and application
        function loadConfig(window)
            try
                window.settings.loadHwConfig(window.configDrop.Value);
                window.refreshUI();
                window.notifySettingsChanged();
            catch exception
                uialert(window.fig, exception.message, 'Cannot load configuration');
            end
        end

        function saveConfig(window, saveAs)
            if ~window.machineIdle
                uialert(window.fig, ...
                    'Hardware settings can only be changed while idle.', ...
                    'Machine active');
                return;
            end
            filename = window.configDrop.Value;
            if saveAs
                answer = inputdlg('Configuration name:', ...
                    'Save hardware configuration', [1, 45], {'new_hardware'});
                restoreFigureFocus(window.fig);
                if isempty(answer) || isempty(strtrim(answer{1}))
                    return;
                end
                filename = strtrim(answer{1});
            end
            try
                window.gatherConfig();
                window.settings.saveHwConfig(filename);
                window.configDrop.Items = window.nonEmptyItems( ...
                    window.settings.listHwConfigs());
                window.configDrop.Value = filename;
                window.notifySettingsChanged();
            catch exception
                uialert(window.fig, exception.message, 'Cannot save configuration');
            end
        end

        function gatherConfig(window)
            % Pull every visible value into Settings as one atomic snapshot.
            cfg = window.settings.hwConfig;
            cfg.camera = window.pullFields(window.camUI, cfg.camera);
            cfg.plc.xAxis = window.pullFields(window.plcXUI, cfg.plc.xAxis);
            cfg.plc.yAxis = window.pullFields(window.plcYUI, cfg.plc.yAxis);
            window.settings.hwConfig = cfg;
        end

        function applySettings(window)
            if ~window.machineIdle
                uialert(window.fig, ...
                    'Hardware settings can only be applied while idle.', ...
                    'Machine active');
                return;
            end
            try
                window.gatherConfig();
                window.settings.applyCameraConfig();
                window.settings.applyPlcConfig();
                window.settings.rememberHwConfig();
                window.notifySettingsChanged();
            catch exception
                uialert(window.fig, exception.message, 'Cannot apply configuration');
            end
        end

        %% UI helpers
        function items = nonEmptyItems(~, items)
            if isempty(items)
                items = {'default'};
            end
        end

        function [label, unit] = fieldPresentation(~, name)
            labels = struct( ...
                'exposureTimeAbs', 'Exposure time', ...
                'gainRaw', 'Camera gain', ...
                'acquisitionFrameRateAbs', 'Frame rate', ...
                'fTenzoOffset', 'Force sensor offset', ...
                'fTenzoCons', 'Force calibration', ...
                'fKp', 'Proportional gain', ...
                'fKi', 'Integral gain', ...
                'fIntegralLimit', 'Integral limit', ...
                'fForceTolerance', 'Minimum force tolerance', ...
                'fMaxVelocity', 'Maximum velocity', ...
                'fMaxForce', 'Maximum force', ...
                'fForceReliefDistance', 'Force relief distance', ...
                'fForceReliefVelocity', 'Force relief velocity');
            units = struct( ...
                'exposureTimeAbs', 'us', ...
                'gainRaw', 'raw', ...
                'acquisitionFrameRateAbs', 'frames/s', ...
                'fTenzoOffset', 'N', ...
                'fTenzoCons', 'N/count', ...
                'fKp', 'mm/(s N)', ...
                'fKi', 'mm/(N s^2)', ...
                'fIntegralLimit', 'N s', ...
                'fForceTolerance', 'N', ...
                'fMaxVelocity', 'mm/s', ...
                'fMaxForce', 'N', ...
                'fForceReliefDistance', 'mm', ...
                'fForceReliefVelocity', 'mm/s');
            if isfield(labels, name)
                label = labels.(name);
                unit = units.(name);
                return;
            end
            label = regexprep(name, '([a-z])([A-Z])', '$1 $2');
            label = [upper(label(1)), label(2:end)];
            unit = '-';
        end

        function handles = configFieldHandles(~, fields)
            names = fieldnames(fields);
            handles = gobjects(1, numel(names));
            for index = 1:numel(names)
                handles(index) = fields.(names{index});
            end
        end

        function configureVisibleLimit(~, control, name)
            positive = {'exposureTimeAbs', 'acquisitionFrameRateAbs', ...
                'fMaxVelocity', 'fMaxForce', 'fForceReliefDistance', ...
                'fForceReliefVelocity'};
            nonnegative = {'gainRaw', 'fIntegralLimit', ...
                'fForceTolerance'};
            if ismember(name, positive)
                control.Limits = [0, Inf];
                control.LowerLimitInclusive = 'off';
                control.Tooltip = 'Value must be greater than 0.';
            elseif ismember(name, nonnegative)
                control.Limits = [0, Inf];
                control.Tooltip = 'Value must be 0 or greater.';
            end
        end

        function notifySettingsChanged(window)
            if ~isempty(window.settingsChanged)
                window.settingsChanged();
            end
        end
    end
end
