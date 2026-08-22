classdef View < handle
    %VIEW Coordinates the main window and its independent UI components.

    properties
        % Controller dependency and top-level application window
        controller Control
        fig
        % Toolbar controls and owned UI components
        camSwitch
        plcSwitch
        settingsCamBtn
        postProcessButton
        systemStatusLabel
        testPanel TestPanel
        machinePanel MachinePanel
        settingsWindow SettingsWindow
        % UI state mirrored from the controller and PLC
        hasError = false
        errorMessage = ''
        operationActive = false
    end

    methods
        %% Window lifecycle and controller-facing facade
        function app = View(controller)
            app.controller = controller;
            app.createMainWindow();
            app.settingsWindow = SettingsWindow(controller.settings, app.fig, @() app.previewChanged());
            app.loadStartupDefaults();
            app.updateErrorStatus(false, '');
            app.updateMachineStatus([], false);
            app.fig.CloseRequestFcn = @(~, ~) app.shutdown();
        end

        function shutdown(app)
            % Tear down timers before releasing hardware or UI objects.
            app.fig.CloseRequestFcn = '';
            try
                app.stopAndDeleteTimer(app.controller.plcReadTimer);
                app.stopAndDeleteTimer(app.controller.displayTimer);
            catch
            end
            try
                % Abort is best-effort because shutdown may follow a controller error.
                app.controller.safeAbort('Application shutdown');
            catch
            end
            try
                app.controller.camera.closeCam();
            catch
                % Camera cleanup must not prevent PLC power-off.
            end
            try
                app.controller.plc.disconnectPLC();
            catch
                % Hardware objects may already have been released.
            end
            if ~isempty(app.settingsWindow) && isvalid(app.settingsWindow)
                app.settingsWindow.close();
            end
            if ~isempty(app.fig) && isvalid(app.fig)
                delete(app.fig);
            end
            applicationKey = 'AortyApplicationView';
            if isappdata(groot, applicationKey)
                registered = getappdata(groot, applicationKey);
                if isempty(registered) || ~isvalid(registered) || isequal(registered, app)
                    rmappdata(groot, applicationKey);
                end
            end
            delete(app);
        end

        function connectCameraCallback(app, src)
            % Connection changes are locked while acquisition may own the camera.
            if app.operationActive || app.controller.testRunning || app.controller.model.isRecording
                if app.controller.camera.connected
                    src.Value = 'ON';
                else
                    src.Value = 'OFF';
                end
                uialert(app.fig, ...
                    'Camera connection cannot change while a test is active.', ...
                    'Test active');
                return;
            end
            app.controller.camera.connectCamera(app, src);
            if src.Value == "ON" && app.controller.camera.connected
                try
                    app.ensureHardwareConfigLoaded();
                    app.controller.settings.applyCameraConfig();
                catch exception
                    app.controller.camera.closeCam();
                    src.Value = 'OFF';
                    uialert(app.fig, exception.message, ...
                        'Cannot apply camera hardware settings');
                end
            end
        end

        function connectPlcCallback(app, src)
            app.controller.plc.connectPLC(app, src);
            if src.Value ~= "ON" || ~app.controller.plc.connected
                return;
            end
            try
                app.ensureHardwareConfigLoaded();
                app.controller.settings.applyPlcConfig();
                app.updateMachineStatus( app.controller.plc.pollStatus(), true);
            catch exception
                app.controller.plc.disconnectPLC();
                src.Value = 'OFF';
                app.updateMachineStatus([], false);
                uialert(app.fig, exception.message, ...
                    'Cannot apply PLC hardware settings');
            end
        end

        function updateErrorStatus(app, hasError, message)
            app.hasError = logical(hasError);
            if nargin < 3 || isempty(message)
                message = '';
            end
            app.errorMessage = char(message);
            app.machinePanel.updateErrorStatus( ...
                app.hasError, app.errorMessage);
        end

        function openSettingsWindow(app)
            app.settingsWindow.show();
            app.settingsWindow.setMachineIdle( ...
                app.machinePanel.isIdle());
        end

        function config = getTestConfiguration(app)
            config = app.testPanel.getConfiguration();
        end

        function mode = getAxisMode(app)
            mode = app.testPanel.getAxisMode();
        end

        function definition = getGeneralTestDefinition(app)
            definition = app.testPanel.getGeneralDefinition();
        end

        function values = getManualMotion(app)
            values = app.machinePanel.getManualMotion();
        end

        function mode = getPlotMode(app)
            mode = app.machinePanel.getPlotMode();
        end

        function updateCameraFrame(app, frame)
            app.machinePanel.updateCameraFrame(frame);
        end

        function appendPlotData(app, batch, samplePeriod)
            app.machinePanel.appendPlotData(batch, samplePeriod);
        end

        function updateMachineStatus(app, statuses, connected)
            % A disconnect invalidates buffered samples from the previous session.
            if ~connected
                app.controller.samples.clear();
            end
            app.machinePanel.updateMachineStatus(statuses, connected);
            app.updateSystemStatusIndicator(statuses, connected);
            app.testPanel.setMachineAvailability(connected, statuses);
            if ~isempty(app.settingsWindow) && isvalid(app.settingsWindow)
                app.settingsWindow.setMachineIdle( ...
                    app.machinePanel.isIdle());
            end
        end

        function setOperationActive(app, active)
            app.operationActive = logical(active);
            app.machinePanel.setOperationActive(app.operationActive);
            app.testPanel.setRuntimeLocked(app.operationActive);
            app.setEnabled(app.camSwitch, ~app.operationActive);
            app.setEnabled(app.plcSwitch, ~app.operationActive);
            app.setEnabled(app.settingsCamBtn, ~app.operationActive);
            app.setEnabled(app.postProcessButton, ~app.operationActive);
            if ~isempty(app.settingsWindow) && isvalid(app.settingsWindow)
                app.settingsWindow.setMachineIdle( ...
                    app.machinePanel.isIdle());
            end
        end
    end

    methods (Access = private)
        %% Window construction
        function createMainWindow(app)
            screen = get(groot, 'ScreenSize');
            width = min(1480, screen(3) - 80);
            height = min(860, screen(4) - 120);
            app.fig = uifigure( ...
                'Name', 'Aorty - biaxial test control', ...
                'Position', [40, 50, width, height], ...
                'Color', [0.96, 0.96, 0.96]);
            mainGrid = uigridlayout(app.fig, [2, 3]);
            mainGrid.RowHeight = {72, '1x'};
            mainGrid.ColumnWidth = {'1.25x', '0.72x', '1x'};
            mainGrid.Padding = [10, 10, 10, 10];
            mainGrid.RowSpacing = 8;
            mainGrid.ColumnSpacing = 8;

            callbacks = struct( ...
                'runPre', @(~, ~) app.onRunPreTest(), ...
                'runSingle', @(~, ~) app.onRunSingleTest(), ...
                'runCyclic', @(~, ~) app.onRunCyclicTest(), ...
                'runGeneral', @(~, ~) app.onRunGeneralTest(), ...
                'axisModeChanged', @() app.axisModeChanged(), ...
                'previewChanged', @() app.previewChanged());
            app.testPanel = TestPanel(app.controller.settings, app.fig, callbacks);
            app.createToolbar(mainGrid);
            app.testPanel.create(mainGrid);

            machineCallbacks = struct( ...
                'liveAction', @() app.onLiveAction(), ...
                'save', @() app.onSavePosition(), ...
                'restore', @() app.onRestorePosition(), ...
                'error', @() app.onErrorButtonClicked(), ...
                'power', @() app.onPowerClicked(), ...
                'stop', @(button) app.controller.panicStop(button), ...
                'jog', @(axis, direction, pressed) ...
                app.onJogAxis(axis, direction, pressed));
            app.machinePanel = MachinePanel( ...
                mainGrid, machineCallbacks, ...
                @() app.getAxisMode(), ...
                @() app.testPanel.getForceReferencePreview());
        end

        function createToolbar(app, mainGrid)
            toolbar = uipanel(mainGrid, 'Title', 'Test configuration');
            toolbar.Layout.Row = 1;
            toolbar.Layout.Column = [1, 3];
            grid = uigridlayout(toolbar, [1, 10]);
            grid.ColumnWidth = {135, 70, '1x', 60, 72, 120, ...
                105, 120, 120, 190};
            grid.Padding = [6, 2, 6, 2];
            grid.ColumnSpacing = 6;
            app.postProcessButton = uibutton(grid, ...
                'Text', 'Post-process data', ...
                'Tooltip', 'Process a previously recorded test directory', ...
                'ButtonPushedFcn', @(~, ~) app.onManualPostProcess());
            app.testPanel.createToolbarControls(grid);
            app.settingsCamBtn = uibutton(grid, ...
                'Text', 'HW settings', ...
                'ButtonPushedFcn', @(~, ~) app.openSettingsWindow());
            app.camSwitch = app.connectionSwitch( ...
                grid, 'Camera', @(src, ~) app.connectCameraCallback(src));
            app.plcSwitch = app.connectionSwitch( ...
                grid, 'PLC', ...
                @(src, ~) app.connectPlcCallback(src));
            statusPanel = uipanel(grid, 'Title', 'System status');
            statusGrid = uigridlayout(statusPanel, [1, 1]);
            statusGrid.Padding = [4, 0, 4, 0];
            app.systemStatusLabel = uilabel(statusGrid, ...
                'Text', 'Disconnected', ...
                'HorizontalAlignment', 'center', ...
                'FontWeight', 'bold', ...
                'FontColor', [0.35, 0.35, 0.35], ...
                'BackgroundColor', [0.88, 0.88, 0.88]);
        end

        function control = connectionSwitch(~, parent, titleText, callback)
            container = uipanel(parent, 'Title', titleText);
            grid = uigridlayout(container, [1, 1]);
            grid.Padding = [4, 0, 4, 0];
            control = uiswitch(grid, 'slider', ...
                'Items', {'OFF', 'ON'}, ...
                'ValueChangedFcn', callback);
            control.Value = 'OFF';
        end

        %% PLC status presentation
        function updateSystemStatusIndicator(app, statuses, connected)
            if ~connected || isempty(statuses)
                app.systemStatusLabel.Text = 'Disconnected';
                app.systemStatusLabel.FontColor = [0.35, 0.35, 0.35];
                app.systemStatusLabel.BackgroundColor = [0.88, 0.88, 0.88];
                return;
            end
            values = [double(statuses.X.systemStatus), double(statuses.Y.systemStatus)];
            active = values(values ~= 0);
            if isempty(active)
                status = 0;
            elseif any(active ~= active(1))
                [xName, ~] = app.systemStatusStyle(values(1));
                [yName, ~] = app.systemStatusStyle(values(2));
                app.systemStatusLabel.Text = sprintf( ...
                    'X %d %s | Y %d %s', ...
                    values(1), xName, values(2), yName);
                app.systemStatusLabel.FontColor = [0.65, 0.1, 0.1];
                app.systemStatusLabel.BackgroundColor = ...
                    [1.0, 0.78, 0.72];
                return;
            else
                status = active(1);
            end
            [name, color] = app.systemStatusStyle(status);
            app.systemStatusLabel.Text = sprintf('%d - %s', status, name);
            app.systemStatusLabel.FontColor = [0.12, 0.12, 0.12];
            app.systemStatusLabel.BackgroundColor = color;
        end

        function [name, color] = systemStatusStyle(~, status)
            switch double(status)
                case 0
                    name = 'Idle';
                    color = [0.88, 0.88, 0.88];
                case 1
                    name = 'Error';
                    color = [1.0, 0.70, 0.66];
                case 2
                    name = 'Homing';
                    color = [0.78, 0.88, 1.0];
                case 3
                    name = 'Stopping';
                    color = [1.0, 0.78, 0.62];
                case 4
                    name = 'Taring';
                    color = [0.88, 0.80, 1.0];
                case 5
                    name = 'BasicMove';
                    color = [0.78, 0.88, 1.0];
                case 6
                    name = 'ForceMode';
                    color = [0.74, 0.90, 0.94];
                case 10
                    name = 'Pretension';
                    color = [0.78, 0.88, 1.0];
                case 11
                    name = 'PreTestCyclic';
                    color = [0.78, 0.88, 1.0];
                case 20
                    name = 'SingleTest';
                    color = [0.72, 0.92, 0.76];
                case 21
                    name = 'CyclicTest';
                    color = [0.72, 0.92, 0.76];
                case 30
                    name = 'PostTest';
                    color = [1.0, 0.88, 0.65];
                otherwise
                    name = 'Unknown';
                    color = [0.88, 0.88, 0.88];
            end
        end

        %% UI callbacks
        function axisModeChanged(app)
            app.machinePanel.refreshAxisMode();
            app.testPanel.setMachineAvailability(app.machinePanel.connected, app.machinePanel.statuses);
        end

        function previewChanged(app)
            if ~isempty(app.machinePanel) && isvalid(app.machinePanel)
                app.machinePanel.refreshAxisMode();
            end
        end

        function onManualPostProcess(app)
            folder = uigetdir('', 'Choose recorded test directory');
            restoreFigureFocus(app.fig);
            if isequal(folder, 0)
                return;
            end
            settings = promptPostProcessOptions(app.fig);
            if isempty(settings)
                return;
            end
            progress = uiprogressdlg(app.fig, ...
                'Title', 'Post-processing', ...
                'Message', 'Creating TIFF files...', ...
                'Indeterminate', 'on');
            try
                result = app.controller.runManualPostProcessing( ...
                    folder, settings.samplingPeriod, ...
                    settings.includePrePost);
                if isvalid(progress), close(progress); end
                if isfield(result, 'status') && ...
                        strcmpi(result.status, 'skipped')
                    uialert(app.fig, result.message, ...
                        'Post-processing skipped', 'Icon', 'info');
                    return;
                end
                uialert(app.fig, sprintf( ...
                    'Exported %d TIFF file(s) to:\n%s', ...
                    result.exportedFrameCount, result.outputFolder), ...
                    'Post-processing complete', 'Icon', 'success');
            catch exception
                if isvalid(progress), close(progress); end
                uialert(app.fig, exception.message, ...
                    'Post-processing failed', 'Icon', 'error');
            end
        end

        function onRunPreTest(app)
            app.runUiAction( ...
                @() app.controller.runPreTest(app), ...
                'Cannot start pre-test');
        end

        function onRunSingleTest(app)
            app.runUiAction( ...
                @() app.controller.runSingleTest(app), ...
                'Cannot start Single Test');
        end

        function onRunCyclicTest(app)
            app.runUiAction( ...
                @() app.controller.runCyclicTest(app), ...
                'Cannot start Cyclic Test');
        end

        function onRunGeneralTest(app)
            app.runUiAction( ...
                @() app.controller.runGeneralTest(app), ...
                'Cannot start General Test');
        end

        function onLiveAction(app)
            if strcmp(app.machinePanel.getPlotMode(), 'Force')
                action = @() app.controller.tare(app.getAxisMode());
                titleText = 'Cannot tare load cells';
            else
                action = @() app.controller.moveToLowerLimit(app.getAxisMode());
                titleText = 'Cannot move to lower limit';
            end
            app.runUiAction(action, titleText);
        end

        function onErrorButtonClicked(app)
            if ~app.hasError
                return;
            end
            message = app.errorMessage;
            if isempty(message)
                message = 'The PLC reported an unspecified error.';
            end
            choice = uiconfirm(app.fig, message, 'PLC error', ...
                'Options', {'Reset', 'Cancel'}, ...
                'DefaultOption', 2, 'CancelOption', 2, ...
                'Icon', 'error');
            if strcmp(choice, 'Reset')
                app.runUiAction( ...
                    @() app.controller.resetErrors(), ...
                    'Cannot reset PLC error');
            end
        end

        function onPowerClicked(app)
            powered = app.machinePanel.selectedAxesPowered();
            app.runUiAction( ...
                @() app.controller.setPower( ...
                app.getAxisMode(), ~powered), ...
                'Cannot change axis power');
        end

        function onSavePosition(app)
            app.runUiAction( ...
                @() app.controller.savePosition(app), ...
                'Cannot save position');
        end

        function onRestorePosition(app)
            app.runUiAction( ...
                @() app.controller.restorePosition(app), ...
                'Cannot restore position');
        end

        function onJogAxis(app, axisName, direction, pressed)
            if pressed && ~app.testPanel.isAxisActive(axisName)
                return;
            end
            manual = app.machinePanel.getManualMotion();
            app.runUiAction( ...
                @() app.controller.jog(axisName, pressed, ...
                direction * manual.speed.(axisName)), ...
                sprintf('Cannot jog %s axis', upper(axisName)));
        end

        %% Shared callback helpers
        function runUiAction(app, action, titleText)
            try
                action();
            catch exception
                uialert(app.fig, exception.message, titleText);
            end
        end

        function setEnabled(~, control, enabled)
            if enabled
                control.Enable = 'on';
            else
                control.Enable = 'off';
            end
        end

        function loadStartupDefaults(app)
            try
                app.controller.settings.loadHwConfig('default');
            catch exception
                uialert(app.fig, exception.message, ...
                    'Cannot load default hardware settings');
                return;
            end
            try
                app.testPanel.loadPresetByName('default');
            catch exception
                uialert(app.fig, exception.message, ...
                    'Cannot load default test preset');
            end
        end

        function ensureHardwareConfigLoaded(app)
            if isempty(app.controller.settings.hwConfig)
                app.controller.settings.loadHwConfig('default');
            end
        end

        function stopAndDeleteTimer(~, timerObject)
            if ~isempty(timerObject) && isvalid(timerObject)
                stop(timerObject);
                delete(timerObject);
            end
        end
    end
end
