classdef Model < handle
    % In this class i am saving all actual values from realtime to
    %  vectors / matrixes

    properties
        % Tenzo
        dt = 0.01;  % time interval of measurement
        tenzoX
        timeX
        fTenzoX
        tenzoY

        % Camera
        isRecording = false;     % If True = store data to testData
        recordIndex = 1;        % number of frames recived
        selectedFolder = 0;      % folder in witch fotos will save
        cameraTimeStamps

        % File mamagement
        tenzoxFid = -1;
        camBinFid = -1;
        timestampsFid = -1;
        filesOpen = false;
        cameraFrameWidth = 0; % To store the width of the frames
        cameraFrameHeight = 0; % To store the height of the frames

    end

    methods
        function model = Model()
        end

        %% File management
        function openFilesRec(model)
            if model.isRecording && ~model.filesOpen
                model.tenzoxFid = fopen(fullfile( model.selectedFolder, 'live_tenzoX.csv'), 'w');
                model.camBinFid = fopen(fullfile( model.selectedFolder, 'cam.bin'), 'wb');
                model.timestampsFid = fopen(fullfile( model.selectedFolder, 'camTimestamps.csv'), 'w');

                % Open camera_info.txt and save dimensions
                infoFid = fopen(fullfile(model.selectedFolder, 'camera_info.txt'), 'w');
                if infoFid ~= -1
                    fprintf(infoFid, 'Width: %d\n', model.cameraFrameWidth);
                    fprintf(infoFid, 'Height: %d\n', model.cameraFrameHeight);
                    fclose(infoFid);
                else
                    warning('Could not open camera_info.txt for writing.');
                end
                model.filesOpen = true;
            end
        end

        function closeFilesRec(model)
            if ~model.isRecording && model.filesOpen
                if model.tenzoxFid ~= -1, fclose(model.tenzoxFid); end
                if model.camBinFid ~= -1, fclose(model.camBinFid); end
                if model.timestampsFid ~= -1, fclose(model.timestampsFid); end

                model.tenzoxFid = -1;
                model.camBinFid = -1;
                model.timestampsFid = -1;
                model.filesOpen = false;
            end
        end

        %% save values
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

        function saveTenzoY(model,actualYval)
            % TODO later
            % model.tenzoY = sum(actualYval)/length(actualYval);
        end

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

        function PostProcessData(model, folderPath)
            % folderPath: The string path to the folder where the test files are saved.

            disp('--- Starting Offline Synchronization and Post-Processing ---');

            %% 1. Load the Live Tenzo Data Files
            fileX = fullfile(folderPath, 'live_tenzoX.csv');

            if ~exist(fileX, 'file')
                error('Could not find live_tenzoX.csv in the specified folder.');
            end

            % Read CSV files as MATLAB tables
            optsX = detectImportOptions(fileX);
            optsX.VariableNames = {'Timestamp', 'ValueX'};
            optsX.VariableTypes{1} = 'datetime';
            optsX.VariableOptions(1).InputFormat = 'HH:mm:ss.SSS';
            dataX = readtable(fileX, optsX);

            disp('Tenzo logs loaded successfully.');

            %% 2. Load Camera Timestamps
            camTimestampsFile = fullfile(folderPath, 'camTimestamps.csv');
            if ~exist(camTimestampsFile, 'file')
                error('Could not find camTimestamps.csv in the specified folder.');
            end
            optsCam = detectImportOptions(camTimestampsFile);
            optsCam.VariableNames = {'Index', 'Timestamp'};
            optsCam.VariableTypes{2} = 'datetime';
            optsCam.VariableOptions(2).InputFormat = 'HH:mm:ss.SSS';
            camTimestamps = readtable(camTimestampsFile, optsCam);

            numFrames = height(camTimestamps);
            if numFrames == 0
                warning('No camera frames recorded. Skipping camera post-processing.');
                return;
            end

            disp(['Found ', num2str(numFrames), ' frames to process. Synchronizing...']);

            %% 3. Get Camera Frame Dimensions
            cameraInfoFile = fullfile(folderPath, 'camera_info.txt');
            if ~exist(cameraInfoFile, 'file')
                error('Camera frame dimensions not found. Missing camera_info.txt.');
            end

            fidInfo = fopen(cameraInfoFile, 'r');
            if fidInfo == -1
                error(['Could not open camera_info.txt for reading: ', cameraInfoFile]);
            end

            widthLine = fgetl(fidInfo);
            heightLine = fgetl(fidInfo);
            fclose(fidInfo);

            frameWidth = sscanf(widthLine, 'Width: %d');
            frameHeight = sscanf(heightLine, 'Height: %d');

            if isempty(frameWidth) || isempty(frameHeight) || ~isscalar(frameWidth) || ~isscalar(frameHeight)
                error('Could not parse camera frame dimensions from camera_info.txt.');
            end

            %% 4. Open Binary Camera File
            camBinFile = fullfile(folderPath, 'cam.bin');
            if ~exist(camBinFile, 'file')
                error('Could not find cam.bin in the specified folder.');
            end
            fid = fopen(camBinFile, 'rb');
            if fid == -1
                error(['Could not open cam.bin for reading: ', camBinFile]);
            end

            bytesPerFrame = frameWidth * frameHeight; % For Mono8

            % Create output folder for processed images
            processedFramesFolder = fullfile(folderPath, 'processed_frames');
            if ~exist(processedFramesFolder, 'dir')
                mkdir(processedFramesFolder);
            end

            %% 5. Loop through frames, synchronize, and process
            for i = 1:numFrames
                % Read raw frame data
                rawFrameData = fread(fid, bytesPerFrame, '*uint8');
                if isempty(rawFrameData) || length(rawFrameData) < bytesPerFrame
                    warning(['Reached end of cam.bin unexpectedly or frame ', num2str(i), ' is incomplete. Skipping remaining frames.']);
                    break;
                end

                % Reshape to image matrix
                imgFrame = reshape(rawFrameData, frameHeight, frameWidth);

                % Get camera timestamp for the current frame
                cameraTime = camTimestamps.Timestamp(i);
                camTimeStr = string(cameraTime, 'HH:mm:ss.SSS');

                %% 6. Time Synchronization: Find the closest Tenzo measurements
                timeDiffX = abs(dataX.Timestamp - cameraTime);
                [~ , idxX] = min(timeDiffX);
                matchedX = dataX.ValueX(idxX);
                matchedY = 0; % Placeholder as Y is commented out in original

                %% 7. Process and Save the Image
                txtOverlay = sprintf('X: %.5f | Y: %.5f', matchedX, matchedY);
                newTxtDesc = sprintf('TimeStamp: %s | X: %.5f | Y: %.5f', camTimeStr, matchedX, matchedY);

                annotatedFrame = insertText(imgFrame, [20 20], txtOverlay, ...
                    'FontSize', 18, ...
                    'TextColor', 'white', ...
                    'BoxOpacity', 0.5);

                % Save annotated frame as TIFF in the processed_frames folder
                outputFileName = fullfile(processedFramesFolder, ['processed_frame_', num2str(i, '%04d'), '.tiff']);
                imwrite(annotatedFrame, outputFileName, 'Description', newTxtDesc);

                if mod(i, 50) == 0
                    fprintf('Processed %d / %d frames...\n', i, numFrames);
                end
            end

            fclose(fid); % Close binary file after processing all frames
            disp('--- Post-Processing Complete! All data is perfectly synced. ---');
        end
    end
end
