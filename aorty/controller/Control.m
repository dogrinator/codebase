classdef Control < handle
    % Coordinates PLC-owned test sequences, camera, recording, and the UI.

    properties
        camera Camera
        plc Plc
        model Model
        settings Settings
        plcReadTimer
        displayTimer
        app

        xForceData = []
        yForceData = []
        xUntaredForceData = []
        yUntaredForceData = []
        xPositionData = []
        yPositionData = []

        operationStartCounters = struct('X', uint32(0), 'Y', uint32(0))
        activeTestAxes = {}
        testRunning = false
        abortInProgress = false
    end

    methods
        function controler = Control(model, plc, camera)
            controler.model = model;
            if nargin >= 3 && ~isempty(camera)
                controler.camera = camera;
            else
                controler.camera = Camera(model);
            end
            controler.camera.errorHandler = @(exception) ...
                controler.handleRuntimeError(exception, 'Camera error');
            if nargin >= 2 && ~isempty(plc)
                controler.plc = plc;
            else
                controler.plc = Plc(model);
            end
            controler.settings = Settings(controler.plc, controler.camera);
        end

        function startTimers(controler, app)
            controler.app = app;
            controler.plcReadTimer = timer('ExecutionMode', 'fixedRate', ...
                'BusyMode', 'drop', 'Period', 0.5, ...
                'TimerFcn', @(~, ~) controler.readCallback());
            controler.displayTimer = timer('ExecutionMode', 'fixedRate', ...
                'BusyMode', 'drop', 'Period', 0.067, ...
                'TimerFcn', @(~, ~) controler.updateDisplay());
            start(controler.plcReadTimer);
            start(controler.displayTimer);
        end

        function readCallback(controler)
            if ~controler.plc.connected || controler.plc.disconnecting
                controler.notifyMachineStatus([], false);
                return;
            end
            try
                [fx, fy, ufx, ufy, px, py, statuses] = ...
                    controler.plc.fifoProcess();
                controler.xForceData = [controler.xForceData, fx];
                controler.yForceData = [controler.yForceData, fy];
                controler.xUntaredForceData = ...
                    [controler.xUntaredForceData, ufx];
                controler.yUntaredForceData = ...
                    [controler.yUntaredForceData, ufy];
                controler.xPositionData = [controler.xPositionData, px];
                controler.yPositionData = [controler.yPositionData, py];
                controler.updateStatusUI(statuses);
                controler.notifyMachineStatus(statuses, true);
                controler.advanceTest(statuses);
            catch exception
                controler.handleRuntimeError(exception, 'ADS read error');
            end
        end

        function updateDisplay(controler)
            viewApp = controler.app;
            if isempty(viewApp) || ~isvalid(viewApp) || ...
                    isempty(viewApp.fig) || ~isvalid(viewApp.fig) || ...
                    isempty(viewApp.modeDrop) || ~isvalid(viewApp.modeDrop)
                return;
            end
            try
                if controler.camera.connected && ...
                        ~isempty(controler.camera.latestFrame)
                    if ~isempty(viewApp.cameraAxes) && ...
                            isvalid(viewApp.cameraAxes) && ...
                            ~isempty(viewApp.camImageHandle) && ...
                            isvalid(viewApp.camImageHandle)
                        viewApp.updateCameraFrame( ...
                            controler.camera.latestFrame);
                    end
                    controler.camera.latestFrame = [];
                end

                if strcmp(viewApp.modeDrop.Value, 'Force')
                    xBatch = controler.xForceData;
                    yBatch = controler.yForceData;
                else
                    xBatch = controler.xPositionData;
                    yBatch = controler.yPositionData;
                end
                forceX = controler.xForceData;
                forceY = controler.yForceData;
                untaredX = controler.xUntaredForceData;
                untaredY = controler.yUntaredForceData;
                posX = controler.xPositionData;
                posY = controler.yPositionData;
                controler.xForceData = [];
                controler.yForceData = [];
                controler.xUntaredForceData = [];
                controler.yUntaredForceData = [];
                controler.xPositionData = [];
                controler.yPositionData = [];

                controler.appendPlot(viewApp.fxLine, viewApp.fxAxes, ...
                    xBatch, 'X');
                controler.appendPlot(viewApp.fyLine, viewApp.fyAxes, ...
                    yBatch, 'Y');
                controler.model.saveAxisSamples('X', forceX, untaredX, posX);
                controler.model.saveAxisSamples('Y', forceY, untaredY, posY);
                drawnow limitrate nocallbacks;
            catch exception
                controler.handleRuntimeError(exception, 'Display update error');
            end
        end

        function panicStop(controler, button)
            try
                controler.safeAbort('Operator STOP');
            catch exception
                uialert(controler.app.fig, exception.message, 'STOP failed');
            end
            button.Value = false;
            button.Text = 'STOP';
            button.BackgroundColor = [1, 0.45, 0.2];
        end

        function jog(controler, axisName, direction, distance, velocity)
            controler.plc.jog(axisName, direction * abs(distance), velocity);
        end

        function tare(controler, axisMode)
            controler.plc.tare(controler.activeAxes(axisMode));
        end

        function moveToLowerLimit(controler, axisMode)
            controler.plc.moveToLowerLimit(controler.activeAxes(axisMode));
        end

        function resetErrors(controler)
            axes = {};
            if isfield(controler.plc.status, 'X') && ...
                    isfield(controler.plc.status.X, 'error') && ...
                    controler.plc.status.X.error
                axes{end + 1} = 'X';
            end
            if isfield(controler.plc.status, 'Y') && ...
                    isfield(controler.plc.status.Y, 'error') && ...
                    controler.plc.status.Y.error
                axes{end + 1} = 'Y';
            end
            if ~isempty(axes), controler.plc.resetErrors(axes); end
        end

        function setPower(controler, axisMode, enabled)
            controler.plc.setPower(controler.activeAxes(axisMode), enabled);
        end

        function savePosition(controler, app)
            controler.plc.savePosition( ...
                controler.activeAxes(app.getAxisMode()));
        end

        function restorePosition(controler, app)
            axes = controler.activeAxes(app.getAxisMode());
            manual = app.getManualMotion();
            controler.plc.restorePosition(axes, manual.speed);
        end

        function runPreTest(controler, app)
            config = app.getTestConfiguration();
            commands = controler.buildCommands(config, 'pre');
            controler.startTest(app, commands, config.pre.cameraPeriod);
        end

        function runSingleTest(controler, app)
            config = app.getTestConfiguration();
            commands = controler.buildCommands(config, 'single');
            controler.startTest(app, commands, config.single.cameraPeriod);
        end

        function runCyclicTest(controler, app)
            config = app.getTestConfiguration();
            commands = controler.buildCommands(config, 'cyclic');
            controler.startTest(app, commands, config.cyclic.cameraPeriod);
        end

        function runGeneralTest(controler, app)
            definition = app.getGeneralTestDefinition();
            commands = controler.buildGeneralCommands(definition);
            cameraControls = struct('enabled', logical(definition.camera.enabled), ...
                'value', double(definition.camera.period));
            controler.startTest(app, commands, cameraControls);
        end

        function safeAbort(controler, reason)
            if controler.abortInProgress, return; end
            wasActive = controler.testRunning || controler.model.isRecording || ...
                controler.model.filesOpen;
            controler.abortInProgress = true;
            controler.testRunning = false;
            controler.activeTestAxes = {};
            try
                if controler.plc.connected && ~controler.plc.disconnecting
                    controler.plc.stop({'X', 'Y'});
                end
            catch exception
                warning('Control:AbortStop', ...
                    'Could not stop PLC during abort: %s', exception.message);
            end
            if controler.model.isRecording
                controler.finishRecording(reason);
            elseif wasActive
                controler.model.recordingStatus = 'aborted';
                controler.model.recordingReason = char(reason);
                controler.model.writeRecordingStatus();
            end
            controler.abortInProgress = false;
        end

        function processTestStatusForTesting(controler, statuses)
            % Offline test seam for operation-counter and peer-halt logic.
            controler.advanceTest(statuses);
        end
    end

    methods (Access = private)
        function startTest(controler, ~, commands, cameraControls)
            if controler.testRunning || controler.plc.isWorking
                error('Control:Busy', 'A PLC operation is already active.');
            end
            folder = uigetdir('', 'Choose test output folder');
            if isequal(folder, 0), return; end

            statuses = controler.plc.pollStatus();
            axes = controler.commandAxes(commands);
            for index = 1:numel(axes)
                axis = axes{index};
                controler.operationStartCounters.(axis) = ...
                    statuses.(axis).operationCounter;
            end
            if cameraControls.enabled
                if ~isfinite(cameraControls.value) || cameraControls.value <= 0
                    error('Control:InvalidCameraPeriod', ...
                        'Camera sampling period must be positive.');
                end
                controler.camera.recordingPeriod = cameraControls.value;
            else
                controler.camera.recordingPeriod = 0;
            end
            controler.prepareRecording(folder);
            controler.model.isRecording = true;
            controler.model.recordingStatus = 'starting';
            controler.model.recordingReason = '';
            controler.testRunning = true;
            controler.activeTestAxes = axes;
            try
                controler.model.openFilesRec();
                controler.plc.sendTestSequence(commands);
            catch exception
                controler.testRunning = false;
                controler.activeTestAxes = {};
                controler.model.isRecording = false;
                controler.model.closeFilesRec();
                controler.model.recordingStatus = 'aborted';
                controler.model.recordingReason = ...
                    ['Startup failed: ', exception.message];
                controler.model.writeRecordingStatus();
                rethrow(exception);
            end
        end

        function advanceTest(controler, statuses)
            if ~controler.testRunning, return; end
            anyError = false;
            allCompleted = true;
            anyWorking = false;
            for index = 1:numel(controler.activeTestAxes)
                axis = controler.activeTestAxes{index};
                statusNow = statuses.(axis);
                anyError = anyError || statusNow.error;
                anyWorking = anyWorking || statusNow.working;
                allCompleted = allCompleted && ...
                    statusNow.operationCounter ~= ...
                    controler.operationStartCounters.(axis);
            end
            if anyError
                messages = PlcErrorCatalog.messagesForStatuses(statuses);
                if isempty(messages), messages = {'PLC operation failed.'}; end
                try
                    controler.plc.stop(controler.activeTestAxes);
                catch exception
                    warning('Control:PeerStop', ...
                        'Could not halt the peer axis: %s', exception.message);
                end
                controler.testRunning = false;
                controler.activeTestAxes = {};
                controler.finishRecording(strjoin(messages, ' | '));
            elseif allCompleted && ~anyWorking
                controler.testRunning = false;
                controler.activeTestAxes = {};
                controler.finishRecording('Completed');
            end
        end

        function commands = buildCommands(controler, config, testType)
            axes = controler.activeAxes(config.system.axisMode);
            commands = struct('X', [], 'Y', []);
            postMode = controler.postMode(config.post.afterTest);
            for index = 1:numel(axes)
                axis = axes{index};
                field = lower(axis);
                command = controler.emptyCommand();
                command.postTestMode = postMode;
                if strcmp(testType, 'pre')
                    command = controler.applyPreTest(command, config.pre, ...
                        field, true);
                    command.preTestOnly = true;
                elseif strcmp(testType, 'single')
                    command = controler.applyPreTest(command, config.pre, ...
                        field, logical(config.single.includePre));
                    command.testRate = config.single.rate.(field);
                    command.forceHoldTime = config.single.holdTime.(field);
                    command.stop1Mode = ...
                        controler.controlMode(config.single.primaryMode, false);
                    command.stop1Value = config.single.primary.(field);
                    command.stop2Mode = ...
                        controler.controlMode(config.single.secondaryMode, true);
                    command.stop2Value = config.single.secondary.(field);
                    command.forceDropPercent = config.single.forceDrop;
                    command.forceDropThreshold = ...
                        config.single.failureThreshold.(field);
                else
                    command = controler.applyPreTest(command, config.pre, ...
                        field, logical(config.cyclic.includePre));
                    command.testRate = config.cyclic.rate.(field);
                    command.forceHoldTime = config.cyclic.holdTime.(field);
                    command.cycleCount = round(config.cyclic.cycles);
                    command.loadMode = ...
                        controler.controlMode(config.cyclic.loadMode, false);
                    command.unloadMode = ...
                        controler.controlMode(config.cyclic.unloadMode, false);
                    command.loadValues = repmat(config.cyclic.load.(field), ...
                        1, command.cycleCount);
                    command.unloadValues = repmat( ...
                        config.cyclic.unload.(field), 1, command.cycleCount);
                    command.forceDropPercent = config.cyclic.forceDrop;
                    command.forceDropThreshold = ...
                        config.cyclic.failureThreshold.(field);
                end
                commands.(axis) = command;
            end
        end

        function commands = buildGeneralCommands(controler, definition)
            GeneralTestDefinition.validate(definition);
            switch lower(char(definition.axisMode))
                case 'x'
                    axes = {'X'};
                case 'y'
                    axes = {'Y'};
                otherwise
                    axes = {'X', 'Y'};
            end
            commands = struct('X', [], 'Y', []);
            for index = 1:numel(axes)
                axis = axes{index};
                field = lower(axis);
                command = controler.emptyCommand();
                command = controler.applyPreTest(command, ...
                    definition.preTest, field, definition.preTest.enabled);
                command.postTestMode = ...
                    controler.stablePostMode(definition.postTest);
                if strcmpi(definition.testType, 'single')
                    value = definition.single;
                    command.testRate = value.rate.(field);
                    command.forceHoldTime = value.holdTime.(field);
                    command.stop1Mode = ...
                        controler.controlMode(value.primaryMode, false);
                    command.stop1Value = value.primaryValue.(field);
                    command.stop2Mode = ...
                        controler.controlMode(value.secondaryMode, true);
                    command.stop2Value = value.secondaryValue.(field);
                    if isfield(value, 'forceDropPercent')
                        command.forceDropPercent = value.forceDropPercent;
                    end
                    if isfield(value, 'forceDropThreshold')
                        command.forceDropThreshold = ...
                            value.forceDropThreshold.(field);
                    end
                else
                    value = definition.cyclic;
                    command.testRate = value.rate.(field);
                    command.forceHoldTime = value.holdTime.(field);
                    command.cycleCount = numel(value.loadValues.(field));
                    command.loadMode = ...
                        controler.controlMode(value.loadMode, false);
                    command.unloadMode = ...
                        controler.controlMode(value.unloadMode, false);
                    command.loadValues = ...
                        double(value.loadValues.(field)(:))';
                    command.unloadValues = ...
                        double(value.unloadValues.(field)(:))';
                    if isfield(value, 'forceDropPercent')
                        command.forceDropPercent = value.forceDropPercent;
                    end
                    if isfield(value, 'forceDropThreshold')
                        command.forceDropThreshold = ...
                            value.forceDropThreshold.(field);
                    end
                end
                commands.(axis) = command;
            end
        end

        function command = applyPreTest(~, command, pre, field, enabled)
            command.includePreTest = logical(enabled);
            if ~enabled, return; end
            cycles = round(pre.cycles);
            if ~pre.cyclic, cycles = 0; end
            command.preCycleCount = cycles;
            command.preloadEnabled = logical(pre.preload.enabled);
            command.preloadValue = pre.preload.value.(field);
            command.preLoadValue = pre.load.(field);
            command.preUnloadValue = pre.unload.(field);
            command.preUnloadToStart = logical(pre.unloadToStart);
            command.preTestRate = pre.rate.(field);
            command.preTestHoldTime = pre.holdTime.(field);
        end

        function command = emptyCommand(~)
            command = struct( ...
                'includePreTest', false, 'preTestOnly', false, ...
                'preCycleCount', 1, 'preloadEnabled', false, ...
                'preloadValue', 0, 'preLoadValue', 0, ...
                'preUnloadValue', 0, 'preUnloadToStart', false, ...
                'preTestRate', 1, 'preTestHoldTime', 0, ...
                'testRate', 1, 'forceHoldTime', 0, ...
                'forceDropPercent', 0, 'forceDropThreshold', 0, ...
                'cycleCount', 0, 'loadMode', 1, 'loadValues', [], ...
                'unloadMode', 1, 'unloadValues', [], ...
                'stop1Mode', 1, 'stop1Value', 0, ...
                'stop2Mode', 0, 'stop2Value', 0, ...
                'postTestMode', 0);
        end

        function mode = controlMode(~, value, allowNone)
            value = lower(strtrim(char(value)));
            if strcmp(value, 'displacement')
                mode = 1;
            elseif strcmp(value, 'force')
                mode = 2;
            elseif allowNone && strcmp(value, 'none')
                mode = 0;
            else
                error('Control:InvalidMode', 'Unsupported control mode: %s.', value);
            end
        end

        function mode = postMode(~, value)
            switch char(value)
                case 'Return to saved position'
                    mode = 1;
                case 'Return to start position'
                    mode = 2;
                case 'Return to pre-test final position'
                    mode = 3;
                case 'Unload (force)'
                    mode = 4;
                otherwise
                    mode = 0;
            end
        end

        function mode = stablePostMode(~, value)
            switch lower(char(value))
                case 'saved'
                    mode = 1;
                case 'sequence_start'
                    mode = 2;
                case 'pretest_final'
                    mode = 3;
                case 'zero_force'
                    mode = 4;
                otherwise
                    mode = 0;
            end
        end

        function axes = commandAxes(~, commands)
            axes = {};
            for axis = {'X', 'Y'}
                if isfield(commands, axis{1}) && ~isempty(commands.(axis{1}))
                    axes{end + 1} = axis{1}; %#ok<AGROW>
                end
            end
        end

        function axes = activeAxes(~, mode)
            switch char(mode)
                case {'X only', 'x', 'X'}
                    axes = {'X'};
                case {'Y only', 'y', 'Y'}
                    axes = {'Y'};
                otherwise
                    axes = {'X', 'Y'};
            end
        end

        function prepareRecording(controler, folder)
            controler.model.selectedFolder = folder;
            controler.model.recordIndex = 1;
            if ~isempty(controler.camera.cameraHW) && ...
                    isvalid(controler.camera.cameraHW)
                resolution = controler.camera.cameraHW.VideoResolution;
                controler.model.cameraFrameWidth = resolution(1);
                controler.model.cameraFrameHeight = resolution(2);
            else
                controler.model.cameraFrameWidth = 1024;
                controler.model.cameraFrameHeight = 1024;
            end
        end

        function updateStatusUI(controler, statuses)
            messages = PlcErrorCatalog.messagesForStatuses(statuses);
            controler.app.updateErrorStatus(~isempty(messages), ...
                strjoin(messages, newline));
        end

        function notifyMachineStatus(controler, statuses, connected)
            if ~isempty(controler.app) && isvalid(controler.app) && ...
                    ismethod(controler.app, 'updateMachineStatus')
                controler.app.updateMachineStatus(statuses, connected);
            end
        end

        function appendPlot(controler, lineHandle, axesHandle, batch, axisName)
            if isempty(batch) || isempty(lineHandle) || ...
                    ~isvalid(lineHandle) || isempty(axesHandle) || ...
                    ~isvalid(axesHandle)
                return;
            end
            property = ['totalTime', axisName];
            count = numel(batch);
            time = controler.plc.(property) + controler.plc.ts * (1:count);
            addpoints(lineHandle, time, batch);
            controler.plc.(property) = controler.plc.(property) + ...
                controler.plc.ts * count;
            window = 5;
            axesHandle.XLim = [max(0, controler.plc.(property) - window), ...
                max(window, controler.plc.(property))];
        end

        function finishRecording(controler, reason)
            if nargin < 2 || isempty(reason), reason = 'Completed'; end
            if ~controler.model.isRecording, return; end
            controler.model.isRecording = false;
            controler.model.closeFilesRec();
            if strcmpi(reason, 'Completed')
                controler.model.recordingStatus = 'completed';
            else
                controler.model.recordingStatus = 'aborted';
            end
            controler.model.recordingReason = char(reason);
            controler.model.writeRecordingStatus();
            try
                controler.model.PostProcessData(controler.model.selectedFolder);
            catch exception
                warning('Control:PostProcess', '%s', exception.message);
            end
            controler.camera.recordingPeriod = 0;
        end

        function handleRuntimeError(controler, exception, titleText)
            if strcmp(titleText, 'ADS read error') && ...
                    (~controler.plc.connected || controler.plc.disconnecting)
                return;
            end
            warning('Control:Runtime', '%s: %s', titleText, exception.message);
            if (strcmp(titleText, 'ADS read error') || ...
                    strcmp(titleText, 'Camera error')) && ...
                    ~controler.abortInProgress
                controler.safeAbort([titleText, ': ', exception.message]);
            end
            if ~isempty(controler.app) && isvalid(controler.app)
                controler.app.updateErrorStatus(true, ...
                    sprintf('%s: %s', titleText, exception.message));
            end
        end
    end
end
