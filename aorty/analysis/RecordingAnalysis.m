classdef RecordingAnalysis < handle
    %RecordingAnalysis Loads, analyses, and plots one recording.h5 file.

    properties (SetAccess = private)
        FilePath
        Recording
    end

    methods
        %% Loading, analysis, and plotting
        function validator = RecordingAnalysis(filePath)
            if nargin < 1
                error('RecordingAnalysis:MissingRecording', ...
                    ['Provide a recording.h5 path or call ' ...
                    'RecordingAnalysis.open() to choose one.']);
            end
            validator.FilePath = RecordingAnalysis.normalizePath(filePath);
            validator.Recording = RecordingAnalysis.readRecording(validator.FilePath);
        end

        function metrics = analyze(validator)
            % Return descriptive integrity, axis, phase, and target metrics.
            recording = validator.Recording;
            warnings = string(recording.Warnings(:));

            metadata = recording.Metadata;
            actualCamera = height(recording.Camera);
            actualX = height(recording.X);
            actualY = height(recording.Y);
            recordedCamera = RecordingAnalysis.numericField( ...
                metadata, 'camera_record_count', NaN);
            recordedX = RecordingAnalysis.numericField( ...
                metadata, 'x_sample_count', NaN);
            recordedY = RecordingAnalysis.numericField( ...
                metadata, 'y_sample_count', NaN);
            droppedX = RecordingAnalysis.numericField( ...
                metadata, 'x_dropped_sample_count', 0);
            droppedY = RecordingAnalysis.numericField( ...
                metadata, 'y_dropped_sample_count', 0);
            sampleLoss = logical(RecordingAnalysis.numericField( ...
                metadata, 'sample_loss_detected', droppedX + droppedY > 0));
            restart = logical(RecordingAnalysis.numericField( ...
                metadata, 'plc_restart_detected', 0));
            fileStatus = string(RecordingAnalysis.textField( ...
                metadata, 'status', 'unknown'));

            if ~strcmpi(fileStatus, 'completed')
                warnings(end + 1, 1) = ...
                    "Recording status is " + fileStatus + ".";
            end
            [warnings, cameraCountMatches] = ...
                RecordingAnalysis.countWarning(warnings, ...
                'camera', recordedCamera, actualCamera);
            [warnings, xCountMatches] = RecordingAnalysis.countWarning( ...
                warnings, 'X-axis', recordedX, actualX);
            [warnings, yCountMatches] = RecordingAnalysis.countWarning( ...
                warnings, 'Y-axis', recordedY, actualY);
            if sampleLoss
                warnings(end + 1, 1) = sprintf( ...
                    'Recording reports dropped PLC samples (X=%g, Y=%g).', ...
                    droppedX, droppedY);
            end
            if restart
                warnings(end + 1, 1) = ...
                    "Recording reports a PLC restart or counter reset.";
            end

            metrics = struct();
            metrics.Integrity = table( ...
                fileStatus, recordedCamera, actualCamera, ...
                recordedX, actualX, recordedY, actualY, ...
                droppedX, droppedY, sampleLoss, restart, ...
                cameraCountMatches, xCountMatches, yCountMatches, ...
                'VariableNames', {'FileStatus', ...
                'RecordedCameraCount', 'ActualCameraCount', ...
                'RecordedXSampleCount', 'ActualXSampleCount', ...
                'RecordedYSampleCount', 'ActualYSampleCount', ...
                'XDroppedSamples', 'YDroppedSamples', ...
                'SampleLossDetected', 'PlcRestartDetected', ...
                'CameraCountMatches', 'XCountMatches', 'YCountMatches'});
            metrics.Axes = validator.axisMetrics();
            [metrics.Phases, phaseWarnings] = validator.phaseMetrics();
            warnings = [warnings; phaseWarnings(:)];
            [metrics.Targets, targetWarnings] = validator.targetMetrics();
            warnings = [warnings; targetWarnings(:)];
            metrics.Warnings = unique(warnings(strlength(warnings) > 0), ...
                'stable');
        end

        function fig = plot(validator)
            % Plot raw force and position data with phase and target overlays.
            recording = validator.Recording;
            fig = figure('Name', ['Test validation - ', ...
                RecordingAnalysis.fileName(validator.FilePath)], ...
                'NumberTitle', 'off', 'Color', 'white');
            layout = tiledlayout(fig, 1, 2, ...
                'TileSpacing', 'compact', 'Padding', 'compact');
            forceAxes = nexttile(layout, 1);
            positionAxes = nexttile(layout, 2);
            RecordingAnalysis.applyPlotTheme(forceAxes);
            RecordingAnalysis.applyPlotTheme(positionAxes);
            hold(forceAxes, 'on');
            hold(positionAxes, 'on');

            colors = struct('X', [0.10, 0.45, 0.85], ...
                'Y', [0.90, 0.38, 0.12]);
            for item = recording.ActiveAxes
                axisName = item{1};
                samples = recording.(axisName);
                if isempty(samples)
                    continue;
                end
                plot(forceAxes, samples.ElapsedSeconds, samples.Force, ...
                    'Color', colors.(axisName), 'LineWidth', 1.25, ...
                    'DisplayName', [axisName, ' axis']);
                plot(positionAxes, samples.ElapsedSeconds, ...
                    samples.Position, 'Color', colors.(axisName), ...
                    'LineWidth', 1.25, ...
                    'DisplayName', [axisName, ' axis']);
            end

            RecordingAnalysis.finishAxes(forceAxes, ...
                'Force', 'Force [N]');
            RecordingAnalysis.finishAxes(positionAxes, ...
                'Position', 'Position [mm]');
            segments = RecordingAnalysis.statusSegments( ...
                recording.Camera, recording);
            RecordingAnalysis.addPhaseBands(forceAxes, segments);
            RecordingAnalysis.addPhaseBands(positionAxes, segments);
            validator.addTargetReferences(forceAxes, segments, colors);
            RecordingAnalysis.addPhaseLabels(forceAxes, segments);
            RecordingAnalysis.addPhaseLabels(positionAxes, segments);

            titleText = validator.recordingTitle();
            heading = sgtitle(layout, titleText, 'Interpreter', 'none');
            heading.Color = [0.12, 0.12, 0.12];
        end
    end

    methods (Static)
        %% Interactive entry point
        function [metrics, fig, validator] = open(filePath)
            % Select or open one recording, then analyse and plot it.
            metrics = [];
            fig = gobjects(0);
            validator = [];
            if nargin < 1 || isempty(filePath)
                [name, folder] = uigetfile( ...
                    {'*.h5;*.hdf5', ...
                    'HDF5 recordings (*.h5, *.hdf5)'}, ...
                    'Choose recording.h5');
                if isequal(name, 0)
                    return;
                end
                filePath = fullfile(folder, name);
            end
            validator = RecordingAnalysis(filePath);
            metrics = validator.analyze();
            fig = validator.plot();
        end
    end

    methods (Access = private)
        %% Metric calculation and plot annotations
        function result = axisMetrics(validator)
            rows = cell(0, 11);
            for item = validator.Recording.ActiveAxes
                axisName = item{1};
                samples = validator.Recording.(axisName);
                if isempty(samples)
                    rows(end + 1, :) = {string(axisName), 0, NaN, ...
                        NaN, NaN, NaN, NaN, NaN, NaN, NaN, NaN}; %#ok<AGROW>
                    continue;
                end
                time = samples.ElapsedSeconds;
                baseline = time <= time(1) + 0.5;
                rows(end + 1, :) = {string(axisName), height(samples), ...
                    time(end) - time(1), min(samples.Force), ...
                    max(samples.Force), min(samples.Position), ...
                    max(samples.Position), ...
                    max(samples.Position) - min(samples.Position), ...
                    mean(samples.Force(baseline)), ...
                    std(samples.Force(baseline)), ...
                    median(samples.UntaredForce - samples.Force)}; %#ok<AGROW>
            end
            result = cell2table(rows, 'VariableNames', ...
                {'Axis', 'SampleCount', 'DurationSeconds', ...
                'ForceMin', 'ForceMax', 'PositionMin', 'PositionMax', ...
                'PositionTravel', 'BaselineForce', ...
                'BaselineNoiseStd', 'TareOffsetMedian'});
        end

        function [result, warnings] = phaseMetrics(validator)
            warnings = strings(0, 1);
            recording = validator.Recording;
            segments = RecordingAnalysis.statusSegments( ...
                recording.Camera, recording);
            rows = cell(0, 12);
            if isempty(segments)
                result = RecordingAnalysis.emptyPhaseTable();
                warnings(end + 1, 1) = ...
                    "Camera status rows are unavailable; phase metrics are empty.";
                return;
            end
            for segmentIndex = 1:height(segments)
                if segments.Status(segmentIndex) == 0
                    continue;
                end
                for item = recording.ActiveAxes
                    axisName = item{1};
                    samples = recording.(axisName);
                    mask = RecordingAnalysis.segmentMask(samples.ElapsedSeconds, ...
                        segments.StartSeconds(segmentIndex), ...
                        segments.StopSeconds(segmentIndex), ...
                        segmentIndex == height(segments));
                    if any(mask)
                        forceMin = min(samples.Force(mask));
                        forceMax = max(samples.Force(mask));
                        positionMin = min(samples.Position(mask));
                        positionMax = max(samples.Position(mask));
                    else
                        forceMin = NaN; forceMax = NaN;
                        positionMin = NaN; positionMax = NaN;
                    end
                    rows(end + 1, :) = {string(axisName), segmentIndex, ...
                        segments.Status(segmentIndex), ...
                        segments.Phase(segmentIndex), ...
                        segments.StartSeconds(segmentIndex), ...
                        segments.StopSeconds(segmentIndex), ...
                        segments.DurationSeconds(segmentIndex), ...
                        sum(mask), forceMin, forceMax, ...
                        positionMin, positionMax}; %#ok<AGROW>
                end
            end
            if isempty(rows)
                result = RecordingAnalysis.emptyPhaseTable();
            else
                result = cell2table(rows, 'VariableNames', ...
                    {'Axis', 'Segment', 'Status', 'Phase', ...
                    'StartSeconds', 'StopSeconds', 'DurationSeconds', ...
                    'SampleCount', 'ForceMin', 'ForceMax', ...
                    'PositionMin', 'PositionMax'});
            end
        end

        function [result, warnings] = targetMetrics(validator)
            warnings = strings(0, 1);
            recording = validator.Recording;
            definitions = RecordingAnalysis.targetDefinitions(recording);
            if isempty(definitions)
                result = RecordingAnalysis.emptyTargetTable();
                return;
            end
            if isempty(recording.Camera)
                warnings(end + 1, 1) = ...
                    "Camera status rows are unavailable; target timing " + ...
                    "metrics cannot be calculated.";
            end
            rows = cell(0, 19);
            for index = 1:height(definitions)
                definition = definitions(index, :);
                axisName = char(definition.Axis);
                samples = recording.(axisName);
                coarseEndpointPhase = ismember(definition.Status, [11, 21]);
                available = ~definition.Ambiguous && ...
                    ~coarseEndpointPhase && ...
                    ~isempty(recording.Camera) && ~isempty(samples);
                firstReach = NaN;
                overshoot = NaN;
                meanError = NaN;
                stdError = NaN;
                inFraction = NaN;
                totalInside = NaN;
                longestInside = NaN;
                entryCount = NaN;
                phaseDuration = NaN;

                if definition.Ambiguous
                    warnings(end + 1, 1) = sprintf( ...
                        ['%s-axis %s uses variable per-cycle targets; ' ...
                         'timing and overshoot metrics are unavailable.'], ...
                        axisName, char(definition.Role)); %#ok<AGROW>
                elseif coarseEndpointPhase
                    warnings(end + 1, 1) = sprintf( ...
                        ['%s-axis %s shares one recorded PLC status with ' ...
                         'the opposite endpoint; timing and overshoot ' ...
                         'metrics are unavailable.'], ...
                        axisName, char(definition.Role)); %#ok<AGROW>
                elseif available
                    statuses = RecordingAnalysis.sampleStatuses( ...
                        samples.ElapsedSeconds, recording.Camera);
                    phaseMask = statuses == definition.Status;
                    if any(phaseMask)
                        phaseTime = samples.ElapsedSeconds(phaseMask);
                        phaseForce = samples.Force(phaseMask);
                        phaseDuration = phaseTime(end) - phaseTime(1);
                        errorValues = phaseForce - definition.Target;
                        inside = abs(errorValues) <= definition.Tolerance;
                        first = find(inside, 1, 'first');
                        if ~isempty(first)
                            firstReach = phaseTime(first) - phaseTime(1);
                            direction = RecordingAnalysis.targetDirection( ...
                                definition.Role, definition.Target, ...
                                phaseForce);
                            overshoot = max( ...
                                direction * errorValues(first:end));
                        end
                        inFraction = mean(inside);
                        runs = RecordingAnalysis.logicalRuns(inside);
                        entryCount = size(runs, 1);
                        totalInside = 0;
                        if ~isempty(runs)
                            durations = phaseTime(runs(:, 2)) - ...
                                phaseTime(runs(:, 1));
                            totalInside = sum(durations);
                            longestInside = max(durations);
                            meanError = mean(errorValues(inside));
                            stdError = std(errorValues(inside));
                        end
                    else
                        available = false;
                        warnings(end + 1, 1) = sprintf( ...
                            '%s-axis %s phase is not present in the recording.', ...
                            axisName, char(definition.Role)); %#ok<AGROW>
                    end
                end

                rows(end + 1, :) = {definition.Axis, ...
                    definition.Phase, definition.Role, definition.Status, ...
                    definition.Target, definition.Tolerance, ...
                    definition.ConfiguredHoldSeconds, ...
                    definition.RequestedCount, definition.Ambiguous, ...
                    available, phaseDuration, firstReach, overshoot, ...
                    meanError, stdError, inFraction, totalInside, ...
                    longestInside, entryCount}; %#ok<AGROW>
            end
            result = cell2table(rows, 'VariableNames', ...
                {'Axis', 'Phase', 'Role', 'Status', 'Target', ...
                'Tolerance', 'ConfiguredHoldSeconds', 'RequestedCount', ...
                'Ambiguous', 'MetricsAvailable', 'PhaseDurationSeconds', ...
                'TimeToFirstToleranceSeconds', 'DirectionalOvershoot', ...
                'MeanErrorInTolerance', 'StdErrorInTolerance', ...
                'InToleranceFraction', 'TotalInToleranceSeconds', ...
                'LongestContinuousInToleranceSeconds', ...
                'ToleranceEntryCount'});
        end

        function addTargetReferences(validator, axesHandle, segments, colors)
            definitions = RecordingAnalysis.targetDefinitions( ...
                validator.Recording);
            if isempty(definitions)
                return;
            end
            xLimits = axesHandle.XLim;
            for index = 1:height(definitions)
                definition = definitions(index, :);
                if ismember(definition.Status, [11, 21])
                    continue;
                end
                axisName = char(definition.Axis);
                intervals = segments(segments.Status == definition.Status, :);
                if isempty(intervals)
                    intervals = table(xLimits(1), xLimits(2), ...
                        'VariableNames', {'StartSeconds', 'StopSeconds'});
                end
                for intervalIndex = 1:height(intervals)
                    startTime = intervals.StartSeconds(intervalIndex);
                    stopTime = intervals.StopSeconds(intervalIndex);
                    lower = definition.Target - definition.Tolerance;
                    upper = definition.Target + definition.Tolerance;
                    patch(axesHandle, ...
                        [startTime, stopTime, stopTime, startTime], ...
                        [lower, lower, upper, upper], ...
                        colors.(axisName), 'FaceAlpha', 0.08, ...
                        'EdgeColor', 'none', 'HandleVisibility', 'off', ...
                        'HitTest', 'off', 'PickableParts', 'none');
                    plot(axesHandle, [startTime, stopTime], ...
                        [definition.Target, definition.Target], '--', ...
                        'Color', colors.(axisName), 'LineWidth', 1.0, ...
                        'HandleVisibility', 'off', 'HitTest', 'off');
                end
            end
            RecordingAnalysis.pushPatchesToBack(axesHandle);
        end

        function value = recordingTitle(validator)
            metadata = validator.Recording.Metadata;
            started = RecordingAnalysis.textField( ...
                metadata, 'start_time', 'unknown date');
            status = RecordingAnalysis.textField( ...
                metadata, 'status', 'unknown');
            kind = RecordingAnalysis.textField( ...
                validator.Recording.Test.Common, 'test_kind', 'test');
            value = sprintf('%s | %s | %s | %s', ...
                RecordingAnalysis.fileName(validator.FilePath), ...
                started, kind, status);
        end
    end

    methods (Static, Access = private)
        %% Recording input and normalization
        function path = normalizePath(value)
            if ~(ischar(value) || ...
                    (isstring(value) && isscalar(value)))
                error('RecordingAnalysis:InvalidPath', ...
                    'The recording path must be one text value.');
            end
            value = char(value);
            if ~isfile(value)
                error('RecordingAnalysis:MissingRecording', ...
                    'Could not find HDF5 recording: %s', value);
            end
            [~, ~, extension] = fileparts(value);
            if ~ismember(lower(extension), {'.h5', '.hdf5'})
                error('RecordingAnalysis:InvalidPath', ...
                    'Select a .h5 or .hdf5 recording file.');
            end
            [ok, attributes] = fileattrib(value);
            if ~ok
                error('RecordingAnalysis:InvalidPath', ...
                    'Could not resolve recording path: %s', value);
            end
            path = attributes.Name;
        end

        function recording = readRecording(filePath)
            warnings = strings(0, 1);
            try
                schema = double(h5read( ...
                    filePath, '/metadata/schema_version'));
            catch exception
                error('RecordingAnalysis:InvalidRecording', ...
                    'Missing or invalid recording schema: %s', ...
                    exception.message);
            end
            if ~isscalar(schema) || schema ~= 1
                error('RecordingAnalysis:SchemaVersion', ...
                    'Unsupported recording schema version %s.', ...
                    mat2str(schema));
            end

            metadata = RecordingAnalysis.readAttributes( ...
                filePath, '/metadata', true);
            cameraSettings = RecordingAnalysis.readAttributes( ...
                filePath, '/camera', false);
            controllerX = RecordingAnalysis.readAttributes( ...
                filePath, '/settings/plc/X', true);
            controllerY = RecordingAnalysis.readAttributes( ...
                filePath, '/settings/plc/Y', true);
            testCommon = RecordingAnalysis.readAttributes( ...
                filePath, '/settings/test', true);
            testX = RecordingAnalysis.readAttributes( ...
                filePath, '/settings/test/X', true);
            testY = RecordingAnalysis.readAttributes( ...
                filePath, '/settings/test/Y', true);
            plcInterval = RecordingAnalysis.numericField( ...
                metadata, 'plc_interval_seconds', NaN);
            if ~isscalar(plcInterval) || ~isfinite(plcInterval) || ...
                    plcInterval <= 0
                error('RecordingAnalysis:InvalidRecording', ...
                    'Metadata PLC interval must be finite and positive.');
            end

            xValues = RecordingAnalysis.readRequiredDataset( ...
                filePath, '/plc/X/samples');
            yValues = RecordingAnalysis.readRequiredDataset( ...
                filePath, '/plc/Y/samples');
            [xSamples, recoveredX] = RecordingAnalysis.sampleTable( ...
                xValues, 'X', plcInterval);
            [ySamples, recoveredY] = RecordingAnalysis.sampleTable( ...
                yValues, 'Y', plcInterval);
            if recoveredX
                warnings(end + 1, 1) = ...
                    "X-axis timestamps were non-monotonic and were " + ...
                    "rebuilt from the recorded PLC interval.";
            end
            if recoveredY
                warnings(end + 1, 1) = ...
                    "Y-axis timestamps were non-monotonic and were " + ...
                    "rebuilt from the recorded PLC interval.";
            end

            try
                cameraValues = double(h5read( ...
                    filePath, '/camera/records'));
            catch exception
                error('RecordingAnalysis:InvalidRecording', ...
                    'Missing or invalid /camera/records: %s', ...
                    exception.message);
            end
            camera = RecordingAnalysis.cameraTable(cameraValues);
            if isempty(camera)
                warnings(end + 1, 1) = ...
                    "Camera status rows are empty.";
            end

            [activeAxes, axisWarning] = ...
                RecordingAnalysis.activeAxes(testCommon, xSamples, ySamples);
            if strlength(axisWarning) > 0
                warnings(end + 1, 1) = axisWarning;
            end
            recording = struct( ...
                'SchemaVersion', schema, ...
                'Metadata', metadata, ...
                'CameraSettings', cameraSettings, ...
                'Controller', struct('X', controllerX, 'Y', controllerY), ...
                'Test', struct('Common', testCommon, ...
                    'X', testX, 'Y', testY), ...
                'Camera', camera, 'X', xSamples, 'Y', ySamples, ...
                'ActiveAxes', {activeAxes}, 'Warnings', warnings);
        end

        function value = readRequiredDataset(filePath, dataset)
            try
                value = double(h5read(filePath, dataset));
            catch exception
                error('RecordingAnalysis:InvalidRecording', ...
                    'Missing or invalid %s: %s', dataset, ...
                    exception.message);
            end
        end

        function attributes = readAttributes(filePath, group, required)
            try
                info = h5info(filePath, group);
            catch exception
                if required
                    error('RecordingAnalysis:InvalidRecording', ...
                        'Missing or invalid %s: %s', group, ...
                        exception.message);
                end
                attributes = struct();
                return;
            end
            attributes = struct();
            for index = 1:numel(info.Attributes)
                name = matlab.lang.makeValidName(info.Attributes(index).Name);
                value = info.Attributes(index).Value;
                if ischar(value) || isstring(value)
                    value = strtrim(char(value));
                elseif isnumeric(value) || islogical(value)
                    value = double(value);
                    if ~isscalar(value)
                        value = value(:)';
                    end
                end
                attributes.(name) = value;
            end
        end

        %% Recorded sample and phase interpretation
        function [samples, recovered] = sampleTable(values, axisName, interval)
            if size(values, 1) ~= 4 || any(~isfinite(values), 'all')
                error('RecordingAnalysis:InvalidRecording', ...
                    '%s-axis samples must contain four finite rows.', ...
                    axisName);
            end
            recovered = false;
            if ~isempty(values) && any(diff(values(1, :)) < 0)
                values(1, :) = values(1, 1) + ...
                    (0:size(values, 2) - 1) * interval;
                recovered = true;
            end
            samples = table(values(1, :)', values(2, :)', ...
                values(3, :)', values(4, :)', ...
                'VariableNames', {'ElapsedSeconds', 'Force', ...
                'UntaredForce', 'Position'});
        end

        function camera = cameraTable(values)
            if size(values, 1) ~= 3 || any(~isfinite(values), 'all')
                error('RecordingAnalysis:InvalidRecording', ...
                    'Camera records must contain three finite rows.');
            end
            if ~isempty(values) && (any(diff(values(2, :)) < 0) || ...
                    any(values(1, :) < 1) || ...
                    any(values(1, :) ~= fix(values(1, :))))
                error('RecordingAnalysis:InvalidRecording', ...
                    ['Camera frame indexes must be positive integers and ' ...
                    'timestamps must be chronological.']);
            end
            validStatuses = [0, 1, 2, 3, 4, 5, 6, ...
                10, 11, 20, 21, 30];
            if any(values(3, :) ~= fix(values(3, :))) || ...
                    any(~ismember(values(3, :), validStatuses))
                error('RecordingAnalysis:InvalidRecording', ...
                    'Camera records contain an unsupported system status.');
            end
            camera = table(values(1, :)', values(2, :)', values(3, :)', ...
                'VariableNames', {'FrameIndex', 'ElapsedSeconds', ...
                'SystemStatus'});
        end

        function [axes, warningText] = activeAxes(common, xSamples, ySamples)
            warningText = "";
            text = RecordingAnalysis.textField(common, 'active_axes', '');
            parts = upper(strtrim(string(split(text, ','))));
            axes = cellstr(parts(ismember(parts, ["X", "Y"]))');
            axes = unique(axes, 'stable');
            if isempty(axes)
                axes = {};
                if ~isempty(xSamples), axes{end + 1} = 'X'; end
                if ~isempty(ySamples), axes{end + 1} = 'Y'; end
                warningText = ...
                    "Recorded active_axes metadata is unavailable or invalid; " + ...
                    "using axes with available samples.";
            end
            if isempty(axes)
                error('RecordingAnalysis:InvalidRecording', ...
                    'The recording contains no usable active-axis samples.');
            end
        end

        function segments = statusSegments(camera, recording)
            if isempty(camera)
                segments = RecordingAnalysis.emptySegmentTable();
                return;
            end
            status = camera.SystemStatus;
            starts = [1; find(diff(status) ~= 0) + 1];
            stops = [starts(2:end); height(camera) + 1];
            recordingEnd = max([camera.ElapsedSeconds(end); ...
                RecordingAnalysis.lastTime(recording.X); ...
                RecordingAnalysis.lastTime(recording.Y)], [], 'omitnan');
            rows = cell(numel(starts), 6);
            for index = 1:numel(starts)
                startRow = starts(index);
                startTime = camera.ElapsedSeconds(startRow);
                if stops(index) <= height(camera)
                    stopTime = camera.ElapsedSeconds(stops(index));
                else
                    stopTime = recordingEnd;
                end
                rows(index, :) = {index, status(startRow), ...
                    string(RecordingAnalysis.statusLabel(status(startRow))), ...
                    startTime, stopTime, max(0, stopTime - startTime)};
            end
            segments = cell2table(rows, 'VariableNames', ...
                {'Segment', 'Status', 'Phase', 'StartSeconds', ...
                'StopSeconds', 'DurationSeconds'});
        end

        %% Target reconstruction
        function definitions = targetDefinitions(recording)
            rows = cell(0, 9);
            for item = recording.ActiveAxes
                axisName = item{1};
                command = recording.Test.(axisName);
                controller = recording.Controller.(axisName);
                if RecordingAnalysis.numericField( ...
                        command, 'includePreTest', 0) ~= 0
                    tolerance = RecordingAnalysis.numericField( ...
                        command, 'preTestForceTolerance', NaN);
                    if RecordingAnalysis.numericField( ...
                            command, 'preloadEnabled', 0) ~= 0
                        rows(end + 1, :) = RecordingAnalysis.targetRow( ...
                            axisName, 10, 'Preload', 'Preload', ...
                            RecordingAnalysis.numericField( ...
                                command, 'preloadValue', NaN), ...
                            tolerance, RecordingAnalysis.numericField( ...
                                command, 'preloadHoldTime', 0), 1, false); %#ok<AGROW>
                    end
                    preCount = RecordingAnalysis.numericField( ...
                        command, 'preCycleCount', 0);
                    if preCount > 0
                        rows(end + 1, :) = RecordingAnalysis.targetRow( ...
                            axisName, 11, 'Pre-test cycles', ...
                            'Pre-cycle load', RecordingAnalysis.numericField( ...
                                command, 'preCycleLoadValue', NaN), ...
                            tolerance, RecordingAnalysis.numericField( ...
                                command, 'preCycleHoldTime', 0), ...
                            preCount, false); %#ok<AGROW>
                        if RecordingAnalysis.numericField( ...
                                command, 'preUnloadToStart', 0) == 0
                            rows(end + 1, :) = RecordingAnalysis.targetRow( ...
                                axisName, 11, 'Pre-test cycles', ...
                                'Pre-cycle unload', ...
                                RecordingAnalysis.numericField( ...
                                    command, 'preUnloadValue', NaN), ...
                                tolerance, RecordingAnalysis.numericField( ...
                                    command, 'preCycleHoldTime', 0), ...
                                preCount, false); %#ok<AGROW>
                        end
                    end
                end

                if RecordingAnalysis.numericField(command, 'cycleCount', 0) == 0
                    tolerance = RecordingAnalysis.numericField( ...
                        command, 'singleForceTolerance', NaN);
                    if RecordingAnalysis.numericField( ...
                            command, 'stop1Mode', 0) == 2
                        rows(end + 1, :) = RecordingAnalysis.targetRow( ...
                            axisName, 20, 'Single test', ...
                            'Primary endpoint', RecordingAnalysis.numericField( ...
                                command, 'stop1Value', NaN), tolerance, ...
                            RecordingAnalysis.numericField( ...
                                command, 'singleForceHoldTime', 0), ...
                            1, false); %#ok<AGROW>
                    end
                    if RecordingAnalysis.numericField( ...
                            command, 'stop2Mode', 0) == 2
                        rows(end + 1, :) = RecordingAnalysis.targetRow( ...
                            axisName, 20, 'Single test', ...
                            'Secondary endpoint', ...
                            RecordingAnalysis.numericField( ...
                                command, 'stop2Value', NaN), ...
                            tolerance, 0, 1, false); %#ok<AGROW>
                    end
                else
                    count = RecordingAnalysis.numericField( ...
                        command, 'cycleCount', 0);
                    tolerance = RecordingAnalysis.numericField( ...
                        command, 'cyclicForceTolerance', NaN);
                    holdTime = RecordingAnalysis.numericField( ...
                        command, 'cyclicForceHoldTime', 0);
                    if RecordingAnalysis.numericField( ...
                            command, 'loadMode', 0) == 2
                        values = RecordingAnalysis.vectorField( ...
                            command, 'loadValues', count);
                        rows = [rows; RecordingAnalysis.cyclicTargetRows( ...
                            axisName, 'Load endpoint', values, ...
                            tolerance, holdTime)]; %#ok<AGROW>
                    end
                    if RecordingAnalysis.numericField( ...
                            command, 'unloadMode', 0) == 2
                        values = RecordingAnalysis.vectorField( ...
                            command, 'unloadValues', count);
                        rows = [rows; RecordingAnalysis.cyclicTargetRows( ...
                            axisName, 'Unload endpoint', values, ...
                            tolerance, holdTime)]; %#ok<AGROW>
                    end
                end

                if RecordingAnalysis.numericField( ...
                        command, 'postTestMode', 0) == 4
                    rows(end + 1, :) = RecordingAnalysis.targetRow( ...
                        axisName, 30, 'Post-test', 'Zero-force release', ...
                        0, RecordingAnalysis.numericField( ...
                            controller, 'fForceTolerance', NaN), ...
                        0, 1, false); %#ok<AGROW>
                end
            end
            valid = cellfun(@(value) isnumeric(value) && ...
                isscalar(value) && isfinite(value), rows(:, 5:6));
            rows = rows(all(valid, 2), :);
            if isempty(rows)
                definitions = RecordingAnalysis.emptyDefinitionTable();
            else
                definitions = cell2table(rows, 'VariableNames', ...
                    {'Axis', 'Status', 'Phase', 'Role', 'Target', ...
                    'Tolerance', 'ConfiguredHoldSeconds', ...
                    'RequestedCount', 'Ambiguous'});
            end
        end

        function rows = cyclicTargetRows(axisName, role, values, tolerance, holdTime)
            rows = cell(0, 9);
            if isempty(values)
                return;
            end
            uniqueValues = unique(values, 'stable');
            ambiguous = numel(uniqueValues) > 1;
            for value = uniqueValues(:)'
                requested = sum(values == value);
                rows(end + 1, :) = RecordingAnalysis.targetRow( ...
                    axisName, 21, 'Cyclic test', role, value, ...
                    tolerance, holdTime, requested, ambiguous); %#ok<AGROW>
            end
        end

        function row = targetRow(axisName, status, phase, role, ...
                target, tolerance, holdTime, count, ambiguous)
            row = {string(axisName), status, string(phase), string(role), ...
                target, tolerance, holdTime, count, logical(ambiguous)};
        end

        function statuses = sampleStatuses(times, camera)
            statuses = interp1(camera.ElapsedSeconds, ...
                camera.SystemStatus, times, 'previous', 'extrap');
        end

        function direction = targetDirection(role, target, force)
            startValue = median(force(1:min(20, numel(force))));
            direction = sign(target - startValue);
            if direction == 0
                if contains(lower(char(role)), 'unload') || ...
                        contains(lower(char(role)), 'zero-force')
                    direction = -1;
                else
                    direction = 1;
                end
            end
        end

        function runs = logicalRuns(mask)
            edges = diff([false; logical(mask(:)); false]);
            runs = [find(edges == 1), find(edges == -1) - 1];
        end

        %% Plot presentation
        function addPhaseBands(axesHandle, segments)
            if isempty(segments)
                return;
            end
            limits = axesHandle.YLim;
            for index = 1:height(segments)
                color = RecordingAnalysis.phaseColor(segments.Status(index));
                if isempty(color) || segments.Status(index) == 0
                    continue;
                end
                patch(axesHandle, ...
                    [segments.StartSeconds(index), ...
                    segments.StopSeconds(index), ...
                    segments.StopSeconds(index), ...
                    segments.StartSeconds(index)], ...
                    [limits(1), limits(1), limits(2), limits(2)], color, ...
                    'FaceAlpha', 0.07, 'EdgeColor', 'none', ...
                    'HandleVisibility', 'off', 'HitTest', 'off', ...
                    'PickableParts', 'none');
            end
            RecordingAnalysis.pushPatchesToBack(axesHandle);
        end

        function addPhaseLabels(axesHandle, segments)
            if isempty(segments)
                return;
            end
            limits = axesHandle.YLim;
            y = limits(2) - 0.03 * diff(limits);
            for index = 1:height(segments)
                if segments.Status(index) == 0 || ...
                        segments.DurationSeconds(index) <= 0
                    continue;
                end
                text(axesHandle, ...
                    mean([segments.StartSeconds(index), ...
                    segments.StopSeconds(index)]), y, ...
                    segments.Phase(index), 'HorizontalAlignment', 'center', ...
                    'VerticalAlignment', 'top', 'FontSize', 8, ...
                    'Color', axesHandle.XColor, ...
                    'Interpreter', 'none', 'Clipping', 'on', ...
                    'HitTest', 'off');
            end
        end

        function pushPatchesToBack(axesHandle)
            patches = findobj(axesHandle, 'Type', 'patch');
            for index = 1:numel(patches)
                try uistack(patches(index), 'bottom'); catch, end
            end
        end

        function finishAxes(axesHandle, titleText, yText)
            titleHandle = title(axesHandle, titleText);
            xLabel = xlabel(axesHandle, 'Elapsed time [s]');
            yLabel = ylabel(axesHandle, yText);
            titleHandle.Color = [0.12, 0.12, 0.12];
            xLabel.Color = [0.12, 0.12, 0.12];
            yLabel.Color = [0.12, 0.12, 0.12];
            grid(axesHandle, 'on');
            box(axesHandle, 'on');
            legendHandle = legend(axesHandle, 'Location', 'best');
            legendHandle.Color = 'white';
            legendHandle.TextColor = [0.12, 0.12, 0.12];
            legendHandle.EdgeColor = [0.55, 0.55, 0.55];
        end

        function applyPlotTheme(axesHandle)
            axesHandle.Color = 'white';
            axesHandle.XColor = [0.12, 0.12, 0.12];
            axesHandle.YColor = [0.12, 0.12, 0.12];
            axesHandle.GridColor = [0.72, 0.72, 0.72];
            axesHandle.MinorGridColor = [0.82, 0.82, 0.82];
        end

        function color = phaseColor(status)
            switch status
                case 10
                    color = [0.25, 0.70, 0.45];
                case 11
                    color = [0.85, 0.35, 0.65];
                case {20, 21}
                    color = [0.45, 0.40, 0.85];
                case 30
                    color = [0.25, 0.70, 0.75];
                case {1, 3}
                    color = [0.85, 0.25, 0.20];
                otherwise
                    color = [];
            end
        end

        function label = statusLabel(status)
            switch status
                case 0, label = 'Idle';
                case 1, label = 'Error';
                case 2, label = 'Homing';
                case 3, label = 'Stopping';
                case 4, label = 'Taring';
                case 5, label = 'Basic move';
                case 6, label = 'Force mode';
                case 10, label = 'Preload';
                case 11, label = 'Pre-test cycles';
                case 20, label = 'Single test';
                case 21, label = 'Cyclic test';
                case 30, label = 'Post-test';
                otherwise, label = sprintf('Status %g', status);
            end
        end

        %% Value and table helpers
        function [warnings, matches] = countWarning( ...
                warnings, label, recorded, actual)
            matches = isnan(recorded) || recorded == actual;
            if ~matches
                warnings(end + 1, 1) = sprintf( ...
                    'Recorded %s count is %g but the dataset contains %d.', ...
                    label, recorded, actual);
            end
        end

        function value = numericField(values, name, default)
            if isfield(values, name) && isnumeric(values.(name)) && ...
                    isscalar(values.(name))
                value = double(values.(name));
            else
                value = default;
            end
        end

        function value = vectorField(values, name, count)
            if isfield(values, name) && isnumeric(values.(name))
                value = double(values.(name)(:))';
                value = value(1:min(numel(value), max(0, round(count))));
            else
                value = [];
            end
        end

        function value = textField(values, name, default)
            if isfield(values, name) && ...
                    (ischar(values.(name)) || isstring(values.(name)))
                value = strtrim(char(values.(name)));
            else
                value = default;
            end
        end

        function value = lastTime(samples)
            if isempty(samples)
                value = NaN;
            else
                value = samples.ElapsedSeconds(end);
            end
        end

        function mask = segmentMask(times, startTime, stopTime, isLast)
            if isLast
                mask = times >= startTime & times <= stopTime;
            else
                mask = times >= startTime & times < stopTime;
            end
        end

        function name = fileName(path)
            [basePath, baseName, extension] = fileparts(path);
            [~, folderName] = fileparts(basePath);
            if strcmpi([baseName, extension], 'recording.h5') && ...
                    ~isempty(folderName)
                name = [folderName, filesep, baseName, extension];
            else
                name = [baseName, extension];
            end
        end

        function value = emptyPhaseTable()
            value = table('Size', [0, 12], ...
                'VariableTypes', {'string', 'double', 'double', 'string', ...
                'double', 'double', 'double', 'double', 'double', ...
                'double', 'double', 'double'}, ...
                'VariableNames', {'Axis', 'Segment', 'Status', 'Phase', ...
                'StartSeconds', 'StopSeconds', 'DurationSeconds', ...
                'SampleCount', 'ForceMin', 'ForceMax', ...
                'PositionMin', 'PositionMax'});
        end

        function value = emptyTargetTable()
            value = table('Size', [0, 19], ...
                'VariableTypes', {'string', 'string', 'string', 'double', ...
                'double', 'double', 'double', 'double', 'logical', ...
                'logical', 'double', 'double', 'double', 'double', ...
                'double', 'double', 'double', 'double', 'double'}, ...
                'VariableNames', {'Axis', 'Phase', 'Role', 'Status', ...
                'Target', 'Tolerance', 'ConfiguredHoldSeconds', ...
                'RequestedCount', 'Ambiguous', 'MetricsAvailable', ...
                'PhaseDurationSeconds', 'TimeToFirstToleranceSeconds', ...
                'DirectionalOvershoot', 'MeanErrorInTolerance', ...
                'StdErrorInTolerance', 'InToleranceFraction', ...
                'TotalInToleranceSeconds', ...
                'LongestContinuousInToleranceSeconds', ...
                'ToleranceEntryCount'});
        end

        function value = emptyDefinitionTable()
            value = table('Size', [0, 9], ...
                'VariableTypes', {'string', 'double', 'string', 'string', ...
                'double', 'double', 'double', 'double', 'logical'}, ...
                'VariableNames', {'Axis', 'Status', 'Phase', 'Role', ...
                'Target', 'Tolerance', 'ConfiguredHoldSeconds', ...
                'RequestedCount', 'Ambiguous'});
        end

        function value = emptySegmentTable()
            value = table('Size', [0, 6], ...
                'VariableTypes', {'double', 'double', 'string', ...
                'double', 'double', 'double'}, ...
                'VariableNames', {'Segment', 'Status', 'Phase', ...
                'StartSeconds', 'StopSeconds', 'DurationSeconds'});
        end
    end
end
