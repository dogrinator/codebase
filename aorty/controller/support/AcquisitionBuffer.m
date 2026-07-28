classdef AcquisitionBuffer < handle
    %ACQUISITIONBUFFER Holds unread X/Y samples between PLC and UI updates.

    properties (SetAccess = private)
        forceX = []
        forceY = []
        untaredForceX = []
        untaredForceY = []
        positionX = []
        positionY = []
    end

    methods
        function append(buffer, forceX, forceY, untaredX, untaredY, ...
                positionX, positionY)
            buffer.forceX = [buffer.forceX, forceX];
            buffer.forceY = [buffer.forceY, forceY];
            buffer.untaredForceX = [buffer.untaredForceX, untaredX];
            buffer.untaredForceY = [buffer.untaredForceY, untaredY];
            buffer.positionX = [buffer.positionX, positionX];
            buffer.positionY = [buffer.positionY, positionY];
        end

        function [xValues, yValues] = plotValues(buffer, mode)
            if strcmpi(char(mode), 'Force')
                xValues = buffer.forceX;
                yValues = buffer.forceY;
            else
                xValues = buffer.positionX;
                yValues = buffer.positionY;
            end
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
        end
    end

    methods (Access = private)
        function flushAxis(buffer, model, axisName)
            if strcmp(axisName, 'X')
                force = buffer.forceX;
                untared = buffer.untaredForceX;
                position = buffer.positionX;
            else
                force = buffer.forceY;
                untared = buffer.untaredForceY;
                position = buffer.positionY;
            end
            if isempty(force) && isempty(untared) && isempty(position)
                return;
            end

            % Clear only after a successful write so a transient failure
            % cannot silently discard samples.
            model.saveAxisSamples(axisName, force, untared, position);
            if strcmp(axisName, 'X')
                buffer.forceX = [];
                buffer.untaredForceX = [];
                buffer.positionX = [];
            else
                buffer.forceY = [];
                buffer.untaredForceY = [];
                buffer.positionY = [];
            end
        end
    end
end
