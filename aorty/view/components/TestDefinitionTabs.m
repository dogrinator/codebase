classdef TestDefinitionTabs < handle
    %TESTDEFINITIONTABS Owns test-definition controls and their dependencies.

    properties (SetAccess = private)
        tabs
    end

    properties (Access = private)
        % Parent window and callbacks supplied by the owning TestPanel
        parentFig
        callbacks
        axisModeGetter
        axisModeSetter
        hardwareConfigGetter

        % Test controls and mutually exclusive post-test selection
        controls = struct()
        postButtons
        postSelection = 'Stay at unchanged position'
        runButtons = gobjects(0)
        preRun
        generalRun
        generalSummary
        generalDefinition = []
        unitLabels = struct()

        % Runtime lock snapshot used to restore each control's prior state
        runtimeLocked = false
        lockedControls = gobjects(0)
        lockedEnableStates = {}
    end

    methods
        %% Construction, preset data, and public state
        function view = TestDefinitionTabs( ...
                parent, parentFig, callbacks, axisModeGetter, ...
                axisModeSetter, hardwareConfigGetter)
            view.parentFig = parentFig;
            view.callbacks = callbacks;
            view.axisModeGetter = axisModeGetter;
            view.axisModeSetter = axisModeSetter;
            view.hardwareConfigGetter = hardwareConfigGetter;

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

        function applyValidatedConfiguration(view, config)
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

        function preview = getForceReferencePreview(view, hwConfig)
            if isempty(view.tabs) || ~isvalid(view.tabs) || ...
                    isempty(view.tabs.SelectedTab)
                preview = PlotReferenceBuilder.build( ...
                    '', view.getConfiguration(), ...
                    view.axisModeGetter(), hwConfig);
                return;
            end
            selectedTab = char(view.tabs.SelectedTab.Title);
            preview = PlotReferenceBuilder.build( ...
                selectedTab, view.getConfiguration(), ...
                view.axisModeGetter(), hwConfig);
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
            % Preserve per-control enable states so unlocking restores dependencies.
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

        function adjusted = refreshHardwareLimits(view)
            adjusted = view.applyHardwareLimits();
            view.refreshDependencies();
        end
    end

    methods (Access = private)
        %% Test-tab construction
        function createPreTestTab(view, tab)
            root = uigridlayout(tab, [4, 1]);
            % Include each panel title in addition to its grid rows so no
            % editable row is clipped at the section boundary.
            root.RowHeight = {200, 165, 325, 44};
            root.Padding = [8, 8, 8, 8];
            root.RowSpacing = 8;
            root.Scrollable = 'on';
            changed = @() view.notifyPreviewChanged();

            generalPanel = uipanel(root, 'Title', 'General settings');
            generalGrid = TestControlFactory.sectionGrid(generalPanel, 3);
            view.controls.pre.rate = TestControlFactory.axisRow( ...
                generalGrid, 2, 'Movement speed', ...
                1, 'mm/s', changed);
            view.tagAxisRow(view.controls.pre.rate, 'PreSpeed');
            view.configurePositiveAxisRow(view.controls.pre.rate);
            view.controls.pre.forceTolerance = ...
                TestControlFactory.axisRow(generalGrid, 3, ...
                'Force endpoint tolerance', 1, '%', changed);
            view.configurePercentAxisRow( ...
                view.controls.pre.forceTolerance);
            view.controls.pre.record = TestControlFactory.checkRow( ...
                generalGrid, 4, 'Record pre-test data', true);
            view.controls.pre.record.Tooltip = ...
                ['When checked, choose an output folder and record the ' ...
                'standalone pre-test.'];

            preloadPanel = uipanel(root, 'Title', 'Preload');
            preloadGrid = TestControlFactory.sectionGrid(preloadPanel, 2);
            view.controls.pre.preload = ...
                TestControlFactory.optionalAxisRow(preloadGrid, 2, ...
                'Force', 0, 'N', ...
                @() view.refreshAndNotify());
            view.tagAxisRow(view.controls.pre.preload.value, 'PreloadForce');
            view.controls.pre.preload.holdTime = ...
                TestControlFactory.axisRow(preloadGrid, 3, ...
                'Hold time', 0, 's', changed);
            view.configureNonnegativeAxisRow( ...
                view.controls.pre.preload.holdTime);

            precyclePanel = uipanel(root, 'Title', 'Precycle');
            precycleGrid = TestControlFactory.sectionGrid(precyclePanel, 6);
            view.controls.pre.cyclic = TestControlFactory.checkRow( ...
                precycleGrid, 2, 'Enable cycles', false);
            view.controls.pre.cycles = ...
                TestControlFactory.numericCycleRow( ...
                precycleGrid, 3, 'Number of cycles', 1, 'cycles');
            view.controls.pre.cycles.Tag = 'PreCycleCount';
            view.controls.pre.cycles.Tooltip = ...
                'Choose a whole cycle count from 1 to 50.';
            view.controls.pre.load = TestControlFactory.axisRow( ...
                precycleGrid, 4, 'Load force', 0, 'N', changed);
            view.tagAxisRow(view.controls.pre.load, 'PreCycleLoadForce');
            view.controls.pre.unload = TestControlFactory.axisRow( ...
                precycleGrid, 5, 'Unload force', 0, 'N', changed);
            view.tagAxisRow(view.controls.pre.unload, 'PreCycleUnloadForce');
            view.controls.pre.unloadToStart = TestControlFactory.checkRow( ...
                precycleGrid, 6, ...
                'Unload to captured start position', false);
            view.controls.pre.holdTime = TestControlFactory.axisRow( ...
                precycleGrid, 7, ...
                'Endpoint hold time', 0, 's', changed);
            view.configureNonnegativeAxisRow(view.controls.pre.holdTime);

            view.preRun = uibutton(root, 'Text', 'RUN PRE-TEST', ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.72, 0.88, 0.72], ...
                'ButtonPushedFcn', view.callbacks.runPre);
            view.runButtons(end + 1) = view.preRun;
            view.controls.pre.cyclic.ValueChangedFcn = ...
                @(~, ~) view.refreshAndNotify();
            view.controls.pre.unloadToStart.ValueChangedFcn = ...
                @(~, ~) view.refreshAndNotify();
        end

        function createSingleTestTab(view, tab)
            grid = TestControlFactory.formGrid(tab, 12);
            changed = @() view.notifyPreviewChanged();
            view.controls.single.includePre = TestControlFactory.checkRow( ...
                grid, 2, 'Include force pre-test', false);
            view.controls.single.primaryMode = TestControlFactory.dropRow( ...
                grid, 3, 'Primary endpoint mode', ...
                {'Displacement', 'Force'});
            view.controls.single.primaryMode.Tag = 'SinglePrimaryMode';
            [view.controls.single.primary, ...
                view.unitLabels.singlePrimary] = ...
                TestControlFactory.axisRow( ...
                grid, 4, 'Primary endpoint', 0, 'mm', changed);
            view.unitLabels.singlePrimary.Tag = 'SinglePrimaryUnit';
            view.tagAxisRow(view.controls.single.primary, 'SinglePrimary');
            view.controls.single.secondaryMode = TestControlFactory.dropRow( ...
                grid, 5, 'Secondary endpoint mode (OR)', ...
                {'None', 'Displacement', 'Force'});
            view.controls.single.secondaryMode.Tag = 'SingleSecondaryMode';
            [view.controls.single.secondary, ...
                view.unitLabels.singleSecondary] = ...
                TestControlFactory.axisRow( ...
                grid, 6, 'Secondary endpoint', 0, '', changed);
            view.unitLabels.singleSecondary.Tag = 'SingleSecondaryUnit';
            view.tagAxisRow(view.controls.single.secondary, 'SingleSecondary');
            view.controls.single.rate = TestControlFactory.axisRow( ...
                grid, 7, 'Movement speed', 1, 'mm/s', changed);
            view.tagAxisRow(view.controls.single.rate, 'SingleSpeed');
            view.configurePositiveAxisRow(view.controls.single.rate);
            view.controls.single.forceTolerance = ...
                TestControlFactory.axisRow(grid, 8, ...
                'Force endpoint tolerance', 1, '%', changed);
            view.configurePercentAxisRow( ...
                view.controls.single.forceTolerance);
            view.controls.single.holdTime = TestControlFactory.axisRow( ...
                grid, 9, 'Primary endpoint hold time', 0, 's', changed);
            view.configureNonnegativeAxisRow(view.controls.single.holdTime);
            view.controls.single.rupture = TestControlFactory.optionalRow( ...
                grid, 10, 'Stop on force drop', 10, '% drop', ...
                @() view.refreshDependencies());
            view.controls.single.rupture.value.Limits = [0, 100];
            view.controls.single.rupture.value.LowerLimitInclusive = 'off';
            view.controls.single.rupture.enabled.Tooltip = ...
                ['Stop when force drops this percentage below its test ' ...
                'peak. This replaces the optional OR endpoint.'];
            post = TestControlFactory.optionalRow(grid, 11, ...
                'TIFF sampling period', 0.1, 's', ...
                @() view.refreshDependencies());
            view.controls.single.postProcess.enabled = post.enabled;
            view.controls.single.postProcess.samplingPeriod = post.value;
            view.configureNonnegativeField(post.value);
            view.controls.single.postProcess.includePrePost = ...
                TestControlFactory.checkRow(grid, 12, ...
                'Include pre/post-test frames', false);
            view.configurePostProcessTooltips( ...
                view.controls.single.postProcess);
            view.runButtons(end + 1) = TestControlFactory.runButton( ...
                grid, 13, 'RUN SINGLE TEST', view.callbacks.runSingle);
            view.controls.single.secondaryMode.ValueChangedFcn = ...
                @(~, ~) view.endpointModeChanged();
            view.controls.single.primaryMode.ValueChangedFcn = ...
                @(~, ~) view.endpointModeChanged();
            tip = view.displacementTooltip();
            view.controls.single.primaryMode.Tooltip = tip;
            view.controls.single.secondaryMode.Tooltip = tip;
        end

        function createCyclicTestTab(view, tab)
            grid = TestControlFactory.formGrid(tab, 12);
            changed = @() view.notifyPreviewChanged();
            view.controls.cyclic.includePre = TestControlFactory.checkRow( ...
                grid, 2, 'Include force pre-test', false);
            view.controls.cyclic.cycles = ...
                TestControlFactory.numericCycleRow( ...
                grid, 3, 'Number of cycles', 1, 'cycles');
            view.controls.cyclic.cycles.Tag = 'CyclicCycleCount';
            view.controls.cyclic.loadMode = TestControlFactory.dropRow( ...
                grid, 4, 'Load mode', {'Displacement', 'Force'});
            view.controls.cyclic.loadMode.Tag = 'CyclicLoadMode';
            [view.controls.cyclic.load, view.unitLabels.cyclicLoad] = ...
                TestControlFactory.axisRow( ...
                grid, 5, 'Load endpoint', 0, 'mm', changed);
            view.unitLabels.cyclicLoad.Tag = 'CyclicLoadUnit';
            view.tagAxisRow(view.controls.cyclic.load, 'CyclicLoad');
            view.controls.cyclic.unloadMode = TestControlFactory.dropRow( ...
                grid, 6, 'Unload mode', {'Displacement', 'Force'});
            view.controls.cyclic.unloadMode.Tag = 'CyclicUnloadMode';
            [view.controls.cyclic.unload, ...
                view.unitLabels.cyclicUnload] = ...
                TestControlFactory.axisRow( ...
                grid, 7, 'Unload endpoint', 0, 'mm', changed);
            view.unitLabels.cyclicUnload.Tag = 'CyclicUnloadUnit';
            view.tagAxisRow(view.controls.cyclic.unload, 'CyclicUnload');
            view.controls.cyclic.rate = TestControlFactory.axisRow( ...
                grid, 8, 'Movement speed', 1, 'mm/s', changed);
            view.tagAxisRow(view.controls.cyclic.rate, 'CyclicSpeed');
            view.configurePositiveAxisRow(view.controls.cyclic.rate);
            view.controls.cyclic.forceTolerance = ...
                TestControlFactory.axisRow(grid, 9, ...
                'Force endpoint tolerance', 1, '%', changed);
            view.configurePercentAxisRow( ...
                view.controls.cyclic.forceTolerance);
            view.controls.cyclic.holdTime = TestControlFactory.axisRow( ...
                grid, 10, 'Endpoint hold time', 0, 's', changed);
            view.configureNonnegativeAxisRow(view.controls.cyclic.holdTime);
            post = TestControlFactory.optionalRow(grid, 11, ...
                'TIFF sampling period', 0.1, 's', ...
                @() view.refreshDependencies());
            view.controls.cyclic.postProcess.enabled = post.enabled;
            view.controls.cyclic.postProcess.samplingPeriod = post.value;
            view.configureNonnegativeField(post.value);
            view.controls.cyclic.postProcess.includePrePost = ...
                TestControlFactory.checkRow(grid, 12, ...
                'Include pre/post-test frames', false);
            view.configurePostProcessTooltips( ...
                view.controls.cyclic.postProcess);
            view.runButtons(end + 1) = TestControlFactory.runButton( ...
                grid, 13, 'RUN CYCLIC TEST', view.callbacks.runCyclic);
            view.controls.cyclic.loadMode.ValueChangedFcn = ...
                @(~, ~) view.endpointModeChanged();
            view.controls.cyclic.unloadMode.ValueChangedFcn = ...
                @(~, ~) view.endpointModeChanged();
            tip = view.displacementTooltip();
            view.controls.cyclic.loadMode.Tooltip = tip;
            view.controls.cyclic.unloadMode.Tooltip = tip;
        end

        function createGeneralTestTab(view, tab)
            grid = TestControlFactory.formGrid(tab, 6);
            view.controls.general.testFile = TestControlFactory.textRow( ...
                grid, 2, 'Complete JSON definition', 'No file selected');
            browse = uibutton(grid, 'Text', 'Browse', ...
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
                'Run is enabled after a schemaVersion 2 JSON file validates.';
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
                'Return to pre-test final position', 'Unload to zero force', ...
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

        %% Control dependencies and runtime locking
        function refreshDependencies(view)
            % Compute dependency state first; the runtime lock is applied last.
            view.refreshModePresentation();
            view.applyHardwareLimits();
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
            view.setAxisByMode(view.controls.pre.forceTolerance, preAny);
            view.setAxisByMode(view.controls.pre.holdTime, preCyclic);
            preloadEnabled = view.controls.pre.preload.enabled.Value;
            view.setAxisByMode(view.controls.pre.preload.value, ...
                preloadEnabled);
            view.setAxisByMode( ...
                view.controls.pre.preload.holdTime, preloadEnabled);
            view.setAxisByMode(view.controls.single.secondary, ...
                ~view.controls.single.rupture.enabled.Value && ...
                ~strcmp(view.controls.single.secondaryMode.Value, 'None'));
            view.setEnabled(view.controls.single.secondaryMode, ...
                ~view.controls.single.rupture.enabled.Value);
            view.setEnabled(view.controls.single.rupture.value, ...
                view.controls.single.rupture.enabled.Value);
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

        %% General-test import
        function browseGeneralTest(view)
            [file, folder] = uigetfile({'*.json', ...
                'General Test JSON (*.json)'});
            restoreFigureFocus(view.parentFig);
            if isequal(file, 0)
                return;
            end
            filename = fullfile(folder, file);
            try
                % A valid imported definition is authoritative for axis selection.
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

        %% Preset serialization and validation
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

        %% Post-test selection and change notifications
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

        function endpointModeChanged(view)
            adjusted = view.applyHardwareLimits();
            view.refreshDependencies();
            view.notifyPreviewChanged();
            if adjusted
                uialert(view.parentFig, ...
                    ['The endpoint was reset to 0 because it is outside ' ...
                    'the selected force mode limit.'], ...
                    'Endpoint adjusted');
            end
        end

        function notifyPreviewChanged(view)
            if isfield(view.callbacks, 'previewChanged') && ...
                    ~isempty(view.callbacks.previewChanged)
                view.callbacks.previewChanged();
            end
        end

        %% Numeric constraints and UI helpers
        function adjusted = applyHardwareLimits(view)
            adjusted = false;
            config = view.hardwareConfigGetter();
            if isempty(config) || ~isfield(config, 'plc')
                return;
            end
            adjusted = view.configureSpeedLimits( ...
                view.controls.pre.rate, config) || adjusted;
            adjusted = view.configureSpeedLimits( ...
                view.controls.single.rate, config) || adjusted;
            adjusted = view.configureSpeedLimits( ...
                view.controls.cyclic.rate, config) || adjusted;

            adjusted = view.configureForceLimits( ...
                view.controls.pre.preload.value, config) || adjusted;
            adjusted = view.configureForceLimits( ...
                view.controls.pre.load, config) || adjusted;
            adjusted = view.configureForceLimits( ...
                view.controls.pre.unload, config) || adjusted;
            adjusted = view.configureEndpointLimits( ...
                view.controls.single.primary, ...
                view.controls.single.primaryMode.Value, config) || adjusted;
            adjusted = view.configureEndpointLimits( ...
                view.controls.single.secondary, ...
                view.controls.single.secondaryMode.Value, config) || adjusted;
            adjusted = view.configureEndpointLimits( ...
                view.controls.cyclic.load, ...
                view.controls.cyclic.loadMode.Value, config) || adjusted;
            adjusted = view.configureEndpointLimits( ...
                view.controls.cyclic.unload, ...
                view.controls.cyclic.unloadMode.Value, config) || adjusted;
        end

        function refreshModePresentation(view)
            TestControlFactory.setUnitLabel( ...
                view.unitLabels.singlePrimary, ...
                view.unitForMode(view.controls.single.primaryMode.Value));
            TestControlFactory.setUnitLabel( ...
                view.unitLabels.singleSecondary, ...
                view.unitForMode(view.controls.single.secondaryMode.Value));
            TestControlFactory.setUnitLabel( ...
                view.unitLabels.cyclicLoad, ...
                view.unitForMode(view.controls.cyclic.loadMode.Value));
            TestControlFactory.setUnitLabel( ...
                view.unitLabels.cyclicUnload, ...
                view.unitForMode(view.controls.cyclic.unloadMode.Value));
        end

        function adjusted = configureSpeedLimits(view, controls, config)
            adjusted = false;
            for item = {'x', 'y'}
                field = item{1};
                maximum = double(config.plc.([field, 'Axis']).fMaxVelocity);
                changed = view.setNumericLimits(controls.(field), ...
                    [0, maximum], 'off', 'on', min(1, maximum));
                controls.(field).Tooltip = sprintf( ...
                    'Value must be greater than 0 and at most %.6g mm per s.', ...
                    maximum);
                adjusted = changed || adjusted;
            end
        end

        function adjusted = configureForceLimits(view, controls, config)
            adjusted = false;
            for item = {'x', 'y'}
                field = item{1};
                maximum = double(config.plc.([field, 'Axis']).fMaxForce);
                changed = view.setNumericLimits(controls.(field), ...
                    [-maximum, maximum], 'off', 'off', 0);
                controls.(field).Tooltip = sprintf( ...
                    'Absolute force must remain below %.6g N.', maximum);
                adjusted = changed || adjusted;
            end
        end

        function adjusted = configureEndpointLimits( ...
                view, controls, mode, config)
            if strcmp(mode, 'Force')
                adjusted = view.configureForceLimits(controls, config);
                return;
            end
            adjusted = false;
            for item = {'x', 'y'}
                field = item{1};
                changed = view.setNumericLimits(controls.(field), ...
                    [-Inf, Inf], 'on', 'on', 0);
                controls.(field).Tooltip = view.displacementTooltip();
                adjusted = changed || adjusted;
            end
        end

        function adjusted = setNumericLimits( ...
                ~, control, limits, lowerInclusive, upperInclusive, fallback)
            value = double(control.Value);
            lowerValid = value > limits(1) || ...
                (strcmp(lowerInclusive, 'on') && value == limits(1));
            upperValid = value < limits(2) || ...
                (strcmp(upperInclusive, 'on') && value == limits(2));
            adjusted = ~(lowerValid && upperValid);
            if adjusted
                control.Value = fallback;
            end
            control.Limits = limits;
            control.LowerLimitInclusive = lowerInclusive;
            control.UpperLimitInclusive = upperInclusive;
        end

        function unit = unitForMode(~, mode)
            switch char(mode)
                case 'Displacement'
                    unit = 'mm';
                case 'Force'
                    unit = 'N';
                otherwise
                    unit = '';
            end
        end

        function tagAxisRow(~, controls, prefix)
            controls.x.Tag = [prefix, 'X'];
            controls.y.Tag = [prefix, 'Y'];
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

        function configurePercentAxisRow(~, controls)
            for field = {'x', 'y'}
                control = controls.(field{1});
                control.Limits = [0, 100];
                control.Tooltip = ...
                    ['Percentage of each force endpoint, using the hardware ' ...
                    'force tolerance as the minimum (0 to 100%).'];
            end
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
