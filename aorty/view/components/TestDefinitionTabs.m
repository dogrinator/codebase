classdef TestDefinitionTabs < handle
    %TESTDEFINITIONTABS Owns test-definition controls and their dependencies.

    properties (SetAccess = private)
        tabs
    end

    properties (Access = private)
        parentFig
        callbacks
        axisModeGetter
        axisModeSetter
        controls = struct()
        postButtons
        postSelection = 'Stay at unchanged position'
        runButtons = gobjects(0)
        preRun
        generalRun
        generalSummary
        generalDefinition = []
        runtimeLocked = false
        lockedControls = gobjects(0)
        lockedEnableStates = {}
    end

    methods
        function view = TestDefinitionTabs( ...
                parent, parentFig, callbacks, axisModeGetter, axisModeSetter)
            view.parentFig = parentFig;
            view.callbacks = callbacks;
            view.axisModeGetter = axisModeGetter;
            view.axisModeSetter = axisModeSetter;

            container = uipanel(parent, 'Title', 'Test definition');
            container.Layout.Row = 2;
            container.Layout.Column = 1;
            layout = uigridlayout(container, [1, 1]);
            layout.Padding = [4, 4, 4, 4];
            view.tabs = uitabgroup(layout);
            view.tabs.SelectionChangedFcn = @(~, ~) ...
                view.notifyPreviewChanged();
            view.createPreTestTab(uitab(view.tabs, 'Title', 'Pre-test'));
            view.createSingleTestTab(uitab(view.tabs, 'Title', 'Single test'));
            view.createCyclicTestTab(uitab(view.tabs, 'Title', 'Cyclic test'));
            view.createGeneralTestTab(uitab(view.tabs, 'Title', 'General test'));
            view.createPostTestTab(uitab(view.tabs, 'Title', 'Post-test'));
            view.refreshDependencies();
        end

        function config = getConfiguration(view)
            config = view.collectValues(view.controls);
            config.post.afterTest = view.postSelection;
        end

        function applyConfiguration(view, config)
            view.validateConfiguration(config);
            sections = {'pre', 'single', 'cyclic', 'general'};
            for index = 1:numel(sections)
                name = sections{index};
                view.applyValues(view.controls.(name), config.(name));
            end
            view.selectPostAction(config.post.afterTest);
            view.refreshDependencies();
            view.notifyPreviewChanged();
        end

        function validateConfiguration(view, config)
            sections = {'pre', 'single', 'cyclic', 'general'};
            TestDefinitionTabs.requireExactFields( ...
                config, [sections, {'post'}], 'preset');
            TestDefinitionTabs.requireExactFields( ...
                config.post, {'afterTest'}, 'preset.post');
            for index = 1:numel(sections)
                name = sections{index};
                view.validateValues(view.controls.(name), ...
                    config.(name), ['preset.', name]);
            end
            validPostActions = cellstr(string({view.postButtons.Text}));
            if ~ismember(char(config.post.afterTest), validPostActions)
                error('TestPreset:InvalidValue', ...
                    'preset.post.afterTest is not a selectable action.');
            end
        end

        function definition = getGeneralDefinition(view)
            if isempty(view.generalDefinition)
                error('GeneralTest:NoValidFile', ...
                    'Browse to a valid General Test JSON file first.');
            end
            definition = view.generalDefinition;
        end

        function preview = getForceReferencePreview(view)
            if isempty(view.tabs) || ~isvalid(view.tabs) || ...
                    isempty(view.tabs.SelectedTab)
                preview = PlotReferenceBuilder.build( ...
                    '', view.getConfiguration(), ...
                    view.axisModeGetter());
                return;
            end
            selectedTab = char(view.tabs.SelectedTab.Title);
            preview = PlotReferenceBuilder.build( ...
                selectedTab, view.getConfiguration(), ...
                view.axisModeGetter());
        end

        function setAvailability(view, ordinaryAllowed, generalAllowed, locked)
            for index = 1:numel(view.runButtons)
                view.setEnabled(view.runButtons(index), ...
                    ordinaryAllowed && ~locked);
            end
            preSelected = view.controls.pre.cyclic.Value || ...
                view.controls.pre.preload.enabled.Value;
            view.setEnabled(view.preRun, ...
                ordinaryAllowed && preSelected && ~locked);
            view.setEnabled(view.generalRun, ...
                generalAllowed && ~isempty(view.generalDefinition) && ...
                ~locked);
        end

        function setRuntimeLocked(view, locked)
            locked = logical(locked);
            if locked == view.runtimeLocked
                view.enforceRuntimeLock();
                return;
            end
            view.runtimeLocked = locked;
            if locked
                view.lockedControls = findall( ...
                    view.tabs, '-property', 'Enable');
                view.lockedEnableStates = cell( ...
                    size(view.lockedControls));
                for index = 1:numel(view.lockedControls)
                    control = view.lockedControls(index);
                    view.lockedEnableStates{index} = control.Enable;
                    control.Enable = 'off';
                end
            else
                for index = 1:numel(view.lockedControls)
                    control = view.lockedControls(index);
                    if isvalid(control)
                        control.Enable = ...
                            view.lockedEnableStates{index};
                    end
                end
                view.lockedControls = gobjects(0);
                view.lockedEnableStates = {};
                view.refreshDependencies();
            end
        end

        function refreshAxisMode(view)
            view.refreshDependencies();
            view.notifyPreviewChanged();
        end
    end

    methods (Access = private)
        function createPreTestTab(view, tab)
            grid = TestControlFactory.formGrid(tab, 13);
            grid.Scrollable = 'on';
            changed = @() view.notifyPreviewChanged();
            view.controls.pre.rate = TestControlFactory.axisRow( ...
                grid, 2, 'Movement speed (> 0)', 1, '[mm/s]', changed);
            view.configurePositiveAxisRow(view.controls.pre.rate);
            view.controls.pre.record = TestControlFactory.checkRow( ...
                grid, 3, 'Record pre-test data', true);
            view.controls.pre.record.Tooltip = ...
                ['When checked, choose an output folder and record the ' ...
                'standalone pre-test.'];
            view.controls.pre.cyclic = TestControlFactory.checkRow( ...
                grid, 4, 'Cyclic pre-conditioning', false);
            view.controls.pre.cycles = TestControlFactory.cycleRow( ...
                grid, 5, 'Number of cycles', 1, '[cyc.]');
            view.controls.pre.cycles.Tooltip = ...
                'Choose a whole cycle count from 1 to 50.';
            view.controls.pre.load = TestControlFactory.axisRow( ...
                grid, 6, 'Pre-cycle load force', 0, '[N]', changed);
            view.controls.pre.unload = TestControlFactory.axisRow( ...
                grid, 7, 'Unload force', 0, '[N]', changed);
            view.controls.pre.unloadToStart = TestControlFactory.checkRow( ...
                grid, 8, 'Unload to captured start position', false);
            view.controls.pre.cyclicForceTolerance = ...
                TestControlFactory.axisRow(grid, 9, ...
                'Pre-cycle force tolerance', 0.1, '[N]', changed);
            view.configureNonnegativeAxisRow( ...
                view.controls.pre.cyclicForceTolerance);
            view.controls.pre.holdTime = TestControlFactory.axisRow( ...
                grid, 10, 'Pre-cycle endpoint hold time', 0, '[s]', changed);
            view.configureNonnegativeAxisRow(view.controls.pre.holdTime);
            view.controls.pre.preload = ...
                TestControlFactory.optionalAxisRow(grid, 11, ...
                'Initial preload force', 0, '[N]', ...
                @() view.refreshAndNotify());
            view.controls.pre.preload.forceTolerance = ...
                TestControlFactory.axisRow(grid, 12, ...
                'Initial preload force tolerance', 0.1, '[N]', changed);
            view.configureNonnegativeAxisRow( ...
                view.controls.pre.preload.forceTolerance);
            view.controls.pre.preload.holdTime = ...
                TestControlFactory.axisRow(grid, 13, ...
                'Initial preload force hold time', 0, '[s]', changed);
            view.configureNonnegativeAxisRow( ...
                view.controls.pre.preload.holdTime);
            view.preRun = TestControlFactory.runButton( ...
                grid, 14, 'RUN PRE-TEST', view.callbacks.runPre);
            view.runButtons(end + 1) = view.preRun;
            view.controls.pre.cyclic.ValueChangedFcn = ...
                @(~, ~) view.refreshAndNotify();
            view.controls.pre.unloadToStart.ValueChangedFcn = ...
                @(~, ~) view.refreshDependencies();
        end

        function createSingleTestTab(view, tab)
            grid = TestControlFactory.formGrid(tab, 11);
            changed = @() view.notifyPreviewChanged();
            view.controls.single.includePre = TestControlFactory.checkRow( ...
                grid, 2, 'Include force pre-test', false);
            view.controls.single.primaryMode = TestControlFactory.dropRow( ...
                grid, 3, 'Primary endpoint mode', ...
                {'Displacement', 'Force'});
            view.controls.single.primary = TestControlFactory.axisRow( ...
                grid, 4, 'Primary endpoint value', 0, '[mm / N]', changed);
            view.controls.single.secondaryMode = TestControlFactory.dropRow( ...
                grid, 5, 'Optional OR endpoint', ...
                {'None', 'Displacement', 'Force'});
            view.controls.single.secondary = TestControlFactory.axisRow( ...
                grid, 6, 'OR endpoint value', 0, '[mm / N]', changed);
            view.controls.single.rate = TestControlFactory.axisRow( ...
                grid, 7, 'Movement speed (> 0)', 1, '[mm/s]', changed);
            view.configurePositiveAxisRow(view.controls.single.rate);
            view.controls.single.forceTolerance = ...
                TestControlFactory.axisRow(grid, 8, ...
                'Force tolerance', 0.1, '[N]', changed);
            view.configureNonnegativeAxisRow( ...
                view.controls.single.forceTolerance);
            view.controls.single.holdTime = TestControlFactory.axisRow( ...
                grid, 9, 'Primary endpoint hold time', 0, '[s]', changed);
            view.configureNonnegativeAxisRow(view.controls.single.holdTime);
            post = TestControlFactory.optionalRow(grid, 10, ...
                'Sampling period', 0.1, '[s]', ...
                @() view.refreshDependencies());
            view.controls.single.postProcess.enabled = post.enabled;
            view.controls.single.postProcess.samplingPeriod = post.value;
            view.configureNonnegativeField(post.value);
            view.controls.single.postProcess.includePrePost = ...
                TestControlFactory.checkRow(grid, 11, ...
                'Include pre-test and post-test', false);
            view.configurePostProcessTooltips( ...
                view.controls.single.postProcess);
            view.runButtons(end + 1) = TestControlFactory.runButton( ...
                grid, 12, 'RUN SINGLE TEST', view.callbacks.runSingle);
            view.controls.single.secondaryMode.ValueChangedFcn = ...
                @(~, ~) view.refreshAndNotify();
            view.controls.single.primaryMode.ValueChangedFcn = ...
                @(~, ~) view.refreshAndNotify();
            tip = view.displacementTooltip();
            view.controls.single.primaryMode.Tooltip = tip;
            view.controls.single.secondaryMode.Tooltip = tip;
        end

        function createCyclicTestTab(view, tab)
            grid = TestControlFactory.formGrid(tab, 12);
            changed = @() view.notifyPreviewChanged();
            view.controls.cyclic.includePre = TestControlFactory.checkRow( ...
                grid, 2, 'Include force pre-test', false);
            view.controls.cyclic.cycles = TestControlFactory.cycleRow( ...
                grid, 3, 'Number of cycles', 1, '[cyc.]');
            view.controls.cyclic.cycles.Tooltip = ...
                'Choose a whole cycle count from 1 to 50.';
            view.controls.cyclic.loadMode = TestControlFactory.dropRow( ...
                grid, 4, 'Load mode', {'Displacement', 'Force'});
            view.controls.cyclic.load = TestControlFactory.axisRow( ...
                grid, 5, 'Constant load value', 0, '[mm / N]', changed);
            view.controls.cyclic.unloadMode = TestControlFactory.dropRow( ...
                grid, 6, 'Unload mode', {'Displacement', 'Force'});
            view.controls.cyclic.unload = TestControlFactory.axisRow( ...
                grid, 7, 'Constant unload value', 0, '[mm / N]', changed);
            view.controls.cyclic.rate = TestControlFactory.axisRow( ...
                grid, 8, 'Movement speed (> 0)', 1, '[mm/s]', changed);
            view.configurePositiveAxisRow(view.controls.cyclic.rate);
            view.controls.cyclic.forceTolerance = ...
                TestControlFactory.axisRow(grid, 9, ...
                'Force tolerance', 0.1, '[N]', changed);
            view.configureNonnegativeAxisRow( ...
                view.controls.cyclic.forceTolerance);
            view.controls.cyclic.holdTime = TestControlFactory.axisRow( ...
                grid, 10, 'Load/unload endpoint hold time', 0, '[s]', changed);
            view.configureNonnegativeAxisRow(view.controls.cyclic.holdTime);
            post = TestControlFactory.optionalRow(grid, 11, ...
                'Sampling period', 0.1, '[s]', ...
                @() view.refreshDependencies());
            view.controls.cyclic.postProcess.enabled = post.enabled;
            view.controls.cyclic.postProcess.samplingPeriod = post.value;
            view.configureNonnegativeField(post.value);
            view.controls.cyclic.postProcess.includePrePost = ...
                TestControlFactory.checkRow(grid, 12, ...
                'Include pre-test and post-test', false);
            view.configurePostProcessTooltips( ...
                view.controls.cyclic.postProcess);
            view.runButtons(end + 1) = TestControlFactory.runButton( ...
                grid, 13, 'RUN CYCLIC TEST', view.callbacks.runCyclic);
            view.controls.cyclic.loadMode.ValueChangedFcn = ...
                @(~, ~) view.refreshAndNotify();
            view.controls.cyclic.unloadMode.ValueChangedFcn = ...
                @(~, ~) view.refreshAndNotify();
            tip = view.displacementTooltip();
            view.controls.cyclic.loadMode.Tooltip = tip;
            view.controls.cyclic.unloadMode.Tooltip = tip;
        end

        function createGeneralTestTab(view, tab)
            grid = TestControlFactory.formGrid(tab, 6);
            view.controls.general.testFile = TestControlFactory.textRow( ...
                grid, 2, 'Complete JSON definition', 'No file selected');
            browse = uibutton(grid, 'Text', 'Browse JSON', ...
                'ButtonPushedFcn', @(~, ~) view.browseGeneralTest());
            browse.Layout.Row = 2;
            browse.Layout.Column = 5;
            label = uilabel(grid, 'Text', 'Imported test summary');
            label.Layout.Row = 3;
            label.Layout.Column = 1;
            view.generalSummary = uitextarea(grid, 'Editable', 'off', ...
                'Value', {'No valid General Test has been imported.'});
            view.generalSummary.Layout.Row = [3, 5];
            view.generalSummary.Layout.Column = [2, 5];
            view.generalRun = TestControlFactory.runButton( ...
                grid, 6, 'RUN IMPORTED TEST', view.callbacks.runGeneral);
            view.generalRun.Enable = 'off';
            view.generalRun.Tooltip = ...
                'Run is enabled after a schemaVersion 1 JSON file validates.';
        end

        function createPostTestTab(view, tab)
            grid = uigridlayout(tab, [2, 1]);
            grid.RowHeight = {28, '1x'};
            grid.Padding = [12, 12, 12, 12];
            uilabel(grid, 'Text', ...
                'PLC action after successful test:', 'FontWeight', 'bold');
            buttonGrid = uigridlayout(grid, [5, 1]);
            buttonGrid.RowHeight = repmat({40}, 1, 5);
            buttonGrid.Padding = [4, 4, 4, 4];
            buttonGrid.RowSpacing = 6;
            labels = {'Return to saved position', ...
                'Return to start position', ...
                'Return to pre-test final position', 'Unload (force)', ...
                'Stay at unchanged position'};
            view.postButtons = gobjects(numel(labels), 1);
            for index = 1:numel(labels)
                view.postButtons(index) = uibutton(buttonGrid, 'state', ...
                    'Text', labels{index}, ...
                    'ValueChangedFcn', ...
                    @(src, ~) view.postActionSelected(src));
            end
            view.selectPostAction('Stay at unchanged position');
        end

        function refreshDependencies(view)
            rows = {view.controls.single.primary, ...
                view.controls.single.rate, ...
                view.controls.single.holdTime, ...
                view.controls.cyclic.load, ...
                view.controls.cyclic.unload, ...
                view.controls.cyclic.rate, ...
                view.controls.cyclic.holdTime};
            for index = 1:numel(rows)
                view.setAxisByMode(rows{index}, true);
            end
            preCyclic = view.controls.pre.cyclic.Value;
            preAny = preCyclic || ...
                view.controls.pre.preload.enabled.Value;
            view.setAxisByMode(view.controls.pre.rate, preAny);
            view.setEnabled(view.controls.pre.cycles, preCyclic);
            view.setAxisByMode(view.controls.pre.load, preCyclic);
            view.setAxisByMode(view.controls.pre.unload, ...
                preCyclic && ~view.controls.pre.unloadToStart.Value);
            view.setEnabled(view.controls.pre.unloadToStart, preCyclic);
            view.setAxisByMode( ...
                view.controls.pre.cyclicForceTolerance, preCyclic);
            view.setAxisByMode(view.controls.pre.holdTime, preCyclic);
            preloadEnabled = view.controls.pre.preload.enabled.Value;
            view.setAxisByMode(view.controls.pre.preload.value, ...
                preloadEnabled);
            view.setAxisByMode( ...
                view.controls.pre.preload.forceTolerance, preloadEnabled);
            view.setAxisByMode( ...
                view.controls.pre.preload.holdTime, preloadEnabled);
            view.setAxisByMode(view.controls.single.secondary, ...
                ~strcmp(view.controls.single.secondaryMode.Value, 'None'));
            singleUsesForce = ...
                strcmp(view.controls.single.primaryMode.Value, 'Force') || ...
                strcmp(view.controls.single.secondaryMode.Value, 'Force');
            view.setAxisByMode( ...
                view.controls.single.forceTolerance, singleUsesForce);
            cyclicUsesForce = ...
                strcmp(view.controls.cyclic.loadMode.Value, 'Force') || ...
                strcmp(view.controls.cyclic.unloadMode.Value, 'Force');
            view.setAxisByMode( ...
                view.controls.cyclic.forceTolerance, cyclicUsesForce);
            for name = {'single', 'cyclic'}
                post = view.controls.(name{1}).postProcess;
                view.setEnabled(post.samplingPeriod, post.enabled.Value);
                view.setEnabled(post.includePrePost, post.enabled.Value);
            end
            view.enforceRuntimeLock();
        end

        function enforceRuntimeLock(view)
            if ~view.runtimeLocked
                return;
            end
            for index = 1:numel(view.lockedControls)
                if isvalid(view.lockedControls(index))
                    view.lockedControls(index).Enable = 'off';
                end
            end
        end

        function setAxisByMode(view, controls, baseEnabled)
            mode = view.axisModeGetter();
            view.setEnabled(controls.x, baseEnabled && ...
                (strcmp(mode, 'Both') || strcmp(mode, 'X only')));
            view.setEnabled(controls.y, baseEnabled && ...
                (strcmp(mode, 'Both') || strcmp(mode, 'Y only')));
            view.setEnabled(controls.lock, baseEnabled && ...
                strcmp(mode, 'Both'));
        end

        function browseGeneralTest(view)
            [file, folder] = uigetfile({'*.json', ...
                'General Test JSON (*.json)'});
            if isequal(file, 0)
                return;
            end
            filename = fullfile(folder, file);
            try
                view.generalDefinition = ...
                    GeneralTestDefinition.load(filename);
                view.controls.general.testFile.Value = filename;
                view.generalSummary.Value = ...
                    {GeneralTestDefinition.summary(view.generalDefinition)};
                switch lower(char(view.generalDefinition.axisMode))
                    case 'x'
                        view.axisModeSetter('X only');
                    case 'y'
                        view.axisModeSetter('Y only');
                    otherwise
                        view.axisModeSetter('Both');
                end
                view.generalRun.Tooltip = ...
                    'The imported definition is complete and authoritative.';
            catch exception
                view.generalDefinition = [];
                view.controls.general.testFile.Value = filename;
                view.generalSummary.Value = ...
                    {['Invalid file: ', exception.message]};
                view.generalRun.Tooltip = exception.message;
                uialert(view.parentFig, exception.message, ...
                    'Invalid General Test');
            end
            view.notifyPreviewChanged();
        end

        function values = collectValues(view, controls)
            if isstruct(controls)
                values = struct();
                names = fieldnames(controls);
                for index = 1:numel(names)
                    name = names{index};
                    values.(name) = ...
                        view.collectValues(controls.(name));
                end
            elseif isprop(controls, 'Value')
                values = controls.Value;
            else
                values = [];
            end
        end

        function validateValues(view, controls, values, path)
            if isstruct(controls)
                TestDefinitionTabs.requireExactFields( ...
                    values, fieldnames(controls)', path);
                names = fieldnames(controls);
                for index = 1:numel(names)
                    name = names{index};
                    view.validateValues(controls.(name), ...
                        values.(name), [path, '.', name]);
                end
                return;
            end
            if ~isprop(controls, 'Value')
                return;
            end
            if isa(controls, 'matlab.ui.control.NumericEditField')
                lowerExclusive = strcmp( ...
                    string(controls.LowerLimitInclusive), "off");
                if ~isnumeric(values) || ~isscalar(values) || ...
                        ~isfinite(values) || values < controls.Limits(1) || ...
                        values > controls.Limits(2) || ...
                        (lowerExclusive && ...
                        values == controls.Limits(1))
                    error('TestPreset:InvalidValue', ...
                        '%s is outside the visible input limits.', path);
                end
            elseif isa(controls, 'matlab.ui.control.DropDown')
                allowed = controls.Items;
                if ~isempty(controls.ItemsData)
                    allowed = controls.ItemsData;
                end
                if ~any(ismember(allowed, values))
                    error('TestPreset:InvalidValue', ...
                        '%s is not a selectable value.', path);
                end
            elseif isa(controls, 'matlab.ui.control.CheckBox') || ...
                    isa(controls, 'matlab.ui.control.StateButton')
                if ~islogical(values) || ~isscalar(values)
                    error('TestPreset:InvalidValue', ...
                        '%s must be true or false.', path);
                end
            elseif ~(ischar(values) || ...
                    (isstring(values) && isscalar(values)))
                error('TestPreset:InvalidValue', ...
                    '%s must be text.', path);
            end
        end

        function applyValues(view, controls, values)
            if isstruct(controls)
                names = fieldnames(controls);
                for index = 1:numel(names)
                    name = names{index};
                    view.applyValues(controls.(name), values.(name));
                end
            elseif isprop(controls, 'Value')
                controls.Value = values;
            end
        end

        function postActionSelected(view, selected)
            if ~selected.Value
                selected.Value = true;
                return;
            end
            view.selectPostAction(selected.Text);
        end

        function selectPostAction(view, action)
            view.postSelection = char(action);
            for index = 1:numel(view.postButtons)
                selected = strcmp( ...
                    view.postButtons(index).Text, view.postSelection);
                view.postButtons(index).Value = selected;
                if selected
                    view.postButtons(index).BackgroundColor = ...
                        [0.55, 0.75, 0.95];
                    view.postButtons(index).FontWeight = 'bold';
                else
                    view.postButtons(index).BackgroundColor = ...
                        [0.94, 0.94, 0.94];
                    view.postButtons(index).FontWeight = 'normal';
                end
            end
        end

        function refreshAndNotify(view)
            view.refreshDependencies();
            view.notifyPreviewChanged();
        end

        function notifyPreviewChanged(view)
            if isfield(view.callbacks, 'previewChanged') && ...
                    ~isempty(view.callbacks.previewChanged)
                view.callbacks.previewChanged();
            end
        end

        function configurePositiveAxisRow(view, controls)
            view.configurePositiveField(controls.x);
            view.configurePositiveField(controls.y);
        end

        function configurePositiveField(~, control)
            control.Limits = [0, Inf];
            control.LowerLimitInclusive = 'off';
            control.Tooltip = 'Value must be greater than 0.';
        end

        function configureNonnegativeAxisRow(view, controls)
            view.configureNonnegativeField(controls.x);
            view.configureNonnegativeField(controls.y);
        end

        function configureNonnegativeField(~, control)
            control.Limits = [0, Inf];
            control.Tooltip = 'Value must be 0 or greater.';
        end

        function configurePostProcessTooltips(~, controls)
            controls.samplingPeriod.Tooltip = ...
                ['TIFF output interval. Raw frames are always saved at ' ...
                'the configured camera FPS.'];
            controls.includePrePost.Tooltip = ...
                ['Controls automatic TIFF output only; raw frames from ' ...
                'all phases remain recorded.'];
        end

        function setEnabled(~, control, enabled)
            if enabled
                control.Enable = 'on';
            else
                control.Enable = 'off';
            end
        end

        function text = displacementTooltip(~)
            text = ['Displacement is the current axis position relative ' ...
                'to the position captured at test start (start = 0 mm).'];
        end
    end

    methods (Static, Access = private)
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
