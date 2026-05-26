classdef Model < handle
    % In this class i am saving all actual values from realtime to
    %  vectors / matrixes

    properties
        % Tenzo
        dt = 0.01  % time interval of measurement
        fid = -1
        tenzoX
        timeX
        fTenzoX
        tenzoY

        % Camera
        isRecording = false;     % If True = store data to testData
        recordIndex = 1;        % number of frames recived
        selectedFolder = 0      % folder in witch fotos will save
        cameraTimeStamps
    end

    methods
        function model = Model()
        end

        %% save values
        function saveTenzoX(model,actualXval)
            try
                % Save data if recording is on
                if model.isRecording
                    % calculate time stamps
                    timeStamp = datetime('now');
                    timeVec = timeStamp - seconds(length(actualXval) -1:-1:0) * model.dt;

                    % save to file
                    tString = string(timeVec, 'HH:mm:ss.SSS');
                    % check id folder is open
                    if model.fid == -1
                        model.fid = fopen(fullfile( model.selectedFolder, 'live_tenzoX.csv'), 'a');
                    end
                    % if folder is open save data
                    if model.fid~= -1
                        dataLog = [tString(:), string(actualXval(:))]';
                        % Save to file
                        fprintf(model.fid,'%s,%s,\n', dataLog{:});
                    end
                end
                if ~model.isRecording && model.fid ~= -1
                    fclose(model.fid);
                end
            catch ME
                fprintf(2, 'Tenzo X save frame Error: %s\n', getReport(ME));
            end
        end

        function saveTenzoY(model,actualYval)
            % TODO later
            % model.tenzoY = sum(actualYval)/length(actualYval);
        end

        function saveCameraFrame(model, frame)
            try
                if model.isRecording
                    % get time
                    tStr = string(datetime('now'), 'HH:mm:ss.SSS');

                    % create file
                    filename = sprintf('/frame_%05d.tiff', model.recordIndex);
                    fullFileName = fullfile(model.selectedFolder, filename);

                    % save img
                    imwrite(frame, fullFileName, 'Description', tStr);

                    % add +1
                    model.recordIndex = model.recordIndex + 1;
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
            % fileY = fullfile(folderPath, 'live_tenzoY.csv');

            if ~exist(fileX, 'file') %|| ~exist(fileY, 'file')
                error('Could not find live_tenzoX.csv or live_tenzoY.csv in the specified folder.');
            end

            % Read CSV files as MATLAB tables
            optsX = detectImportOptions(fileX);
            optsX.VariableNames = {'Timestamp', 'ValueX'};
            % Force MATLAB to treat the timestamp column as a datetime object
            optsX.VariableTypes{1} = 'datetime';
            optsX.VariableOptions(1).InputFormat = 'HH:mm:ss.SSS';
            dataX = readtable(fileX, optsX);

            % optsY = detectImportOptions(fileY);
            % optsY.VariableNames = {'Timestamp', 'ValueY'};
            % optsY.VariableTypes{1} = 'datetime';
            % optsY.VariableOptions(1).InputFormat = 'HH:mm:ss.SSS';
            % dataY = readtable(fileY, optsY);

            disp('Tenzo logs loaded successfully.');

            %% 2. Find and Loop through all the TIFF Images
            % Get a list of all tiff files matching your frame naming pattern
            tiffFiles = dir(fullfile(folderPath, 'frame_*.tiff'));
            numFrames = length(tiffFiles);

            if numFrames == 0
                error('No tiff frames found in the specified folder.');
            end

            disp(['Found ', num2size(numFrames), ' frames to process. Synchronizing...']);

            % Loop through every single frame
            for i = 1:numFrames
                % Build the full file path for the current frame
                filename = tiffFiles(i).name;
                fullFileName = fullfile(folderPath, filename);

                %% 3. Extract the hidden Camera Timestamp from TIFF Metadata
                info = imfinfo(fullFileName);

                if ~isfield(info, 'ImageDescription') || isempty(info.ImageDescription)
                    warning(['Frame ', filename, ' is missing its metadata timestamp. Skipping.']);
                    continue;
                end

                % Read string and parse it back
                camTimeStr = info.ImageDescription;
                cameraTime = datetime(camTimeStr, 'InputFormat', 'HH:mm:ss.SSS');

                %% 4. Time Synchronization: Find the closest Tenzo measurements
                % Calculate the absolute time difference between this frame and ALL Tenzo X points
                timeDiffX = abs(dataX.Timestamp - cameraTime);
                [~ , idxX] = min(timeDiffX); % min returns the lowest difference and its array index

                % Calculate the absolute time difference for Tenzo Y
                % timeDiffY = abs(dataY.Timestamp - cameraTime);
                % [minDiffY, idxY] = min(timeDiffY);

                % Extract the perfectly matched physical values
                matchedX = dataX.ValueX(idxX);
                matchedY = 0; % dataY.ValueY(idxY);

                %% 5. Process and Overwrite the Image
                % Now we read the actual image pixels since we need to write on them
                imgFrame = imread(fullFileName);

                % Prepare your display texts
                txtOverlay = sprintf('X: %.5f | Y: %.5f', matchedX, matchedY);

                % Combine original camera timestamp + values into a permanent Description text
                newTxtDesc = sprintf('TimeStamp: %s | X: %.5f | Y: %.5f', camTimeStr, matchedX, matchedY);

                % Burn the text directly into the image pixels
                annotatedFrame = insertText(imgFrame, [20 20], txtOverlay, ...
                    'FontSize', 18, ...
                    'TextColor', 'white', ...
                    'BoxOpacity', 0.5); % Adds a clean semi-transparent background box behind text

                % Save it back to disk, overwriting the raw file with the finalized synced version
                imwrite(annotatedFrame, fullFileName, 'Description', newTxtDesc);

                % Print progress every 50 frames
                if mod(i, 50) == 0
                    fprintf('Processed %d / %d frames...\n', i, numFrames);
                end
            end

            disp('--- Post-Processing Complete! All data is perfectly synced. ---');
        end
    end
end
