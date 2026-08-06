classdef PostProcessor
    %PostProcessor Aligns recorded sensor samples to camera frames and exports TIFFs.

    methods (Static)
        % Process recorded data and save annotated camera frames.
        function result = processData(folderPath, options)
            % folderPath is the directory containing recording.h5 and cam.bin.
            if nargin < 2
                options = struct();
            end
            options = PostProcessor.normalizeOptions(folderPath, options);
            result = struct( ...
                'outputFolder', options.outputFolder, ...
                'exportedFrameCount', 0, ...
                'status', 'completed', ...
                'message', '');

            disp('--- Starting offline post-processing ---');

            recording = PostProcessor.readRecording(folderPath);
            dataX = recording.dataX;
            dataY = recording.dataY;
            camTimestamps = recording.cameraRows;

            numFrames = height(camTimestamps);
            if numFrames == 0
                result.status = 'skipped';
                result.message = [ ...
                    'No camera frames were recorded, so no TIFF files ' ...
                    'were created.'];
                warning('PostProcessor:NoCameraFrames', ...
                    '%s', result.message);
                return;
            end
            phaseEligible = PostProcessor.eligibleFrameMask( ...
                camTimestamps, options.phaseScope);
            coverageStart = max( ...
                [dataX.Timestamp(1); dataY.Timestamp(1)]);
            coverageEnd = min( ...
                [dataX.Timestamp(end); dataY.Timestamp(end)]);
            if coverageStart <= coverageEnd
                coverageMask = ...
                    camTimestamps.Timestamp >= coverageStart & ...
                    camTimestamps.Timestamp <= coverageEnd;
            else
                coverageMask = false(numFrames, 1);
            end

            outsideCoverage = phaseEligible & ~coverageMask;
            skippedCount = sum(outsideCoverage);
            if skippedCount > 0
                earlyMask = outsideCoverage & ...
                    camTimestamps.Timestamp < coverageStart;
                lateMask = outsideCoverage & ~earlyMask;
                result.message = sprintf( ...
                    ['Skipped %d phase-eligible camera frame(s) outside ' ...
                    'common PLC coverage (%d early, %d late).'], ...
                    skippedCount, sum(earlyMask), sum(lateMask));
                warning('PostProcessor:SkippedOutOfRangeFrames', ...
                    '%s', result.message);
            end

            selectedRows = PostProcessor.selectFrameRows( ...
                camTimestamps, options.samplingPeriod, ...
                options.phaseScope, coverageMask);
            if isempty(selectedRows)
                result.status = 'skipped';
                if isempty(result.message)
                    result.message = [ ...
                        'No non-Idle camera frames match the selected ' ...
                        'system statuses and common PLC coverage.'];
                    warning('PostProcessor:NoMatchingFrames', ...
                        '%s', result.message);
                end
                return;
            end
            if exist('insertText', 'file') ~= 2
                error('PostProcessor:MissingComputerVisionToolbox', ...
                    ['TIFF annotation requires insertText from Computer ' ...
                    'Vision Toolbox. Install or license that toolbox ' ...
                    'before running post-processing.']);
            end
            selectedMask = false(numFrames, 1);
            selectedMask(selectedRows) = true;

            fprintf('Found %d frame(s); exporting %d after filtering.\n', ...
                numFrames, numel(selectedRows));
            baseTime = camTimestamps.Timestamp(1);
            frameWidth = recording.frameWidth;
            frameHeight = recording.frameHeight;

            %% Open Binary Camera File
            camBinFile = fullfile(folderPath, 'cam.bin');
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

            %% Synchronize and process
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
                %% Match the nearest sensor values
                sampleX = PostProcessor.nearestSample(dataX, cameraTime);
                sampleY = PostProcessor.nearestSample(dataY, cameraTime);
                matchedX = sampleX.Force;
                matchedUntaredX = sampleX.UntaredForce;
                matchedPositionX = sampleX.Position;
                matchedY = sampleY.Force;
                matchedUntaredY = sampleY.UntaredForce;
                matchedPositionY = sampleY.Position;

                %% Process and Save the Image
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
                PostProcessor.writeLegacyTiff( ...
                    outputFileName, annotatedFrame, newTxtDesc);

                if mod(outputIndex, 50) == 0
                    fprintf('Processed %d / %d frames...\n', ...
                        outputIndex, numel(selectedRows));
                    drawnow limitrate;
                end
            end

            result.exportedFrameCount = outputIndex;
            disp('--- Post-processing complete ---');
        end

        function options = normalizeOptions(folderPath, options)
            % Apply defaults and validate all caller-provided options.
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

        function recording = readRecording(folderPath)
            % Read and validate one recording for post-processing.
            h5File = fullfile(folderPath, 'recording.h5');
            camBinFile = fullfile(folderPath, 'cam.bin');
            if ~isfile(h5File)
                error('PostProcessor:MissingRecording', ...
                    ['Could not find recording.h5. Legacy CSV recordings ' ...
                    'are not supported.']);
            end
            if ~isfile(camBinFile)
                error('PostProcessor:MissingCameraBinary', ...
                    'Could not find cam.bin.');
            end
            try
                schemaVersion = h5read( ...
                    h5File, '/metadata/schema_version');
                startText = strtrim(char(h5readatt( ...
                    h5File, '/metadata', 'start_time')));
                status = strtrim(char(h5readatt( ...
                    h5File, '/metadata', 'status')));
                frameWidth = double(h5readatt( ...
                    h5File, '/camera', 'width'));
                frameHeight = double(h5readatt( ...
                    h5File, '/camera', 'height'));
                cameraData = double(h5read( ...
                    h5File, '/camera/records'));
                xData = double(h5read(h5File, '/plc/X/samples'));
                yData = double(h5read(h5File, '/plc/Y/samples'));
            catch exception
                error('PostProcessor:InvalidRecording', ...
                    'recording.h5 is incomplete or invalid: %s', ...
                    exception.message);
            end
            if ~isscalar(schemaVersion) || schemaVersion ~= 1
                error('PostProcessor:SchemaVersion', ...
                    'Unsupported recording schema version %s.', ...
                    mat2str(schemaVersion));
            end
            try
                startTime = datetime(startText, ...
                    'InputFormat', 'yyyy-MM-dd HH:mm:ss.SSS');
            catch exception
                error('PostProcessor:InvalidStartTime', ...
                    'Recording start time is invalid: %s', ...
                    exception.message);
            end
            if ~strcmpi(status, 'completed')
                warning('PostProcessor:InterruptedRecording', ...
                    'Recording status is "%s"; recovering complete data.', ...
                    status);
            end

            dataX = PostProcessor.sampleTable(xData, startTime, 'X');
            dataY = PostProcessor.sampleTable(yData, startTime, 'Y');
            if isempty(dataX) || isempty(dataY)
                error('PostProcessor:MissingPlcSamples', ...
                    'The recording must contain usable X and Y PLC samples.');
            end

            if size(cameraData, 1) ~= 3 || ...
                    any(~isfinite(cameraData), 'all')
                error('PostProcessor:InvalidCameraRecords', ...
                    'Camera records must contain three finite rows.');
            end
            if ~isempty(cameraData) && ...
                    (any(diff(cameraData(2, :)) < 0) || ...
                    any(cameraData(1, :) < 1) || ...
                    any(cameraData(1, :) ~= fix(cameraData(1, :))))
                error('PostProcessor:InvalidCameraRecords', ...
                    ['Camera indexes must be positive integers and ' ...
                    'timestamps must be chronological.']);
            end
            statuses = cameraData(3, :);
            validStatuses = [0, 1, 2, 3, 4, 5, 6, ...
                10, 11, 20, 21, 30];
            if any(statuses ~= fix(statuses)) || ...
                    any(~ismember(statuses, validStatuses))
                error('PostProcessor:InvalidSystemStatus', ...
                    'Camera records contain an unsupported SystemStatus.');
            end

            metadataCount = size(cameraData, 2);
            binaryInfo = dir(camBinFile);
            hasCameraData = metadataCount > 0 || binaryInfo.bytes > 0;
            if hasCameraData && ...
                    (~isscalar(frameWidth) || ~isscalar(frameHeight) || ...
                    ~isfinite(frameWidth) || ~isfinite(frameHeight) || ...
                    frameWidth < 1 || frameHeight < 1 || ...
                    frameWidth ~= fix(frameWidth) || ...
                    frameHeight ~= fix(frameHeight))
                error('PostProcessor:InvalidCameraDimensions', ...
                    'Camera dimensions must be positive integers.');
            end
            if ~hasCameraData
                completeBinaryFrames = 0;
                trailingBytes = 0;
            else
                bytesPerFrame = frameWidth * frameHeight;
                completeBinaryFrames = floor( ...
                    binaryInfo.bytes / bytesPerFrame);
                trailingBytes = mod(binaryInfo.bytes, bytesPerFrame);
            end
            usableCount = min(metadataCount, completeBinaryFrames);
            if metadataCount ~= completeBinaryFrames || trailingBytes ~= 0
                warning('PostProcessor:RecoveredCameraTail', ...
                    ['Using %d complete frame/timestamp pair(s); ' ...
                    'recording.h5 has %d camera row(s), cam.bin has %d ' ...
                    'complete frame(s), and %d trailing byte(s).'], ...
                    usableCount, metadataCount, completeBinaryFrames, ...
                    trailingBytes);
            end
            cameraData = cameraData(:, 1:usableCount);
            cameraRows = table( ...
                cameraData(1, :)', ...
                startTime + seconds(cameraData(2, :)'), ...
                cameraData(3, :)', ...
                'VariableNames', ...
                {'Index', 'Timestamp', 'SystemStatus'});
            recording = struct( ...
                'dataX', dataX, ...
                'dataY', dataY, ...
                'cameraRows', cameraRows, ...
                'frameWidth', frameWidth, ...
                'frameHeight', frameHeight);
        end

        function data = sampleTable(values, startTime, axisName)
            % Convert one axis dataset to a timestamped sample table.
            if size(values, 1) ~= 4 || any(~isfinite(values), 'all')
                error('PostProcessor:InvalidMeasurementData', ...
                    '%s-axis samples must contain four finite rows.', ...
                    axisName);
            end
            if ~isempty(values) && any(diff(values(1, :)) < 0)
                error('PostProcessor:InvalidMeasurementData', ...
                    '%s-axis timestamps must be chronological.', axisName);
            end
            data = table( ...
                startTime + seconds(values(1, :)'), ...
                values(2, :)', values(3, :)', values(4, :)', ...
                'VariableNames', ...
                {'Timestamp', 'Force', 'UntaredForce', 'Position'});
        end

        function eligible = eligibleFrameMask(camTimestamps, phaseScope)
            % Return phase eligibility without applying time sampling.
            statuses = double(camTimestamps.SystemStatus);
            switch char(phaseScope)
                case 'main-test'
                    eligible = ismember(statuses, [20, 21]);
                case 'complete-test'
                    eligible = ismember( ...
                        statuses, [10, 11, 20, 21, 30]);
                otherwise
                    eligible = statuses ~= 0;
            end
            eligible = logical(eligible(:));
        end

        function selectedRows = selectFrameRows(camTimestamps, samplingPeriod, phaseScope, coverageMask)
            % Select frames from the requested phases before interval sampling.
            if nargin < 4 || isempty(coverageMask)
                coverageMask = true(height(camTimestamps), 1);
            end
            if ~isvector(coverageMask) || ...
                    numel(coverageMask) ~= height(camTimestamps)
                error('PostProcessor:InvalidCoverageMask', ...
                    'Frame coverage mask must match the camera row count.');
            end
            statuses = double(camTimestamps.SystemStatus);
            eligible = PostProcessor.eligibleFrameMask( ...
                camTimestamps, phaseScope);
            candidates = find(eligible & logical(coverageMask(:)));
            if samplingPeriod == 0 || isempty(candidates)
                selectedRows = candidates;
                return;
            end

            selectedRows = zeros(numel(candidates), 1);
            selectedCount = 0;
            previousCandidate = 0;
            previousStatus = NaN;
            lastSelectedTime = NaT;
            for index = 1:numel(candidates)
                row = candidates(index);
                statusChanged = statuses(row) ~= previousStatus;
                statusGap = previousCandidate > 0 && ...
                    row > previousCandidate + 1;
                select = selectedCount == 0 || ...
                    statusChanged || statusGap || ...
                    seconds(camTimestamps.Timestamp(row) - ...
                    lastSelectedTime) >= samplingPeriod;
                if select
                    selectedCount = selectedCount + 1;
                    selectedRows(selectedCount) = row;
                    lastSelectedTime = camTimestamps.Timestamp(row);
                end
                previousCandidate = row;
                previousStatus = statuses(row);
            end
            selectedRows = selectedRows(1:selectedCount);
        end

        function writeLegacyTiff(filename, frame, description)
            % Preserve the downstream Basler-compatible single-strip TIFF:
            % little endian, IFD at byte 8, metadata at byte 256, pixels at
            % byte 1024, and one uncompressed Mono8 sample per pixel.
            if ndims(frame) == 3
                frame = rgb2gray(frame);
            end
            frame = uint8(frame);
            [height, width] = size(frame);
            if width < 1 || height < 1 || ...
                    width > intmax('uint16') || ...
                    height > intmax('uint16')
                error('PostProcessor:TiffDimensions', ...
                    ['TIFF dimensions must be positive and fit unsigned ' ...
                    '16-bit fields.']);
            end
            descriptionBytes = unicode2native( ...
                char(description), 'ISO-8859-1');
            descriptionBytes(end + 1) = uint8(0);
            if numel(descriptionBytes) > 768
                error('PostProcessor:TiffDescription', ...
                    'TIFF Description exceeds the 768-byte metadata area.');
            end

            fid = fopen(filename, 'wb', 'ieee-le');
            if fid == -1
                error('PostProcessor:TiffOpen', ...
                    'Could not create %s.', filename);
            end
            cleanup = onCleanup(@() fclose(fid));
            fwrite(fid, uint8('II'), 'uint8');
            fwrite(fid, uint16(42), 'uint16');
            fwrite(fid, uint32(8), 'uint32');
            fwrite(fid, uint16(13), 'uint16');

            PostProcessor.writeTiffEntry(fid, 256, 3, 1, width);
            PostProcessor.writeTiffEntry(fid, 257, 3, 1, height);
            PostProcessor.writeTiffEntry(fid, 258, 3, 1, 8);
            PostProcessor.writeTiffEntry(fid, 259, 3, 1, 1);
            PostProcessor.writeTiffEntry(fid, 262, 3, 1, 1);
            PostProcessor.writeTiffEntry(fid, 270, 2, ...
                numel(descriptionBytes), 256);
            PostProcessor.writeTiffEntry(fid, 273, 4, 1, 1024);
            PostProcessor.writeTiffEntry(fid, 277, 3, 1, 1);
            PostProcessor.writeTiffEntry(fid, 278, 4, 1, height);
            PostProcessor.writeTiffEntry(fid, 279, 4, 1, width * height);
            PostProcessor.writeTiffEntry(fid, 282, 5, 1, 180);
            PostProcessor.writeTiffEntry(fid, 283, 5, 1, 188);
            PostProcessor.writeTiffEntry(fid, 296, 3, 1, 2);
            fwrite(fid, uint32(0), 'uint32');

            PostProcessor.padTiffToOffset(fid, 180);
            fwrite(fid, uint32([72, 1, 72, 1]), 'uint32');
            PostProcessor.padTiffToOffset(fid, 256);
            fwrite(fid, descriptionBytes, 'uint8');
            PostProcessor.padTiffToOffset(fid, 1024);
            written = fwrite(fid, frame', 'uint8');
            if written ~= numel(frame)
                error('PostProcessor:TiffWrite', ...
                    'Could not write all image pixels to %s.', filename);
            end
            clear cleanup;
        end

        function writeTiffEntry(fid, tag, type, count, value)
            % Write one 12-byte TIFF image-file-directory entry.
            fwrite(fid, uint16(tag), 'uint16');
            fwrite(fid, uint16(type), 'uint16');
            fwrite(fid, uint32(count), 'uint32');
            if type == 3 && count == 1
                fwrite(fid, uint16(value), 'uint16');
                fwrite(fid, uint16(0), 'uint16');
            else
                fwrite(fid, uint32(value), 'uint32');
            end
        end

        function padTiffToOffset(fid, byteOffset)
            % Pad forward without crossing the fixed TIFF layout boundary.
            current = ftell(fid);
            if current > byteOffset
                error('PostProcessor:TiffLayout', ...
                    'TIFF metadata exceeded its fixed byte layout.');
            end
            if current < byteOffset
                fwrite(fid, zeros(1, byteOffset - current, 'uint8'), ...
                    'uint8');
            end
        end

        function value = nearestSample(data, timestamp)
            % Return the sample with the smallest timestamp difference.
            if timestamp < data.Timestamp(1) || ...
                    timestamp > data.Timestamp(end)
                error('PostProcessor:TimestampOutsidePlcCoverage', ...
                    ['Camera timestamp is outside the available PLC ' ...
                    'sample range.']);
            end
            [~, index] = min(abs(data.Timestamp - timestamp));
            value = data(index, :);
        end
    end
end

