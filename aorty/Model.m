classdef Model < handle
    % In this class i am saving all actual values from realtime to
    %  vectors / matrixes

    properties
        % Tenzo
        dt = 0.01;  % time interval of measurement

        % Camera
        isRecording = false;     % If True = store data to testData
        recordIndex = 1;        % number of frames recived
        selectedFolder = 0;      % folder in witch fotos will save
        cameraTimeStamps

        % File mamagement
        tenzoxFid, tenzoyFid = -1;
        untaredTenzoxFid, untaredTenzoyFid = -1;
        posxFid, posyFid = -1;
        camBinFid = -1;
        timestampsFid = -1;
        filesOpen = false;
        recordingStatus = 'idle';
        recordingReason = '';
        cameraFrameWidth = 0; % To store the width of the frames
        cameraFrameHeight = 0; % To store the height of the frames

    end

    methods
        % Model handles this operation.
        function model = Model()
        end

        %% File management
        function openFilesRec(model)
            if model.isRecording && ~model.filesOpen
                fids = [fopen(fullfile(model.selectedFolder, 'live_tenzoX.csv'), 'w'), ...
                    fopen(fullfile(model.selectedFolder, 'live_tenzoY.csv'), 'w'), ...
                    fopen(fullfile(model.selectedFolder, 'live_tenzoX_untared.csv'), 'w'), ...
                    fopen(fullfile(model.selectedFolder, 'live_tenzoY_untared.csv'), 'w'), ...
                    fopen(fullfile(model.selectedFolder, 'live_positionX.csv'), 'w'), ...
                    fopen(fullfile(model.selectedFolder, 'live_positionY.csv'), 'w'), ...
                    fopen(fullfile(model.selectedFolder, 'cam.bin'), 'wb'), ...
                    fopen(fullfile(model.selectedFolder, 'camTimestamps.csv'), 'w')];
                if any(fids == -1)
                    for fid = fids(fids ~= -1)
                        fclose(fid);
                    end
                    error('Model:RecordingOpenFailed', ...
                        'Could not open one or more recording files in %s.', model.selectedFolder);
                end
                model.tenzoxFid = fids(1);
                model.tenzoyFid = fids(2);
                model.untaredTenzoxFid = fids(3);
                model.untaredTenzoyFid = fids(4);
                model.posxFid = fids(5);
                model.posyFid = fids(6);
                model.camBinFid = fids(7);
                model.timestampsFid = fids(8);

                % Open camera_info.txt and save dimensions
                infoFid = fopen(fullfile(model.selectedFolder, 'camera_info.txt'), 'w');
                if infoFid ~= -1
                    fprintf(infoFid, 'Width: %d\n', model.cameraFrameWidth);
                    fprintf(infoFid, 'Height: %d\n', model.cameraFrameHeight);
                    fclose(infoFid);
                else
                    model.isRecording = false;
                    model.closeFilesRec();
                    error('Model:RecordingOpenFailed', ...
                        'Could not open camera_info.txt in %s.', model.selectedFolder);
                end
                model.isRecording = true;
                model.filesOpen = true;
                model.recordingStatus = 'recording';
                model.recordingReason = '';
            end
        end

        % closeFilesRec handles this operation.
        function closeFilesRec(model)
            if ~model.isRecording && model.filesOpen
                if model.tenzoxFid ~= -1, fclose(model.tenzoxFid); end
                if model.tenzoyFid ~= -1, fclose(model.tenzoyFid); end
                if model.untaredTenzoxFid ~= -1, fclose(model.untaredTenzoxFid); end
                if model.untaredTenzoyFid ~= -1, fclose(model.untaredTenzoyFid); end
                if model.posxFid ~= -1, fclose(model.posxFid); end
                if model.posyFid ~= -1, fclose(model.posyFid); end
                if model.camBinFid ~= -1, fclose(model.camBinFid); end
                if model.timestampsFid ~= -1, fclose(model.timestampsFid); end

                model.tenzoxFid = -1;
                model.tenzoyFid = -1;
                model.untaredTenzoxFid = -1;
                model.untaredTenzoyFid = -1;
                model.posxFid = -1;
                model.posyFid = -1;
                model.camBinFid = -1;
                model.timestampsFid = -1;
                model.filesOpen = false;
            end
        end

        % writeRecordingStatus handles this operation.
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
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
            fprintf(fid, 'Status: %s\nReason: %s\n', ...
                model.recordingStatus, model.recordingReason);
        end

        %% save values
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
            timeStrings = string(timeVec, 'HH:mm:ss.SSS');
            if strcmpi(axisName, 'X')
                forceFid = model.tenzoxFid;
                untaredForceFid = model.untaredTenzoxFid;
                positionFid = model.posxFid;
            else
                forceFid = model.tenzoyFid;
                untaredForceFid = model.untaredTenzoyFid;
                positionFid = model.posyFid;
            end
            forceLog = [timeStrings(:), string(forceValues(:))]';
            untaredForceLog = [timeStrings(:), string(untaredForceValues(:))]';
            positionLog = [timeStrings(:), string(positionValues(:))]';
            fprintf(forceFid, '%s,%s,\n', forceLog{:});
            fprintf(untaredForceFid, '%s,%s,\n', untaredForceLog{:});
            fprintf(positionFid, '%s,%s,\n', positionLog{:});
        end

        % saveTenzoX handles this operation.
        function saveTenzoX(model,actualXval)
            try
                % Save data if recording is on
                if model.isRecording
                    % calculate time stamps
                    timeStamp = datetime('now');
                    timeVec = timeStamp - seconds(length(actualXval) -1:-1:0) * model.dt;

                    % save
                    tString = string(timeVec, 'HH:mm:ss.SSS');
                    dataLog = [tString(:), string(actualXval(:))]';
                    fprintf(model.tenzoxFid,'%s,%s,\n', dataLog{:});
                end
            catch ME
                fprintf(2, 'Tenzo X save frame Error: %s\n', getReport(ME));
            end
        end

        % saveTenzoY handles this operation.
        function saveTenzoY(model,actualYval)
            try
                % Save data if recording is on
                if model.isRecording
                    % calculate time stamps
                    timeStamp = datetime('now');
                    timeVec = timeStamp - seconds(length(actualYval) -1:-1:0) * model.dt;

                    % save
                    tString = string(timeVec, 'HH:mm:ss.SSS');
                    dataLog = [tString(:), string(actualYval(:))]';
                    fprintf(model.tenzoyFid,'%s,%s,\n', dataLog{:});
                end
            catch ME
                fprintf(2, 'Tenzo Y save frame Error: %s\n', getReport(ME));
            end
        end

        % saveCameraFrame handles this operation.
        function saveCameraFrame(model, frame, timeStamp)
            try
                if model.isRecording
                    % save timeStamp
                    tString = string(timeStamp, 'HH:mm:ss.SSS');
                    fprintf(model.timestampsFid,'%d,%s,\n',model.recordIndex, tString);
                    model.recordIndex = model.recordIndex + 1;

                    % save img
                    fwrite(model.camBinFid, frame, 'uint8');
                end
            catch ME
                fprintf(2, 'Camera save frame Error: %s\n', getReport(ME));
            end
        end

        % Post-process recorded data through the dedicated processor.
        function PostProcessData(~, folderPath)
            PostProcessor.processData(folderPath);
        end

    end
end
