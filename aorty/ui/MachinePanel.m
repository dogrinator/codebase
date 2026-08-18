classdef MachinePanel < handle
    %MACHINEPANEL Owns live plots, camera preview, and manual machine controls.

    properties (SetAccess = private)
        % UI handles exposed to the owning view and integration tests
        cameraAxes
        cameraImage
        modeDrop
        sampleCountField
        hoverInspector
        stopButton
        powerButton
        errorButton

        % PLC status state
        connected = false
        statuses = []
    end

    properties (Access = private)
        % Callbacks and state providers supplied by View
        callbacks
        axisModeGetter
        previewGetter

        % Camera preview and manual-motion controls
        cameraContent
        xJogOverlay
        yJogOverlay
        fxAxes
        fyAxes
        plotLines = struct()
        posX
        posY
        velX
        velY
        jogButtons = struct()
        liveActionButton
        savePositionButton
        restorePositionButton
        machineStatusLabel

        % Live plot state, force references, and hover selection
        forceReferences = struct('X', [], 'Y', [])
        positionLimitLines = struct('X', [], 'Y', [])
        operationActive = false
        plotTime = struct('X', 0, 'Y', 0)
        sampleCount = 500
        samplePeriod = 0.01
        hoveredReference = struct('axis', '', 'index', 0)
        figureHandle
    end

    methods
        %% Live display updates and machine state
        function panel = MachinePanel(parent, callbacks, axisModeGetter, previewGetter)
            panel.callbacks = callbacks;
            panel.axisModeGetter = axisModeGetter;
            panel.previewGetter = previewGetter;
            panel.createLivePanel(parent);
            panel.createMachinePanel(parent);
            panel.applyState();
        end

        function updateCameraFrame(panel, frame)
            % Preserve image pixels and refit the axes without stretching.
            if isempty(frame) || isempty(panel.cameraImage) || ...
                    ~isvalid(panel.cameraImage)
                return;
            end
            frameHeight = size(frame, 1);
            frameWidth = size(frame, 2);
            if frameHeight < 1 || frameWidth < 1
                return;
            end
            panel.cameraImage.CData = frame;
            panel.cameraImage.XData = [1, frameWidth];
            panel.cameraImage.YData = [1, frameHeight];
            panel.cameraAxes.DataAspectRatio = [1, 1, 1];
            panel.cameraAxes.DataAspectRatioMode = 'manual';
            panel.fitCameraImage();
        end

        function appendPlotData(panel, batch, samplePeriod)
            % Use the latest valid acquisition period for both axis timelines.
            if isnumeric(samplePeriod) && isscalar(samplePeriod) && ...
                    isfinite(samplePeriod) && samplePeriod > 0
                panel.samplePeriod = double(samplePeriod);
            end
            panel.appendAxisPlot('X', batch, panel.samplePeriod);
            panel.appendAxisPlot('Y', batch, panel.samplePeriod);
        end

        function mode = getPlotMode(panel)
            mode = char(panel.modeDrop.Value);
        end

        function values = getManualMotion(panel)
            values.distance = struct( ...
                'X', panel.posX.Value, 'Y', panel.posY.Value);
            values.speed = struct( ...
                'X', panel.velX.Value, 'Y', panel.velY.Value);
        end

        function updateMachineStatus(panel, statuses, connected)
            % A new connection state invalidates display state from the old session.
            wasConnected = panel.connected;
            panel.connected = logical(connected);
            panel.statuses = statuses;
            if wasConnected && ~panel.connected
                panel.clearPlotData();
            end
            if ~panel.connected || isempty(statuses)
                panel.machineStatusLabel.Text = 'PLC disconnected';
                panel.machineStatusLabel.FontColor = [0.55, 0.2, 0.2];
                panel.applyState();
                return;
            end

            summaries = cell(1, 2);
            for item = {'X', 'Y'}
                axis = item{1};
                state = statuses.(axis);
                words = {};
                if state.powered
                    words{end + 1} = 'powered'; %#ok<AGROW>
                else
                    words{end + 1} = 'not powered'; %#ok<AGROW>
                end
                if state.working, words{end + 1} = 'busy'; end %#ok<AGROW>
                if state.stopped, words{end + 1} = 'stopped'; end %#ok<AGROW>
                if state.homing, words{end + 1} = 'homing'; end %#ok<AGROW>
                if state.homed, words{end + 1} = 'homed'; end %#ok<AGROW>
                if state.savedPositionValid
                    words{end + 1} = 'saved'; %#ok<AGROW>
                end
                if state.error
                    words{end + 1} = sprintf('ERROR %u', state.errorCode); %#ok<AGROW>
                end
                index = 1 + strcmp(axis, 'Y');
                summaries{index} = sprintf('%s: %s', axis, strjoin(words, ', '));
            end
            panel.machineStatusLabel.Text = strjoin(summaries, '   |   ');
            if statuses.X.error || statuses.Y.error
                panel.machineStatusLabel.FontColor = [0.75, 0.1, 0.1];
            elseif statuses.X.working || statuses.Y.working
                panel.machineStatusLabel.FontColor = [0.75, 0.4, 0.05];
            else
                panel.machineStatusLabel.FontColor = [0.1, 0.45, 0.15];
            end
            panel.applyState();
            if wasConnected ~= panel.connected
                panel.updateForceReferenceLines();
            end
        end

        function clearPlotData(panel)
            % Reset timelines with the plotted samples so new data starts at zero.
            panel.plotTime = struct('X', 0, 'Y', 0);
            for axisItem = {'X', 'Y'}
                axisName = axisItem{1};
                if ~isfield(panel.plotLines, axisName)
                    continue;
                end
                for modeItem = {'Force', 'Displacement'}
                    mode = modeItem{1};
                    line = panel.plotLines.(axisName).(mode);
                    if ~isempty(line) && isvalid(line)
                        clearpoints(line);
                    end
                end
            end
            window = panel.sampleCount * panel.samplePeriod;
            if ~isempty(panel.fxAxes) && isvalid(panel.fxAxes)
                panel.fxAxes.XLim = [0, window];
            end
            if ~isempty(panel.fyAxes) && isvalid(panel.fyAxes)
                panel.fyAxes.XLim = [0, window];
            end
            panel.clearForceReferenceLines();
        end

        function setOperationActive(panel, active)
            panel.operationActive = logical(active);
            panel.applyState();
        end

        function updateErrorStatus(panel, hasError, message)
            if hasError
                panel.errorButton.Text = 'ERROR / RESET';
                panel.errorButton.BackgroundColor = [0.95, 0.35, 0.25];
                panel.errorButton.Tooltip = char(message);
            else
                panel.errorButton.Text = 'System OK';
                panel.errorButton.BackgroundColor = [0.55, 0.85, 0.55];
                panel.errorButton.Tooltip = 'No PLC error reported';
            end
        end

        function refreshAxisMode(panel)
            panel.applyState();
            panel.updateForceReferenceLines();
        end

        %% Machine state queries
        function powered = selectedAxesPowered(panel)
            axes = TestCommandBuilder.axesForMode(panel.axisModeGetter());
            powered = panel.connected && ~isempty(panel.statuses);
            for index = 1:numel(axes)
                powered = powered && panel.statuses.(axes{index}).powered;
            end
        end

        function idle = isIdle(panel)
            idle = ~panel.operationActive;
            if idle && ~isempty(panel.statuses)
                idle = ~panel.statuses.X.working && ~panel.statuses.Y.working;
            end
        end
    end

    methods (Access = private)
        %% UI construction
        function createLivePanel(panel, parent)
            container = uipanel(parent, 'Title', 'Live measurements');
            container.Layout.Row = 2;
            container.Layout.Column = 2;
            layout = uigridlayout(container, [5, 1]);
            layout.RowHeight = {34, 44, '1x', '1x', 40};
            layout.Padding = [6, 6, 6, 6];

            controls = uigridlayout(layout, [1, 3]);
            controls.ColumnWidth = {'1x', 92, 76};
            controls.Padding = [0, 0, 0, 0];
            controls.ColumnSpacing = 5;
            panel.modeDrop = uidropdown(controls, ...
                'Items', {'Force', 'Displacement'}, 'Value', 'Force', ...
                'Tooltip', panel.displacementTooltip(), ...
                'ValueChangedFcn', @(src, ~) panel.plotModeChanged(src.Value));
            uilabel(controls, 'Text', 'Samples shown', ...
                'HorizontalAlignment', 'right');
            panel.sampleCountField = uieditfield(controls, 'numeric', ...
                'Value', panel.sampleCount, 'Limits', [50, 50000], ...
                'RoundFractionalValues', 'on', ...
                'Tooltip', ...
                ['Rolling samples retained and displayed for both signals. ' ...
                'At 100 Hz, 500 samples is 5 seconds.'], ...
                'ValueChangedFcn', ...
                @(src, ~) panel.sampleCountChanged(src.Value));

            panel.hoverInspector = uilabel(layout, ...
                'Text', 'No force targets on this tab.', ...
                'HorizontalAlignment', 'center', ...
                'VerticalAlignment', 'center', ...
                'WordWrap', 'on', ...
                'BackgroundColor', [0.93, 0.94, 0.96], ...
                'FontColor', [0.25, 0.25, 0.28]);

            [panel.fxAxes, panel.plotLines.X] = panel.createPlot( ...
                layout, 'X', [0.1, 0.45, 0.8]);
            [panel.fyAxes, panel.plotLines.Y] = panel.createPlot( ...
                layout, 'Y', [0.85, 0.35, 0.18]);
            panel.positionLimitLines.X = panel.createPositionLimitLines( ...
                panel.fxAxes, 'X');
            panel.positionLimitLines.Y = panel.createPositionLimitLines( ...
                panel.fyAxes, 'Y');
            panel.liveActionButton = uibutton(layout, ...
                'Text', 'Tare load cells', ...
                'ButtonPushedFcn', @(~, ~) panel.callbacks.liveAction());
            panel.figureHandle = ancestor(parent, 'figure');
            if ~isempty(panel.figureHandle) && isvalid(panel.figureHandle)
                panel.figureHandle.WindowButtonMotionFcn = ...
                    @(~, ~) panel.updateHoverInspector();
            end
        end

        function [axesHandle, lines] = createPlot(panel, parent, axisName, color)
            axesHandle = uiaxes(parent);
            title(axesHandle, [axisName, ' axis']);
            xlabel(axesHandle, 'Time [s]');
            ylabel(axesHandle, 'Force [N]');
            axesHandle.XGrid = 'on';
            axesHandle.YGrid = 'on';
            lines = struct();
            lines.Force = animatedline(axesHandle, ...
                'Color', color, 'LineWidth', 1.3, ...
                'MaximumNumPoints', panel.sampleCount);
            lines.Displacement = animatedline(axesHandle, ...
                'Color', color, 'LineWidth', 1.3, ...
                'MaximumNumPoints', panel.sampleCount, ...
                'Visible', 'off');
        end

        function lines = createPositionLimitLines(~, axesHandle, axisName)
            limits = AppInfo.POSITION_LIMITS_MM.(axisName);
            labels = {'Visual minimum', 'Visual maximum'};
            lines = gobjects(1, numel(limits));
            for index = 1:numel(limits)
                lines(index) = yline(axesHandle, limits(index), '--', ...
                    sprintf('%s: %g mm', labels{index}, limits(index)), ...
                    'Color', [0.75, 0.16, 0.16], 'LineWidth', 1.25, ...
                    'LabelHorizontalAlignment', 'left', ...
                    'Visible', 'off', 'HitTest', 'off', ...
                    'PickableParts', 'none', 'Tag', 'PositionLimit');
            end
        end

        function createMachinePanel(panel, parent)
            container = uipanel(parent, 'Title', 'Machine control');
            container.Layout.Row = 2;
            container.Layout.Column = 3;
            layout = uigridlayout(container, [3, 1]);
            layout.RowHeight = {'1.25x', 175, 124};
            layout.Padding = [6, 6, 6, 6];
            panel.createCameraPanel(layout);
            panel.createManualControls(layout);
            panel.createMachineActions(layout);
        end

        function createCameraPanel(panel, parent)
            cameraPanel = uipanel(parent, 'Title', 'CAM - live view');
            layout = uigridlayout(cameraPanel, [1, 1]);
            layout.Padding = 0;
            layout.RowSpacing = 0;
            layout.ColumnSpacing = 0;
            panel.cameraContent = uipanel(layout, ...
                'BorderType', 'none', 'BackgroundColor', [0, 0, 0]);
            panel.cameraContent.AutoResizeChildren = 'off';
            panel.cameraAxes = uiaxes(panel.cameraContent);
            panel.cameraAxes.Units = 'normalized';
            panel.cameraAxes.Position = [0, 0, 1, 1];
            panel.cameraImage = image( ...
                panel.cameraAxes, zeros(512, 512, 'uint8'));
            panel.cameraAxes.CLim = [0, 255];
            panel.cameraAxes.Color = [0, 0, 0];
            colormap(panel.cameraAxes, gray);
            axis(panel.cameraAxes, 'off');
            panel.cameraAxes.Toolbar.Visible = 'off';
            panel.cameraAxes.Interactions = [];
            panel.createJogOverlays();
            panel.cameraContent.SizeChangedFcn = ...
                @(~, ~) panel.resizeCameraOverlays();
            panel.resizeCameraOverlays();
        end

        function createJogOverlays(panel)
            overlayColor = [0.10, 0.10, 0.10];
            panel.xJogOverlay = uipanel(panel.cameraContent, ...
                'BorderType', 'none', 'BackgroundColor', overlayColor);
            panel.xJogOverlay.Units = 'pixels';
            panel.xJogOverlay.Position = [6, 8, 76, 86];
            panel.xJogOverlay.AutoResizeChildren = 'off';
            xControls = uigridlayout(panel.xJogOverlay, [2, 1]);
            xControls.RowHeight = {'1x', '1x'};
            xControls.Padding = [2, 2, 2, 2];
            xControls.RowSpacing = 2;
            xControls.BackgroundColor = overlayColor;
            panel.jogButtons.xMinus = panel.addJogButton( ...
                xControls, 1, 1, [char(8592), ' X'], 'X', -1);
            panel.jogButtons.xPlus = panel.addJogButton( ...
                xControls, 2, 1, ['X ', char(8594)], 'X', 1);
            panel.yJogOverlay = uipanel(panel.cameraContent, ...
                'BorderType', 'none', 'BackgroundColor', overlayColor);
            panel.yJogOverlay.Units = 'pixels';
            panel.yJogOverlay.Position = [8, 6, 156, 44];
            panel.yJogOverlay.AutoResizeChildren = 'off';
            yControls = uigridlayout(panel.yJogOverlay, [1, 2]);
            yControls.ColumnWidth = {'1x', '1x'};
            yControls.Padding = [2, 2, 2, 2];
            yControls.ColumnSpacing = 2;
            yControls.BackgroundColor = overlayColor;
            panel.jogButtons.yMinus = panel.addJogButton( ...
                yControls, 1, 1, [char(8595), ' Y'], 'Y', -1);
            panel.jogButtons.yPlus = panel.addJogButton( ...
                yControls, 1, 2, ['Y ', char(8593)], 'Y', 1);
        end

        function createManualControls(panel, parent)
            container = uipanel(parent, 'Title', 'Manual positioning');
            grid = uigridlayout(container, [3, 3]);
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
            panel.posX = uieditfield(grid, 'numeric', 'Value', 10);
            panel.velX = panel.speedField(grid);
            uilabel(grid, 'Text', 'Y', 'FontWeight', 'bold', ...
                'HorizontalAlignment', 'center');
            panel.posY = uieditfield(grid, 'numeric', 'Value', 10);
            panel.velY = panel.speedField(grid);
        end

        function control = speedField(~, parent)
            control = uieditfield(parent, 'numeric', 'Value', 1, ...
                'Limits', [0, Inf], 'LowerLimitInclusive', 'off', ...
                'Tooltip', 'Speed must be greater than 0.');
        end

        function createMachineActions(panel, parent)
            grid = uigridlayout(parent, [3, 6]);
            grid.ColumnWidth = repmat({'1x'}, 1, 6);
            grid.RowHeight = {24, 36, 42};
            grid.RowSpacing = 5;
            grid.ColumnSpacing = 6;
            grid.Padding = [4, 2, 4, 2];
            panel.machineStatusLabel = uilabel(grid, ...
                'Text', 'PLC disconnected', ...
                'HorizontalAlignment', 'center', 'FontWeight', 'bold');
            panel.machineStatusLabel.Layout.Row = 1;
            panel.machineStatusLabel.Layout.Column = [1, 6];
            panel.savePositionButton = panel.actionButton( ...
                grid, 'Save position', panel.callbacks.save, 2, [1, 2]);
            panel.restorePositionButton = panel.actionButton( ...
                grid, 'Restore position', panel.callbacks.restore, 2, [3, 4]);
            panel.errorButton = panel.actionButton( ...
                grid, 'System OK', panel.callbacks.error, 2, [5, 6]);
            panel.errorButton.FontWeight = 'bold';
            panel.errorButton.BackgroundColor = [0.55, 0.85, 0.55];
            panel.powerButton = panel.actionButton( ...
                grid, 'POWER ON', panel.callbacks.power, 3, [3, 4]);
            panel.powerButton.FontWeight = 'bold';
            panel.powerButton.FontSize = 14;
            panel.powerButton.BackgroundColor = [0.35, 0.62, 0.9];
            panel.stopButton = uibutton(grid, 'state', ...
                'Text', 'STOP', 'FontWeight', 'bold', 'FontSize', 16, ...
                'BackgroundColor', [1, 0.45, 0.2], ...
                'ValueChangedFcn', ...
                @(src, ~) panel.callbacks.stop(src));
            panel.stopButton.Layout.Row = 3;
            panel.stopButton.Layout.Column = [5, 6];
            panel.stopButton.Tooltip = ...
                ['Controlled software stop; this is not a safety-rated ' ...
                'emergency stop.'];
        end

        function button = actionButton(~, grid, text, callback, row, columns)
            button = uibutton(grid, 'Text', text, ...
                'ButtonPushedFcn', @(~, ~) callback());
            button.Layout.Row = row;
            button.Layout.Column = columns;
        end

        function button = addJogButton( ...
                panel, grid, row, column, text, axisName, direction)
            button = uibutton(grid, 'Text', text, ...
                'FontWeight', 'bold', 'FontColor', [1, 1, 1], ...
                'BackgroundColor', [0.22, 0.22, 0.22], ...
                'ButtonPushedFcn', ...
                @(~, ~) panel.callbacks.jog(axisName, direction));
            button.Layout.Row = row;
            button.Layout.Column = column;
        end

        %% Control-state coordination
        function applyState(panel)
            % Manual motion requires every selected axis to be powered and idle.
            mode = panel.axisModeGetter();
            selectedX = strcmp(mode, 'Both') || strcmp(mode, 'X only');
            selectedY = strcmp(mode, 'Both') || strcmp(mode, 'Y only');
            ready = panel.connected && ~panel.operationActive;
            restoreReady = ready;
            if ready && ~isempty(panel.statuses)
                axes = TestCommandBuilder.axesForMode(mode);
                for index = 1:numel(axes)
                    state = panel.statuses.(axes{index});
                    ready = ready && state.powered && ...
                        ~state.working && ~state.error;
                    restoreReady = restoreReady && state.powered && ...
                        ~state.working && ~state.error && ...
                        state.savedPositionValid;
                end
            else
                restoreReady = false;
            end
            panel.setEnabled(panel.posX, selectedX && ready);
            panel.setEnabled(panel.velX, selectedX && ready);
            panel.setEnabled(panel.posY, selectedY && ready);
            panel.setEnabled(panel.velY, selectedY && ready);
            panel.setEnabled(panel.jogButtons.xMinus, selectedX && ready);
            panel.setEnabled(panel.jogButtons.xPlus, selectedX && ready);
            panel.setEnabled(panel.jogButtons.yMinus, selectedY && ready);
            panel.setEnabled(panel.jogButtons.yPlus, selectedY && ready);
            panel.setEnabled(panel.liveActionButton, ready);
            panel.setEnabled(panel.savePositionButton, ready);
            panel.setEnabled(panel.restorePositionButton, restoreReady);
            panel.setEnabled(panel.powerButton, ...
                panel.connected && ~panel.operationActive);
            panel.setEnabled(panel.stopButton, panel.connected);
            panel.updateAxisPlotTitle('X', panel.fxAxes, selectedX);
            panel.updateAxisPlotTitle('Y', panel.fyAxes, selectedY);
            panel.updatePowerButton();
        end

        %% Live plot data
        function appendAxisPlot(panel, axisName, batch, samplePeriod)
            forceValues = batch.Force.(axisName);
            displacementValues = batch.Displacement.(axisName);
            count = max(numel(forceValues), numel(displacementValues));
            if count == 0
                return;
            end
            if strcmp(axisName, 'X')
                axesHandle = panel.fxAxes;
            else
                axesHandle = panel.fyAxes;
            end

            startTime = panel.plotTime.(axisName);
            % Each axis owns a monotonic display timeline across incoming batches.
            if ~isempty(forceValues)
                forceTime = startTime + samplePeriod * (1:numel(forceValues));
                addpoints(panel.plotLines.(axisName).Force, forceTime, forceValues);
            end
            if ~isempty(displacementValues)
                displacementTime = startTime + samplePeriod * (1:numel(displacementValues));
                addpoints(panel.plotLines.(axisName).Displacement, displacementTime, displacementValues);
            end
            panel.plotTime.(axisName) = startTime + samplePeriod * count;
            panel.updateAxisTimeWindow(axisName, axesHandle);
        end

        function plotModeChanged(panel, mode)
            for axisItem = {'X', 'Y'}
                axisName = axisItem{1};
                for modeItem = {'Force', 'Displacement'}
                    signal = modeItem{1};
                    if strcmp(signal, mode)
                        panel.plotLines.(axisName).(signal).Visible = 'on';
                    else
                        panel.plotLines.(axisName).(signal).Visible = 'off';
                    end
                end
            end
            if strcmp(mode, 'Force')
                ylabel(panel.fxAxes, 'Force [N]');
                ylabel(panel.fyAxes, 'Force [N]');
                panel.liveActionButton.Text = 'Tare load cells';
            else
                ylabel(panel.fxAxes, 'Displacement [mm]');
                ylabel(panel.fyAxes, 'Displacement [mm]');
                panel.liveActionButton.Text = 'Auto home';
            end
            panel.updatePositionLimitLines(mode);
            panel.updateForceReferenceLines();
        end

        function updatePositionLimitLines(panel, mode)
            visibility = 'off';
            if strcmp(mode, 'Displacement')
                visibility = 'on';
            end
            for axisItem = {'X', 'Y'}
                lines = panel.positionLimitLines.(axisItem{1});
                for index = 1:numel(lines)
                    if isgraphics(lines(index))
                        lines(index).Visible = visibility;
                    end
                end
            end
        end

        function sampleCountChanged(panel, value)
            % Preserve only the newest points when reducing the rolling window.
            value = min(50000, max(50, round(double(value))));
            panel.sampleCount = value;
            panel.sampleCountField.Value = value;
            for axisItem = {'X', 'Y'}
                axisName = axisItem{1};
                for modeItem = {'Force', 'Displacement'}
                    signal = modeItem{1};
                    line = panel.plotLines.(axisName).(signal);
                    [xValues, yValues] = getpoints(line);
                    keep = max(1, numel(xValues) - value + 1):numel(xValues);
                    if isempty(xValues)
                        keep = [];
                    end
                    clearpoints(line);
                    line.MaximumNumPoints = value;
                    if ~isempty(keep)
                        addpoints(line, xValues(keep), yValues(keep));
                    end
                end
                if strcmp(axisName, 'X')
                    axesHandle = panel.fxAxes;
                else
                    axesHandle = panel.fyAxes;
                end
                panel.updateAxisTimeWindow(axisName, axesHandle);
            end
        end

        function updateAxisTimeWindow(panel, axisName, axesHandle)
            window = panel.sampleCount * panel.samplePeriod;
            currentTime = panel.plotTime.(axisName);
            axesHandle.XLim = [ ...
                max(0, currentTime - window), ...
                max(window, currentTime)];
            panel.updateReferenceBandExtents(axisName, axesHandle.XLim);
        end

        %% Force-target overlays and hover inspection
        function updateForceReferenceLines(panel)
            panel.clearForceReferenceLines();
            if ~panel.connected || ~strcmp(panel.modeDrop.Value, 'Force')
                panel.updateHoverPrompt();
                return;
            end
            preview = panel.previewGetter();
            if isempty(preview.testType)
                panel.updateHoverPrompt();
                return;
            end
            panel.forceReferences.X = panel.createReferenceLines( ...
                panel.fxAxes, preview.X);
            panel.forceReferences.Y = panel.createReferenceLines( ...
                panel.fyAxes, preview.Y);
            panel.updateHoverPrompt();
        end

        function clearForceReferenceLines(panel)
            panel.resetHoveredReference();
            for item = {'X', 'Y'}
                axis = item{1};
                if ~isfield(panel.forceReferences, axis)
                    continue;
                end
                references = panel.forceReferences.(axis);
                for index = 1:numel(references)
                    if isfield(references, 'line') && ...
                            isgraphics(references(index).line)
                        delete(references(index).line);
                    end
                    if isfield(references, 'band') && ...
                            isgraphics(references(index).band)
                        delete(references(index).band);
                    end
                end
            end
            panel.forceReferences = struct('X', [], 'Y', []);
            panel.updateHoverPrompt();
        end

        function references = createReferenceLines( ...
                panel, axesHandle, entries)
            references = struct( ...
                'line', {}, 'band', {}, 'entry', {}, ...
                'baseWidth', {});
            if isempty(entries)
                return;
            end
            valid = arrayfun(@(entry) ...
                isfinite(entry.target) && ...
                isfinite(entry.tolerance) && entry.tolerance >= 0, ...
                entries);
            entries = PlotReferenceBuilder.group(entries(valid));
            % One rendered band represents all entries with the same target range.
            xLimits = axesHandle.XLim;
            for index = 1:numel(entries)
                entry = entries(index);
                [color, lineStyle] = ...
                    panel.referenceStyle(entry.role);
                lower = entry.target - entry.tolerance;
                upper = entry.target + entry.tolerance;
                band = patch(axesHandle, ...
                    [xLimits(1), xLimits(2), xLimits(2), xLimits(1)], ...
                    [lower, lower, upper, upper], color, ...
                    'FaceAlpha', 0.09, 'EdgeColor', 'none', ...
                    'HitTest', 'off', 'PickableParts', 'none');
                line = yline(axesHandle, entry.target, lineStyle, ...
                    'Color', color, 'LineWidth', 1.25, ...
                    'HitTest', 'off', 'PickableParts', 'none');
                references(end + 1) = struct( ...
                    'line', line, 'band', band, ...
                    'entry', entry, 'baseWidth', 1.25);%#ok<AGROW>
            end
        end

        function [color, lineStyle] = referenceStyle(~, role)
            switch char(role)
                case 'preload'
                    color = [0.12, 0.42, 0.72];
                    lineStyle = ':';
                case {'primary', 'load'}
                    color = [0.72, 0.18, 0.18];
                    lineStyle = '--';
                otherwise
                    color = [0.45, 0.23, 0.72];
                    lineStyle = '-.';
            end
        end

        function updateReferenceBandExtents(panel, axisName, xLimits)
            if ~isfield(panel.forceReferences, axisName)
                return;
            end
            references = panel.forceReferences.(axisName);
            for index = 1:numel(references)
                band = references(index).band;
                if isgraphics(band)
                    band.XData = [ ...
                        xLimits(1), xLimits(2), ...
                        xLimits(2), xLimits(1)];
                end
            end
        end

        function updateHoverInspector(panel)
            if isempty(panel.figureHandle) || ...
                    ~isvalid(panel.figureHandle) || ...
                    ~strcmp(panel.modeDrop.Value, 'Force')
                panel.resetHoveredReference();
                panel.updateHoverPrompt();
                return;
            end
            figurePoint = panel.figureHandle.CurrentPoint;
            % Compare in pixels so the hover threshold is zoom-independent.
            bestAxis = '';
            bestIndex = 0;
            bestDistance = Inf;
            for axisItem = {'X', 'Y'}
                axisName = axisItem{1};
                if strcmp(axisName, 'X')
                    axesHandle = panel.fxAxes;
                else
                    axesHandle = panel.fyAxes;
                end
                position = getpixelposition(axesHandle, true);
                inside = figurePoint(1) >= position(1) && ...
                    figurePoint(1) <= position(1) + position(3) && ...
                    figurePoint(2) >= position(2) && ...
                    figurePoint(2) <= position(2) + position(4);
                if ~inside || diff(axesHandle.YLim) <= 0
                    continue;
                end
                references = panel.forceReferences.(axisName);
                currentPoint = axesHandle.CurrentPoint;
                dataY = currentPoint(1, 2);
                pixelsPerUnit = position(4) / diff(axesHandle.YLim);
                for index = 1:numel(references)
                    distance = abs( ...
                        references(index).entry.target - dataY) * ...
                        pixelsPerUnit;
                    if distance <= 6 && distance < bestDistance
                        bestAxis = axisName;
                        bestIndex = index;
                        bestDistance = distance;
                    end
                end
            end
            if bestIndex == 0
                panel.resetHoveredReference();
                panel.updateHoverPrompt();
                return;
            end
            panel.showHoveredReference(bestAxis, bestIndex);
        end

        function showHoveredReference(panel, axisName, index)
            previous = panel.hoveredReference;
            if previous.index == index && strcmp(previous.axis, axisName)
                return;
            end
            panel.resetHoveredReference();
            reference = panel.forceReferences.(axisName)(index);
            if isgraphics(reference.line)
                reference.line.LineWidth = 2.4;
            end
            entry = reference.entry;
            lower = entry.target - entry.tolerance;
            upper = entry.target + entry.tolerance;
            panel.hoverInspector.Text = sprintf( ...
                ['%s axis | %s | %s: %g N | ', ...
                'tolerance %g%% of %g N max = +/- %g N ', ...
                '(%g to %g N)'], ...
                axisName, entry.phase, entry.label, ...
                entry.target, entry.tolerancePercent, entry.maxForce, ...
                entry.tolerance, lower, upper);
            [color, ~] = panel.referenceStyle(entry.role);
            panel.hoverInspector.FontColor = color;
            panel.hoverInspector.FontWeight = 'bold';
            panel.hoveredReference = struct( ...
                'axis', axisName, 'index', index);
        end

        function resetHoveredReference(panel)
            axisName = panel.hoveredReference.axis;
            index = panel.hoveredReference.index;
            if index > 0 && isfield(panel.forceReferences, axisName) && ...
                    numel(panel.forceReferences.(axisName)) >= index
                reference = panel.forceReferences.(axisName)(index);
                if isgraphics(reference.line)
                    reference.line.LineWidth = reference.baseWidth;
                end
            end
            panel.hoveredReference = struct('axis', '', 'index', 0);
        end

        function updateHoverPrompt(panel)
            if isempty(panel.hoverInspector) || ...
                    ~isvalid(panel.hoverInspector) || ...
                    panel.hoveredReference.index > 0
                return;
            end
            panel.hoverInspector.FontWeight = 'normal';
            panel.hoverInspector.FontColor = [0.25, 0.25, 0.28];
            if ~strcmp(panel.modeDrop.Value, 'Force')
                panel.hoverInspector.Text = ...
                    'Force endpoint overlays are hidden in Displacement mode.';
                return;
            end
            count = numel(panel.forceReferences.X) + ...
                numel(panel.forceReferences.Y);
            if count == 0
                panel.hoverInspector.Text = ...
                    'No force targets on this tab.';
            else
                panel.hoverInspector.Text = ...
                    'Hover a target line for endpoint and tolerance details.';
            end
        end

        %% Status decoration and camera layout
        function updateAxisPlotTitle( ...
                panel, axisName, axesHandle, selected)
            suffix = '';
            if ~selected
                suffix = ' (inactive)';
            elseif ~panel.connected || isempty(panel.statuses)
                suffix = ' (PLC disconnected)';
            else
                state = panel.statuses.(axisName);
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

        function updatePowerButton(panel)
            if panel.selectedAxesPowered()
                panel.powerButton.Text = 'POWER OFF';
                panel.powerButton.BackgroundColor = [0.95, 0.72, 0.28];
            else
                panel.powerButton.Text = 'POWER ON';
                panel.powerButton.BackgroundColor = [0.35, 0.62, 0.9];
            end
        end

        function resizeCameraOverlays(panel)
            % Keep jog overlays visible and non-overlapping on small panels.
            if isempty(panel.cameraContent) || ...
                    ~isvalid(panel.cameraContent)
                return;
            end
            position = getpixelposition(panel.cameraContent);
            width = max(1, floor(position(3)));
            height = max(1, floor(position(4)));
            margin = max(0, min(6, floor((min(width, height) - 1) / 2)));
            spacing = min(4, margin);
            yWidth = min(156, max(1, width - 2 * margin));
            yHeight = min(44, max(1, height - 2 * margin));
            yX = max(margin, floor((width - yWidth) / 2));
            panel.yJogOverlay.Position = [yX, margin, yWidth, yHeight];
            xWidth = min(76, max(1, width - 2 * margin));
            xHeight = min(86, max(1, height - 2 * margin));
            xY = max(margin, floor((height - xHeight) / 2));
            minimumXY = margin + yHeight + spacing;
            if xY < minimumXY
                maximumXHeight = height - margin - minimumXY;
                if maximumXHeight >= 1
                    xHeight = min(xHeight, maximumXHeight);
                    xY = minimumXY;
                end
            end
            xY = min(xY, max(margin, height - margin - xHeight));
            panel.xJogOverlay.Position = [margin, xY, xWidth, xHeight];
            panel.fitCameraImage();
        end

        function fitCameraImage(panel)
            % Crop the axes limits to fill the panel without distorting the frame.
            frame = panel.cameraImage.CData;
            frameHeight = size(frame, 1);
            frameWidth = size(frame, 2);
            position = getpixelposition(panel.cameraAxes, true);
            if frameHeight < 1 || frameWidth < 1 || ...
                    position(3) < 1 || position(4) < 1
                return;
            end
            imageAspect = frameWidth / frameHeight;
            panelAspect = position(3) / position(4);
            if panelAspect >= imageAspect
                visibleHeight = frameWidth / panelAspect;
                centerY = (frameHeight + 1) / 2;
                panel.cameraAxes.XLim = [0.5, frameWidth + 0.5];
                panel.cameraAxes.YLim = ...
                    centerY + [-visibleHeight, visibleHeight] / 2;
            else
                visibleWidth = frameHeight * panelAspect;
                centerX = (frameWidth + 1) / 2;
                panel.cameraAxes.XLim = ...
                    centerX + [-visibleWidth, visibleWidth] / 2;
                panel.cameraAxes.YLim = [0.5, frameHeight + 0.5];
            end
        end

        %% UI helpers
        function setEnabled(~, control, enabled)
            if enabled
                control.Enable = 'on';
            else
                control.Enable = 'off';
            end
        end

        function text = displacementTooltip(~)
            text = ['Displacement plots show the absolute NC axis ' ...
                'position. Visual position limits come from AppInfo and are ' ...
                'not enforced. Endpoint overlays are shown only for Force.'];
        end
    end
end
