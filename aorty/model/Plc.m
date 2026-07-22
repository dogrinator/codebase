classdef Plc < handle
    % Typed ADS interface for the two-axis TwinCAT application.

    properties
        model Model
        amsNetID = '5.85.113.174.1.1'
        dllPath = 'C:\Program Files (x86)\Beckhoff\TwinCAT\3.1\Components\Plc\LacBinaries\GAC_MSIL\TwinCAT.Ads\4.3.28.0__180016cd49e5e8c3\TwinCAT.Ads.dll'
        client
        connected = false

        handles = struct()
        netBuffers = struct()
        arrayLengths
        lastSampleCounter = struct('X', [], 'Y', [])
        droppedSamples = struct('X', 0, 'Y', 0)
        status = struct('X', struct(), 'Y', struct())

        isWorking = false
        totalTimeX = 0
        totalTimeY = 0
        ts = 0.01

        % Compatibility aliases used by older controller code.
        hHaltX
        hHaltY
    end

    methods
        % Plc handles this operation.
        function plc = Plc(model)
            plc.model = model;
        end

        % connectPLC handles this operation.
        function connectPLC(plc, app, src)
            if src.Value ~= "ON"
                plc.disconnectPLC();
                return;
            end

            try
                plc.disconnectPLC();
                NET.addAssembly(plc.dllPath);
                plc.client = TwinCAT.Ads.TcAdsClient();
                plc.client.Connect(plc.amsNetID, 851);
                plc.handles.X = plc.createAxisHandles('X');
                plc.handles.Y = plc.createAxisHandles('Y');
                plc.hHaltX = plc.handles.X.command.halt;
                plc.hHaltY = plc.handles.Y.command.halt;

                plc.arrayLengths = NET.createArray('System.Int32', 1);
                plc.arrayLengths(1) = 150;
                plc.netBuffers.X.distance = NET.createArray('System.Double', 100);
                plc.netBuffers.X.velocity = NET.createArray('System.Double', 100);
                plc.netBuffers.Y.distance = NET.createArray('System.Double', 100);
                plc.netBuffers.Y.velocity = NET.createArray('System.Double', 100);

                plc.resetStreamingState();
                plc.connected = true;
                disp('PLC connected.');
            catch exception
                plc.disconnectPLC();
                src.Value = "OFF";
                uialert(app.fig, exception.message, 'PLC connection error');
            end
        end

        % disconnectPLC handles this operation.
        function disconnectPLC(plc)
            if ~isempty(plc.client)
                try
                    plc.deleteHandleTree(plc.handles);
                catch exception
                    warning('PLC:HandleCleanup', 'Could not delete all ADS handles: %s', exception.message);
                end
                try
                    plc.client.Disconnect();
                    plc.client.Dispose();
                catch
                end
            end
            plc.client = [];
            plc.handles = struct();
            plc.connected = false;
            plc.isWorking = false;
            plc.resetStreamingState();
        end

        % fifoProcess handles this operation.
        function [forceX, forceY, untaredX, untaredY, posX, posY, statuses] = fifoProcess(plc)
            plc.requireConnection();
            [forceX, posX, plc.status.X] = plc.readAxisSnapshot('X');
            [forceY, posY, plc.status.Y] = plc.readAxisSnapshot('Y');
            untaredX = forceX - plc.status.X.tareOffset;
            untaredY = forceY - plc.status.Y.tareOffset;
            plc.isWorking = plc.status.X.working || plc.status.Y.working;
            statuses = plc.status;
        end

        % pollStatus handles this operation.
        function statuses = pollStatus(plc)
            plc.requireConnection();
            plc.status.X = plc.readAxisStatus('X');
            plc.status.Y = plc.readAxisStatus('Y');
            plc.isWorking = plc.status.X.working || plc.status.Y.working;
            statuses = plc.status;
        end

        % SendCommands handles this operation.
        function accepted = SendCommands(plc, mode, xPos, xVel, yPos, yVel)
            accepted = false;
            plc.requireConnection();
            statuses = plc.pollStatus();
            activeX = ~isempty(xPos);
            activeY = ~isempty(yPos);
            if (activeX && statuses.X.working) || (activeY && statuses.Y.working)
                error('PLC:Busy', 'An active axis is already working.');
            end
            if activeX, plc.ensureAxisPowered('X'); end
            if activeY, plc.ensureAxisPowered('Y'); end
            if activeX
                plc.sendAxisTrajectory('X', mode, xPos, xVel, true);
            end
            if activeY
                plc.sendAxisTrajectory('Y', mode, yPos, yVel, true);
            end
            accepted = activeX || activeY;
        end

        % sendSingleTest handles this operation.
        function sendSingleTest(plc, axisName, controlMode, rate, stop1Mode, stop1Value, stop2Mode, stop2Value)
            plc.requireConnection();
            axisName = upper(char(axisName));
            values = [double(rate), double(stop1Value), double(stop2Value)];
            if any(~isfinite(values)) || rate == 0
                error('PLC:InvalidSingleTest', 'Single-test values must be finite and the rate must be non-zero.');
            end
            statusNow = plc.readAxisStatus(axisName);
            if statusNow.working || statusNow.error
                error('PLC:AxisUnavailable', '%s axis is busy or in error.', axisName);
            end
            plc.ensureAxisPowered(axisName);
            command = plc.handles.(axisName).command;
            plc.writeInt(command.mode, 4);
            plc.writeInt(command.singleControlMode, controlMode);
            plc.writeLreal(command.singleRate, rate);
            plc.writeInt(command.stop1Mode, stop1Mode);
            plc.writeLreal(command.stop1Value, stop1Value);
            plc.writeInt(command.stop2Mode, stop2Mode);
            plc.writeLreal(command.stop2Value, stop2Value);
            plc.writeBool(command.execute, true);
        end

        % jog handles this operation.
        function jog(plc, axisName, distance, velocity)
            if ~isfinite(distance) || distance == 0 || ~isfinite(velocity) || velocity <= 0
                error('PLC:InvalidJog', 'Jog distance must be non-zero and velocity must be positive.');
            end
            plc.sendAxisTrajectory(axisName, 1, distance, velocity);
        end

        % stop handles this operation.
        function stop(plc, axes)
            plc.writeCommandForAxes(axes, 'halt');
        end

        % resetErrors handles this operation.
        function resetErrors(plc, axes)
            plc.writeCommandForAxes(axes, 'reset');
        end

        % tare handles this operation.
        function tare(plc, axes)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            for index = 1:numel(axes)
                axisName = axes{index};
                statusNow = plc.readAxisStatus(axisName);
                if statusNow.working || statusNow.error
                    error('PLC:AxisUnavailable', '%s axis is busy or in error.', axisName);
                end
                plc.writeBool(plc.handles.(axisName).command.tare, true);
            end
        end

        % moveToLowerLimit handles this operation.
        function moveToLowerLimit(plc, axes)
            axes = plc.normalizeAxes(axes);
            for index = 1:numel(axes)
                axisName = axes{index};
                statusNow = plc.readAxisStatus(axisName);
                if statusNow.working || statusNow.error
                    error('PLC:AxisUnavailable', '%s axis is busy or in error.', axisName);
                end
                plc.ensureAxisPowered(axisName);
                plc.writeBool(plc.handles.(axisName).command.home, true);
            end
        end

        % setPower handles this operation.
        function setPower(plc, axes, enabled)
            axes = plc.normalizeAxes(axes);
            for index = 1:numel(axes)
                plc.writeBool(plc.handles.(axes{index}).command.power, logical(enabled));
            end
        end

        % ensurePowered handles this operation.
        function ensurePowered(plc, axes)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            for index = 1:numel(axes)
                plc.ensureAxisPowered(axes{index});
            end
        end

        % writeAxisConfig handles this operation.
        function writeAxisConfig(plc, axisCfg, axisName)
            plc.requireConnection();
            values = [axisCfg.fTenzoCons, axisCfg.fTenzoOffset, axisCfg.fKp, axisCfg.fKi, ...
                axisCfg.fIntegralLimit, axisCfg.fForceTolerance, axisCfg.fMaxVelocity, ...
                axisCfg.fMaxForce, axisCfg.fMaxPosition];
            if any(~isfinite(double(values))) || axisCfg.fTenzoCons == 0 || ...
                    axisCfg.fIntegralLimit < 0 || axisCfg.fForceTolerance < 0 || ...
                    axisCfg.fMaxVelocity <= 0 || axisCfg.fMaxForce <= 0 || axisCfg.fMaxPosition <= 0
                error('PLC:InvalidConfiguration', 'Hardware configuration contains invalid values.');
            end
            settings = plc.handles.(upper(char(axisName))).settings;
            plc.writeLreal(settings.tenzoCons, axisCfg.fTenzoCons);
            plc.writeLreal(settings.tenzoOffset, axisCfg.fTenzoOffset);
            plc.writeLreal(settings.kp, axisCfg.fKp);
            plc.writeLreal(settings.ki, axisCfg.fKi);
            plc.writeLreal(settings.integralLimit, axisCfg.fIntegralLimit);
            plc.writeLreal(settings.forceTolerance, axisCfg.fForceTolerance);
            plc.writeLreal(settings.maxVelocity, axisCfg.fMaxVelocity);
            plc.writeLreal(settings.maxForce, axisCfg.fMaxForce);
            plc.writeLreal(settings.maxPosition, axisCfg.fMaxPosition);
        end

    end

    methods (Access = private)
        % createAxisHandles handles this operation.
        function handles = createAxisHandles(plc, axisName)
            statusRoot = sprintf('MAIN.stSystemStatus%s.', axisName);
            commandRoot = sprintf('MAIN.stMoveCommand%s.', axisName);
            settingsRoot = sprintf('MAIN.stSettings%s.', axisName);

            handles.status = struct( ...
                'working', plc.makeHandle(statusRoot + "bWorking"), ...
                'head', plc.makeHandle(statusRoot + "nBufferHead"), ...
                'sampleCounter', plc.makeHandle(statusRoot + "nSampleCounter"), ...
                'operationCounter', plc.makeHandle(statusRoot + "nOperationCounter"), ...
                'forceBuffer', plc.makeHandle(statusRoot + "fTenzoBuffer"), ...
                'positionBuffer', plc.makeHandle(statusRoot + "fPosBuffer"), ...
                'tareOffset', plc.makeHandle(statusRoot + "fTenzoTarOffset"), ...
                'tareWorking', plc.makeHandle(statusRoot + "bTarWorking"), ...
                'error', plc.makeHandle(statusRoot + "bError"), ...
                'errorCode', plc.makeHandle(statusRoot + "nErrorCode"), ...
                'axisErrorID', plc.makeHandle(statusRoot + "nAxisErrorID"), ...
                'powered', plc.makeHandle(statusRoot + "bPowered"), ...
                'homing', plc.makeHandle(statusRoot + "bHoming"), ...
                'homed', plc.makeHandle(statusRoot + "bHomed"), ...
                'stopped', plc.makeHandle(statusRoot + "bStopped"), ...
                'actPosition', plc.makeHandle(statusRoot + "fActPosition"));

            handles.command = struct( ...
                'distance', plc.makeHandle(commandRoot + "fDistances"), ...
                'velocity', plc.makeHandle(commandRoot + "fVelocities"), ...
                'total', plc.makeHandle(commandRoot + "nTotalSteps"), ...
                'mode', plc.makeHandle(commandRoot + "nMode"), ...
                'execute', plc.makeHandle(commandRoot + "bExecute"), ...
                'halt', plc.makeHandle(commandRoot + "bHalt"), ...
                'power', plc.makeHandle(commandRoot + "bPower"), ...
                'reset', plc.makeHandle(commandRoot + "bReset"), ...
                'home', plc.makeHandle(commandRoot + "bHome"), ...
                'tare', plc.makeHandle(commandRoot + "bStartTar"), ...
                'singleControlMode', plc.makeHandle(commandRoot + "nSingleControlMode"), ...
                'singleRate', plc.makeHandle(commandRoot + "fSingleRate"), ...
                'stop1Mode', plc.makeHandle(commandRoot + "nStop1Mode"), ...
                'stop1Value', plc.makeHandle(commandRoot + "fStop1Value"), ...
                'stop2Mode', plc.makeHandle(commandRoot + "nStop2Mode"), ...
                'stop2Value', plc.makeHandle(commandRoot + "fStop2Value"));

            handles.settings = struct( ...
                'tenzoCons', plc.makeHandle(settingsRoot + "fTenzoCons"), ...
                'tenzoOffset', plc.makeHandle(settingsRoot + "fTenzoOffset"), ...
                'kp', plc.makeHandle(settingsRoot + "fKp"), ...
                'ki', plc.makeHandle(settingsRoot + "fKi"), ...
                'integralLimit', plc.makeHandle(settingsRoot + "fIntegralLimit"), ...
                'forceTolerance', plc.makeHandle(settingsRoot + "fForceTolerance"), ...
                'maxVelocity', plc.makeHandle(settingsRoot + "fMaxVelocity"), ...
                'maxForce', plc.makeHandle(settingsRoot + "fMaxForce"), ...
                'maxPosition', plc.makeHandle(settingsRoot + "fMaxPosition"));
        end

        % makeHandle handles this operation.
        function handle = makeHandle(plc, symbol)
            handle = int32(plc.client.CreateVariableHandle(char(symbol)));
        end

        % readAxisSnapshot handles this operation.
        function [forceData, positionData, statusNow] = readAxisSnapshot(plc, axisName)
            statusHandles = plc.handles.(axisName).status;
            for attempt = 1:2
                counterBefore = plc.readUdint(statusHandles.sampleCounter);
                head = double(plc.readInt(statusHandles.head));
                forceBuffer = double(plc.client.ReadAny(statusHandles.forceBuffer, ...
                    System.Type.GetType('System.Double[]'), plc.arrayLengths));
                positionBuffer = double(plc.client.ReadAny(statusHandles.positionBuffer, ...
                    System.Type.GetType('System.Double[]'), plc.arrayLengths));
                counterAfter = plc.readUdint(statusHandles.sampleCounter);
                if counterBefore == counterAfter
                    break;
                end
            end

            statusNow = plc.readAxisStatus(axisName);
            previous = plc.lastSampleCounter.(axisName);
            if isempty(previous)
                plc.lastSampleCounter.(axisName) = double(counterAfter);
                forceData = [];
                positionData = [];
                return;
            end

            if double(counterAfter) < double(previous) && double(previous) < (2^32 - 150)
                % Counter moved backwards away from its natural wrap point: PLC restarted.
                plc.lastSampleCounter.(axisName) = double(counterAfter);
                forceData = [];
                positionData = [];
                return;
            end
            count = mod(double(counterAfter) - double(previous), 2^32);
            plc.lastSampleCounter.(axisName) = double(counterAfter);
            if count == 0
                forceData = [];
                positionData = [];
                return;
            end
            if count > 150
                plc.droppedSamples.(axisName) = plc.droppedSamples.(axisName) + count - 150;
                count = 150;
            end
            startIndex = mod(head - count, 150) + 1;
            indices = mod((startIndex - 1) + (0:count-1), 150) + 1;
            forceData = forceBuffer(indices);
            positionData = positionBuffer(indices);
        end

        % readAxisStatus handles this operation.
        function statusNow = readAxisStatus(plc, axisName)
            h = plc.handles.(axisName).status;
            statusNow = struct( ...
                'working', plc.readBool(h.working), ...
                'tareOffset', plc.readLreal(h.tareOffset), ...
                'tareWorking', plc.readBool(h.tareWorking), ...
                'error', plc.readBool(h.error), ...
                'errorCode', plc.readUdint(h.errorCode), ...
                'axisErrorID', plc.readUdint(h.axisErrorID), ...
                'powered', plc.readBool(h.powered), ...
                'homing', plc.readBool(h.homing), ...
                'homed', plc.readBool(h.homed), ...
                'stopped', plc.readBool(h.stopped), ...
                'position', plc.readLreal(h.actPosition));
            statusNow.operationCounter = plc.readUdint(h.operationCounter);
        end

        % sendAxisTrajectory handles this operation.
        function sendAxisTrajectory(plc, axisName, mode, distances, velocities, powerConfirmed)
            if nargin < 6
                powerConfirmed = false;
            end
            axisName = upper(char(axisName));
            distances = double(distances(:)');
            velocities = double(velocities(:)');
            if isempty(distances) || numel(distances) ~= numel(velocities) || numel(distances) > 100
                error('PLC:InvalidTrajectory', 'Trajectory arrays must have equal lengths from 1 to 100.');
            end
            if any(~isfinite(distances)) || any(~isfinite(velocities))
                error('PLC:InvalidTrajectory', 'Trajectory values must be finite.');
            end
            statusNow = plc.readAxisStatus(axisName);
            if statusNow.working || statusNow.error
                error('PLC:AxisUnavailable', '%s axis is busy or in error.', axisName);
            end
            if ~powerConfirmed
                plc.ensureAxisPowered(axisName);
            end

            distanceBuffer = zeros(1, 100);
            velocityBuffer = zeros(1, 100);
            distanceBuffer(1:numel(distances)) = distances;
            velocityBuffer(1:numel(velocities)) = velocities;
            for index = 1:100
                plc.netBuffers.(axisName).distance(index) = distanceBuffer(index);
                plc.netBuffers.(axisName).velocity(index) = velocityBuffer(index);
            end
            command = plc.handles.(axisName).command;
            plc.client.WriteAny(command.distance, plc.netBuffers.(axisName).distance);
            plc.client.WriteAny(command.velocity, plc.netBuffers.(axisName).velocity);
            plc.writeInt(command.total, numel(distances));
            plc.writeInt(command.mode, mode);
            plc.writeBool(command.execute, true);
        end

        % ensureAxisPowered handles this operation.
        function ensureAxisPowered(plc, axisName)
            statusNow = plc.readAxisStatus(axisName);
            if statusNow.powered
                return;
            end
            plc.writeBool(plc.handles.(axisName).command.power, true);
            deadline = tic;
            while toc(deadline) < 5
                pause(0.05);
                drawnow limitrate;
                statusNow = plc.readAxisStatus(axisName);
                if statusNow.error
                    error('PLC:PowerError', '%s', PlcErrorCatalog.describe( ...
                        axisName, statusNow.errorCode, statusNow.axisErrorID));
                end
                if statusNow.powered
                    return;
                end
            end
            error('PLC:PowerTimeout', '%s axis did not power on within 5 seconds.', axisName);
        end

        % writeCommandForAxes handles this operation.
        function writeCommandForAxes(plc, axes, commandName)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            for index = 1:numel(axes)
                plc.writeBool(plc.handles.(axes{index}).command.(commandName), true);
            end
        end

        % normalizeAxes handles this operation.
        function axes = normalizeAxes(~, axes)
            if ischar(axes) || isstring(axes)
                value = char(axes);
                if strcmpi(value, 'Both')
                    axes = {'X', 'Y'};
                elseif strcmpi(value, 'X only') || strcmpi(value, 'X')
                    axes = {'X'};
                elseif strcmpi(value, 'Y only') || strcmpi(value, 'Y')
                    axes = {'Y'};
                else
                    error('PLC:InvalidAxes', 'Unknown axis selection: %s', value);
                end
            end
        end

        % readBool handles this operation.
        function value = readBool(plc, handle)
            value = logical(plc.client.ReadAny(handle, System.Type.GetType('System.Boolean')));
        end

        % readInt handles this operation.
        function value = readInt(plc, handle)
            value = int16(plc.client.ReadAny(handle, System.Type.GetType('System.Int16')));
        end

        % readUdint handles this operation.
        function value = readUdint(plc, handle)
            value = uint32(plc.client.ReadAny(handle, System.Type.GetType('System.UInt32')));
        end

        % readLreal handles this operation.
        function value = readLreal(plc, handle)
            value = double(plc.client.ReadAny(handle, System.Type.GetType('System.Double')));
        end

        % writeBool handles this operation.
        function writeBool(plc, handle, value)
            plc.client.WriteAny(handle, logical(value));
        end

        % writeInt handles this operation.
        function writeInt(plc, handle, value)
            plc.client.WriteAny(handle, int16(value));
        end

        % writeLreal handles this operation.
        function writeLreal(plc, handle, value)
            plc.client.WriteAny(handle, double(value));
        end

        % requireConnection handles this operation.
        function requireConnection(plc)
            if ~plc.connected || isempty(plc.client)
                error('PLC:Disconnected', 'PLC is disconnected.');
            end
        end

        % resetStreamingState handles this operation.
        function resetStreamingState(plc)
            plc.lastSampleCounter = struct('X', [], 'Y', []);
            plc.droppedSamples = struct('X', 0, 'Y', 0);
            plc.totalTimeX = 0;
            plc.totalTimeY = 0;
        end

        % deleteHandleTree handles this operation.
        function deleteHandleTree(plc, value)
            if isstruct(value)
                names = fieldnames(value);
                for index = 1:numel(names)
                    plc.deleteHandleTree(value.(names{index}));
                end
            elseif ~isempty(value)
                plc.client.DeleteVariableHandle(value);
            end
        end
    end
end

