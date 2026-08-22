classdef TestPanel < handle
    %TESTPANEL Coordinates presets, axis selection, and test-definition tabs.

    properties (SetAccess = private)
        % Tab group exposed for integration with the main window
        tabs
    end

    properties (Access = private)
        % Dependencies and child component
        settings Settings
        parentFig
        callbacks
        definitionTabs TestDefinitionTabs

        % Toolbar controls
        presetDrop
        axisModeDrop
        toolbarEditControls = gobjects(0)

        % Run permissions derived from PLC and application state
        machineRunAllowed = false
        generalMachineAllowed = false
        runtimeLocked = false
    end

    methods
        %% Construction and preset data
        function panel = TestPanel(settings, parentFig, callbacks)
            panel.settings = settings;
            panel.parentFig = parentFig;
            panel.callbacks = callbacks;
        end

        function createToolbarControls(panel, grid)
            uilabel(grid, 'Text', 'Preset:');
            panel.presetDrop = uidropdown(grid, ...
                'Items', panel.nonEmptyItems( ...
                    panel.settings.listAppConfigs()), ...
                'ValueChangedFcn', @(~, ~) panel.loadSelectedPreset());
            preferred = panel.settings.activeAppConfigName;
            if isempty(preferred) && ...
                    ismember('default', panel.presetDrop.Items)
                preferred = 'default';
            end
            if ~isempty(preferred) && ...
                    ismember(preferred, panel.presetDrop.Items)
                panel.presetDrop.Value = preferred;
            end
            saveButton = uibutton(grid, 'Text', 'Save', ...
                'ButtonPushedFcn', @(~, ~) panel.savePreset(false));
            saveAsButton = uibutton(grid, 'Text', 'Save as', ...
                'ButtonPushedFcn', @(~, ~) panel.savePreset(true));
            axisPanel = uipanel(grid, 'Title', 'Active axes');
            axisGrid = uigridlayout(axisPanel, [1, 1]);
            axisGrid.Padding = [4, 0, 4, 0];
            panel.axisModeDrop = uidropdown(axisGrid, ...
                'Items', {'Both', 'X only', 'Y only'}, ...
                'Value', 'Both', ...
                'ValueChangedFcn', @(~, ~) panel.axisModeChanged());
            panel.toolbarEditControls = [panel.presetDrop, ...
                saveButton, saveAsButton, panel.axisModeDrop];
        end

        function create(panel, parent)
            tabCallbacks = struct( ...
                'runPre', panel.callbacks.runPre, ...
                'runSingle', panel.callbacks.runSingle, ...
                'runCyclic', panel.callbacks.runCyclic, ...
                'runGeneral', panel.callbacks.runGeneral, ...
                'previewChanged', panel.callbacks.previewChanged);
            panel.definitionTabs = TestDefinitionTabs( ...
                parent, panel.parentFig, tabCallbacks, ...
                @() panel.getAxisMode(), ...
                @(value) panel.setAxisMode(value));
            panel.tabs = panel.definitionTabs.tabs;
            panel.refreshRunAvailability();
        end

        function config = getConfiguration(panel)
            values = panel.definitionTabs.getConfiguration();
            config = struct( ...
                'schemaVersion', 2, ...
                'system', struct('axisMode', panel.getAxisMode()), ...
                'pre', values.pre, ...
                'single', values.single, ...
                'cyclic', values.cyclic, ...
                'general', values.general, ...
                'post', values.post);
        end

        function applyPreset(panel, config)
            % Validate the complete preset before mutating any visible control.
            panel.validatePresetRoot(config);
            definition = rmfield(config, {'schemaVersion', 'system'});
            panel.definitionTabs.validateConfiguration(definition);
            TestCommandBuilder.fromPreset( ...
                config, 'pre', panel.settings.hwConfig);
            panel.definitionTabs.applyValidatedConfiguration(definition);
            panel.axisModeDrop.Value = config.system.axisMode;
            panel.axisModeChanged();
        end

        function loadPresetByName(panel, filename)
            panel.settings.loadAppConfig(filename);
            panel.applyPreset(panel.settings.appConfig);
            panel.settings.rememberAppConfig();
            if ismember(filename, panel.presetDrop.Items)
                panel.presetDrop.Value = filename;
            end
        end

        function mode = getAxisMode(panel)
            mode = char(panel.axisModeDrop.Value);
        end

        function definition = getGeneralDefinition(panel)
            definition = panel.definitionTabs.getGeneralDefinition();
        end

        function preview = getForceReferencePreview(panel)
            preview = panel.definitionTabs.getForceReferencePreview( ...
                panel.settings.hwConfig);
        end

        function enabled = isAxisActive(panel, axisName)
            axes = TestCommandBuilder.axesForMode(panel.getAxisMode());
            enabled = ismember(upper(char(axisName)), axes);
        end

        %% Runtime availability
        function setMachineAvailability(panel, connected, statuses)
            panel.machineRunAllowed = panel.axesAvailable( ...
                logical(connected), statuses, ...
                TestCommandBuilder.axesForMode(panel.getAxisMode()));
            panel.generalMachineAllowed = logical(connected);
            if panel.generalMachineAllowed && ~isempty(statuses)
                try
                    definition = panel.definitionTabs.getGeneralDefinition();
                    axes = TestCommandBuilder.axesForMode( ...
                        definition.axisMode);
                    panel.generalMachineAllowed = panel.axesAvailable( ...
                        true, statuses, axes);
                catch
                    panel.generalMachineAllowed = false;
                end
            end
            panel.refreshRunAvailability();
        end

        function setRuntimeLocked(panel, locked)
            panel.runtimeLocked = logical(locked);
            if ~isempty(panel.definitionTabs) && ...
                    isvalid(panel.definitionTabs)
                panel.definitionTabs.setRuntimeLocked( ...
                    panel.runtimeLocked);
            end
            for index = 1:numel(panel.toolbarEditControls)
                if isvalid(panel.toolbarEditControls(index))
                    panel.setEnabled(panel.toolbarEditControls(index), ...
                        ~panel.runtimeLocked);
                end
            end
            panel.refreshRunAvailability();
        end
    end

    methods (Access = private)
        %% Preset persistence and validation
        function loadSelectedPreset(panel)
            try
                panel.loadPresetByName(panel.presetDrop.Value);
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
                restoreFigureFocus(panel.parentFig);
                if isempty(answer) || isempty(strtrim(answer{1}))
                    return;
                end
                filename = strtrim(answer{1});
            end
            try
                panel.settings.appConfig = panel.getConfiguration();
                panel.validatePresetRoot(panel.settings.appConfig);
                TestCommandBuilder.fromPreset( ...
                    panel.settings.appConfig, 'pre', ...
                    panel.settings.hwConfig);
                panel.settings.saveAppConfig(filename);
                panel.presetDrop.Items = panel.nonEmptyItems( ...
                    panel.settings.listAppConfigs());
                panel.presetDrop.Value = filename;
            catch exception
                uialert(panel.parentFig, exception.message, ...
                    'Cannot save test preset');
            end
        end

        function validatePresetRoot(~, config)
            required = {'schemaVersion', 'system', 'pre', 'single', ...
                'cyclic', 'general', 'post'};
            TestPanel.requireExactFields(config, required, 'preset');
            if ~isnumeric(config.schemaVersion) || ...
                    ~isscalar(config.schemaVersion) || ...
                    config.schemaVersion ~= 2
                error('TestPreset:SchemaVersion', ...
                    'preset.schemaVersion must be 2.');
            end
            TestPanel.requireExactFields( ...
                config.system, {'axisMode'}, 'preset.system');
            if ~ismember(char(config.system.axisMode), ...
                    {'Both', 'X only', 'Y only'})
                error('TestPreset:InvalidValue', ...
                    'preset.system.axisMode is not selectable.');
            end
        end

        %% Dependency and availability helpers
        function axisModeChanged(panel)
            panel.definitionTabs.refreshAxisMode();
            panel.callbacks.axisModeChanged();
            panel.refreshRunAvailability();
        end

        function setAxisMode(panel, value)
            panel.axisModeDrop.Value = value;
            panel.axisModeChanged();
        end

        function refreshRunAvailability(panel)
            if isempty(panel.definitionTabs) || ...
                    ~isvalid(panel.definitionTabs)
                return;
            end
            panel.definitionTabs.setAvailability( ...
                panel.machineRunAllowed, ...
                panel.generalMachineAllowed, panel.runtimeLocked);
        end

        function allowed = axesAvailable(~, allowed, statuses, axes)
            if ~allowed || isempty(statuses)
                return;
            end
            for index = 1:numel(axes)
                state = statuses.(axes{index});
                allowed = allowed && ~state.working && ~state.error;
            end
        end

        function setEnabled(~, control, enabled)
            if enabled
                control.Enable = 'on';
            else
                control.Enable = 'off';
            end
        end

        function items = nonEmptyItems(~, items)
            if isempty(items)
                items = {'default'};
            end
        end
    end

    methods (Static, Access = private)
        %% Exact preset-schema validation
        function requireExactFields(value, required, path)
            if ~isstruct(value) || ~isscalar(value)
                error('TestPreset:InvalidObject', ...
                    '%s must be one object.', path);
            end
            names = fieldnames(value);
            missing = setdiff(required, names, 'stable');
            unknown = setdiff(names, required, 'stable');
            if ~isempty(missing)
                error('TestPreset:MissingField', ...
                    '%s is missing %s.', path, missing{1});
            end
            if ~isempty(unknown)
                error('TestPreset:UnsupportedField', ...
                    '%s contains unsupported field %s.', ...
                    path, unknown{1});
            end
        end
    end
end
