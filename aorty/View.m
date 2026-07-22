classdef View < handle
    %VIEW User interface for the biaxial biological test machine.

    properties
        controler Control

        % Main window and compatibility handles used by Control.
        fig
        mainGrid
        cameraPanel
        cameraAxes
        camImageHandle
        camSwitch
        settingsCamBtn
        tenzoPanel
        fxAxes
        fxLine
        fyAxes
        fyLine
        plcPanel
        plcSwitch
        settingsPlcBtn
        modeDrop
        dynamicControlGroup
        posX
        posY
        velX
        velY

        testPanel TestPanel
        jogButtons = struct()
        liveActionButton
        errorButton
        hasError = false
        errorMessage = ''

        settingsWindow SettingsWindow
    end

    methods
        % View handles this operation.
        function app = View(controler)
            app.controler = controler;
            app.createMainWindow();
            app.settingsWindow = SettingsWindow(controler.settings, app.fig);
            app.applyAxisMode();
            app.updateErrorStatus(false, '');
            app.fig.CloseRequestFcn = @(~, ~) app.shutdown();
        end

        % shutdown handles this operation.
        function shutdown(app)
            app.fig.CloseRequestFcn = '';
            try
                if ~isempty(app.controler.plcReadTimer) && isvalid(app.controler.plcReadTimer)
                    stop(app.controler.plcReadTimer);
                    delete(app.controler.plcReadTimer);
                end
                if ~isempty(app.controler.displayTimer) && isvalid(app.controler.displayTimer)
                    stop(app.controler.displayTimer);
                    delete(app.controler.displayTimer);
                end
            catch
            end
            try
                app.controler.safeAbort('Application shutdown');
            catch
            end
            try
                app.controler.camera.closeCam();
                app.controler.plc.disconnectPLC();
            catch
                % Hardware may already be disconnected or destroyed.
            end

            if ~isempty(app.settingsWindow) && isvalid(app.settingsWindow)
                app.settingsWindow.close();
            end
            if ~isempty(app.fig) && isvalid(app.fig)
                delete(app.fig);
            end
            delete(app);
        end

        % connectCameraCallback handles this operation.
        function connectCameraCallback(app, src)
            app.controler.camera.connectCamera(app, src);
        end

        % updateErrorStatus handles this operation.
        function updateErrorStatus(app, hasError, message)
            app.hasError = logical(hasError);
            if nargin < 3 || isempty(message)
                message = '';
            end
            app.errorMessage = char(message);

            if isempty(app.errorButton) || ~isvalid(app.errorButton)
                return;
            end
            if app.hasError
                app.errorButton.Text = 'ERROR / RESET';
                app.errorButton.BackgroundColor = [0.95, 0.35, 0.3];
                if isempty(app.errorMessage)
                    app.errorButton.Tooltip = 'PLC error reported';
                else
                    app.errorButton.Tooltip = app.errorMessage;
                end
            else
                app.errorButton.Text = 'System OK';
                app.errorButton.BackgroundColor = [0.55, 0.85, 0.55];
                app.errorButton.Tooltip = 'No PLC error reported';
            end
        end

        % openSettingsWindow handles this operation.
        function openSettingsWindow(app)
            app.settingsWindow.show();
        end

        % getTestConfiguration handles this operation.
        function config = getTestConfiguration(app)
            config = app.testPanel.getConfiguration();
        end

        % getAxisMode handles this operation.
        function mode = getAxisMode(app)
            mode = app.testPanel.getAxisMode();
        end

        % getPostTestAction handles this operation.
        function action = getPostTestAction(app)
            action = app.testPanel.getPostTestAction();
        end

        % getManualMotion handles this operation.
        function values = getManualMotion(app)
            values.distance = struct('X', app.posX.Value, 'Y', app.posY.Value);
            values.speed = struct('X', app.velX.Value, 'Y', app.velY.Value);
        end
    end

    methods (Access = private)
        % createMainWindow handles this operation.
        function createMainWindow(app)
            screen = get(groot, 'ScreenSize');
            width = min(1480, screen(3) - 80);
            height = min(860, screen(4) - 120);
            app.fig = uifigure( ...
                'Name', 'Aorty - biaxial test control', ...
                'Position', [40, 50, width, height], ...
                'Color', [0.96, 0.96, 0.96]);

            app.mainGrid = uigridlayout(app.fig, [2, 3]);
            app.mainGrid.RowHeight = {72, '1x'};
            app.mainGrid.ColumnWidth = {'1.25x', '0.72x', '1x'};
            app.mainGrid.Padding = [10, 10, 10, 10];
            app.mainGrid.RowSpacing = 8;
            app.mainGrid.ColumnSpacing = 8;

            callbacks = struct( ...
                'runPre', @(~, ~) app.onRunPreTest(), ...
                'runSingle', @(~, ~) app.onRunSingleTest(), ...
                'runCyclic', @(~, ~) app.onRunCyclicTest(), ...
                'runGeneral', @(~, ~) app.onRunGeneralTest(), ...
                'axisModeChanged', @() app.applyAxisMode());
            app.testPanel = TestPanel(app.controler.settings, app.fig, callbacks);

            app.createToolbar();
            app.testPanel.create(app.mainGrid);
            app.createTenzoPanel();
            app.createMachinePanel();
        end

        % createToolbar handles this operation.
        function createToolbar(app)
            toolbar = uipanel(app.mainGrid, 'Title', 'Test configuration');
            toolbar.Layout.Row = 1;
            toolbar.Layout.Column = [1, 3];

            grid = uigridlayout(toolbar, [1, 8]);
            grid.ColumnWidth = {70, '1x', 60, 72, 120, 105, 120, 120};
            grid.Padding = [6, 2, 6, 2];
            grid.ColumnSpacing = 6;

            app.testPanel.createToolbarControls(grid);
            app.settingsCamBtn = uibutton(grid, 'Text', 'HW settings', ...
                'ButtonPushedFcn', @(~, ~) app.openSettingsWindow());
            cameraConnection = uipanel(grid, 'Title', 'Camera');
            cameraGrid = uigridlayout(cameraConnection, [1, 1]);
            cameraGrid.Padding = [4, 0, 4, 0];
            app.camSwitch = uiswitch(cameraGrid, 'slider', 'Items', {'OFF', 'ON'}, ...
                'ValueChangedFcn', @(src, ~) app.connectCameraCallback(src));
            app.camSwitch.Value = 'OFF';
            plcConnection = uipanel(grid, 'Title', 'PLC');
            plcGrid = uigridlayout(plcConnection, [1, 1]);
            plcGrid.Padding = [4, 0, 4, 0];
            app.plcSwitch = uiswitch(plcGrid, 'slider', 'Items', {'OFF', 'ON'}, ...
                'ValueChangedFcn', @(src, ~) app.controler.plc.connectPLC(app, src));
            app.plcSwitch.Value = 'OFF';
        end

        % createTenzoPanel handles this operation.
        function createTenzoPanel(app)
            app.tenzoPanel = uipanel(app.mainGrid, 'Title', 'Live loads');
            app.tenzoPanel.Layout.Row = 2;
            app.tenzoPanel.Layout.Column = 2;

            layout = uigridlayout(app.tenzoPanel, [4, 1]);
            layout.RowHeight = {34, '1x', '1x', 40};
            layout.Padding = [6, 6, 6, 6];

            app.modeDrop = uidropdown(layout, ...
                'Items', {'Force', 'Displacement'}, 'Value', 'Force', ...
                'ValueChangedFcn', @(src, ~) app.onPlotModeChanged(src.Value));

            app.fxAxes = uiaxes(layout);
            title(app.fxAxes, 'X axis');
            xlabel(app.fxAxes, 'Time [s]');
            ylabel(app.fxAxes, 'Force [N]');
            app.fxAxes.XGrid = 'on';
            app.fxAxes.YGrid = 'on';
            app.fxLine = animatedline(app.fxAxes, ...
                'Color', [0.1, 0.45, 0.8], 'LineWidth', 1.3);

            app.fyAxes = uiaxes(layout);
            title(app.fyAxes, 'Y axis');
            xlabel(app.fyAxes, 'Time [s]');
            ylabel(app.fyAxes, 'Force [N]');
            app.fyAxes.XGrid = 'on';
            app.fyAxes.YGrid = 'on';
            app.fyLine = animatedline(app.fyAxes, ...
                'Color', [0.85, 0.35, 0.18], 'LineWidth', 1.3);

            app.liveActionButton = uibutton(layout, 'Text', 'Tare load cells', ...
                'ButtonPushedFcn', @(~, ~) app.onLiveAction());
        end

        % createMachinePanel handles this operation.
        function createMachinePanel(app)
            app.plcPanel = uipanel(app.mainGrid, 'Title', 'Machine control');
            app.plcPanel.Layout.Row = 2;
            app.plcPanel.Layout.Column = 3;

            app.dynamicControlGroup = uigridlayout(app.plcPanel, [3, 1]);
            app.dynamicControlGroup.RowHeight = {'1.25x', 175, 58};
            app.dynamicControlGroup.Padding = [6, 6, 6, 6];
            app.createCameraPanel(app.dynamicControlGroup);
            app.createManualControlPanel(app.dynamicControlGroup);
            app.createMachineActions(app.dynamicControlGroup);
        end

        % createCameraPanel handles this operation.
        function createCameraPanel(app, parent)
            app.cameraPanel = uipanel(parent, 'Title', 'CAM - live view');
            layout = uigridlayout(app.cameraPanel, [2, 2]);
            layout.RowHeight = {'1x', 42};
            layout.ColumnWidth = {42, '1x'};
            layout.Padding = [4, 4, 4, 4];
            layout.RowSpacing = 4;
            layout.ColumnSpacing = 4;

            app.cameraAxes = uiaxes(layout);
            app.cameraAxes.Layout.Row = 1;
            app.cameraAxes.Layout.Column = 2;
            app.camImageHandle = image(app.cameraAxes, zeros(512, 512, 'uint8'));
            app.cameraAxes.CLim = [0, 255];
            colormap(app.cameraAxes, gray);
            axis(app.cameraAxes, 'off');
            axis(app.cameraAxes, 'image');
            app.cameraAxes.Toolbar.Visible = 'off';
            app.cameraAxes.Interactions = [];

            xControls = uigridlayout(layout, [4, 1]);
            xControls.Layout.Row = 1;
            xControls.Layout.Column = 1;
            xControls.RowHeight = {'1x', 42, 42, '1x'};
            xControls.Padding = 0;
            xControls.RowSpacing = 4;
            xLabel = uilabel(xControls, 'Text', 'X', ...
                'FontWeight', 'bold', 'HorizontalAlignment', 'center');
            xLabel.Layout.Row = 1;
            app.jogButtons.xMinus = app.addJogButton(xControls, 2, 1, char(8592), 'X', -1);
            app.jogButtons.xPlus = app.addJogButton(xControls, 3, 1, char(8594), 'X', 1);

            yControls = uigridlayout(layout, [1, 4]);
            yControls.Layout.Row = 2;
            yControls.Layout.Column = 2;
            yControls.ColumnWidth = {'1x', 42, 42, '1x'};
            yControls.Padding = 0;
            yControls.ColumnSpacing = 4;
            yLabel = uilabel(yControls, 'Text', 'Y', ...
                'FontWeight', 'bold', 'HorizontalAlignment', 'right');
            yLabel.Layout.Column = 1;
            app.jogButtons.yMinus = app.addJogButton(yControls, 1, 2, char(8595), 'Y', -1);
            app.jogButtons.yPlus = app.addJogButton(yControls, 1, 3, char(8593), 'Y', 1);
        end

        % createManualControlPanel handles this operation.
        function createManualControlPanel(app, parent)
            panel = uipanel(parent, 'Title', 'Manual positioning');
            grid = uigridlayout(panel, [3, 3]);
            grid.RowHeight = {30, 34, 34};
            grid.ColumnWidth = {50, '1x', '1x'};
            grid.Padding = [6, 4, 6, 4];

            uilabel(grid, 'Text', 'Axis', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            uilabel(grid, 'Text', 'Distance [mm]', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            uilabel(grid, 'Text', 'Speed [mm/s]', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');

            uilabel(grid, 'Text', 'X', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            app.posX = uieditfield(grid, 'numeric', 'Value', 10);
            app.velX = uieditfield(grid, 'numeric', 'Value', 1, 'Limits', [0, Inf]);

            uilabel(grid, 'Text', 'Y', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            app.posY = uieditfield(grid, 'numeric', 'Value', 10);
            app.velY = uieditfield(grid, 'numeric', 'Value', 1, 'Limits', [0, Inf]);

        end

        % createMachineActions handles this operation.
        function createMachineActions(app, parent)
            grid = uigridlayout(parent, [1, 4]);
            grid.ColumnWidth = {'1x', '1x', 120, 115};
            grid.Padding = 0;
            uibutton(grid, 'Text', 'Save position', ...
                'ButtonPushedFcn', @(~, ~) app.onSavePosition());
            uibutton(grid, 'Text', 'Restore position', ...
                'ButtonPushedFcn', @(~, ~) app.onRestorePosition());
            app.errorButton = uibutton(grid, 'Text', 'System OK', ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.55, 0.85, 0.55], ...
                'Tooltip', 'No PLC error reported', ...
                'ButtonPushedFcn', @(~, ~) app.onErrorButtonClicked());
            stopButton = uibutton(grid, 'state', 'Text', 'STOP', ...
                'FontWeight', 'bold', 'FontSize', 16, ...
                'BackgroundColor', [1, 0.45, 0.2], ...
                'ValueChangedFcn', @(src, ~) app.controler.panicStop(src));
            stopButton.Tooltip = 'Controlled software stop; this is not a safety-rated emergency stop.';
        end

        % addJogButton handles this operation.
        function button = addJogButton(app, grid, row, column, text, axisName, direction)
            button = uibutton(grid, 'Text', text, ...
                'ButtonPushedFcn', @(~, ~) app.onJogAxis(axisName, direction));
            button.Layout.Row = row;
            button.Layout.Column = column;
        end

        % setControlEnabled handles this operation.
        function setControlEnabled(~, control, enabled)
            if enabled
                control.Enable = 'on';
            else
                control.Enable = 'off';
            end
        end

        % applyAxisMode handles this operation.
        function applyAxisMode(app)
            mode = app.getAxisMode();
            enableX = strcmp(mode, 'Both') || strcmp(mode, 'X only');
            enableY = strcmp(mode, 'Both') || strcmp(mode, 'Y only');
            app.setControlEnabled(app.posX, enableX);
            app.setControlEnabled(app.velX, enableX);
            app.setControlEnabled(app.posY, enableY);
            app.setControlEnabled(app.velY, enableY);
            app.setControlEnabled(app.jogButtons.xMinus, enableX);
            app.setControlEnabled(app.jogButtons.xPlus, enableX);
            app.setControlEnabled(app.jogButtons.yMinus, enableY);
            app.setControlEnabled(app.jogButtons.yPlus, enableY);

            app.styleAxisPlot(app.fxAxes, app.fxLine, enableX, [0.1, 0.45, 0.8]);
            app.styleAxisPlot(app.fyAxes, app.fyLine, enableY, [0.85, 0.35, 0.18]);
        end

        % styleAxisPlot handles this operation.
        function styleAxisPlot(~, axesHandle, lineHandle, enabled, activeColor)
            if enabled
                axesHandle.Color = [1, 1, 1];
                axesHandle.Title.Color = [0, 0, 0];
                lineHandle.Color = activeColor;
            else
                axesHandle.Color = [0.92, 0.92, 0.92];
                axesHandle.Title.Color = [0.55, 0.55, 0.55];
                lineHandle.Color = [0.7, 0.7, 0.7];
            end
        end

        % isAxisActive handles this operation.
        function enabled = isAxisActive(app, axisName)
            enabled = app.testPanel.isAxisActive(axisName);
        end

        % UI-only or intentionally unlinked handlers.
        function onRunPreTest(app)
            app.runUiAction(@() app.controler.runPreTest(app), 'Cannot start pre-test');
        end

        % onRunSingleTest handles this operation.
        function onRunSingleTest(app)
            app.runUiAction(@() app.controler.runSingleTest(app), 'Cannot start Single Test');
        end

        % onRunCyclicTest handles this operation.
        function onRunCyclicTest(app)
            app.runUiAction(@() app.controler.runCyclicTest(app), 'Cannot start Cyclic Test');
        end

        % onRunGeneralTest handles this operation.
        function onRunGeneralTest(app)
            uialert(app.fig, 'General Test import is not available yet.', 'Unavailable');
        end

        % onTare handles this operation.
        function onTare(app)
            app.runUiAction(@() app.controler.tare(app.getAxisMode()), 'Cannot tare load cells');
        end

        % onAutoHome handles this operation.
        function onAutoHome(app)
            app.runUiAction(@() app.controler.moveToLowerLimit(app.getAxisMode()), ...
                'Cannot move to lower limit');
        end

        % onLiveAction handles this operation.
        function onLiveAction(app)
            if strcmp(app.modeDrop.Value, 'Force')
                app.onTare();
            else
                app.onAutoHome();
            end
        end

        % onErrorButtonClicked handles this operation.
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
                'DefaultOption', 2, ...
                'CancelOption', 2, ...
                'Icon', 'error');
            if strcmp(choice, 'Reset')
                app.onResetError();
            end
        end

        % onResetError handles this operation.
        function onResetError(app)
            app.runUiAction(@() app.controler.resetErrors(), 'Cannot reset PLC error');
        end

        % onSavePosition handles this operation.
        function onSavePosition(app)
            app.runUiAction(@() app.controler.savePosition(), 'Cannot save position');
        end

        % onRestorePosition handles this operation.
        function onRestorePosition(app)
            app.runUiAction(@() app.controler.restorePosition(app), 'Cannot restore position');
        end
        % onJogAxis handles this operation.
        function onJogAxis(app, axisName, direction)
            if ~app.isAxisActive(axisName)
                fprintf('Jog %s ignored because the axis is disabled.\n', axisName);
                return;
            end
            if strcmpi(axisName, 'X')
                distance = app.posX.Value;
                velocity = app.velX.Value;
            else
                distance = app.posY.Value;
                velocity = app.velY.Value;
            end
            app.runUiAction(@() app.controler.jog(axisName, direction, distance, velocity), ...
                sprintf('Cannot jog %s axis', upper(axisName)));
        end
        % onPlotModeChanged handles this operation.
        function onPlotModeChanged(app, value)
            if strcmp(value, 'Force')
                yLabel = 'Force [N]';
                app.liveActionButton.Text = 'Tare load cells';
            else
                yLabel = 'Displacement [mm]';
                app.liveActionButton.Text = 'Move to lower limit';
            end
            ylabel(app.fxAxes, yLabel);
            ylabel(app.fyAxes, yLabel);
        end

        % runUiAction handles this operation.
        function runUiAction(app, action, titleText)
            try
                action();
            catch exception
                uialert(app.fig, exception.message, titleText);
            end
        end
    end
end


