classdef View < handle
    %VIEW User interface for the biaxial biological test machine.

    properties
        controler Control

        % Main window and compatibility handles used by Control.
        fig
        mainGrid
        cameraPanel
        cameraContent
        cameraAxes
        camImageHandle
        xJogOverlay
        yJogOverlay
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
        savePositionButton
        restorePositionButton
        powerButton
        stopButton
        machineStatusLabel
        hasError = false
        errorMessage = ''
        machineConnected = false
        lastStatuses = []

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
            app.updateMachineStatus([], false);
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

        function definition = getGeneralTestDefinition(app)
            definition = app.testPanel.getGeneralDefinition();
        end

        % getManualMotion handles this operation.
        function values = getManualMotion(app)
            values.distance = struct('X', app.posX.Value, 'Y', app.posY.Value);
            values.speed = struct('X', app.velX.Value, 'Y', app.velY.Value);
        end

        function updateMachineStatus(app, statuses, connected)
            app.machineConnected = logical(connected);
            app.lastStatuses = statuses;
            if isempty(app.machineStatusLabel) || ~isvalid(app.machineStatusLabel)
                return;
            end
            if ~app.machineConnected || isempty(statuses)
                app.machineStatusLabel.Text = 'PLC disconnected';
                app.machineStatusLabel.FontColor = [0.55, 0.2, 0.2];
                app.testPanel.setMachineAvailability(false, []);
                app.applyAxisMode();
                return;
            end

            summaries = cell(1, 2);
            axisNames = {'X', 'Y'};
            for index = 1:2
                axis = axisNames{index};
                state = statuses.(axis);
                words = {};
                if state.powered, words{end + 1} = 'powered'; else, words{end + 1} = 'not powered'; end %#ok<AGROW>
                if state.working, words{end + 1} = 'busy'; end %#ok<AGROW>
                if state.stopped, words{end + 1} = 'stopped'; end %#ok<AGROW>
                if state.homing, words{end + 1} = 'homing'; end %#ok<AGROW>
                if state.homed, words{end + 1} = 'homed'; end %#ok<AGROW>
                if state.savedPositionValid, words{end + 1} = 'saved'; end %#ok<AGROW>
                if state.error
                    words{end + 1} = sprintf('ERROR %u', ...
                        state.errorCode); %#ok<AGROW>
                end
                summaries{index} = sprintf('%s: %s', axis, strjoin(words, ', '));
            end
            app.machineStatusLabel.Text = strjoin(summaries, '   |   ');
            if statuses.X.error || statuses.Y.error
                app.machineStatusLabel.FontColor = [0.75, 0.1, 0.1];
            elseif statuses.X.working || statuses.Y.working
                app.machineStatusLabel.FontColor = [0.75, 0.4, 0.05];
            else
                app.machineStatusLabel.FontColor = [0.1, 0.45, 0.15];
            end
            app.testPanel.setMachineAvailability(true, statuses);
            app.applyAxisMode();
        end

        % updateCameraFrame fills the preview while preserving image proportions.
        function updateCameraFrame(app, frame)
            if isempty(frame) || isempty(app.cameraAxes) || ...
                    ~isvalid(app.cameraAxes) || ...
                    isempty(app.camImageHandle) || ...
                    ~isvalid(app.camImageHandle)
                return;
            end

            frameHeight = size(frame, 1);
            frameWidth = size(frame, 2);
            if frameHeight < 1 || frameWidth < 1
                return;
            end

            app.camImageHandle.CData = frame;
            app.camImageHandle.XData = [1, frameWidth];
            app.camImageHandle.YData = [1, frameHeight];
            app.cameraAxes.DataAspectRatio = [1, 1, 1];
            app.cameraAxes.DataAspectRatioMode = 'manual';
            app.fitCameraImage();
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
            app.dynamicControlGroup.RowHeight = {'1.25x', 175, 124};
            app.dynamicControlGroup.Padding = [6, 6, 6, 6];
            app.createCameraPanel(app.dynamicControlGroup);
            app.createManualControlPanel(app.dynamicControlGroup);
            app.createMachineActions(app.dynamicControlGroup);
        end

        % createCameraPanel handles this operation.
        function createCameraPanel(app, parent)
            app.cameraPanel = uipanel(parent, 'Title', 'CAM - live view');
            layout = uigridlayout(app.cameraPanel, [1, 1]);
            layout.Padding = 0;
            layout.RowSpacing = 0;
            layout.ColumnSpacing = 0;

            app.cameraContent = uipanel(layout, ...
                'BorderType', 'none', 'BackgroundColor', [0, 0, 0]);
            app.cameraContent.AutoResizeChildren = 'off';

            app.cameraAxes = uiaxes(app.cameraContent);
            app.cameraAxes.Units = 'normalized';
            app.cameraAxes.Position = [0, 0, 1, 1];
            app.camImageHandle = image(app.cameraAxes, zeros(512, 512, 'uint8'));
            app.cameraAxes.CLim = [0, 255];
            app.cameraAxes.Color = [0, 0, 0];
            colormap(app.cameraAxes, gray);
            axis(app.cameraAxes, 'off');
            app.cameraAxes.Toolbar.Visible = 'off';
            app.cameraAxes.Interactions = [];

            % Jog controls float over the image and remain anchored to the
            % requested edges when the camera panel is resized.
            overlayColor = [0.10, 0.10, 0.10];
            app.xJogOverlay = uipanel(app.cameraContent, 'BorderType', 'none', ...
                'BackgroundColor', overlayColor);
            app.xJogOverlay.Units = 'pixels';
            app.xJogOverlay.Position = [6, 8, 76, 86];
            app.xJogOverlay.AutoResizeChildren = 'off';
            xControls = uigridlayout(app.xJogOverlay, [2, 1]);
            xControls.RowHeight = {'1x', '1x'};
            xControls.Padding = [2, 2, 2, 2];
            xControls.RowSpacing = 2;
            xControls.BackgroundColor = overlayColor;
            app.jogButtons.xMinus = app.addJogButton( ...
                xControls, 1, 1, [char(8592), ' X'], 'X', -1);
            app.jogButtons.xPlus = app.addJogButton( ...
                xControls, 2, 1, ['X ', char(8594)], 'X', 1);

            app.yJogOverlay = uipanel(app.cameraContent, 'BorderType', 'none', ...
                'BackgroundColor', overlayColor);
            app.yJogOverlay.Units = 'pixels';
            app.yJogOverlay.Position = [8, 6, 156, 44];
            app.yJogOverlay.AutoResizeChildren = 'off';
            yControls = uigridlayout(app.yJogOverlay, [1, 2]);
            yControls.ColumnWidth = {'1x', '1x'};
            yControls.Padding = [2, 2, 2, 2];
            yControls.ColumnSpacing = 2;
            yControls.BackgroundColor = overlayColor;
            app.jogButtons.yMinus = app.addJogButton( ...
                yControls, 1, 1, [char(8595), ' Y'], 'Y', -1);
            app.jogButtons.yPlus = app.addJogButton( ...
                yControls, 1, 2, ['Y ', char(8593)], 'Y', 1);

            app.cameraContent.SizeChangedFcn = @(~, ~) ...
                app.resizeCameraOverlays();
            app.resizeCameraOverlays();
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
            grid = uigridlayout(parent, [3, 6]);
            grid.ColumnWidth = {'1x', '1x', '1x', '1x', '1x', '1x'};
            grid.RowHeight = {24, 36, 42};
            grid.RowSpacing = 5;
            grid.ColumnSpacing = 6;
            grid.Padding = [4, 2, 4, 2];
            app.machineStatusLabel = uilabel(grid, ...
                'Text', 'PLC disconnected', ...
                'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            app.machineStatusLabel.Layout.Row = 1;
            app.machineStatusLabel.Layout.Column = [1, 6];
            app.savePositionButton = uibutton(grid, 'Text', 'Save position', ...
                'ButtonPushedFcn', @(~, ~) app.onSavePosition());
            app.savePositionButton.Layout.Row = 2;
            app.savePositionButton.Layout.Column = [1, 2];
            app.restorePositionButton = uibutton(grid, ...
                'Text', 'Restore position', ...
                'ButtonPushedFcn', @(~, ~) app.onRestorePosition());
            app.restorePositionButton.Layout.Row = 2;
            app.restorePositionButton.Layout.Column = [3, 4];
            app.errorButton = uibutton(grid, 'Text', 'System OK', ...
                'FontWeight', 'bold', ...
                'BackgroundColor', [0.55, 0.85, 0.55], ...
                'Tooltip', 'No PLC error reported', ...
                'ButtonPushedFcn', @(~, ~) app.onErrorButtonClicked());
            app.errorButton.Layout.Row = 2;
            app.errorButton.Layout.Column = [5, 6];
            app.powerButton = uibutton(grid, 'Text', 'POWER ON', ...
                'FontWeight', 'bold', 'FontSize', 14, ...
                'BackgroundColor', [0.35, 0.62, 0.9], ...
                'ButtonPushedFcn', @(~, ~) app.onPowerClicked());
            app.powerButton.Layout.Row = 3;
            app.powerButton.Layout.Column = [3, 4];
            app.stopButton = uibutton(grid, 'state', 'Text', 'STOP', ...
                'FontWeight', 'bold', 'FontSize', 16, ...
                'BackgroundColor', [1, 0.45, 0.2], ...
                'ValueChangedFcn', @(src, ~) app.controler.panicStop(src));
            app.stopButton.Layout.Row = 3;
            app.stopButton.Layout.Column = [5, 6];
            app.stopButton.Tooltip = ...
                ['Controlled software stop; this is not a safety-rated ' ...
                'emergency stop.'];
        end

        % addJogButton handles this operation.
        function button = addJogButton(app, grid, row, column, text, axisName, direction)
            button = uibutton(grid, 'Text', text, ...
                'FontWeight', 'bold', 'FontColor', [1, 1, 1], ...
                'BackgroundColor', [0.22, 0.22, 0.22], ...
                'ButtonPushedFcn', @(~, ~) app.onJogAxis(axisName, direction));
            button.Layout.Row = row;
            button.Layout.Column = column;
        end

        % Keep jog overlays anchored and contained as the camera area resizes.
        function resizeCameraOverlays(app)
            if isempty(app.cameraContent) || ~isvalid(app.cameraContent) || ...
                    isempty(app.xJogOverlay) || ~isvalid(app.xJogOverlay) || ...
                    isempty(app.yJogOverlay) || ~isvalid(app.yJogOverlay)
                return;
            end

            containerPosition = getpixelposition(app.cameraContent);
            availableWidth = max(1, floor(containerPosition(3)));
            availableHeight = max(1, floor(containerPosition(4)));
            margin = min(6, floor((min(availableWidth, availableHeight) - 1) / 2));
            margin = max(0, margin);
            spacing = min(4, margin);

            yWidth = min(156, max(1, availableWidth - 2 * margin));
            yHeight = min(44, max(1, availableHeight - 2 * margin));
            yX = max(margin, floor((availableWidth - yWidth) / 2));
            app.yJogOverlay.Position = [yX, margin, yWidth, yHeight];

            xWidth = min(76, max(1, availableWidth - 2 * margin));
            xHeight = min(86, max(1, availableHeight - 2 * margin));
            xY = max(margin, floor((availableHeight - xHeight) / 2));

            % At short panel heights, move and shrink the X group just
            % enough to keep it from colliding with the bottom Y group.
            minimumXY = margin + yHeight + spacing;
            if xY < minimumXY
                maximumXHeight = availableHeight - margin - minimumXY;
                if maximumXHeight >= 1
                    xHeight = min(xHeight, maximumXHeight);
                    xY = minimumXY;
                end
            end
            xY = min(xY, max(margin, availableHeight - margin - xHeight));
            app.xJogOverlay.Position = [margin, xY, xWidth, xHeight];
            app.fitCameraImage();
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
            selectedX = strcmp(mode, 'Both') || strcmp(mode, 'X only');
            selectedY = strcmp(mode, 'Both') || strcmp(mode, 'Y only');
            ready = app.machineConnected;
            restoreReady = ready;
            if ready && ~isempty(app.lastStatuses)
                axes = {};
                if selectedX, axes{end + 1} = 'X'; end
                if selectedY, axes{end + 1} = 'Y'; end
                for index = 1:numel(axes)
                    state = app.lastStatuses.(axes{index});
                    ready = ready && state.powered && ...
                        ~state.working && ~state.error;
                    restoreReady = restoreReady && ...
                        state.powered && ~state.working && ~state.error && ...
                        state.savedPositionValid;
                end
            else
                restoreReady = false;
            end
            enableX = selectedX && ready;
            enableY = selectedY && ready;
            app.setControlEnabled(app.posX, enableX);
            app.setControlEnabled(app.velX, enableX);
            app.setControlEnabled(app.posY, enableY);
            app.setControlEnabled(app.velY, enableY);
            app.setControlEnabled(app.jogButtons.xMinus, enableX);
            app.setControlEnabled(app.jogButtons.xPlus, enableX);
            app.setControlEnabled(app.jogButtons.yMinus, enableY);
            app.setControlEnabled(app.jogButtons.yPlus, enableY);
            app.setControlEnabled(app.liveActionButton, ready);
            app.setControlEnabled(app.savePositionButton, ready);
            app.setControlEnabled(app.restorePositionButton, restoreReady);
            app.setControlEnabled(app.powerButton, app.machineConnected);
            app.setControlEnabled(app.stopButton, app.machineConnected);

            app.styleAxisPlot(app.fxAxes, app.fxLine, [0.1, 0.45, 0.8]);
            app.styleAxisPlot(app.fyAxes, app.fyLine, [0.85, 0.35, 0.18]);
            app.updateAxisPlotTitle('X', app.fxAxes, selectedX);
            app.updateAxisPlotTitle('Y', app.fyAxes, selectedY);
            app.updatePowerButton(selectedX, selectedY);
            app.testPanel.setMachineAvailability( ...
                app.machineConnected, app.lastStatuses);
        end

        % styleAxisPlot handles this operation.
        function styleAxisPlot(~, axesHandle, lineHandle, activeColor)
            axesHandle.Color = [1, 1, 1];
            axesHandle.Title.Color = [0, 0, 0];
            lineHandle.Color = activeColor;
        end

        function updateAxisPlotTitle(app, axisName, axesHandle, selected)
            suffix = '';
            if ~selected
                suffix = ' (inactive)';
            elseif ~app.machineConnected || isempty(app.lastStatuses)
                suffix = ' (PLC disconnected)';
            else
                state = app.lastStatuses.(axisName);
                if state.error
                    suffix = sprintf(' (ERROR %u)', state.errorCode);
                elseif ~state.powered
                    suffix = ' (not powered)';
                elseif state.working
                    suffix = ' (busy)';
                end
            end
            title(axesHandle, [axisName, ' axis', suffix]);
        end

        function updatePowerButton(app, selectedX, selectedY)
            if isempty(app.powerButton) || ~isvalid(app.powerButton)
                return;
            end
            allPowered = false;
            if app.machineConnected && ~isempty(app.lastStatuses)
                powered = [];
                if selectedX, powered(end + 1) = app.lastStatuses.X.powered; end
                if selectedY, powered(end + 1) = app.lastStatuses.Y.powered; end
                allPowered = ~isempty(powered) && all(powered);
            end
            if allPowered
                app.powerButton.Text = 'POWER OFF';
                app.powerButton.BackgroundColor = [0.95, 0.72, 0.28];
            else
                app.powerButton.Text = 'POWER ON';
                app.powerButton.BackgroundColor = [0.35, 0.62, 0.9];
            end
        end

        function fitCameraImage(app)
            if isempty(app.cameraAxes) || ~isvalid(app.cameraAxes) || ...
                    isempty(app.camImageHandle) || ~isvalid(app.camImageHandle)
                return;
            end
            frame = app.camImageHandle.CData;
            frameHeight = size(frame, 1);
            frameWidth = size(frame, 2);
            axesPosition = getpixelposition(app.cameraAxes, true);
            if frameHeight < 1 || frameWidth < 1 || ...
                    axesPosition(3) < 1 || axesPosition(4) < 1
                return;
            end
            imageAspect = frameWidth / frameHeight;
            panelAspect = axesPosition(3) / axesPosition(4);
            if panelAspect >= imageAspect
                visibleHeight = frameWidth / panelAspect;
                centerY = (frameHeight + 1) / 2;
                app.cameraAxes.XLim = [0.5, frameWidth + 0.5];
                app.cameraAxes.YLim = centerY + [-visibleHeight, visibleHeight] / 2;
            else
                visibleWidth = frameHeight * panelAspect;
                centerX = (frameWidth + 1) / 2;
                app.cameraAxes.XLim = centerX + [-visibleWidth, visibleWidth] / 2;
                app.cameraAxes.YLim = [0.5, frameHeight + 0.5];
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
            app.runUiAction(@() app.controler.runGeneralTest(app), ...
                'Cannot start General Test');
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

        function onPowerClicked(app)
            mode = app.getAxisMode();
            selectedX = strcmp(mode, 'Both') || strcmp(mode, 'X only');
            selectedY = strcmp(mode, 'Both') || strcmp(mode, 'Y only');
            allPowered = true;
            if isempty(app.lastStatuses)
                allPowered = false;
            else
                if selectedX, allPowered = allPowered && app.lastStatuses.X.powered; end
                if selectedY, allPowered = allPowered && app.lastStatuses.Y.powered; end
            end
            app.runUiAction(@() app.controler.setPower(mode, ~allPowered), ...
                'Cannot change axis power');
        end

        % onSavePosition handles this operation.
        function onSavePosition(app)
            app.runUiAction(@() app.controler.savePosition(app), ...
                'Cannot save position');
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


