classdef AcquisitionBuffer < handle
    %ACQUISITIONBUFFER Holds unread X/Y samples between PLC and UI updates.

    properties (SetAccess = private)
        forceX = []
        forceY = []
        untaredForceX = []
        untaredForceY = []
        positionX = []
        positionY = []
        timestampX = NaT(1, 0)
        timestampY = NaT(1, 0)
    end

    methods
        function append(buffer, forceX, forceY, untaredX, untaredY, ...
                positionX, positionY, timestampX, timestampY)
            buffer.forceX = [buffer.forceX, forceX];
            buffer.forceY = [buffer.forceY, forceY];
            buffer.untaredForceX = [buffer.untaredForceX, untaredX];
            buffer.untaredForceY = [buffer.untaredForceY, untaredY];
            buffer.positionX = [buffer.positionX, positionX];
            buffer.positionY = [buffer.positionY, positionY];
            buffer.timestampX = [buffer.timestampX, timestampX];
            buffer.timestampY = [buffer.timestampY, timestampY];
        end

        function batch = plotBatch(buffer)
            batch = struct( ...
                'Force', struct( ...
                    'X', buffer.forceX, 'Y', buffer.forceY), ...
                'Displacement', struct( ...
                    'X', buffer.positionX, 'Y', buffer.positionY));
        end

        function flush(buffer, model)
            buffer.flushAxis(model, 'X');
            buffer.flushAxis(model, 'Y');
        end

        function clear(buffer)
            buffer.forceX = [];
            buffer.forceY = [];
            buffer.untaredForceX = [];
            buffer.untaredForceY = [];
            buffer.positionX = [];
            buffer.positionY = [];
            buffer.timestampX = NaT(1, 0);
            buffer.timestampY = NaT(1, 0);
        end
    end

    methods (Access = private)
        function flushAxis(buffer, model, axisName)
            if strcmp(axisName, 'X')
                force = buffer.forceX;
                untared = buffer.untaredForceX;
                position = buffer.positionX;
                timestamps = buffer.timestampX;
            else
                force = buffer.forceY;
                untared = buffer.untaredForceY;
                position = buffer.positionY;
                timestamps = buffer.timestampY;
            end
            if isempty(force) && isempty(untared) && isempty(position)
                return;
            end

            % Clear only after a successful write so a transient failure
            % cannot silently discard samples.
            model.saveAxisSamples( ...
                axisName, timestamps, force, untared, position);
            if strcmp(axisName, 'X')
                buffer.forceX = [];
                buffer.untaredForceX = [];
                buffer.positionX = [];
                buffer.timestampX = NaT(1, 0);
            else
                buffer.forceY = [];
                buffer.untaredForceY = [];
                buffer.positionY = [];
                buffer.timestampY = NaT(1, 0);
            end
        end
    end
end
