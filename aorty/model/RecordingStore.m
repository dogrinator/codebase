classdef RecordingStore < handle
    %RECORDINGSTORE Owns the two-file recording and append-only HDF5 data.

    properties (SetAccess = private)
        folderPath
        h5Path
        cameraPath
        startTime
        cameraRecordCount = 0
        axisRecordCounts = struct('X', 0, 'Y', 0)
    end

    properties (Access = private)
        cameraFid = -1
        h5FileId = []
        cameraDatasetId = []
        axisDatasetIds = struct('X', [], 'Y', [])
        expectedFrameBytes = 0
        closed = true
    end

    properties (Constant, Access = private)
        TEXT_STATUS_LENGTH = 16
        TEXT_REASON_LENGTH = 1024
        TEXT_TIME_LENGTH = 23
        DATASET_CHUNK_ROWS = 256
    end

    methods
        function store = RecordingStore(folderPath, header)
            store.folderPath = char(folderPath);
            store.h5Path = fullfile(store.folderPath, 'recording.h5');
            store.cameraPath = fullfile(store.folderPath, 'cam.bin');
            store.startTime = datetime('now');
            width = double(header.camera.width);
            height = double(header.camera.height);
            if isfinite(width) && isfinite(height) && ...
                    width > 0 && height > 0
                store.expectedFrameBytes = width * height;
            end

            existing = {};
            if isfile(store.h5Path), existing{end + 1} = 'recording.h5'; end
            if isfile(store.cameraPath), existing{end + 1} = 'cam.bin'; end
            if ~isempty(existing)
                error('Model:RecordingFilesExist', ...
                    ['The selected folder already contains recording ' ...
                    'data (%s). Choose a new or empty folder.'], ...
                    strjoin(existing, ', '));
            end

            try
                store.createHdf5(header);
                store.cameraFid = fopen(store.cameraPath, 'wb');
                if store.cameraFid == -1
                    error('Model:RecordingOpenFailed', ...
                        'Could not create %s.', store.cameraPath);
                end
                store.openPersistentHandles();
                store.closed = false;
            catch exception
                store.close();
                RecordingStore.deleteIfPresent(store.cameraPath);
                RecordingStore.deleteIfPresent(store.h5Path);
                rethrow(exception);
            end
        end

        function appendAxis(store, axisName, timestamps, ...
                forceValues, untaredForceValues, positionValues)
            store.requireOpen();
            axisName = upper(char(axisName));
            if ~ismember(axisName, {'X', 'Y'})
                error('Model:RecordingAxis', ...
                    'Recording axis must be X or Y.');
            end
            counts = [numel(timestamps), numel(forceValues), ...
                numel(untaredForceValues), numel(positionValues)];
            if any(counts ~= counts(1))
                error('Model:RecordingVectorLength', ...
                    ['%s-axis timestamps, force, untared force, and ' ...
                    'position vectors must have equal lengths.'], axisName);
            end
            if counts(1) == 0
                return;
            end

            elapsed = seconds(timestamps(:) - store.startTime);
            values = [double(elapsed(:))'; double(forceValues(:))'; ...
                double(untaredForceValues(:))'; ...
                double(positionValues(:))'];
            if any(~isfinite(values), 'all')
                error('Model:RecordingValues', ...
                    '%s-axis samples must be finite.', axisName);
            end
            current = store.axisRecordCounts.(axisName);
            store.appendDataset( ...
                store.axisDatasetIds.(axisName), values, current);
            store.axisRecordCounts.(axisName) = current + counts(1);
        end

        function appendFrame(store, frame, timestamp, index, systemStatus)
            store.requireOpen();
            frame = uint8(frame);
            if store.expectedFrameBytes > 0 && ...
                    numel(frame) ~= store.expectedFrameBytes
                error('Model:CameraFrameSize', ...
                    ['Camera frame %d has %d byte(s); the recording ' ...
                    'header requires %d.'], index, numel(frame), ...
                    store.expectedFrameBytes);
            end
            validStatuses = int16([0, 1, 2, 3, 4, 5, 6, ...
                10, 11, 20, 21, 30]);
            if ~ismember(int16(systemStatus), validStatuses)
                error('Model:InvalidSystemStatus', ...
                    'Camera frame %d has invalid SystemStatus %d.', ...
                    index, systemStatus);
            end
            written = fwrite(store.cameraFid, frame, 'uint8');
            if written ~= numel(frame)
                error('Model:RecordingWriteFailed', ...
                    'Could not write camera frame %d.', index);
            end

            elapsed = seconds(timestamp - store.startTime);
            record = [double(index); double(elapsed); double(systemStatus)];
            if any(~isfinite(record))
                error('Model:RecordingValues', ...
                    'Camera frame metadata must be finite.');
            end
            store.appendDataset( ...
                store.cameraDatasetId, record, store.cameraRecordCount);
            store.cameraRecordCount = store.cameraRecordCount + 1;
        end

        function finalize(store, status, reason, integrity)
            if store.closed
                return;
            end
            if nargin < 4 || isempty(integrity)
                integrity = struct( ...
                    'droppedSamples', struct('X', 0, 'Y', 0), ...
                    'restartDetected', false);
            end
            status = lower(char(status));
            reason = char(reason);
            endTime = datetime('now');
            store.flush();
            store.close();

            RecordingStore.writeFixedTextAttribute( ...
                store.h5Path, '/metadata', 'status', status, ...
                store.TEXT_STATUS_LENGTH);
            RecordingStore.writeFixedTextAttribute( ...
                store.h5Path, '/metadata', 'reason', reason, ...
                store.TEXT_REASON_LENGTH);
            RecordingStore.writeFixedTextAttribute( ...
                store.h5Path, '/metadata', 'end_time', ...
                RecordingStore.formatTime(endTime), ...
                store.TEXT_TIME_LENGTH);
            h5writeatt(store.h5Path, '/metadata', ...
                'camera_record_count', uint64(store.cameraRecordCount));
            h5writeatt(store.h5Path, '/metadata', ...
                'x_sample_count', uint64(store.axisRecordCounts.X));
            h5writeatt(store.h5Path, '/metadata', ...
                'y_sample_count', uint64(store.axisRecordCounts.Y));
            h5writeatt(store.h5Path, '/metadata', ...
                'x_dropped_sample_count', ...
                uint64(integrity.droppedSamples.X));
            h5writeatt(store.h5Path, '/metadata', ...
                'y_dropped_sample_count', ...
                uint64(integrity.droppedSamples.Y));
            h5writeatt(store.h5Path, '/metadata', ...
                'sample_loss_detected', uint8( ...
                integrity.droppedSamples.X > 0 || ...
                integrity.droppedSamples.Y > 0));
            h5writeatt(store.h5Path, '/metadata', ...
                'plc_restart_detected', ...
                uint8(logical(integrity.restartDetected)));
        end

        function flush(store)
            if ~store.closed && ~isempty(store.h5FileId)
                H5F.flush(store.h5FileId, 'H5F_SCOPE_LOCAL');
            end
        end

        function close(store)
            if ~isempty(store.cameraDatasetId)
                try H5D.close(store.cameraDatasetId); catch, end
                store.cameraDatasetId = [];
            end
            for axisName = {'X', 'Y'}
                axis = axisName{1};
                if ~isempty(store.axisDatasetIds.(axis))
                    try H5D.close(store.axisDatasetIds.(axis)); catch, end
                    store.axisDatasetIds.(axis) = [];
                end
            end
            if ~isempty(store.h5FileId)
                try H5F.close(store.h5FileId); catch, end
                store.h5FileId = [];
            end
            if store.cameraFid ~= -1
                try fclose(store.cameraFid); catch, end
                store.cameraFid = -1;
            end
            store.closed = true;
        end

        function delete(store)
            store.close();
        end
    end

    methods (Access = private)
        function createHdf5(store, header)
            h5create(store.h5Path, '/metadata/schema_version', [1 1], ...
                'Datatype', 'uint32');
            h5write(store.h5Path, '/metadata/schema_version', uint32(1));
            h5create(store.h5Path, '/camera/records', [3 Inf], ...
                'ChunkSize', [3 store.DATASET_CHUNK_ROWS], ...
                'Datatype', 'double');
            h5create(store.h5Path, '/plc/X/samples', [4 Inf], ...
                'ChunkSize', [4 store.DATASET_CHUNK_ROWS], ...
                'Datatype', 'double');
            h5create(store.h5Path, '/plc/Y/samples', [4 Inf], ...
                'ChunkSize', [4 store.DATASET_CHUNK_ROWS], ...
                'Datatype', 'double');
            RecordingStore.createMarker( ...
                store.h5Path, '/settings/plc/X/marker');
            RecordingStore.createMarker( ...
                store.h5Path, '/settings/plc/Y/marker');
            RecordingStore.createMarker( ...
                store.h5Path, '/settings/test/marker');
            RecordingStore.createMarker( ...
                store.h5Path, '/settings/test/X/marker');
            RecordingStore.createMarker( ...
                store.h5Path, '/settings/test/Y/marker');

            RecordingStore.writeFixedTextAttribute( ...
                store.h5Path, '/metadata', 'start_time', ...
                RecordingStore.formatTime(store.startTime), ...
                store.TEXT_TIME_LENGTH);
            RecordingStore.writeFixedTextAttribute( ...
                store.h5Path, '/metadata', 'end_time', '', ...
                store.TEXT_TIME_LENGTH);
            RecordingStore.writeFixedTextAttribute( ...
                store.h5Path, '/metadata', 'status', 'recording', ...
                store.TEXT_STATUS_LENGTH);
            RecordingStore.writeFixedTextAttribute( ...
                store.h5Path, '/metadata', 'reason', '', ...
                store.TEXT_REASON_LENGTH);
            h5writeatt(store.h5Path, '/metadata', ...
                'application_version', char(header.applicationVersion));
            h5writeatt(store.h5Path, '/metadata', ...
                'plc_interface_version', uint32(header.interfaceVersion));
            h5writeatt(store.h5Path, '/metadata', ...
                'plc_interval_seconds', double(header.plcInterval));
            h5writeatt(store.h5Path, '/metadata', ...
                'status_resolution_seconds', ...
                double(header.statusResolutionSeconds));
            h5writeatt(store.h5Path, '/metadata', ...
                'camera_record_count', uint64(0));
            h5writeatt(store.h5Path, '/metadata', ...
                'x_sample_count', uint64(0));
            h5writeatt(store.h5Path, '/metadata', ...
                'y_sample_count', uint64(0));
            h5writeatt(store.h5Path, '/metadata', ...
                'x_dropped_sample_count', uint64(0));
            h5writeatt(store.h5Path, '/metadata', ...
                'y_dropped_sample_count', uint64(0));
            h5writeatt(store.h5Path, '/metadata', ...
                'sample_loss_detected', uint8(0));
            h5writeatt(store.h5Path, '/metadata', ...
                'plc_restart_detected', uint8(0));

            RecordingStore.writeStructAttributes( ...
                store.h5Path, '/camera', header.camera);
            RecordingStore.writeStructAttributes( ...
                store.h5Path, '/settings/plc/X', header.plc.X);
            RecordingStore.writeStructAttributes( ...
                store.h5Path, '/settings/plc/Y', header.plc.Y);
            RecordingStore.writeStructAttributes( ...
                store.h5Path, '/settings/test', ...
                rmfield(header.test, {'commands'}));
            for axisName = {'X', 'Y'}
                axis = axisName{1};
                command = header.test.commands.(axis);
                if ~isempty(command)
                    RecordingStore.writeStructAttributes( ...
                        store.h5Path, ['/settings/test/', axis], command);
                end
            end
            h5writeatt(store.h5Path, '/camera/records', ...
                'columns', 'frame_index,elapsed_seconds,system_status');
            h5writeatt(store.h5Path, '/plc/X/samples', ...
                'columns', ...
                'elapsed_seconds,force,untared_force,position');
            h5writeatt(store.h5Path, '/plc/Y/samples', ...
                'columns', ...
                'elapsed_seconds,force,untared_force,position');
        end

        function openPersistentHandles(store)
            store.h5FileId = H5F.open( ...
                store.h5Path, 'H5F_ACC_RDWR', 'H5P_DEFAULT');
            store.cameraDatasetId = H5D.open( ...
                store.h5FileId, '/camera/records');
            store.axisDatasetIds.X = H5D.open( ...
                store.h5FileId, '/plc/X/samples');
            store.axisDatasetIds.Y = H5D.open( ...
                store.h5FileId, '/plc/Y/samples');
        end

        function appendDataset(~, datasetId, values, currentCount)
            fieldCount = size(values, 1);
            recordCount = size(values, 2);
            H5D.set_extent(datasetId, ...
                [currentCount + recordCount, fieldCount]);
            fileSpace = H5D.get_space(datasetId);
            fileCleanup = onCleanup(@() H5S.close(fileSpace));
            H5S.select_hyperslab(fileSpace, 'H5S_SELECT_SET', ...
                [currentCount, 0], [], [recordCount, fieldCount], []);
            memorySpace = H5S.create_simple( ...
                2, [recordCount, fieldCount], []);
            memoryCleanup = onCleanup(@() H5S.close(memorySpace));
            H5D.write(datasetId, 'H5ML_DEFAULT', memorySpace, ...
                fileSpace, 'H5P_DEFAULT', values);
            clear memoryCleanup fileCleanup;
        end

        function requireOpen(store)
            if store.closed
                error('Model:RecordingClosed', ...
                    'The recording store is not open.');
            end
        end
    end

    methods (Static, Access = private)
        function createMarker(filename, path)
            h5create(filename, path, [1 1], 'Datatype', 'uint8');
            h5write(filename, path, uint8(1));
        end

        function writeStructAttributes(filename, target, values)
            names = fieldnames(values);
            for index = 1:numel(names)
                name = names{index};
                value = values.(name);
                if islogical(value)
                    value = uint8(value);
                elseif isstring(value)
                    value = char(strjoin(value(:)', ','));
                elseif iscell(value)
                    value = strjoin(cellfun(@char, value, ...
                        'UniformOutput', false), ',');
                elseif isempty(value)
                    h5writeatt(filename, target, ...
                        [name, '_count'], uint32(0));
                    continue;
                end
                if isstruct(value)
                    error('Model:RecordingHeader', ...
                        'Nested recording header field %s is unsupported.', ...
                        name);
                end
                h5writeatt(filename, target, name, value);
                if isnumeric(value) && ~isscalar(value)
                    h5writeatt(filename, target, ...
                        [name, '_count'], uint32(numel(value)));
                end
            end
        end

        function writeFixedTextAttribute( ...
                filename, target, name, value, width)
            value = char(value);
            if numel(value) > width
                value = value(1:width);
            end
            value(end + 1:width) = ' ';
            h5writeatt(filename, target, name, value);
        end

        function value = formatTime(timestamp)
            value = char(string(timestamp, ...
                'yyyy-MM-dd HH:mm:ss.SSS'));
        end

        function deleteIfPresent(filename)
            if isfile(filename)
                delete(filename);
            end
        end
    end
end
