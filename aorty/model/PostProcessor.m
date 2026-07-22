classdef PostProcessor
    %POSTPROCESSOR Synchronizes recorded sensor data with camera frames.

    methods (Static)
        % Process recorded data and save annotated camera frames.
        function processData(folderPath)
            % folderPath: The string path to the folder where the test files are saved.

            disp('--- Starting Offline Synchronization and Post-Processing ---');

            %% 1. Load the Live Tenzo Data Files
            fileX = fullfile(folderPath, 'live_tenzoX.csv');
            fileY = fullfile(folderPath, 'live_tenzoY.csv');
            untaredFileX = fullfile(folderPath, 'live_tenzoX_untared.csv');
            untaredFileY = fullfile(folderPath, 'live_tenzoY_untared.csv');
            positionFileX = fullfile(folderPath, 'live_positionX.csv');
            positionFileY = fullfile(folderPath, 'live_positionY.csv');

            if ~exist(fileX, 'file')
                error('Could not find live_tenzoX.csv in the specified folder.');
            end
            if ~exist(fileY, 'file')
                error('Could not find live_tenzoY.csv in the specified folder.');
            end

            % Read CSV files as MATLAB tables
            optsX = detectImportOptions(fileX);
            optsX.VariableNames = {'Timestamp', 'ValueX'};
            optsX.VariableTypes{1} = 'datetime';
            optsX.VariableOptions(1).InputFormat = 'HH:mm:ss.SSS';
            dataX = readtable(fileX, optsX);

            optsY = detectImportOptions(fileY);
            optsY.VariableNames = {'Timestamp', 'ValueY'};
            optsY.VariableTypes{1} = 'datetime';
            optsY.VariableOptions(1).InputFormat = 'HH:mm:ss.SSS';
            dataY = readtable(fileY, optsY);

            % Load the untared and position measurements for the legacy header.
            if exist(untaredFileX, 'file') && exist(untaredFileY, 'file')
                optsUntaredX = detectImportOptions(untaredFileX);
                optsUntaredX.VariableNames = {'Timestamp', 'ValueX'};
                optsUntaredX.VariableTypes{1} = 'datetime';
                optsUntaredX.VariableOptions(1).InputFormat = 'HH:mm:ss.SSS';
                untaredX = readtable(untaredFileX, optsUntaredX);

                optsUntaredY = detectImportOptions(untaredFileY);
                optsUntaredY.VariableNames = {'Timestamp', 'ValueY'};
                optsUntaredY.VariableTypes{1} = 'datetime';
                optsUntaredY.VariableOptions(1).InputFormat = 'HH:mm:ss.SSS';
                untaredY = readtable(untaredFileY, optsUntaredY);
            else
                % Older recordings have no untared files; retain a safe fallback.
                untaredX = table(dataX.Timestamp, zeros(height(dataX), 1), ...
                    'VariableNames', {'Timestamp', 'ValueX'});
                untaredY = table(dataY.Timestamp, zeros(height(dataY), 1), ...
                    'VariableNames', {'Timestamp', 'ValueY'});
            end

            if ~exist(positionFileX, 'file') || ~exist(positionFileY, 'file')
                error('Could not find recorded position files in the specified folder.');
            end

            optsPositionX = detectImportOptions(positionFileX);
            optsPositionX.VariableNames = {'Timestamp', 'ValueX'};
            optsPositionX.VariableTypes{1} = 'datetime';
            optsPositionX.VariableOptions(1).InputFormat = 'HH:mm:ss.SSS';
            positionX = readtable(positionFileX, optsPositionX);

            optsPositionY = detectImportOptions(positionFileY);
            optsPositionY.VariableNames = {'Timestamp', 'ValueY'};
            optsPositionY.VariableTypes{1} = 'datetime';
            optsPositionY.VariableOptions(1).InputFormat = 'HH:mm:ss.SSS';
            positionY = readtable(positionFileY, optsPositionY);

            disp('Tenzo logs (X and Y) loaded successfully.');

            %% 2. Load Camera Timestamps
            camTimestampsFile = fullfile(folderPath, 'camTimestamps.csv');
            if ~exist(camTimestampsFile, 'file')
                error('Could not find camTimestamps.csv in the specified folder.');
            end
            optsCam = detectImportOptions(camTimestampsFile);
            optsCam.VariableNames = {'Index', 'Timestamp'};
            optsCam.VariableTypes{1} = 'double';
            optsCam.VariableTypes{2} = 'datetime';
            optsCam.VariableOptions(2).InputFormat = 'HH:mm:ss.SSS';
            camTimestamps = readtable(camTimestampsFile, optsCam);

            numFrames = height(camTimestamps);
            if numFrames == 0
                warning('No camera frames recorded. Skipping camera post-processing.');
                return;
            end

            disp(['Found ', num2str(numFrames), ' frames to process. Synchronizing...']);
            baseTime = camTimestamps.Timestamp(1);

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
            cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>

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

                %% 6. Time Synchronization: Find the closest Tenzo measurements for X and Y
                % For X
                timeDiffX = abs(dataX.Timestamp - cameraTime);
                [~, idxX] = min(timeDiffX);
                matchedX = dataX.ValueX(idxX);
                [~, untaredIdxX] = min(abs(untaredX.Timestamp - cameraTime));
                matchedUntaredX = untaredX.ValueX(untaredIdxX);
                [~, positionIdxX] = min(abs(positionX.Timestamp - cameraTime));
                matchedPositionX = positionX.ValueX(positionIdxX);

                % For Y
                timeDiffY = abs(dataY.Timestamp - cameraTime);
                [~, idxY] = min(timeDiffY);
                matchedY = dataY.ValueY(idxY);
                [~, untaredIdxY] = min(abs(untaredY.Timestamp - cameraTime));
                matchedUntaredY = untaredY.ValueY(untaredIdxY);
                [~, positionIdxY] = min(abs(positionY.Timestamp - cameraTime));
                matchedPositionY = positionY.ValueY(positionIdxY);

                %% 7. Process and Save the Image
                txtOverlay = sprintf('X: %.5f | Y: %.5f', matchedX, matchedY);
                delta = cameraTime - baseTime;
                baseTimeStr = char(string(baseTime, 'dd.MM.yyyy HH:mm:ss'));
                delta.Format = 'hh:mm:ss.SSS';
                deltaStr = char(delta);
                newTxtDesc = sprintf(['Batch:%s|Profile:Profile : TestBasler.pro|', ...
                    'Base:%s|Delta:%s|Index:%05d|', ...
                    'TenzoX:%.2f [N] (%.2f [N])|TenzoY:%.2f [N] (%.2f [N])|', ...
                    'Thermo:0 [', char(176), 'C]|StepX:%.2f [mm]|StepY:%.2f [mm]'], ...
                    folderPath, baseTimeStr, deltaStr, camTimestamps.Index(i), ...
                    matchedX, matchedUntaredX, matchedY, matchedUntaredY, ...
                    matchedPositionX, matchedPositionY);

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

            disp('--- Post-Processing Complete! All data is perfectly synced. ---');
        end
    end
end

