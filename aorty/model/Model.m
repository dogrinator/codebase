classdef Model < handle
    %MODEL Owns recording state and writes synchronized acquisition files.

    properties
        % Tenzo
        dt = 0.01;  % time interval of measurement

        % Camera
        isRecording = false;     % If True = store data to testData
        recordIndex = 1;        % number of frames recived
        selectedFolder = 0;      % folder in witch fotos will save
        filesOpen = false;
        recordingStatus = 'idle';
        recordingReason = '';
        currentSystemStatus = int16(0);
        cameraFrameWidth = 0; % To store the width of the frames
        cameraFrameHeight = 0; % To store the height of the frames
        recordingDroppedSamples = struct('X', 0, 'Y', 0)
        recordingRestartDetected = false
        statusResolutionSeconds = AppInfo.PLC_READ_PERIOD_SECONDS

    end

    properties (Access = private)
        recordingStore = []
    end

    methods
        %% Recording file lifecycle
        function openFilesRec(model, header)
            if model.filesOpen
                return;
            end
            if nargin < 2 || isempty(header)
                header = model.defaultRecordingHeader();
            end
            model.recordingStore = RecordingStore( ...
                model.selectedFolder, header);
            model.filesOpen = true;
            model.recordingStatus = 'recording';
            model.recordingReason = '';
        end

        function closeFilesRec(model)
            if model.filesOpen
                model.filesOpen = false;
                store = model.recordingStore;
                model.recordingStore = [];
                try
                    store.close();
                catch exception
                    warning('Model:RecordingCloseFailed', ...
                        'Could not close the recording: %s', ...
                        exception.message);
                end
            end
        end

        function finalizeRecording(model, status, reason)
            model.recordingStatus = lower(char(status));
            model.recordingReason = char(reason);
            if ~model.filesOpen || isempty(model.recordingStore)
                return;
            end
            store = model.recordingStore;
            model.filesOpen = false;
            model.recordingStore = [];
            try
                integrity = struct( ...
                    'droppedSamples', model.recordingDroppedSamples, ...
                    'restartDetected', model.recordingRestartDetected);
                store.finalize(model.recordingStatus, ...
                    model.recordingReason, integrity);
            catch exception
                try store.close(); catch, end
                rethrow(exception);
            end
        end

        %% Acquisition writes
        function saveAxisSamples(model, axisName, timestamps, ...
                forceValues, untaredForceValues, positionValues)
            if ~model.isRecording
                return;
            end
            counts = [numel(timestamps), numel(forceValues), ...
                numel(untaredForceValues), numel(positionValues)];
            if any(counts ~= counts(1))
                error('Model:RecordingVectorLength', ...
                    ['%s-axis timestamps, force, untared force, and ' ...
                    'position vectors must have equal lengths.'], ...
                    upper(char(axisName)));
            end
            count = counts(1);
            if count == 0
                return;
            end
            model.recordingStore.appendAxis(axisName, timestamps, ...
                forceValues, untaredForceValues, positionValues);
        end

        function saveCameraFrame(model, frame, timeStamp)
            if model.isRecording
                model.recordingStore.appendFrame( ...
                    frame, timeStamp, model.recordIndex, ...
                    model.currentSystemStatus);
                model.recordIndex = model.recordIndex + 1;
            end
        end

        function updateSystemStatus(model, statuses, activeAxes)
            if isempty(activeAxes)
                model.currentSystemStatus = int16(0);
                return;
            end
            axis = activeAxes{1};
            if isempty(statuses) || ~isfield(statuses, axis) || ...
                    ~isfield(statuses.(axis), 'systemStatus')
                model.currentSystemStatus = int16(0);
                return;
            end
            model.currentSystemStatus = ...
                int16(statuses.(axis).systemStatus);
        end

    end

    methods (Access = private)
        function header = defaultRecordingHeader(model)
            camera = struct( ...
                'connected', false, ...
                'width', double(model.cameraFrameWidth), ...
                'height', double(model.cameraFrameHeight), ...
                'pixel_format', 'Mono8', ...
                'exposure_time', NaN, ...
                'gain', NaN, ...
                'configured_fps', NaN);
            emptyPlc = struct();
            test = struct( ...
                'test_kind', 'unspecified', ...
                'active_axes', '', ...
                'post_process_enabled', false, ...
                'post_process_sampling_period', 0, ...
                'post_process_include_pre_post', false, ...
                'commands', struct('X', [], 'Y', []));
            header = struct( ...
                'applicationVersion', AppInfo.VERSION, ...
                'interfaceVersion', ...
                    PlcAds.EXPECTED_INTERFACE_VERSION, ...
                'plcInterval', double(model.dt), ...
                'statusResolutionSeconds', ...
                    double(model.statusResolutionSeconds), ...
                'camera', camera, ...
                'plc', struct('X', emptyPlc, 'Y', emptyPlc), ...
                'test', test);
        end
    end
end
