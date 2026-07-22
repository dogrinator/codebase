classdef SettingsWindow < handle
    %SETTINGSWINDOW Hardware configuration window and field binding.

    properties (SetAccess = private)
        settings Settings
        parentFig
        fig
    end

    properties (Access = private)
        configDrop
        camUI = struct()
        plcXUI = struct()
        plcYUI = struct()
    end

    methods
        % SettingsWindow handles this operation.
        function window = SettingsWindow(settings, parentFig)
            window.settings = settings;
            window.parentFig = parentFig;
        end

        % show handles this operation.
        function show(window)
            if window.isOpen()
                figure(window.fig);
                return;
            end

            window.ensureConfigLoaded();
            window.fig = uifigure( ...
                'Name', 'Hardware configuration', ...
                'Position', [350, 150, 620, 660], ...
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
            if ismember('default', window.configDrop.Items)
                window.configDrop.Value = 'default';
            end
            window.settings.loadHwConfig(window.configDrop.Value);
            window.ensureTenzoOffsets();
            uibutton(top, 'Text', 'Save', ...
                'ButtonPushedFcn', @(~, ~) window.saveConfig(false));
            uibutton(top, 'Text', 'Save as', ...
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
            uibutton(bottom, 'Text', 'Apply settings', ...
                'FontWeight', 'bold', 'BackgroundColor', [0.72, 0.9, 0.72], ...
                'ButtonPushedFcn', @(~, ~) window.applySettings());
            window.refreshUI();
        end

        % close handles this operation.
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
        end

        % isOpen handles this operation.
        function value = isOpen(window)
            value = ~isempty(window.fig) && isvalid(window.fig);
        end
    end

    methods (Access = private)
        % ensureConfigLoaded handles this operation.
        function ensureConfigLoaded(window)
            if ~isempty(window.settings.hwConfig)
                window.ensureTenzoOffsets();
                return;
            end
            try
                window.settings.loadHwConfig('default');
                window.ensureTenzoOffsets();
            catch exception
                uialert(window.parentFig, exception.message, ...
                    'Cannot load hardware configuration');
                error('SettingsWindow:MissingHardwareConfig', '%s', exception.message);
            end
        end

        % createAxisConfigFields handles this operation.
        function fields = createAxisConfigFields(window, tab, config)
            layout = uigridlayout(tab, [2, 1]);
            layout.RowHeight = {125, '1x'};
            layout.Padding = [8, 8, 8, 8];
            layout.RowSpacing = 8;

            tenzoPanel = uipanel(layout, 'Title', 'Tenzo settings');
            motorPanel = uipanel(layout, 'Title', 'Motor settings');
            tenzoNames = {'fTenzoOffset', 'fTenzoCons'};
            motorOrder = {'fKp', 'fKi', 'fIntegralLimit', 'fForceTolerance', ...
                'fMaxVelocity', 'fMaxForce', 'fMaxPosition'};
            allNames = fieldnames(config)';
            motorNames = [motorOrder, setdiff(allNames, ...
                [tenzoNames, motorOrder], 'stable')];

            fields = window.createConfigFields(tenzoPanel, config, tenzoNames);
            motorFields = window.createConfigFields(motorPanel, config, motorNames);
            names = fieldnames(motorFields);
            for index = 1:numel(names)
                fields.(names{index}) = motorFields.(names{index});
            end
        end

        % createConfigFields handles this operation.
        function fields = createConfigFields(window, parent, config, preferredOrder)
            availableNames = fieldnames(config);
            names = preferredOrder(ismember(preferredOrder, availableNames));
            grid = uigridlayout(parent, [numel(names), 2]);
            grid.ColumnWidth = {210, '1x'};
            grid.RowHeight = repmat({34}, 1, numel(names));
            grid.Padding = [12, 12, 12, 12];
            fields = struct();
            for index = 1:numel(names)
                name = names{index};
                uilabel(grid, 'Text', window.humanizeFieldName(name), ...
                    'HorizontalAlignment', 'right');
                fields.(name) = uieditfield(grid, 'numeric', ...
                    'Value', config.(name));
            end
        end

        % refreshUI handles this operation.
        function refreshUI(window)
            cfg = window.settings.hwConfig;
            window.pushFields(window.camUI, cfg.camera);
            window.pushFields(window.plcXUI, cfg.plc.xAxis);
            window.pushFields(window.plcYUI, cfg.plc.yAxis);
        end

        % pushFields handles this operation.
        function pushFields(~, fields, config)
            names = fieldnames(fields);
            for index = 1:numel(names)
                name = names{index};
                if isfield(config, name)
                    fields.(name).Value = config.(name);
                end
            end
        end

        % pullFields handles this operation.
        function config = pullFields(~, fields, config)
            names = fieldnames(fields);
            for index = 1:numel(names)
                name = names{index};
                config.(name) = fields.(name).Value;
            end
        end

        % loadConfig handles this operation.
        function loadConfig(window)
            try
                window.settings.loadHwConfig(window.configDrop.Value);
                window.ensureTenzoOffsets();
                window.refreshUI();
            catch exception
                uialert(window.fig, exception.message, 'Cannot load configuration');
            end
        end

        % ensureTenzoOffsets handles this operation.
        function ensureTenzoOffsets(window)
            cfg = window.settings.hwConfig;
            if ~isfield(cfg.plc.xAxis, 'fTenzoOffset')
                cfg.plc.xAxis.fTenzoOffset = 0;
            end
            if ~isfield(cfg.plc.yAxis, 'fTenzoOffset')
                cfg.plc.yAxis.fTenzoOffset = 0;
            end
            window.settings.hwConfig = cfg;
        end

        % saveConfig handles this operation.
        function saveConfig(window, saveAs)
            filename = window.configDrop.Value;
            if saveAs
                answer = inputdlg('Configuration name:', ...
                    'Save hardware configuration', [1, 45], {'new_hardware'});
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
            catch exception
                uialert(window.fig, exception.message, 'Cannot save configuration');
            end
        end

        % gatherConfig handles this operation.
        function gatherConfig(window)
            cfg = window.settings.hwConfig;
            cfg.camera = window.pullFields(window.camUI, cfg.camera);
            cfg.plc.xAxis = window.pullFields(window.plcXUI, cfg.plc.xAxis);
            cfg.plc.yAxis = window.pullFields(window.plcYUI, cfg.plc.yAxis);
            window.settings.hwConfig = cfg;
        end

        % applySettings handles this operation.
        function applySettings(window)
            try
                window.gatherConfig();
                window.settings.applyCameraConfig();
                window.settings.applyPlcConfig();
            catch exception
                uialert(window.fig, exception.message, 'Cannot apply configuration');
            end
        end

        % nonEmptyItems handles this operation.
        function items = nonEmptyItems(~, items)
            if isempty(items)
                items = {'default'};
            end
        end

        % humanizeFieldName handles this operation.
        function label = humanizeFieldName(~, name)
            label = regexprep(name, '([a-z])([A-Z])', '$1 $2');
            label = strrep(label, '_', ' ');
            label(1) = upper(label(1));
        end
    end
end


