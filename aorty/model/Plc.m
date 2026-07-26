classdef Plc < handle
    %PLC Typed ADS interface for the two-axis TwinCAT application.

    properties (Constant)
        EXPECTED_INTERFACE_VERSION = uint32(3)
        COMMAND_ARRAY_LENGTH = 100
        STATUS_BUFFER_LENGTH = 150
    end

    properties
        model Model
        amsNetID = '5.85.113.174.1.1'
        adsPort = 851
        dllPath = 'C:\Program Files (x86)\Beckhoff\TwinCAT\3.1\Components\Plc\LacBinaries\GAC_MSIL\TwinCAT.Ads\4.3.28.0__180016cd49e5e8c3\TwinCAT.Ads.dll'
        client
        connected = false
        disconnecting = false

        handles = struct()
        netBuffers = struct()
        statusArrayLengths
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
        function plc = Plc(model)
            plc.model = model;
        end

        function connectPLC(plc, app, src)
            if src.Value ~= "ON"
                plc.disconnectPLC();
                app.updateMachineStatus([], false);
                return;
            end

            try
                plc.disconnectPLC();
                NET.addAssembly(plc.dllPath);
                plc.client = TwinCAT.Ads.TcAdsClient();
                plc.client.Connect(plc.amsNetID, plc.adsPort);
                try
                    versionHandleX = plc.makeHandle( ...
                        'MAIN.stSystemStatusX.nInterfaceVersion');
                    versionHandleY = plc.makeHandle( ...
                        'MAIN.stSystemStatusY.nInterfaceVersion');
                    versionX = plc.readUdint(versionHandleX);
                    versionY = plc.readUdint(versionHandleY);
                    plc.client.DeleteVariableHandle(versionHandleX);
                    plc.client.DeleteVariableHandle(versionHandleY);
                catch versionException
                    if exist('versionHandleX', 'var')
                        try
                            plc.client.DeleteVariableHandle(versionHandleX);
                        catch
                        end
                    end
                    if exist('versionHandleY', 'var')
                        try
                            plc.client.DeleteVariableHandle(versionHandleY);
                        catch
                        end
                    end
                    error('PLC:InterfaceVersion', ...
                        ['PLC does not expose interface version 3. Build and ' ...
                        'deploy the matching TwinCAT project and regenerate ' ...
                        'its symbols. ADS detail: %s'], versionException.message);
                end
                if versionX ~= plc.EXPECTED_INTERFACE_VERSION || ...
                        versionY ~= plc.EXPECTED_INTERFACE_VERSION
                    error('PLC:InterfaceVersion', ...
                        ['PLC/MATLAB interface mismatch. MATLAB expects version %u, ' ...
                        'but PLC reports X=%u and Y=%u. Deploy the matching PLC build.'], ...
                        plc.EXPECTED_INTERFACE_VERSION, versionX, versionY);
                end
                plc.handles.X = plc.createAxisHandles('X');
                plc.handles.Y = plc.createAxisHandles('Y');
                plc.hHaltX = plc.handles.X.command.halt;
                plc.hHaltY = plc.handles.Y.command.halt;

                plc.statusArrayLengths = NET.createArray('System.Int32', 1);
                plc.statusArrayLengths(1) = plc.STATUS_BUFFER_LENGTH;
                for axisName = {'X', 'Y'}
                    axis = axisName{1};
                    plc.netBuffers.(axis).distance = ...
                        NET.createArray('System.Double', plc.COMMAND_ARRAY_LENGTH);
                    plc.netBuffers.(axis).velocity = ...
                        NET.createArray('System.Double', plc.COMMAND_ARRAY_LENGTH);
                    plc.netBuffers.(axis).load = ...
                        NET.createArray('System.Double', plc.COMMAND_ARRAY_LENGTH);
                    plc.netBuffers.(axis).unload = ...
                        NET.createArray('System.Double', plc.COMMAND_ARRAY_LENGTH);
                end

                plc.resetStreamingState();
                plc.connected = true;
                app.updateMachineStatus(plc.pollStatus(), true);
                disp('PLC connected.');
            catch exception
                plc.disconnectPLC();
                src.Value = "OFF";
                uialert(app.fig, exception.message, 'PLC connection error');
            end
        end

        function disconnectPLC(plc)
            if plc.disconnecting
                return;
            end
            plc.disconnecting = true;
            oldClient = plc.client;
            oldHandles = plc.handles;
            plc.connected = false;
            plc.client = [];
            plc.handles = struct();
            plc.netBuffers = struct();
            plc.isWorking = false;
            if ~isempty(oldClient)
                try
                    plc.deleteHandleTree(oldHandles, oldClient);
                    oldClient.Disconnect();
                    oldClient.Dispose();
                catch
                end
            end
            plc.resetStreamingState();
            plc.disconnecting = false;
        end

        function connectClientForTesting(plc, fakeClient)
            % Offline test seam. It exercises the real symbol map, typed
            % reads/writes, validation, padding, and trigger ordering.
            plc.client = fakeClient;
            plc.disconnecting = false;
            plc.handles.X = plc.createAxisHandles('X');
            plc.handles.Y = plc.createAxisHandles('Y');
            plc.hHaltX = plc.handles.X.command.halt;
            plc.hHaltY = plc.handles.Y.command.halt;
            versionX = plc.readUdint(plc.handles.X.status.interfaceVersion);
            versionY = plc.readUdint(plc.handles.Y.status.interfaceVersion);
            if versionX ~= plc.EXPECTED_INTERFACE_VERSION || ...
                    versionY ~= plc.EXPECTED_INTERFACE_VERSION
                plc.client = [];
                plc.handles = struct();
                error('PLC:InterfaceVersion', ...
                    ['PLC/MATLAB interface mismatch. MATLAB expects version %u, ' ...
                    'but PLC reports X=%u and Y=%u.'], ...
                    plc.EXPECTED_INTERFACE_VERSION, versionX, versionY);
            end
            for axisName = {'X', 'Y'}
                axis = axisName{1};
                plc.netBuffers.(axis).distance = ...
                    zeros(1, plc.COMMAND_ARRAY_LENGTH);
                plc.netBuffers.(axis).velocity = ...
                    zeros(1, plc.COMMAND_ARRAY_LENGTH);
                plc.netBuffers.(axis).load = ...
                    zeros(1, plc.COMMAND_ARRAY_LENGTH);
                plc.netBuffers.(axis).unload = ...
                    zeros(1, plc.COMMAND_ARRAY_LENGTH);
            end
            plc.connected = true;
            plc.resetStreamingState();
        end

        function [forceX, forceY, untaredX, untaredY, posX, posY, statuses] = fifoProcess(plc)
            plc.requireConnection();
            [forceX, posX, plc.status.X] = plc.readAxisSnapshot('X');
            [forceY, posY, plc.status.Y] = plc.readAxisSnapshot('Y');
            untaredX = forceX - plc.status.X.tareOffset;
            untaredY = forceY - plc.status.Y.tareOffset;
            plc.isWorking = plc.status.X.working || plc.status.Y.working;
            statuses = plc.status;
        end

        function statuses = pollStatus(plc)
            plc.requireConnection();
            plc.status.X = plc.readAxisStatus('X');
            plc.status.Y = plc.readAxisStatus('Y');
            plc.isWorking = plc.status.X.working || plc.status.Y.working;
            statuses = plc.status;
        end

        function accepted = SendCommands(plc, mode, xPos, xVel, yPos, yVel)
            % Send a Mode 1 or Mode 2 command. Both axes are prepared before
            % either Execute bit is raised.
            accepted = false;
            plc.requireConnection();
            if ~ismember(double(mode), [1, 2])
                error('PLC:InvalidTrajectoryMode', ...
                    'Only PLC modes 1 and 2 use trajectory arrays.');
            end

            statuses = plc.pollStatus();
            activeX = ~isempty(xPos);
            activeY = ~isempty(yPos);
            if ~activeX && ~activeY
                return;
            end
            if (activeX && (statuses.X.working || statuses.X.error)) || ...
                    (activeY && (statuses.Y.working || statuses.Y.error))
                error('PLC:AxisUnavailable', ...
                    'A selected axis is busy or in error.');
            end

            if activeX, plc.ensureAxisPowered('X'); end
            if activeY, plc.ensureAxisPowered('Y'); end
            if activeX
                plc.writeAxisTrajectory('X', mode, xPos, xVel);
            end
            if activeY
                plc.writeAxisTrajectory('Y', mode, yPos, yVel);
            end
            if activeX
                plc.writeBool(plc.handles.X.command.execute, true);
            end
            if activeY
                plc.writeBool(plc.handles.Y.command.execute, true);
            end
            accepted = true;
        end

        function axes = sendTestSequence(plc, commands)
            % Send complete Mode 3 commands. commands.X/Y are either empty
            % or normalized structures produced by Control.
            plc.requireConnection();
            axes = {};
            for axisName = {'X', 'Y'}
                axis = axisName{1};
                if isfield(commands, axis) && ~isempty(commands.(axis))
                    axes{end+1} = axis; %#ok<AGROW>
                end
            end
            if isempty(axes)
                error('PLC:NoAxes', 'No active axis command was provided.');
            end

            statuses = plc.pollStatus();
            for index = 1:numel(axes)
                axis = axes{index};
                statusNow = statuses.(axis);
                if statusNow.working || statusNow.error
                    error('PLC:AxisUnavailable', ...
                        '%s axis is busy or in error.', axis);
                end
                plc.validateTestCommand(commands.(axis), statusNow);
            end

            plc.ensurePowered(axes);
            for index = 1:numel(axes)
                axis = axes{index};
                plc.writeAxisTestCommand(axis, commands.(axis));
            end
            for index = 1:numel(axes)
                plc.writeBool(plc.handles.(axes{index}).command.execute, true);
            end
        end

        function jog(plc, axisName, distance, velocity)
            if ~isfinite(distance) || distance == 0 || ...
                    ~isfinite(velocity) || velocity <= 0
                error('PLC:InvalidJog', ...
                    'Jog distance must be non-zero and velocity must be positive.');
            end
            axisName = upper(char(axisName));
            if strcmp(axisName, 'X')
                plc.SendCommands(1, distance, velocity, [], []);
            elseif strcmp(axisName, 'Y')
                plc.SendCommands(1, [], [], distance, velocity);
            else
                error('PLC:InvalidAxes', 'Unknown axis selection: %s', axisName);
            end
        end

        function stop(plc, axes)
            plc.writeCommandForAxes(axes, 'halt');
        end

        function resetErrors(plc, axes)
            plc.writeCommandForAxes(axes, 'reset');
        end

        function tare(plc, axes)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            for index = 1:numel(axes)
                axis = axes{index};
                statusNow = plc.readAxisStatus(axis);
                if statusNow.working || statusNow.error
                    error('PLC:AxisUnavailable', ...
                        '%s axis is busy or in error.', axis);
                end
                plc.writeBool(plc.handles.(axis).command.tare, true);
            end
        end

        function moveToLowerLimit(plc, axes)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            for index = 1:numel(axes)
                axis = axes{index};
                statusNow = plc.readAxisStatus(axis);
                if statusNow.working || statusNow.error
                    error('PLC:AxisUnavailable', ...
                        '%s axis is busy or in error.', axis);
                end
                plc.ensureAxisPowered(axis);
                plc.writeBool(plc.handles.(axis).command.home, true);
            end
        end

        function savePosition(plc, axes)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            for index = 1:numel(axes)
                axis = axes{index};
                statusNow = plc.readAxisStatus(axis);
                if statusNow.working || statusNow.error
                    error('PLC:AxisUnavailable', ...
                        '%s axis is busy or in error.', axis);
                end
            end
            for index = 1:numel(axes)
                plc.writeBool(plc.handles.(axes{index}).command.savePosition, true);
            end
        end

        function restorePosition(plc, axes, speeds)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            statuses = plc.pollStatus();
            for index = 1:numel(axes)
                axis = axes{index};
                speed = speeds.(axis);
                if statuses.(axis).working || statuses.(axis).error
                    error('PLC:AxisUnavailable', ...
                        '%s axis is busy or in error.', axis);
                end
                if ~statuses.(axis).savedPositionValid
                    error('PLC:NoSavedPosition', ...
                        '%s axis has no saved position.', axis);
                end
                if ~isfinite(speed) || speed <= 0
                    error('PLC:InvalidRestoreSpeed', ...
                        '%s restore speed must be positive.', axis);
                end
            end

            plc.ensurePowered(axes);
            for index = 1:numel(axes)
                axis = axes{index};
                command = plc.handles.(axis).command;
                plc.writeInt(command.mode, 3);
                plc.writeLreal(command.restoreVelocity, speeds.(axis));
            end
            for index = 1:numel(axes)
                plc.writeBool( ...
                    plc.handles.(axes{index}).command.restorePosition, true);
            end
        end

        function setPower(plc, axes, enabled)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            for index = 1:numel(axes)
                plc.writeBool(plc.handles.(axes{index}).command.power, ...
                    logical(enabled));
            end
        end

        function ensurePowered(plc, axes)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            for index = 1:numel(axes)
                plc.ensureAxisPowered(axes{index});
            end
        end

        function writeAxisConfig(plc, axisCfg, axisName)
            plc.requireConnection();
            required = {'fTenzoCons', 'fTenzoOffset', 'fKp', 'fKi', ...
                'fIntegralLimit', 'fForceTolerance', 'fMaxVelocity', ...
                'fMaxForce', 'fForceReliefDistance', 'fForceReliefVelocity'};
            for index = 1:numel(required)
                if ~isfield(axisCfg, required{index})
                    error('PLC:InvalidConfiguration', ...
                        'Hardware configuration is missing %s.', required{index});
                end
            end
            values = cellfun(@(name) double(axisCfg.(name)), required);
            if any(~isfinite(values)) || axisCfg.fTenzoCons == 0 || ...
                    axisCfg.fIntegralLimit < 0 || ...
                    axisCfg.fForceTolerance < 0 || ...
                    axisCfg.fMaxVelocity <= 0 || ...
                    axisCfg.fMaxForce <= 0 || ...
                    axisCfg.fForceReliefDistance <= 0 || ...
                    axisCfg.fForceReliefVelocity <= 0
                error('PLC:InvalidConfiguration', ...
                    'Hardware configuration contains invalid values.');
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
            plc.writeLreal(settings.forceReliefDistance, ...
                axisCfg.fForceReliefDistance);
            plc.writeLreal(settings.forceReliefVelocity, ...
                axisCfg.fForceReliefVelocity);
        end
    end

    methods (Access = private)
        function handles = createAxisHandles(plc, axisName)
            statusRoot = sprintf('MAIN.stSystemStatus%s.', axisName);
            commandRoot = sprintf('MAIN.stMoveCommand%s.', axisName);
            settingsRoot = sprintf('MAIN.stSettings%s.', axisName);

            handles.status = struct( ...
                'working', plc.makeHandle([statusRoot, 'bWorking']), ...
                'head', plc.makeHandle([statusRoot, 'nBufferHead']), ...
                'sampleCounter', plc.makeHandle([statusRoot, 'nSampleCounter']), ...
                'operationCounter', plc.makeHandle([statusRoot, 'nOperationCounter']), ...
                'interfaceVersion', plc.makeHandle([statusRoot, 'nInterfaceVersion']), ...
                'forceBuffer', plc.makeHandle([statusRoot, 'fTenzoBuffer']), ...
                'positionBuffer', plc.makeHandle([statusRoot, 'fPosBuffer']), ...
                'tareOffset', plc.makeHandle([statusRoot, 'fTenzoTarOffset']), ...
                'tareWorking', plc.makeHandle([statusRoot, 'bTarWorking']), ...
                'error', plc.makeHandle([statusRoot, 'bError']), ...
                'errorCode', plc.makeHandle([statusRoot, 'nErrorCode']), ...
                'axisErrorID', plc.makeHandle([statusRoot, 'nAxisErrorID']), ...
                'powered', plc.makeHandle([statusRoot, 'bPowered']), ...
                'homing', plc.makeHandle([statusRoot, 'bHoming']), ...
                'homed', plc.makeHandle([statusRoot, 'bHomed']), ...
                'stopped', plc.makeHandle([statusRoot, 'bStopped']), ...
                'savedPositionValid', ...
                    plc.makeHandle([statusRoot, 'bSavedPositionValid']), ...
                'actPosition', plc.makeHandle([statusRoot, 'fActPosition']));

            handles.command = struct( ...
                'distance', plc.makeHandle([commandRoot, 'fDistances']), ...
                'velocity', plc.makeHandle([commandRoot, 'fVelocities']), ...
                'total', plc.makeHandle([commandRoot, 'nTotalSteps']), ...
                'mode', plc.makeHandle([commandRoot, 'nMode']), ...
                'execute', plc.makeHandle([commandRoot, 'bExecute']), ...
                'halt', plc.makeHandle([commandRoot, 'bHalt']), ...
                'power', plc.makeHandle([commandRoot, 'bPower']), ...
                'reset', plc.makeHandle([commandRoot, 'bReset']), ...
                'home', plc.makeHandle([commandRoot, 'bHome']), ...
                'tare', plc.makeHandle([commandRoot, 'bStartTar']), ...
                'savePosition', plc.makeHandle([commandRoot, 'bSavePosition']), ...
                'restorePosition', plc.makeHandle([commandRoot, 'bRestorePosition']), ...
                'restoreVelocity', plc.makeHandle([commandRoot, 'fRestoreVelocity']), ...
                'includePreTest', plc.makeHandle([commandRoot, 'bIncludePreTest']), ...
                'preTestOnly', plc.makeHandle([commandRoot, 'bPreTestOnly']), ...
                'preCycleCount', plc.makeHandle([commandRoot, 'nPreCycleCount']), ...
                'preloadEnabled', plc.makeHandle([commandRoot, 'bPreloadEnabled']), ...
                'preloadValue', plc.makeHandle([commandRoot, 'fPreloadValue']), ...
                'preLoadValue', plc.makeHandle([commandRoot, 'fPreLoadValue']), ...
                'preUnloadValue', plc.makeHandle([commandRoot, 'fPreUnloadValue']), ...
                'preUnloadToStart', ...
                    plc.makeHandle([commandRoot, 'bPreUnloadToStart']), ...
                'preTestRate', plc.makeHandle([commandRoot, 'fPreTestRate']), ...
                'preTestHoldTime', ...
                    plc.makeHandle([commandRoot, 'fPreTestHoldTime']), ...
                'testRate', plc.makeHandle([commandRoot, 'fTestRate']), ...
                'forceHoldTime', plc.makeHandle([commandRoot, 'fForceHoldTime']), ...
                'forceDropPercent', ...
                    plc.makeHandle([commandRoot, 'fForceDropPercent']), ...
                'forceDropThreshold', ...
                    plc.makeHandle([commandRoot, 'fForceDropThreshold']), ...
                'cycleCount', plc.makeHandle([commandRoot, 'nCycleCount']), ...
                'loadMode', plc.makeHandle([commandRoot, 'nLoadMode']), ...
                'loadValues', plc.makeHandle([commandRoot, 'fLoadValues']), ...
                'unloadMode', plc.makeHandle([commandRoot, 'nUnloadMode']), ...
                'unloadValues', plc.makeHandle([commandRoot, 'fUnloadValues']), ...
                'stop1Mode', plc.makeHandle([commandRoot, 'nStop1Mode']), ...
                'stop1Value', plc.makeHandle([commandRoot, 'fStop1Value']), ...
                'stop2Mode', plc.makeHandle([commandRoot, 'nStop2Mode']), ...
                'stop2Value', plc.makeHandle([commandRoot, 'fStop2Value']), ...
                'postTestMode', plc.makeHandle([commandRoot, 'nPostTestMode']));

            handles.settings = struct( ...
                'tenzoCons', plc.makeHandle([settingsRoot, 'fTenzoCons']), ...
                'tenzoOffset', plc.makeHandle([settingsRoot, 'fTenzoOffset']), ...
                'kp', plc.makeHandle([settingsRoot, 'fKp']), ...
                'ki', plc.makeHandle([settingsRoot, 'fKi']), ...
                'integralLimit', plc.makeHandle([settingsRoot, 'fIntegralLimit']), ...
                'forceTolerance', plc.makeHandle([settingsRoot, 'fForceTolerance']), ...
                'maxVelocity', plc.makeHandle([settingsRoot, 'fMaxVelocity']), ...
                'maxForce', plc.makeHandle([settingsRoot, 'fMaxForce']), ...
                'forceReliefDistance', ...
                    plc.makeHandle([settingsRoot, 'fForceReliefDistance']), ...
                'forceReliefVelocity', ...
                    plc.makeHandle([settingsRoot, 'fForceReliefVelocity']));
        end

        function handle = makeHandle(plc, symbol)
            handle = int32(plc.client.CreateVariableHandle(char(symbol)));
        end

        function [forceData, positionData, statusNow] = readAxisSnapshot(plc, axisName)
            h = plc.handles.(axisName).status;
            counterAfter = plc.readUdint(h.sampleCounter);
            head = double(plc.readInt(h.head));
            forceBuffer = [];
            positionBuffer = [];
            for attempt = 1:2
                counterBefore = plc.readUdint(h.sampleCounter);
                head = double(plc.readInt(h.head));
                forceBuffer = double(plc.client.ReadAny(h.forceBuffer, ...
                    System.Type.GetType('System.Double[]'), plc.statusArrayLengths));
                positionBuffer = double(plc.client.ReadAny(h.positionBuffer, ...
                    System.Type.GetType('System.Double[]'), plc.statusArrayLengths));
                counterAfter = plc.readUdint(h.sampleCounter);
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

            if double(counterAfter) < double(previous) && ...
                    double(previous) < (2^32 - plc.STATUS_BUFFER_LENGTH)
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
            if count > plc.STATUS_BUFFER_LENGTH
                plc.droppedSamples.(axisName) = ...
                    plc.droppedSamples.(axisName) + ...
                    count - plc.STATUS_BUFFER_LENGTH;
                count = plc.STATUS_BUFFER_LENGTH;
            end

            startIndex = mod(head - count, plc.STATUS_BUFFER_LENGTH) + 1;
            indices = mod((startIndex - 1) + (0:count-1), ...
                plc.STATUS_BUFFER_LENGTH) + 1;
            forceData = forceBuffer(indices);
            positionData = positionBuffer(indices);
        end

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
                'savedPositionValid', plc.readBool(h.savedPositionValid), ...
                'position', plc.readLreal(h.actPosition), ...
                'operationCounter', plc.readUdint(h.operationCounter), ...
                'interfaceVersion', plc.readUdint(h.interfaceVersion));
        end

        function writeAxisTrajectory(plc, axisName, mode, distances, velocities)
            distances = double(distances(:)');
            velocities = double(velocities(:)');
            if isempty(distances) || numel(distances) ~= numel(velocities) || ...
                    numel(distances) > plc.COMMAND_ARRAY_LENGTH
                error('PLC:InvalidTrajectory', ...
                    'Trajectory arrays must have equal lengths from 1 to 100.');
            end
            if any(~isfinite(distances)) || any(~isfinite(velocities)) || ...
                    any(abs(velocities) <= 0)
                error('PLC:InvalidTrajectory', ...
                    'Trajectory values must be finite and velocities non-zero.');
            end

            command = plc.handles.(axisName).command;
            plc.writeArray(axisName, 'distance', command.distance, distances);
            plc.writeArray(axisName, 'velocity', command.velocity, velocities);
            plc.writeInt(command.total, numel(distances));
            plc.writeInt(command.mode, mode);
        end

        function validateTestCommand(plc, command, statusNow)
            required = {'includePreTest', 'preTestOnly', 'preCycleCount', ...
                'preloadEnabled', 'preloadValue', 'preLoadValue', ...
                'preUnloadValue', 'preUnloadToStart', 'preTestRate', ...
                'preTestHoldTime', 'testRate', 'forceHoldTime', ...
                'forceDropPercent', 'forceDropThreshold', ...
                'cycleCount', 'loadMode', 'loadValues', 'unloadMode', ...
                'unloadValues', 'stop1Mode', 'stop1Value', 'stop2Mode', ...
                'stop2Value', 'postTestMode'};
            for index = 1:numel(required)
                if ~isfield(command, required{index})
                    error('PLC:InvalidTestCommand', ...
                        'Test command is missing %s.', required{index});
                end
            end

            if ~isfinite(command.testRate) || command.testRate == 0 || ...
                    ~isfinite(command.forceHoldTime) || command.forceHoldTime < 0 || ...
                    ~isfinite(command.forceDropPercent) || ...
                    command.forceDropPercent < 0 || command.forceDropPercent >= 100 || ...
                    ~isfinite(command.forceDropThreshold) || ...
                    command.forceDropThreshold < 0
                error('PLC:InvalidTestCommand', ...
                    ['Movement speed must be non-zero; wait time and force-drop ' ...
                    'threshold must be non-negative; drop must be below 100%%.']);
            end
            if ~plc.isIntegerInRange(command.postTestMode, 0, 4)
                error('PLC:InvalidTestCommand', 'Invalid post-test mode.');
            end
            if command.postTestMode == 1 && ~statusNow.savedPositionValid
                error('PLC:NoSavedPosition', ...
                    'Return-to-saved requires a saved PLC position.');
            end

            if command.preTestOnly && ~command.includePreTest
                error('PLC:InvalidTestCommand', ...
                    'Pre-test-only commands must include a pre-test.');
            end
            if command.includePreTest
                preValues = [command.preloadValue, command.preLoadValue, ...
                    command.preUnloadValue, command.preTestRate, ...
                    command.preTestHoldTime];
                if ~plc.isIntegerInRange(command.preCycleCount, 0, 100) || ...
                        any(~isfinite(preValues)) || command.preTestRate == 0 || ...
                        command.preTestHoldTime < 0
                    error('PLC:InvalidTestCommand', ...
                        'Invalid force pre-conditioning values.');
                end
            end

            if command.preTestOnly
                return;
            end
            if ~plc.isIntegerInRange(command.cycleCount, 0, 100)
                error('PLC:InvalidTestCommand', ...
                    'Cycle count must be an integer from 0 to 100.');
            end
            if command.cycleCount > 0
                if ~ismember(command.loadMode, [1, 2]) || ...
                        ~ismember(command.unloadMode, [1, 2])
                    error('PLC:InvalidTestCommand', ...
                        'Load and unload modes must be displacement or force.');
                end
                if numel(command.loadValues) ~= command.cycleCount || ...
                        numel(command.unloadValues) ~= command.cycleCount || ...
                        any(~isfinite(command.loadValues)) || ...
                        any(~isfinite(command.unloadValues))
                    error('PLC:InvalidTestCommand', ...
                        'Load/unload arrays must match the cycle count.');
                end
            else
                stopValues = [command.stop1Value, command.stop2Value];
                if ~ismember(command.stop1Mode, [1, 2]) || ...
                        ~ismember(command.stop2Mode, [0, 1, 2]) || ...
                        any(~isfinite(stopValues))
                    error('PLC:InvalidTestCommand', ...
                        'Invalid single-test endpoint configuration.');
                end
            end
        end

        function writeAxisTestCommand(plc, axisName, values)
            command = plc.handles.(axisName).command;
            plc.writeArray(axisName, 'load', command.loadValues, values.loadValues);
            plc.writeArray(axisName, 'unload', command.unloadValues, values.unloadValues);

            plc.writeInt(command.mode, 3);
            plc.writeBool(command.includePreTest, values.includePreTest);
            plc.writeBool(command.preTestOnly, values.preTestOnly);
            plc.writeInt(command.preCycleCount, values.preCycleCount);
            plc.writeBool(command.preloadEnabled, values.preloadEnabled);
            plc.writeLreal(command.preloadValue, values.preloadValue);
            plc.writeLreal(command.preLoadValue, values.preLoadValue);
            plc.writeLreal(command.preUnloadValue, values.preUnloadValue);
            plc.writeBool(command.preUnloadToStart, values.preUnloadToStart);
            plc.writeLreal(command.preTestRate, values.preTestRate);
            plc.writeLreal(command.preTestHoldTime, values.preTestHoldTime);
            plc.writeLreal(command.testRate, values.testRate);
            plc.writeLreal(command.forceHoldTime, values.forceHoldTime);
            plc.writeLreal(command.forceDropPercent, values.forceDropPercent);
            plc.writeLreal(command.forceDropThreshold, values.forceDropThreshold);
            plc.writeInt(command.cycleCount, values.cycleCount);
            plc.writeInt(command.loadMode, values.loadMode);
            plc.writeInt(command.unloadMode, values.unloadMode);
            plc.writeInt(command.stop1Mode, values.stop1Mode);
            plc.writeLreal(command.stop1Value, values.stop1Value);
            plc.writeInt(command.stop2Mode, values.stop2Mode);
            plc.writeLreal(command.stop2Value, values.stop2Value);
            plc.writeInt(command.postTestMode, values.postTestMode);
        end

        function writeArray(plc, axisName, bufferName, handle, values)
            values = double(values(:)');
            if numel(values) > plc.COMMAND_ARRAY_LENGTH
                error('PLC:ArrayTooLong', ...
                    'PLC command arrays are limited to 100 entries.');
            end
            buffer = zeros(1, plc.COMMAND_ARRAY_LENGTH);
            buffer(1:numel(values)) = values;
            for index = 1:plc.COMMAND_ARRAY_LENGTH
                plc.netBuffers.(axisName).(bufferName)(index) = buffer(index);
            end
            plc.client.WriteAny(handle, ...
                plc.netBuffers.(axisName).(bufferName));
        end

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
            error('PLC:PowerTimeout', ...
                '%s axis did not power on within 5 seconds.', axisName);
        end

        function writeCommandForAxes(plc, axes, commandName)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            for index = 1:numel(axes)
                plc.writeBool( ...
                    plc.handles.(axes{index}).command.(commandName), true);
            end
        end

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
                    error('PLC:InvalidAxes', ...
                        'Unknown axis selection: %s', value);
                end
            end
        end

        function value = readBool(plc, handle)
            value = logical(plc.client.ReadAny( ...
                handle, System.Type.GetType('System.Boolean')));
        end

        function value = readInt(plc, handle)
            value = int16(plc.client.ReadAny( ...
                handle, System.Type.GetType('System.Int16')));
        end

        function value = readUdint(plc, handle)
            value = uint32(plc.client.ReadAny( ...
                handle, System.Type.GetType('System.UInt32')));
        end

        function value = readLreal(plc, handle)
            value = double(plc.client.ReadAny( ...
                handle, System.Type.GetType('System.Double')));
        end

        function writeBool(plc, handle, value)
            plc.client.WriteAny(handle, logical(value));
        end

        function writeInt(plc, handle, value)
            plc.client.WriteAny(handle, int16(value));
        end

        function writeLreal(plc, handle, value)
            plc.client.WriteAny(handle, double(value));
        end

        function requireConnection(plc)
            if ~plc.connected || plc.disconnecting || isempty(plc.client)
                error('PLC:Disconnected', 'PLC is disconnected.');
            end
        end

        function resetStreamingState(plc)
            plc.lastSampleCounter = struct('X', [], 'Y', []);
            plc.droppedSamples = struct('X', 0, 'Y', 0);
            plc.totalTimeX = 0;
            plc.totalTimeY = 0;
        end

        function deleteHandleTree(plc, value, client)
            if isstruct(value)
                names = fieldnames(value);
                for index = 1:numel(names)
                    plc.deleteHandleTree(value.(names{index}), client);
                end
            elseif ~isempty(value)
                try
                    client.DeleteVariableHandle(value);
                catch exception
                    if ~plc.isExpectedDisconnectError(exception)
                        warning('PLC:HandleCleanup', ...
                            'Could not delete ADS handle: %s', exception.message);
                    end
                end
            end
        end

        function expected = isExpectedDisconnectError(~, exception)
            message = lower(char(exception.message));
            expected = contains(message, '0x710') || ...
                contains(message, 'symbol could not be found') || ...
                contains(message, 'invalid handle') || contains(message, '0x714');
        end

        function valid = isIntegerInRange(~, value, minimum, maximum)
            valid = isscalar(value) && isfinite(value) && ...
                value == round(value) && value >= minimum && value <= maximum;
        end
    end
end
