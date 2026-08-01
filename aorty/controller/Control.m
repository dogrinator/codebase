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
        samples AcquisitionBuffer

        operationStartCounters = struct('X', uint32(0), 'Y', uint32(0))
        operationStartDrops = struct('X', 0, 'Y', 0)
        operationStartRestarts = struct('X', 0, 'Y', 0)
        activeTestAxes = {}
        testRunning = false
        abortInProgress = false
        recordingFolderSelector = []
        activePostProcessSettings = struct( ...
            'enabled', false, 'samplingPeriod', 0, ...
            'includePrePost', false)
    end

    methods
        function controler = Control(model, plc, camera)
            controler.model = model;
            controler.samples = AcquisitionBuffer();
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
                'BusyMode', 'drop', ...
                'Period', AppInfo.PLC_READ_PERIOD_SECONDS, ...
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
                readTime = datetime('now');
                xTimes = controler.sampleTimes(readTime, numel(fx));
                yTimes = controler.sampleTimes(readTime, numel(fy));
                controler.samples.append( ...
                    fx, fy, ufx, ufy, px, py, xTimes, yTimes);
                controler.model.updateSystemStatus( ...
                    statuses, controler.activeTestAxes);
                controler.updateStatusUI(statuses);
                controler.notifyMachineStatus(statuses, true);
                integrityError = controler.acquisitionIntegrityError();
                if ~isempty(integrityError)
                    controler.safeAbort(integrityError);
                    return;
                end
                controler.advanceTest(statuses);
            catch exception
                controler.handleRuntimeError(exception, 'ADS read error');
            end
        end

        function updateDisplay(controler)
            viewApp = controler.app;
            if isempty(viewApp) || ~isvalid(viewApp) || ...
                    isempty(viewApp.fig) || ~isvalid(viewApp.fig)
                return;
            end
            if controler.camera.connected && ...
                    ~isempty(controler.camera.latestFrame)
                try
                    viewApp.updateCameraFrame( ...
                        controler.camera.latestFrame);
                    controler.camera.latestFrame = [];
                catch exception
                    controler.handleRuntimeError( ...
                        exception, 'Display update error');
                end
            end

            plotBatch = controler.samples.plotBatch();
            if controler.model.isRecording
                try
                    controler.samples.flush(controler.model);
                catch exception
                    controler.handleRuntimeError( ...
                        exception, 'Recording write error');
                    return;
                end
            else
                controler.samples.clear();
            end

            try
                viewApp.appendPlotData(plotBatch, controler.model.dt);
                drawnow limitrate nocallbacks;
            catch exception
                controler.handleRuntimeError( ...
                    exception, 'Display update error');
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
            controler.requireIdleOperation('jog an axis');
            controler.plc.jog(axisName, direction * abs(distance), velocity);
        end

        function tare(controler, axisMode)
            controler.requireIdleOperation('tare the load cells');
            controler.plc.tare( ...
                TestCommandBuilder.axesForMode(axisMode));
        end

        function moveToLowerLimit(controler, axisMode)
            controler.requireIdleOperation('home an axis');
            controler.plc.moveToLowerLimit( ...
                TestCommandBuilder.axesForMode(axisMode));
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
            controler.requireIdleOperation('change axis power');
            controler.plc.setPower( ...
                TestCommandBuilder.axesForMode(axisMode), enabled);
        end

        function savePosition(controler, app)
            controler.requireIdleOperation('save a position');
            controler.plc.savePosition( ...
                TestCommandBuilder.axesForMode(app.getAxisMode()));
        end

        function restorePosition(controler, app)
            controler.requireIdleOperation('restore a position');
            axes = TestCommandBuilder.axesForMode(app.getAxisMode());
            manual = app.getManualMotion();
            controler.plc.restorePosition(axes, manual.speed);
        end

        function runPreTest(controler, app)
            config = app.getTestConfiguration();
            commands = TestCommandBuilder.fromPreset(config, 'pre');
            postSettings = struct('enabled', false, ...
                'samplingPeriod', 0, 'includePrePost', true);
            controler.startTest(app, commands, postSettings, ...
                logical(config.pre.record), 'pre');
        end

        function runSingleTest(controler, app)
            config = app.getTestConfiguration();
            commands = TestCommandBuilder.fromPreset(config, 'single');
            controler.startTest( ...
                app, commands, config.single.postProcess, true, 'single');
        end

        function runCyclicTest(controler, app)
            config = app.getTestConfiguration();
            commands = TestCommandBuilder.fromPreset(config, 'cyclic');
            controler.startTest( ...
                app, commands, config.cyclic.postProcess, true, 'cyclic');
        end

        function runGeneralTest(controler, app)
            definition = app.getGeneralTestDefinition();
            commands = TestCommandBuilder.fromGeneral(definition);
            postSettings = struct( ...
                'enabled', logical(definition.camera.enabled), ...
                'samplingPeriod', ...
                    double(definition.camera.samplingPeriod), ...
                'includePrePost', ...
                    logical(definition.camera.includePrePost));
            controler.startTest(app, commands, postSettings, true, ...
                ['general-', lower(char(definition.testType))]);
        end

        function result = runManualPostProcessing(controler, ...
                folderPath, samplingPeriod, includePrePost)
            if controler.testRunning || controler.model.isRecording || ...
                    controler.model.filesOpen
                error('Control:RecordingActive', ...
                    ['Post-processing cannot start while a test ' ...
                    'recording is active.']);
            end
            options = struct( ...
                'samplingPeriod', double(samplingPeriod), ...
                'phaseScope', controler.phaseScope(includePrePost), ...
                'outputFolder', ...
                    controler.manualOutputFolder(folderPath));
            result = PostProcessor.processData(folderPath, options);
        end

        function safeAbort(controler, reason)
            if controler.abortInProgress, return; end
            wasActive = controler.testRunning || controler.model.isRecording || ...
                controler.model.filesOpen;
            controler.abortInProgress = true;
            cleanup = onCleanup(@() controler.finishAbortCleanup());
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
            if wasActive
                controler.finishTest(reason);
            end
            clear cleanup;
        end

        function processTestStatusForTesting(controler, statuses)
            % Offline test seam for operation-counter and peer-halt logic.
            controler.advanceTest(statuses);
        end

        function startTestForTesting( ...
                controler, commands, postSettings, recordEnabled, testKind)
            % Offline test seam for recording and startup lifecycle.
            if nargin < 5
                testKind = 'test';
            end
            controler.startTest( ...
                [], commands, postSettings, recordEnabled, testKind);
        end
    end

    methods (Access = private)
        function startTest( ...
                controler, ~, commands, postSettings, ...
                recordEnabled, testKind)
            if controler.testRunning || controler.plc.isWorking
                error('Control:Busy', 'A PLC operation is already active.');
            end
            if nargin < 5
                recordEnabled = true;
            end
            if nargin < 6
                testKind = 'test';
            end
            recordEnabled = logical(recordEnabled);
            folder = [];
            if recordEnabled
                if isempty(controler.recordingFolderSelector)
                    folder = uigetdir('', 'Choose test output folder');
                else
                    folder = controler.recordingFolderSelector();
                end
                if isequal(folder, 0), return; end
            end

            statuses = controler.plc.pollStatus();
            axes = controler.commandAxes(commands);
            for index = 1:numel(axes)
                axis = axes{index};
                controler.operationStartCounters.(axis) = ...
                    statuses.(axis).operationCounter;
            end
            controler.operationStartDrops = controler.plc.droppedSamples;
            controler.operationStartRestarts = controler.plc.restartCounts;
            controler.samples.clear();
            controler.activePostProcessSettings = ...
                controler.validatePostProcessSettings(postSettings);
            if recordEnabled
                controler.prepareRecording(folder);
                controler.model.recordingStatus = 'starting';
                controler.model.recordingReason = '';
            else
                controler.activePostProcessSettings.enabled = false;
                controler.model.isRecording = false;
            end
            controler.model.updateSystemStatus(statuses, axes);
            controler.model.recordingDroppedSamples = ...
                struct('X', 0, 'Y', 0);
            controler.model.recordingRestartDetected = false;
            controler.model.statusResolutionSeconds = ...
                AppInfo.PLC_READ_PERIOD_SECONDS;
            controler.testRunning = true;
            controler.activeTestAxes = axes;
            controler.setOperationActive(true);
            try
                if recordEnabled
                    header = controler.buildRecordingHeader( ...
                        commands, axes, ...
                        controler.activePostProcessSettings, testKind);
                    controler.model.openFilesRec(header);
                    controler.model.isRecording = true;
                end
                controler.plc.sendTestSequence(commands);
            catch exception
                controler.testRunning = false;
                controler.activeTestAxes = {};
                if recordEnabled
                    controler.model.isRecording = false;
                    reason = ['Startup failed: ', exception.message];
                    if controler.model.filesOpen
                        try
                            controler.model.finalizeRecording( ...
                                'aborted', reason);
                        catch finalizeException
                            warning('Control:RecordingFinalize', ...
                                '%s', finalizeException.message);
                        end
                    else
                        controler.model.recordingStatus = 'aborted';
                        controler.model.recordingReason = reason;
                    end
                end
                controler.model.currentSystemStatus = int16(0);
                controler.activePostProcessSettings.enabled = false;
                controler.setOperationActive(false);
                rethrow(exception);
            end
        end

        function advanceTest(controler, statuses)
            if ~controler.testRunning, return; end
            anyError = false;
            unexpectedCounter = false;
            unexpectedMessages = {};
            allCompleted = true;
            anyWorking = false;
            for index = 1:numel(controler.activeTestAxes)
                axis = controler.activeTestAxes{index};
                statusNow = statuses.(axis);
                anyError = anyError || statusNow.error;
                anyWorking = anyWorking || statusNow.working;
                startCounter = double( ...
                    controler.operationStartCounters.(axis));
                currentCounter = double(statusNow.operationCounter);
                expectedCounter = mod(startCounter + 1, 2^32);
                completed = currentCounter == expectedCounter;
                unchanged = currentCounter == startCounter;
                allCompleted = allCompleted && completed;
                if ~completed && ~unchanged
                    unexpectedCounter = true;
                    unexpectedMessages{end + 1} = sprintf( ...
                        ['%s operation counter changed unexpectedly ' ...
                        'from %u to %u.'], axis, ...
                        controler.operationStartCounters.(axis), ...
                        statusNow.operationCounter); %#ok<AGROW>
                end
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
                controler.finishTest(strjoin(messages, ' | '));
            elseif unexpectedCounter
                try
                    controler.plc.stop(controler.activeTestAxes);
                catch exception
                    warning('Control:CounterStop', ...
                        'Could not halt after counter error: %s', ...
                        exception.message);
                end
                controler.testRunning = false;
                controler.activeTestAxes = {};
                controler.finishTest(strjoin(unexpectedMessages, ' | '));
            elseif allCompleted && ~anyWorking
                controler.testRunning = false;
                controler.activeTestAxes = {};
                controler.finishTest('Completed');
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

        function prepareRecording(controler, folder)
            controler.model.selectedFolder = folder;
            controler.model.recordIndex = 1;
            if ~isempty(controler.camera.cameraHW) && ...
                    isvalid(controler.camera.cameraHW)
                resolution = controler.camera.cameraHW.VideoResolution;
                controler.model.cameraFrameWidth = resolution(1);
                controler.model.cameraFrameHeight = resolution(2);
            else
                controler.model.cameraFrameWidth = 0;
                controler.model.cameraFrameHeight = 0;
            end
        end

        function header = buildRecordingHeader(controler, ...
                commands, axes, postSettings, testKind)
            plcSettings = struct( ...
                'X', controler.plc.readAxisConfig('X'), ...
                'Y', controler.plc.readAxisConfig('Y'));
            cameraSettings = controler.recordingCameraSettings();
            testSettings = struct( ...
                'test_kind', char(testKind), ...
                'active_axes', strjoin(axes, ','), ...
                'post_process_enabled', ...
                    logical(postSettings.enabled), ...
                'post_process_sampling_period', ...
                    double(postSettings.samplingPeriod), ...
                'post_process_include_pre_post', ...
                    logical(postSettings.includePrePost), ...
                'commands', commands);
            header = struct( ...
                'applicationVersion', AppInfo.VERSION, ...
                'interfaceVersion', ...
                    PlcAds.EXPECTED_INTERFACE_VERSION, ...
                'plcInterval', double(controler.model.dt), ...
                'statusResolutionSeconds', ...
                    AppInfo.PLC_READ_PERIOD_SECONDS, ...
                'camera', cameraSettings, ...
                'plc', plcSettings, ...
                'test', testSettings);
        end

        function values = recordingCameraSettings(controler)
            values = struct( ...
                'connected', false, ...
                'width', 0, ...
                'height', 0, ...
                'pixel_format', 'Mono8', ...
                'exposure_time', NaN, ...
                'gain', NaN, ...
                'configured_fps', NaN);
            cameraModel = controler.camera;
            if isempty(cameraModel) || ~cameraModel.connected || ...
                    isempty(cameraModel.cameraHW) || ...
                    ~isvalid(cameraModel.cameraHW)
                return;
            end
            resolution = cameraModel.cameraHW.VideoResolution;
            values.connected = true;
            values.width = double(resolution(1));
            values.height = double(resolution(2));
            source = cameraModel.cameraSrc;
            if ~isempty(source) && isvalid(source)
                if isprop(source, 'ExposureTimeAbs')
                    values.exposure_time = ...
                        double(source.ExposureTimeAbs);
                end
                if isprop(source, 'GainRaw')
                    values.gain = double(source.GainRaw);
                end
                if isprop(source, 'AcquisitionFrameRateAbs')
                    values.configured_fps = ...
                        double(source.AcquisitionFrameRateAbs);
                end
            end
        end

        function updateStatusUI(controler, statuses)
            if isempty(controler.app) || ~isvalid(controler.app) || ...
                    ~ismethod(controler.app, 'updateErrorStatus')
                return;
            end
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

        function finishRecording(controler, reason)
            if nargin < 2 || isempty(reason), reason = 'Completed'; end
            if ~controler.model.isRecording, return; end
            flushError = [];
            try
                controler.samples.flush(controler.model);
            catch exception
                flushError = exception;
                reason = ['Recording write failed: ', exception.message];
            end
            controler.model.isRecording = false;
            [dropCounts, restartDetected] = ...
                controler.recordingIntegrity();
            controler.model.recordingDroppedSamples = dropCounts;
            controler.model.recordingRestartDetected = restartDetected;
            if strcmpi(reason, 'Completed')
                recordingStatus = 'completed';
            else
                recordingStatus = 'aborted';
            end
            try
                controler.model.finalizeRecording( ...
                    recordingStatus, char(reason));
            catch exception
                warning('Control:RecordingFinalize', '%s', exception.message);
                if isempty(flushError)
                    flushError = exception;
                end
            end
            postSettings = controler.activePostProcessSettings;
            controler.activePostProcessSettings.enabled = false;
            if postSettings.enabled && isempty(flushError)
                options = struct( ...
                    'samplingPeriod', postSettings.samplingPeriod, ...
                    'phaseScope', ...
                        controler.phaseScope(postSettings.includePrePost), ...
                    'outputFolder', fullfile( ...
                        controler.model.selectedFolder, ...
                        'processed_frames'));
                try
                    PostProcessor.processData( ...
                        controler.model.selectedFolder, options);
                catch exception
                    warning('Control:PostProcess', '%s', exception.message);
                    if ~isempty(controler.app) && isvalid(controler.app)
                        controler.app.updateErrorStatus(true, ...
                            sprintf('Post-processing failed: %s', ...
                            exception.message));
                    end
                end
            end
            controler.model.currentSystemStatus = int16(0);
            controler.setOperationActive(false);
            if ~isempty(flushError)
                warning('Control:RecordingWrite', '%s', flushError.message);
                if ~isempty(controler.app) && isvalid(controler.app)
                    controler.app.updateErrorStatus(true, ...
                        sprintf('Recording write error: %s', ...
                        flushError.message));
                end
            end
        end

        function finishTest(controler, reason)
            if nargin < 2 || isempty(reason), reason = 'Completed'; end
            if controler.model.isRecording
                controler.finishRecording(reason);
                return;
            end
            if controler.model.filesOpen
                controler.model.finalizeRecording('aborted', char(reason));
            end
            controler.activePostProcessSettings.enabled = false;
            controler.model.currentSystemStatus = int16(0);
            controler.setOperationActive(false);
        end

        function settings = validatePostProcessSettings(~, settings)
            required = {'enabled', 'samplingPeriod', 'includePrePost'};
            for index = 1:numel(required)
                if ~isfield(settings, required{index})
                    error('Control:InvalidPostProcessSettings', ...
                        'Post-processing settings are missing %s.', ...
                        required{index});
                end
            end
            settings.enabled = logical(settings.enabled);
            settings.includePrePost = logical(settings.includePrePost);
            settings.samplingPeriod = double(settings.samplingPeriod);
            if ~isscalar(settings.enabled) || ...
                    ~isscalar(settings.includePrePost) || ...
                    ~isscalar(settings.samplingPeriod) || ...
                    ~isfinite(settings.samplingPeriod) || ...
                    settings.samplingPeriod < 0
                error('Control:InvalidPostProcessSettings', ...
                    ['Sampling period must be a finite non-negative ' ...
                    'number and checkbox values must be scalar.']);
            end
        end

        function scope = phaseScope(~, includePrePost)
            if includePrePost
                scope = 'complete-test';
            else
                scope = 'main-test';
            end
        end

        function outputFolder = manualOutputFolder(~, folderPath)
            stamp = char(datetime('now', ...
                'Format', 'yyyyMMdd_HHmmss_SSS'));
            outputFolder = fullfile(char(folderPath), ...
                ['processed_frames_manual_', stamp]);
            suffix = 1;
            while isfolder(outputFolder)
                outputFolder = fullfile(char(folderPath), ...
                    sprintf('processed_frames_manual_%s_%d', ...
                    stamp, suffix));
                suffix = suffix + 1;
            end
        end

        function handleRuntimeError(controler, exception, titleText)
            if strcmp(titleText, 'ADS read error') && ...
                    (~controler.plc.connected || controler.plc.disconnecting)
                return;
            end
            warning('Control:Runtime', '%s: %s', titleText, exception.message);
            if (strcmp(titleText, 'ADS read error') || ...
                    strcmp(titleText, 'Camera error') || ...
                    strcmp(titleText, 'Recording write error')) && ...
                    ~controler.abortInProgress
                controler.safeAbort([titleText, ': ', exception.message]);
            end
            if ~isempty(controler.app) && isvalid(controler.app)
                controler.app.updateErrorStatus(true, ...
                    sprintf('%s: %s', titleText, exception.message));
            end
        end

        function requireIdleOperation(controler, actionText)
            if controler.testRunning || controler.model.isRecording || ...
                    controler.plc.isWorking
                error('Control:OperationActive', ...
                    'Cannot %s while a test or motion is active.', actionText);
            end
        end

        function setOperationActive(controler, active)
            if ~isempty(controler.app) && isvalid(controler.app) && ...
                    ismethod(controler.app, 'setOperationActive')
                controler.app.setOperationActive(active);
            end
        end

        function finishAbortCleanup(controler)
            controler.abortInProgress = false;
            controler.setOperationActive(false);
        end

        function times = sampleTimes(controler, endTime, count)
            if count == 0
                times = NaT(1, 0);
                return;
            end
            times = endTime - seconds( ...
                (count - 1:-1:0) * controler.model.dt);
        end

        function message = acquisitionIntegrityError(controler)
            message = '';
            if ~controler.testRunning
                return;
            end
            [drops, restartDetected] = controler.recordingIntegrity();
            controler.model.recordingDroppedSamples = drops;
            controler.model.recordingRestartDetected = restartDetected;
            if restartDetected
                message = ['PLC streaming counter restarted during the ' ...
                    'operation. The recording is incomplete.'];
            elseif drops.X > 0 || drops.Y > 0
                message = sprintf( ...
                    ['PLC sample loss detected during the operation ' ...
                    '(X: %d, Y: %d).'], drops.X, drops.Y);
            end
        end

        function [drops, restartDetected] = recordingIntegrity(controler)
            currentDrops = controler.plc.droppedSamples;
            currentRestarts = controler.plc.restartCounts;
            drops = struct( ...
                'X', max(0, currentDrops.X - ...
                    controler.operationStartDrops.X), ...
                'Y', max(0, currentDrops.Y - ...
                    controler.operationStartDrops.Y));
            restartDetected = ...
                currentRestarts.X > controler.operationStartRestarts.X || ...
                currentRestarts.Y > controler.operationStartRestarts.Y;
        end
    end
end
