classdef Control < handle
    % Coordinates PLC, camera, storage, test queues, and View updates.

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

        operationQueue = {}
        operationActive = false
        operationSeenBusy = false
        operationStartCounters = struct('X', uint32(0), 'Y', uint32(0))
        activeOperation = struct()
        testRunning = false
        postScheduled = false
        postAction = 'Stay at unchanged position'
        postSpeeds = struct('X', 1, 'Y', 1)
        testStartPositions = struct('X', NaN, 'Y', NaN)
        preFinalPositions = struct('X', NaN, 'Y', NaN)
        savedPositions = struct('X', NaN, 'Y', NaN)
        abortInProgress = false
    end

    methods
        % Control handles this operation.
        function controler = Control(model)
            controler.model = model;
            controler.camera = Camera(model);
            controler.camera.errorHandler = @(exception) ...
                controler.handleRuntimeError(exception, 'Camera error');
            controler.plc = Plc(model);
            controler.settings = Settings(controler.plc, controler.camera);
        end

        % startTimers handles this operation.
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

        % readCallback handles this operation.
        function readCallback(controler)
            if ~controler.plc.connected
                return;
            end
            try
                [fx, fy, ufx, ufy, px, py, statuses] = controler.plc.fifoProcess();
                controler.xForceData = [controler.xForceData, fx];
                controler.yForceData = [controler.yForceData, fy];
                controler.xUntaredForceData = [controler.xUntaredForceData, ufx];
                controler.yUntaredForceData = [controler.yUntaredForceData, ufy];
                controler.xPositionData = [controler.xPositionData, px];
                controler.yPositionData = [controler.yPositionData, py];
                controler.updateStatusUI(statuses);
                controler.advanceOperationQueue(statuses);
            catch exception
                controler.handleRuntimeError(exception, 'ADS read error');
            end
        end

        % updateDisplay handles this operation.
        function updateDisplay(controler)
            app = controler.app;
            if isempty(app) || ~isvalid(app)
                return;
            end
            try
                if controler.camera.connected && ~isempty(controler.camera.latestFrame) && isvalid(app.cameraAxes)
                    app.camImageHandle.CData = controler.camera.latestFrame;
                    controler.camera.latestFrame = [];
                end

                if strcmp(app.modeDrop.Value, 'Force')
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

                controler.appendPlot(app.fxLine, app.fxAxes, xBatch, 'X');
                controler.appendPlot(app.fyLine, app.fyAxes, yBatch, 'Y');
                controler.model.saveAxisSamples('X', forceX, untaredX, posX);
                controler.model.saveAxisSamples('Y', forceY, untaredY, posY);
                drawnow limitrate;
            catch exception
                controler.handleRuntimeError(exception, 'Display update error');
            end
        end

        % panicStop handles this operation.
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

        % jog handles this operation.
        function jog(controler, axisName, direction, distance, velocity)
            controler.plc.jog(axisName, direction * abs(distance), velocity);
        end

        % tare handles this operation.
        function tare(controler, axisMode)
            controler.plc.tare(axisMode);
        end

        % moveToLowerLimit handles this operation.
        function moveToLowerLimit(controler, axisMode)
            controler.plc.moveToLowerLimit(axisMode);
        end

        % resetErrors handles this operation.
        function resetErrors(controler)
            axes = {};
            if isfield(controler.plc.status, 'X') && isfield(controler.plc.status.X, 'error') && controler.plc.status.X.error
                axes{end+1} = 'X';
            end
            if isfield(controler.plc.status, 'Y') && isfield(controler.plc.status.Y, 'error') && controler.plc.status.Y.error
                axes{end+1} = 'Y';
            end
            if isempty(axes)
                return;
            end
            controler.plc.resetErrors(axes);
        end

        % savePosition handles this operation.
        function savePosition(controler)
            statuses = controler.plc.pollStatus();
            controler.savedPositions.X = statuses.X.position;
            controler.savedPositions.Y = statuses.Y.position;
        end

        % restorePosition handles this operation.
        function restorePosition(controler, app)
            if isnan(controler.savedPositions.X) && isnan(controler.savedPositions.Y)
                error('Control:NoSavedPosition', 'No position has been saved yet.');
            end
            statuses = controler.plc.pollStatus();
            axes = controler.activeAxes(app.getAxisMode());
            manual = app.getManualMotion();
            operation = controler.positionOperation(axes, controler.savedPositions, statuses, ...
                manual.speed, 'restore');
            controler.executeOperation(operation);
        end

        % runPreTest handles this operation.
        function runPreTest(controler, app)
            config = app.getTestConfiguration();
            operations = controler.buildPreTest(config, true);
            controler.startTestQueue(app, operations, config.pre.cameraPeriod);
        end

        % runSingleTest handles this operation.
        function runSingleTest(controler, app)
            config = app.getTestConfiguration();
            if strcmp(config.single.mode, 'Strain controlled')
                error('Control:UnsupportedMode', 'Strain-controlled testing is not available yet.');
            end
            operations = {};
            if config.single.includePre
                operations = controler.buildPreTest(config, false);
            end
            operations{end+1} = controler.buildSingleOperation(config);
            controler.startTestQueue(app, operations, config.single.cameraPeriod);
        end

        % runCyclicTest handles this operation.
        function runCyclicTest(controler, app)
            config = app.getTestConfiguration();
            if ~strcmp(config.cyclic.loadMode, config.cyclic.unloadMode)
                error('Control:MixedCyclicMode', 'Cyclic load and unload must use the same control mode.');
            end
            operations = {};
            if config.cyclic.includePre
                operations = controler.buildPreTest(config, false);
            end
            operations{end+1} = controler.buildCyclicOperation(config);
            controler.startTestQueue(app, operations, config.cyclic.cameraPeriod);
        end

        % safeAbort handles this operation.
        function safeAbort(controler, reason)
            if controler.abortInProgress
                return;
            end
            wasActive = controler.testRunning || controler.operationActive || ...
                controler.model.isRecording || controler.model.filesOpen;
            controler.abortInProgress = true;
            controler.operationQueue = {};
            controler.operationActive = false;
            controler.testRunning = false;
            try
                if controler.plc.connected
                    controler.plc.stop('Both');
                    deadline = tic;
                    while toc(deadline) < 5
                        try
                            statuses = controler.plc.pollStatus();
                            if ~statuses.X.working && ~statuses.Y.working && ...
                                    statuses.X.stopped && statuses.Y.stopped
                                break;
                            end
                        catch
                            break;
                        end
                        pause(0.05);
                        drawnow limitrate;
                    end
                end
            catch stopException
                warning('Control:AbortStop', 'Could not stop PLC during abort: %s', stopException.message);
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
    end

    methods (Access = private)
        % startTestQueue handles this operation.
        function startTestQueue(controler, app, operations, cameraControls)
            if controler.testRunning || controler.plc.isWorking
                error('Control:Busy', 'A PLC operation is already active.');
            end
            folder = uigetdir('', 'Choose test output folder');
            if isequal(folder, 0)
                return;
            end
            statuses = controler.plc.pollStatus();
            controler.testStartPositions = struct('X', statuses.X.position, 'Y', statuses.Y.position);
            controler.preFinalPositions = struct('X', NaN, 'Y', NaN);
            controler.operationQueue = operations;
            controler.operationActive = false;
            controler.operationSeenBusy = false;
            controler.testRunning = true;
            controler.postScheduled = false;
            controler.postAction = app.getPostTestAction();
            manual = app.getManualMotion();
            controler.postSpeeds = manual.speed;
            if cameraControls.enabled
                controler.camera.recordingPeriod = cameraControls.value;
            else
                controler.camera.recordingPeriod = 0;
            end
            controler.prepareRecording(folder);
            controler.model.isRecording = true;
            controler.model.recordingStatus = 'starting';
            controler.model.recordingReason = '';
            try
                controler.model.openFilesRec();
                controler.executeNextOperation();
            catch exception
                controler.model.isRecording = false;
                controler.model.closeFilesRec();
                controler.model.recordingStatus = 'aborted';
                controler.model.recordingReason = ['Startup failed: ', exception.message];
                controler.model.writeRecordingStatus();
                controler.operationQueue = {};
                controler.operationActive = false;
                controler.testRunning = false;
                rethrow(exception);
            end
        end

        % prepareRecording handles this operation.
        function prepareRecording(controler, folder)
            controler.model.selectedFolder = folder;
            controler.model.recordIndex = 1;
            if ~isempty(controler.camera.cameraHW) && isvalid(controler.camera.cameraHW)
                resolution = controler.camera.cameraHW.VideoResolution;
                controler.model.cameraFrameWidth = resolution(1);
                controler.model.cameraFrameHeight = resolution(2);
            else
                controler.model.cameraFrameWidth = 1024;
                controler.model.cameraFrameHeight = 1024;
            end
        end

        % executeNextOperation handles this operation.
        function executeNextOperation(controler)
            if isempty(controler.operationQueue)
                if ~controler.postScheduled
                    controler.postScheduled = true;
                    postOperation = controler.buildPostOperation();
                    if ~isempty(postOperation)
                        controler.operationQueue = {postOperation};
                    end
                end
                if isempty(controler.operationQueue)
                    controler.testRunning = false;
                    controler.finishRecording();
                    return;
                end
            end
            operation = controler.operationQueue{1};
            controler.operationQueue(1) = [];
            statuses = controler.plc.pollStatus();
            controler.operationStartCounters.X = statuses.X.operationCounter;
            controler.operationStartCounters.Y = statuses.Y.operationCounter;
            controler.executeOperation(operation);
            controler.activeOperation = operation;
            controler.operationActive = true;
            controler.operationSeenBusy = false;
        end

        % executeOperation handles this operation.
        function executeOperation(controler, operation)
            switch operation.type
                case 'trajectory'
                    controler.plc.SendCommands(operation.mode, operation.X.distance, operation.X.velocity, ...
                        operation.Y.distance, operation.Y.velocity);
                case 'single'
                    controler.plc.ensurePowered(operation.axes);
                    for axisName = operation.axes
                        axis = axisName{1};
                        values = operation.(axis);
                        controler.plc.sendSingleTest(axis, values.controlMode, values.rate, ...
                            values.stop1Mode, values.stop1Value, values.stop2Mode, values.stop2Value);
                    end
                case 'positionTarget'
                    statuses = controler.plc.pollStatus();
                    xDistance = [];
                    xVelocity = [];
                    yDistance = [];
                    yVelocity = [];
                    if ismember('X', operation.axes)
                        xDistance = operation.targets.X - statuses.X.position;
                        xVelocity = operation.speeds.X;
                    end
                    if ismember('Y', operation.axes)
                        yDistance = operation.targets.Y - statuses.Y.position;
                        yVelocity = operation.speeds.Y;
                    end
                    controler.plc.SendCommands(1, xDistance, xVelocity, yDistance, yVelocity);
                otherwise
                    error('Control:UnknownOperation', 'Unknown operation type %s.', operation.type);
            end
        end

        % advanceOperationQueue handles this operation.
        function advanceOperationQueue(controler, statuses)
            if ~controler.operationActive
                return;
            end
            axes = controler.activeOperation.axes;
            anyError = false;
            anyWorking = false;
            allCompleted = true;
            for index = 1:numel(axes)
                axisName = axes{index};
                status = statuses.(axisName);
                anyError = anyError || status.error;
                anyWorking = anyWorking || status.working;
                allCompleted = allCompleted && ...
                    status.operationCounter ~= controler.operationStartCounters.(axisName);
            end
            if anyError
                controler.operationQueue = {};
                controler.operationActive = false;
                controler.testRunning = false;
                controler.finishRecording();
                return;
            end
            controler.operationSeenBusy = controler.operationSeenBusy || anyWorking;
            if allCompleted && ~anyWorking
                if isfield(controler.activeOperation, 'tag') && strcmp(controler.activeOperation.tag, 'pre-final')
                    controler.preFinalPositions = struct('X', statuses.X.position, 'Y', statuses.Y.position);
                end
                controler.operationActive = false;
                controler.executeNextOperation();
            end
        end

        % buildPreTest handles this operation.
        function operations = buildPreTest(controler, config, markFinal)
            pre = config.pre;
            axes = controler.activeAxes(config.system.axisMode);
            cycles = max(1, round(pre.cycles));
            if ~pre.cyclic
                cycles = 1;
            end
            if pre.unloadToStart
                operations = {};
                for cycle = 1:cycles
                    target = controler.forceTargetOperation( ...
                        axes, pre.load, pre.rate, 'pre-load');
                    if cycle == 1 && pre.preload.enabled
                        for axisName = axes
                            axis = axisName{1};
                            target.(axis).distance = ...
                                [pre.preload.value, target.(axis).distance];
                            target.(axis).velocity = ...
                                [pre.rate.(lower(axis)), target.(axis).velocity];
                        end
                    end
                    operations{end+1} = target;
                    statuses = controler.plc.pollStatus();
                    returnTarget = controler.testStartPositions;
                    if isnan(returnTarget.X)
                        returnTarget = struct('X', statuses.X.position, 'Y', statuses.Y.position);
                    end
                    speed = controler.axisValues(pre.rate);
                    returnOp = controler.positionOperation(axes, returnTarget, statuses, speed, 'pre-return');
                    operations{end+1} = returnOp;
                end
            else
                operation = struct('type', 'trajectory', 'mode', 3, 'axes', {axes}, 'tag', 'pre');
                operation.X = struct('distance', [], 'velocity', []);
                operation.Y = struct('distance', [], 'velocity', []);
                for axisName = axes
                    axis = axisName{1};
                    field = lower(axis);
                    targets = [];
                    if pre.preload.enabled
                        targets(end+1) = pre.preload.value;
                    end
                    for cycle = 1:cycles
                        targets(end+1:end+2) = ...
                            [pre.load.(field), pre.unload.(field)];
                    end
                    operation.(axis).distance = targets;
                    operation.(axis).velocity = ...
                        repmat(pre.rate.(field), size(targets));
                end
                operations = {operation};
            end
            if markFinal || ~isempty(operations)
                operations{end}.tag = 'pre-final';
            end
        end

        % forceTargetOperation handles this operation.
        function operation = forceTargetOperation(~, axes, targets, rates, tag)
            operation = struct('type', 'trajectory', 'mode', 3, 'axes', {axes}, 'tag', tag, ...
                'X', struct('distance', [], 'velocity', []), ...
                'Y', struct('distance', [], 'velocity', []));
            for axisName = axes
                axis = axisName{1};
                field = lower(axis);
                operation.(axis).distance = targets.(field);
                operation.(axis).velocity = rates.(field);
            end
        end

        % buildSingleOperation handles this operation.
        function operation = buildSingleOperation(controler, config)
            single = config.single;
            axes = controler.activeAxes(config.system.axisMode);
            operation = struct('type', 'single', 'axes', {axes}, 'tag', 'single');
            if strcmp(single.mode, 'Displacement controlled')
                controlMode = 1;
            else
                controlMode = 2;
            end
            stop1Mode = controler.criterionMode(single.stop1Mode);
            stop2Mode = controler.criterionMode(single.stop2Mode);
            for axisName = axes
                axis = axisName{1};
                field = lower(axis);
                operation.(axis) = struct('controlMode', controlMode, ...
                    'rate', single.rate.(field), ...
                    'stop1Mode', stop1Mode, 'stop1Value', single.stop1.(field), ...
                    'stop2Mode', stop2Mode, 'stop2Value', single.stop2.(field));
            end
        end

        % buildCyclicOperation handles this operation.
        function operation = buildCyclicOperation(controler, config)
            cyclic = config.cyclic;
            axes = controler.activeAxes(config.system.axisMode);
            cycles = max(1, round(cyclic.cycles));
            isForce = strcmp(cyclic.loadMode, 'Force');
            operation = struct('type', 'trajectory', 'mode', 1 + 2 * isForce, 'axes', {axes}, ...
                'tag', 'cyclic', 'X', struct('distance', [], 'velocity', []), ...
                'Y', struct('distance', [], 'velocity', []));
            for axisName = axes
                axis = axisName{1};
                field = lower(axis);
                loadValue = cyclic.load.(field);
                unloadValue = cyclic.unload.(field);
                rate = cyclic.rate.(field);
                if isForce
                    operation.(axis).distance = repmat([loadValue, unloadValue], 1, cycles);
                else
                    distances = zeros(1, 2 * cycles);
                    distances(1) = loadValue;
                    for index = 2:numel(distances)
                        if mod(index, 2) == 0
                            distances(index) = unloadValue - loadValue;
                        else
                            distances(index) = loadValue - unloadValue;
                        end
                    end
                    operation.(axis).distance = distances;
                end
                operation.(axis).velocity = repmat(rate, size(operation.(axis).distance));
            end
        end

        % buildPostOperation handles this operation.
        function operation = buildPostOperation(controler)
            operation = [];
            statuses = controler.plc.pollStatus();
            axes = controler.activeAxes(controler.app.getAxisMode());
            switch controler.postAction
                case 'Return to saved position'
                    target = controler.savedPositions;
                    if isnan(target.X) && isnan(target.Y), return; end
                    operation = controler.positionOperation(axes, target, statuses, controler.postSpeeds, 'post');
                case 'Return to start position'
                    operation = controler.positionOperation(axes, controler.testStartPositions, statuses, controler.postSpeeds, 'post');
                case 'Return to pre-test final position'
                    if isnan(controler.preFinalPositions.X) && isnan(controler.preFinalPositions.Y), return; end
                    operation = controler.positionOperation(axes, controler.preFinalPositions, statuses, controler.postSpeeds, 'post');
                case 'Unload (force)'
                    operation = struct('type', 'trajectory', 'mode', 3, 'axes', {axes}, 'tag', 'post', ...
                        'X', struct('distance', [], 'velocity', []), 'Y', struct('distance', [], 'velocity', []));
                    for axisName = axes
                        axis = axisName{1};
                        operation.(axis).distance = 0;
                        operation.(axis).velocity = controler.postSpeeds.(axis);
                    end
            end
        end

        % positionOperation handles this operation.
        function operation = positionOperation(~, axes, targets, ~, speeds, tag)
            operation = struct('type', 'positionTarget', 'axes', {axes}, 'tag', tag, ...
                'targets', targets, 'speeds', speeds);
        end

        % axisValues handles this operation.
        function values = axisValues(~, controls)
            values = struct('X', controls.x, 'Y', controls.y);
        end

        % activeAxes handles this operation.
        function axes = activeAxes(~, mode)
            switch mode
                case 'X only', axes = {'X'};
                case 'Y only', axes = {'Y'};
                otherwise, axes = {'X', 'Y'};
            end
        end

        % criterionMode handles this operation.
        function mode = criterionMode(~, value)
            switch value
                case 'Displacement', mode = 1;
                case 'Force', mode = 2;
                otherwise, mode = 0;
            end
        end

        % updateStatusUI handles this operation.
        function updateStatusUI(controler, statuses)
            messages = PlcErrorCatalog.messagesForStatuses(statuses);
            controler.app.updateErrorStatus(~isempty(messages), strjoin(messages, newline));
        end

        % appendPlot handles this operation.
        function appendPlot(controler, lineHandle, axesHandle, batch, axisName)
            if isempty(batch)
                return;
            end
            property = ['totalTime', axisName];
            count = numel(batch);
            time = controler.plc.(property) + controler.plc.ts * (1:count);
            addpoints(lineHandle, time, batch);
            controler.plc.(property) = controler.plc.(property) + controler.plc.ts * count;
            window = 5;
            axesHandle.XLim = [max(0, controler.plc.(property) - window), max(window, controler.plc.(property))];
        end

        % finishRecording handles this operation.
        function finishRecording(controler, reason)
            if nargin < 2 || isempty(reason)
                reason = 'Completed';
            end
            if ~controler.model.isRecording
                return;
            end
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

        % handleRuntimeError handles this operation.
        function handleRuntimeError(controler, exception, titleText)
            warning('Control:Runtime', '%s: %s', titleText, exception.message);
            if (strcmp(titleText, 'ADS read error') || strcmp(titleText, 'Camera error')) && ...
                    ~controler.abortInProgress
                controler.safeAbort([titleText, ': ', exception.message]);
            end
            if ~isempty(controler.app) && isvalid(controler.app)
                controler.app.updateErrorStatus(true, sprintf('%s: %s', titleText, exception.message));
            end
        end
    end
end

