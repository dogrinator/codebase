classdef MachinePanel < handle
    %MACHINEPANEL Owns live plots, camera preview, and manual machine controls.

    properties (SetAccess = private)
        cameraAxes
        cameraImage
        modeDrop
        stopButton
        powerButton
        errorButton
        settingsIdle = true
        connected = false
        statuses = []
    end

    properties (Access = private)
        callbacks
        axisModeGetter
        previewGetter
        cameraContent
        xJogOverlay
        yJogOverlay
        fxAxes
        fyAxes
        fxLine
        fyLine
        posX
        posY
        velX
        velY
        jogButtons = struct()
        liveActionButton
        savePositionButton
        restorePositionButton
        machineStatusLabel
        forceReferenceLines = struct()
        operationActive = false
        plotTime = struct('X', 0, 'Y', 0)
    end

    methods
        function panel = MachinePanel( ...
                parent, callbacks, axisModeGetter, previewGetter)
            panel.callbacks = callbacks;
            panel.axisModeGetter = axisModeGetter;
            panel.previewGetter = previewGetter;
            panel.createLivePanel(parent);
            panel.createMachinePanel(parent);
            panel.applyState();
        end

        function updateCameraFrame(panel, frame)
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

        function appendPlotData(panel, xValues, yValues, samplePeriod)
            panel.appendAxisPlot('X', xValues, samplePeriod);
            panel.appendAxisPlot('Y', yValues, samplePeriod);
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
            wasConnected = panel.connected;
            panel.connected = logical(connected);
            panel.statuses = statuses;
            if wasConnected && ~panel.connected
                panel.plotTime = struct('X', 0, 'Y', 0);
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
                    words{end + 1} = sprintf( ...
                        'ERROR %u', state.errorCode); %#ok<AGROW>
                end
                index = 1 + strcmp(axis, 'Y');
                summaries{index} = sprintf( ...
                    '%s: %s', axis, strjoin(words, ', '));
            end
            panel.machineStatusLabel.Text = ...
                strjoin(summaries, '   |   ');
            if statuses.X.error || statuses.Y.error
                panel.machineStatusLabel.FontColor = [0.75, 0.1, 0.1];
            elseif statuses.X.working || statuses.Y.working
                panel.machineStatusLabel.FontColor = [0.75, 0.4, 0.05];
            else
                panel.machineStatusLabel.FontColor = [0.1, 0.45, 0.15];
            end
            panel.applyState();
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
        end

        function powered = selectedAxesPowered(panel)
            axes = TestCommandBuilder.axesForMode(panel.axisModeGetter());
            powered = panel.connected && ~isempty(panel.statuses);
            for index = 1:numel(axes)
                powered = powered && ...
                    panel.statuses.(axes{index}).powered;
            end
        end

        function idle = isIdle(panel)
            idle = ~panel.operationActive;
            if idle && ~isempty(panel.statuses)
                idle = ~panel.statuses.X.working && ...
                    ~panel.statuses.Y.working;
            end
        end
    end

    methods (Access = private)
        function createLivePanel(panel, parent)
            container = uipanel(parent, 'Title', 'Live loads');
            container.Layout.Row = 2;
            container.Layout.Column = 2;
            layout = uigridlayout(container, [4, 1]);
            layout.RowHeight = {34, '1x', '1x', 40};
            layout.Padding = [6, 6, 6, 6];
            panel.modeDrop = uidropdown(layout, ...
                'Items', {'Force', 'Displacement'}, 'Value', 'Force', ...
                'Tooltip', panel.displacementTooltip(), ...
                'ValueChangedFcn', @(src, ~) panel.plotModeChanged(src.Value));
            [panel.fxAxes, panel.fxLine] = panel.createPlot( ...
                layout, 'X', [0.1, 0.45, 0.8]);
            [panel.fyAxes, panel.fyLine] = panel.createPlot( ...
                layout, 'Y', [0.85, 0.35, 0.18]);
            panel.liveActionButton = uibutton(layout, ...
                'Text', 'Tare load cells', ...
                'ButtonPushedFcn', @(~, ~) panel.callbacks.liveAction());
        end

        function [axesHandle, lineHandle] = ...
                createPlot(~, parent, axisName, color)
            axesHandle = uiaxes(parent);
            title(axesHandle, [axisName, ' axis']);
            xlabel(axesHandle, 'Time [s]');
            ylabel(axesHandle, 'Force [N]');
            axesHandle.XGrid = 'on';
            axesHandle.YGrid = 'on';
            lineHandle = animatedline(axesHandle, ...
                'Color', color, 'LineWidth', 1.3);
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

        function applyState(panel)
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
            panel.updateForceReferenceLines();
        end

        function appendAxisPlot(panel, axisName, values, samplePeriod)
            if isempty(values)
                return;
            end
            count = numel(values);
            time = panel.plotTime.(axisName) + ...
                samplePeriod * (1:count);
            if strcmp(axisName, 'X')
                line = panel.fxLine;
                axesHandle = panel.fxAxes;
            else
                line = panel.fyLine;
                axesHandle = panel.fyAxes;
            end
            addpoints(line, time, values);
            panel.plotTime.(axisName) = ...
                panel.plotTime.(axisName) + samplePeriod * count;
            window = 5;
            axesHandle.XLim = [ ...
                max(0, panel.plotTime.(axisName) - window), ...
                max(window, panel.plotTime.(axisName))];
        end

        function plotModeChanged(panel, mode)
            if strcmp(mode, 'Force')
                ylabel(panel.fxAxes, 'Force [N]');
                ylabel(panel.fyAxes, 'Force [N]');
                panel.liveActionButton.Text = 'Tare load cells';
            else
                ylabel(panel.fxAxes, 'Displacement [mm]');
                ylabel(panel.fyAxes, 'Displacement [mm]');
                panel.liveActionButton.Text = 'Auto home';
            end
            panel.updateForceReferenceLines();
        end

        function updateForceReferenceLines(panel)
            panel.clearForceReferenceLines();
            if ~strcmp(panel.modeDrop.Value, 'Force')
                return;
            end
            preview = panel.previewGetter();
            if isempty(preview.testType)
                return;
            end
            panel.forceReferenceLines.X = panel.createReferenceLines( ...
                panel.fxAxes, preview.X.values, preview.X.labels);
            panel.forceReferenceLines.Y = panel.createReferenceLines( ...
                panel.fyAxes, preview.Y.values, preview.Y.labels);
        end

        function clearForceReferenceLines(panel)
            for item = {'X', 'Y'}
                axis = item{1};
                if ~isfield(panel.forceReferenceLines, axis)
                    continue;
                end
                handles = panel.forceReferenceLines.(axis);
                for index = 1:numel(handles)
                    if isvalid(handles(index))
                        delete(handles(index));
                    end
                end
            end
            panel.forceReferenceLines = struct( ...
                'X', gobjects(0), 'Y', gobjects(0));
        end

        function handles = createReferenceLines( ...
                panel, axesHandle, values, labels)
            handles = gobjects(0);
            valid = isfinite(values);
            values = values(valid);
            labels = labels(valid);
            [values, labels] = panel.combineTargets(values, labels);
            for index = 1:numel(values)
                handles(end + 1) = yline(axesHandle, values(index), '--', ...
                    labels{index}, ...
                    'Color', panel.referenceLineColor(labels{index}), ...
                    'LineWidth', 1.2, ...
                    'LabelHorizontalAlignment', 'left', ...
                    'LabelVerticalAlignment', 'middle'); %#ok<AGROW>
            end
        end

        function [valuesOut, labelsOut] = combineTargets(~, values, labels)
            valuesOut = [];
            labelsOut = {};
            for index = 1:numel(values)
                match = find(valuesOut == values(index), 1);
                if isempty(match)
                    valuesOut(end + 1) = values(index); %#ok<AGROW>
                    labelsOut{end + 1} = labels{index}; %#ok<AGROW>
                else
                    labelsOut{match} = [labelsOut{match}, ...
                        ' / ', labels{index}]; %#ok<AGROW>
                end
            end
        end

        function color = referenceLineColor(~, label)
            if contains(label, 'Primary') || contains(label, 'Load ')
                color = [0.72, 0.18, 0.18];
            else
                color = [0.45, 0.23, 0.72];
            end
        end

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
end
