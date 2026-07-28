classdef PostProcessor
    %POSTPROCESSOR Synchronizes recorded sensor data with camera frames.

    methods (Static)
        % Process recorded data and save annotated camera frames.
        function result = processData(folderPath, options)
            % folderPath: The string path to the folder where the test files are saved.
            if nargin < 2
                options = struct();
            end
            options = PostProcessor.normalizeOptions(folderPath, options);
            result = struct( ...
                'outputFolder', options.outputFolder, ...
                'exportedFrameCount', 0);

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

            dataX = PostProcessor.readMeasurementFile(fileX, 'ValueX');
            dataY = PostProcessor.readMeasurementFile(fileY, 'ValueY');

            % Load the untared and position measurements for the legacy header.
            if exist(untaredFileX, 'file') && exist(untaredFileY, 'file')
                untaredX = PostProcessor.readMeasurementFile( ...
                    untaredFileX, 'ValueX');
                untaredY = PostProcessor.readMeasurementFile( ...
                    untaredFileY, 'ValueY');
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

            positionX = PostProcessor.readMeasurementFile( ...
                positionFileX, 'ValueX');
            positionY = PostProcessor.readMeasurementFile( ...
                positionFileY, 'ValueY');

            disp('Tenzo logs (X and Y) loaded successfully.');

            %% 2. Load Camera Timestamps
            camTimestampsFile = fullfile(folderPath, 'camTimestamps.csv');
            if ~exist(camTimestampsFile, 'file')
                error('Could not find camTimestamps.csv in the specified folder.');
            end
            camTimestamps = PostProcessor.readCameraTimestamps( ...
                camTimestampsFile);

            numFrames = height(camTimestamps);
            if numFrames == 0
                warning('No camera frames recorded. Skipping camera post-processing.');
                return;
            end
            selectedRows = PostProcessor.selectFrameRows( ...
                camTimestamps, options.samplingPeriod, ...
                options.phaseScope);
            if isempty(selectedRows)
                error('PostProcessor:NoMatchingFrames', ...
                    'No recorded camera frames match the selected test phases.');
            end
            selectedMask = false(numFrames, 1);
            selectedMask(selectedRows) = true;

            fprintf('Found %d frame(s); exporting %d after filtering.\n', ...
                numFrames, numel(selectedRows));
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

            if isempty(frameWidth) || isempty(frameHeight) || ...
                    ~isscalar(frameWidth) || ~isscalar(frameHeight) || ...
                    ~isfinite(frameWidth) || ~isfinite(frameHeight) || ...
                    frameWidth < 1 || frameHeight < 1 || ...
                    frameWidth ~= fix(frameWidth) || ...
                    frameHeight ~= fix(frameHeight)
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
            cleanup = onCleanup(@() fclose(fid));

            bytesPerFrame = frameWidth * frameHeight; % For Mono8

            % Create output folder for processed images
            processedFramesFolder = options.outputFolder;
            existingFrames = dir(fullfile( ...
                processedFramesFolder, 'processed_frame_*.tiff'));
            if ~isempty(existingFrames)
                error('PostProcessor:OutputNotEmpty', ...
                    ['The TIFF output already contains generated frames. ' ...
                    'Choose a new output folder.']);
            end
            if ~exist(processedFramesFolder, 'dir')
                mkdir(processedFramesFolder);
            end

            binaryInfo = dir(camBinFile);
            requiredBytes = numFrames * bytesPerFrame;
            if binaryInfo.bytes < requiredBytes
                error('PostProcessor:IncompleteCameraData', ...
                    ['cam.bin contains %d bytes, but %d bytes are required ' ...
                    'for the recorded timestamps.'], ...
                    binaryInfo.bytes, requiredBytes);
            end

            %% 5. Loop through frames, synchronize, and process
            outputIndex = 0;
            for i = 1:numFrames
                % Read raw frame data
                rawFrameData = fread(fid, bytesPerFrame, '*uint8');
                if isempty(rawFrameData) || length(rawFrameData) < bytesPerFrame
                    warning(['Reached end of cam.bin unexpectedly or frame ', num2str(i), ' is incomplete. Skipping remaining frames.']);
                    break;
                end
                if ~selectedMask(i)
                    continue;
                end
                outputIndex = outputIndex + 1;

                % Reshape to image matrix
                imgFrame = reshape(rawFrameData, frameHeight, frameWidth);

                % Get camera timestamp for the current frame
                cameraTime = camTimestamps.Timestamp(i);
                %% 6. Match the nearest sensor values
                matchedX = PostProcessor.nearestValue( ...
                    dataX, cameraTime, 'ValueX');
                matchedUntaredX = PostProcessor.nearestValue( ...
                    untaredX, cameraTime, 'ValueX');
                matchedPositionX = PostProcessor.nearestValue( ...
                    positionX, cameraTime, 'ValueX');
                matchedY = PostProcessor.nearestValue( ...
                    dataY, cameraTime, 'ValueY');
                matchedUntaredY = PostProcessor.nearestValue( ...
                    untaredY, cameraTime, 'ValueY');
                matchedPositionY = PostProcessor.nearestValue( ...
                    positionY, cameraTime, 'ValueY');

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
                outputFileName = fullfile(processedFramesFolder, ...
                    ['processed_frame_', num2str(outputIndex, '%04d'), ...
                    '.tiff']);
                imwrite(annotatedFrame, outputFileName, 'Description', newTxtDesc);

                if mod(outputIndex, 50) == 0
                    fprintf('Processed %d / %d frames...\n', ...
                        outputIndex, numel(selectedRows));
                    drawnow limitrate;
                end
            end

            result.exportedFrameCount = outputIndex;
            disp('--- Post-Processing Complete! All data is perfectly synced. ---');
        end

        function options = normalizeOptions(folderPath, options)
            if ~(ischar(folderPath) || ...
                    (isstring(folderPath) && isscalar(folderPath))) || ...
                    ~isfolder(folderPath)
                error('PostProcessor:InvalidFolder', ...
                    'Select a valid recorded-test directory.');
            end
            if ~isstruct(options) || ~isscalar(options)
                error('PostProcessor:InvalidOptions', ...
                    'Post-processing options must be one structure.');
            end
            if ~isfield(options, 'samplingPeriod')
                options.samplingPeriod = 0;
            end
            if ~isfield(options, 'phaseScope')
                options.phaseScope = 'all-recorded';
            end
            if ~isfield(options, 'outputFolder') || ...
                    isempty(options.outputFolder)
                options.outputFolder = fullfile( ...
                    char(folderPath), 'processed_frames');
            end

            options.samplingPeriod = double(options.samplingPeriod);
            if ~isscalar(options.samplingPeriod) || ...
                    ~isfinite(options.samplingPeriod) || ...
                    options.samplingPeriod < 0
                error('PostProcessor:InvalidSamplingPeriod', ...
                    'Sampling period must be a finite non-negative number.');
            end
            if ~(ischar(options.phaseScope) || ...
                    (isstring(options.phaseScope) && ...
                    isscalar(options.phaseScope)))
                error('PostProcessor:InvalidPhaseScope', ...
                    'Phase scope must be text.');
            end
            options.phaseScope = lower(char(options.phaseScope));
            if ~ismember(options.phaseScope, ...
                    {'all-recorded', 'main-test', 'complete-test'})
                error('PostProcessor:InvalidPhaseScope', ...
                    'Unsupported phase scope: %s.', options.phaseScope);
            end
            if ~(ischar(options.outputFolder) || ...
                    (isstring(options.outputFolder) && ...
                    isscalar(options.outputFolder)))
                error('PostProcessor:InvalidOutputFolder', ...
                    'Output folder must be one path.');
            end
            options.outputFolder = char(options.outputFolder);
        end

        function camTimestamps = readCameraTimestamps(filename)
            opts = delimitedTextImportOptions('NumVariables', 3);
            opts.DataLines = [1, Inf];
            opts.Delimiter = ',';
            opts.VariableNames = {'Index', 'Timestamp', 'TestPhase'};
            opts.VariableTypes = {'double', 'string', 'double'};
            opts.ExtraColumnsRule = 'ignore';
            opts.EmptyLineRule = 'read';
            camTimestamps = readtable(filename, opts);
            camTimestamps.Timestamp = ...
                PostProcessor.parseTimestampStrings( ...
                camTimestamps.Timestamp);

            phases = camTimestamps.TestPhase;
            if ~isempty(phases) && (any(~isfinite(phases)) || ...
                    any(phases ~= fix(phases)) || ...
                    any(phases < 0 | phases > 3))
                error('PostProcessor:MissingTestPhase', ...
                    ['camTimestamps.csv must contain a valid TestPhase ' ...
                    'column with values from 0 to 3.']);
            end
            if any(ismissing(camTimestamps.Timestamp)) || ...
                    any(diff(camTimestamps.Timestamp) < seconds(0))
                error('PostProcessor:InvalidCameraTimestamps', ...
                    'Camera timestamps must be present and chronological.');
            end
        end

        function data = readMeasurementFile(filename, valueName)
            opts = delimitedTextImportOptions('NumVariables', 2);
            opts.DataLines = [1, Inf];
            opts.Delimiter = ',';
            opts.VariableNames = {'Timestamp', valueName};
            opts.VariableTypes = {'string', 'double'};
            opts.ExtraColumnsRule = 'ignore';
            opts.EmptyLineRule = 'read';
            data = readtable(filename, opts);
            data.Timestamp = PostProcessor.parseTimestampStrings( ...
                data.Timestamp);
            if isempty(data) || any(ismissing(data.Timestamp)) || ...
                    any(~isfinite(data.(valueName)))
                error('PostProcessor:InvalidMeasurementData', ...
                    '%s must contain valid timestamps and finite values.', ...
                    filename);
            end
        end

        function timestamps = parseTimestampStrings(values)
            values = string(values);
            if isempty(values)
                timestamps = NaT(size(values));
                return;
            end
            hasDate = contains(values, '-');
            if all(hasDate)
                timestamps = datetime(values, ...
                    'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
                return;
            end
            if any(hasDate)
                error('PostProcessor:InvalidTimestamps', ...
                    'A timestamp file cannot mix dated and time-only values.');
            end

            timesOfDay = datetime(values, ...
                'InputFormat', 'HH:mm:ss.SSS');
            timestamps = timesOfDay;
            dayOffset = 0;
            for index = 2:numel(timestamps)
                if timesOfDay(index) < timesOfDay(index - 1)
                    dayOffset = dayOffset + 1;
                end
                timestamps(index) = timesOfDay(index) + days(dayOffset);
            end
        end

        function selectedRows = selectFrameRows( ...
                camTimestamps, samplingPeriod, phaseScope)
            phases = double(camTimestamps.TestPhase);
            switch char(phaseScope)
                case 'main-test'
                    eligible = phases == 2;
                case 'complete-test'
                    eligible = ismember(phases, [1, 2, 3]);
                otherwise
                    eligible = true(size(phases));
            end
            candidates = find(eligible);
            if samplingPeriod == 0 || isempty(candidates)
                selectedRows = candidates;
                return;
            end

            selectedRows = zeros(numel(candidates), 1);
            selectedCount = 0;
            previousCandidate = 0;
            previousPhase = NaN;
            lastSelectedTime = NaT;
            for index = 1:numel(candidates)
                row = candidates(index);
                phaseChanged = phases(row) ~= previousPhase;
                phaseGap = previousCandidate > 0 && ...
                    row > previousCandidate + 1;
                select = selectedCount == 0 || phaseChanged || phaseGap || ...
                    seconds(camTimestamps.Timestamp(row) - ...
                    lastSelectedTime) >= samplingPeriod;
                if select
                    selectedCount = selectedCount + 1;
                    selectedRows(selectedCount) = row;
                    lastSelectedTime = camTimestamps.Timestamp(row);
                end
                previousCandidate = row;
                previousPhase = phases(row);
            end
            selectedRows = selectedRows(1:selectedCount);
        end

        function value = nearestValue(data, timestamp, valueName)
            [~, index] = min(abs(data.Timestamp - timestamp));
            value = data.(valueName)(index);
        end
    end
end

