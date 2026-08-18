classdef RecordingSession < handle
    %RECORDINGSESSION Coordinates recording state and synchronized writes.

    properties
        % Recording lifecycle and acquisition state
        isRecording = false;     % Whether incoming samples are recorded
        recordIndex = 1;         % Next recorded camera-frame index
        selectedFolder = 0;      % Current recording output folder
        filesOpen = false;
        recordingStatus = 'idle';
        recordingReason = '';
        currentSystemStatus = int16(0);
        recordingRestartDetected = false

        % Recording integrity metadata
        recordingDroppedSamples = struct('X', 0, 'Y', 0)

        % Camera dimensions used by the fallback recording header
        cameraFrameWidth = 0;
        cameraFrameHeight = 0;
    end

    properties (Access = private)
        recordingStore = []
    end

    methods
        %% Recording file lifecycle
        function openFilesRec(recordingSession, header)
            if recordingSession.filesOpen
                return;
            end
            if nargin < 2 || isempty(header)
                header = recordingSession.defaultRecordingHeader();
            end
            recordingSession.recordingStore = RecordingStore( ...
                recordingSession.selectedFolder, header);
            recordingSession.filesOpen = true;
            recordingSession.recordingStatus = 'recording';
            recordingSession.recordingReason = '';
        end


        function finalizeRecording(recordingSession, status, reason)
            recordingSession.recordingStatus = lower(char(status));
            recordingSession.recordingReason = char(reason);
            if ~recordingSession.filesOpen || isempty(recordingSession.recordingStore)
                return;
            end
            store = recordingSession.recordingStore;
            recordingSession.filesOpen = false;
            recordingSession.recordingStore = [];
            try
                integrity = struct( ...
                    'droppedSamples', recordingSession.recordingDroppedSamples, ...
                    'restartDetected', recordingSession.recordingRestartDetected);
                store.finalize(recordingSession.recordingStatus, ...
                    recordingSession.recordingReason, integrity);
            catch exception
                try store.close(); catch, end
                rethrow(exception);
            end
        end

        %% Acquisition writes
        function saveAxisSamples(recordingSession, axisName, timestamps, forceValues, untaredForceValues, positionValues)
            if ~recordingSession.isRecording
                return;
            end
            recordingSession.recordingStore.appendAxis(axisName, timestamps, ...
                forceValues, untaredForceValues, positionValues);
        end

        function saveCameraFrame(recordingSession, frame, timeStamp)
            if recordingSession.isRecording
                recordingSession.recordingStore.appendFrame( ...
                    frame, timeStamp, recordingSession.recordIndex, ...
                    recordingSession.currentSystemStatus);
                recordingSession.recordIndex = recordingSession.recordIndex + 1;
            end
        end

        function updateSystemStatus(recordingSession, statuses, activeAxes)
            if isempty(activeAxes)
                recordingSession.currentSystemStatus = int16(0);
                return;
            end
            axis = activeAxes{1};
            if isempty(statuses) || ~isfield(statuses, axis) || ...
                    ~isfield(statuses.(axis), 'systemStatus')
                recordingSession.currentSystemStatus = int16(0);
                return;
            end
            recordingSession.currentSystemStatus = ...
                int16(statuses.(axis).systemStatus);
        end

    end

    methods (Access = private)
        function header = defaultRecordingHeader(recordingSession)
            camera = struct( ...
                'connected', false, ...
                'width', double(recordingSession.cameraFrameWidth), ...
                'height', double(recordingSession.cameraFrameHeight), ...
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
                'plcInterval', AppInfo.PLC_SAMPLE_PERIOD_SECONDS, ...
                'statusResolutionSeconds', ...
                AppInfo.PLC_READ_PERIOD_SECONDS, ...
                'camera', camera, ...
                'plc', struct('X', emptyPlc, 'Y', emptyPlc), ...
                'test', test);
        end
    end
end
