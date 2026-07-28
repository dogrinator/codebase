classdef Model < handle
    %MODEL Owns recording state and writes synchronized acquisition files.

    properties
        % Tenzo
        dt = 0.01;  % time interval of measurement

        % Camera
        isRecording = false;     % If True = store data to testData
        recordIndex = 1;        % number of frames recived
        selectedFolder = 0;      % folder in witch fotos will save
        fileIds = struct( ...
            'forceX', -1, 'forceY', -1, ...
            'untaredForceX', -1, 'untaredForceY', -1, ...
            'positionX', -1, 'positionY', -1, ...
            'cameraBinary', -1, 'cameraTimestamps', -1)
        filesOpen = false;
        recordingStatus = 'idle';
        recordingReason = '';
        currentTestPhase = uint8(0);
        cameraFrameWidth = 0; % To store the width of the frames
        cameraFrameHeight = 0; % To store the height of the frames

    end

    methods
        %% Recording file lifecycle
        function openFilesRec(model)
            if model.isRecording && ~model.filesOpen
                targetFiles = model.recordingFileNames();
                existing = targetFiles(cellfun(@(name) ...
                    isfile(fullfile(model.selectedFolder, name)), targetFiles));
                if ~isempty(existing)
                    error('Model:RecordingFilesExist', ...
                        ['The selected folder already contains recording ' ...
                        'data (%s). Choose a new or empty folder.'], ...
                        strjoin(existing, ', '));
                end
                specs = Model.recordingFileSpecs();
                fids = -ones(1, numel(specs));
                for index = 1:numel(specs)
                    fids(index) = fopen(fullfile(model.selectedFolder, ...
                        specs(index).name), specs(index).mode);
                end
                if any(fids == -1)
                    for fid = fids(fids ~= -1)
                        fclose(fid);
                    end
                    error('Model:RecordingOpenFailed', ...
                        'Could not open one or more recording files in %s.', model.selectedFolder);
                end
                for index = 1:numel(specs)
                    model.fileIds.(specs(index).field) = fids(index);
                end
                model.filesOpen = true;

                try
                    infoFid = fopen(fullfile( ...
                        model.selectedFolder, 'camera_info.txt'), 'w');
                    if infoFid == -1
                        error('Model:RecordingOpenFailed', ...
                            'Could not open camera_info.txt in %s.', ...
                            model.selectedFolder);
                    end
                    cleanup = onCleanup(@() fclose(infoFid));
                    countWidth = fprintf(infoFid, 'Width: %d\n', ...
                        model.cameraFrameWidth);
                    countHeight = fprintf(infoFid, 'Height: %d\n', ...
                        model.cameraFrameHeight);
                    if countWidth < 0 || countHeight < 0
                        error('Model:RecordingWriteFailed', ...
                            'Could not write camera_info.txt.');
                    end
                    clear cleanup;
                catch exception
                    model.isRecording = false;
                    model.closeFilesRec();
                    rethrow(exception);
                end
                model.isRecording = true;
                model.recordingStatus = 'recording';
                model.recordingReason = '';
            end
        end

        function closeFilesRec(model)
            if model.filesOpen
                fields = fieldnames(model.fileIds);
                fids = cellfun(@(name) model.fileIds.(name), fields);
                % Mark ownership released before closing so a close error
                % cannot leave the model in a permanently half-open state.
                for index = 1:numel(fields)
                    model.fileIds.(fields{index}) = -1;
                end
                model.filesOpen = false;
                for fid = reshape(fids(fids ~= -1), 1, [])
                    try
                        fclose(fid);
                    catch exception
                        warning('Model:RecordingCloseFailed', ...
                            'Could not close a recording file: %s', ...
                            exception.message);
                    end
                end
            end
        end

        function writeRecordingStatus(model)
            if isempty(model.selectedFolder) || isequal(model.selectedFolder, 0) || ...
                    ~ischar(model.selectedFolder) && ~isstring(model.selectedFolder)
                return;
            end
            filename = fullfile(model.selectedFolder, 'recording_status.txt');
            fid = fopen(filename, 'w');
            if fid == -1
                warning('Model:StatusWriteFailed', 'Could not write %s.', filename);
                return;
            end
            cleanup = onCleanup(@() fclose(fid)); 
            fprintf(fid, 'Status: %s\nReason: %s\n', ...
                model.recordingStatus, model.recordingReason);
        end

        %% Acquisition writes
        function saveAxisSamples(model, axisName, forceValues, untaredForceValues, positionValues)
            if ~model.isRecording
                return;
            end
            count = min([numel(forceValues), numel(untaredForceValues), numel(positionValues)]);
            if count == 0
                return;
            end
            forceValues = forceValues(end-count+1:end);
            untaredForceValues = untaredForceValues(end-count+1:end);
            positionValues = positionValues(end-count+1:end);
            timeStamp = datetime('now');
            timeVec = timeStamp - seconds(count-1:-1:0) * model.dt;
            timeStrings = string(timeVec, 'yyyy-MM-dd HH:mm:ss.SSS');
            if strcmpi(axisName, 'X')
                forceFid = model.fileIds.forceX;
                untaredForceFid = model.fileIds.untaredForceX;
                positionFid = model.fileIds.positionX;
            else
                forceFid = model.fileIds.forceY;
                untaredForceFid = model.fileIds.untaredForceY;
                positionFid = model.fileIds.positionY;
            end
            forceLog = [timeStrings(:), string(forceValues(:))]';
            untaredForceLog = [timeStrings(:), string(untaredForceValues(:))]';
            positionLog = [timeStrings(:), string(positionValues(:))]';
            written = [ ...
                fprintf(forceFid, '%s,%s,\n', forceLog{:}), ...
                fprintf(untaredForceFid, '%s,%s,\n', untaredForceLog{:}), ...
                fprintf(positionFid, '%s,%s,\n', positionLog{:})];
            if any(written < 0)
                error('Model:RecordingWriteFailed', ...
                    'Could not write %s-axis sensor samples.', upper(axisName));
            end
        end

        function saveCameraFrame(model, frame, timeStamp)
            if model.isRecording
                % Save a complete wall-clock timestamp so recordings remain
                % chronological across midnight and on later processing days.
                tString = string(timeStamp, 'yyyy-MM-dd HH:mm:ss.SSS');
                timestampCount = fprintf( ...
                    model.fileIds.cameraTimestamps, '%d,%s,%u,\n', ...
                    model.recordIndex, tString, model.currentTestPhase);
                frameCount = fwrite( ...
                    model.fileIds.cameraBinary, frame, 'uint8');
                if timestampCount < 0 || frameCount ~= numel(frame)
                    error('Model:RecordingWriteFailed', ...
                        'Could not write camera frame %d.', model.recordIndex);
                end
                model.recordIndex = model.recordIndex + 1;
            end
        end

        function updateTestPhase(model, statuses, activeAxes)
            if isempty(activeAxes)
                model.currentTestPhase = uint8(0);
                return;
            end
            axis = activeAxes{1};
            if isempty(statuses) || ~isfield(statuses, axis) || ...
                    ~isfield(statuses.(axis), 'testPhase')
                model.currentTestPhase = uint8(0);
                return;
            end
            model.currentTestPhase = uint8(statuses.(axis).testPhase);
        end

    end

    methods (Static, Access = private)
        function names = recordingFileNames()
            specs = Model.recordingFileSpecs();
            names = [{specs.name}, ...
                {'camera_info.txt', 'recording_status.txt'}];
        end

        function specs = recordingFileSpecs()
            specs = struct( ...
                'field', {'forceX', 'forceY', ...
                    'untaredForceX', 'untaredForceY', ...
                    'positionX', 'positionY', ...
                    'cameraBinary', 'cameraTimestamps'}, ...
                'name', {'live_tenzoX.csv', 'live_tenzoY.csv', ...
                    'live_tenzoX_untared.csv', ...
                    'live_tenzoY_untared.csv', ...
                    'live_positionX.csv', 'live_positionY.csv', ...
                    'cam.bin', 'camTimestamps.csv'}, ...
                'mode', {'w', 'w', 'w', 'w', 'w', 'w', 'wb', 'w'});
        end
    end
end
