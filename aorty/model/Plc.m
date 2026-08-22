classdef Plc < handle
    %PLC Application-facing facade for the two-axis TwinCAT controller.
    % High-level validation and sequencing stay here; PlcAds owns every
    % symbol handle and low-level ADS operation.

    properties
        model Model

        % ADS connection settings and client
        amsNetID = '5.85.113.174.1.1'
        adsPort = 851
        dllPath = 'C:\Program Files (x86)\Beckhoff\TwinCAT\3.1\Components\Plc\LacBinaries\GAC_MSIL\TwinCAT.Ads\4.3.28.0__180016cd49e5e8c3\TwinCAT.Ads.dll'
        client

        % PLC connection and machine state
        connected = false
        disconnecting = false
        status = struct('X', struct(), 'Y', struct())
        isWorking = false
    end

    properties (Dependent, SetAccess = private)
        droppedSamples
        restartCounts
    end

    properties (Access = private)
        ads % Ads client
        jogLeaseCounters = struct('X', uint32(0), 'Y', uint32(0))
        activeJog = struct('X', false, 'Y', false)
    end

    methods
        function plc = Plc(model)
            plc.model = model;
        end

        function value = get.droppedSamples(plc)
            % Expose live transport counters without duplicating their state.
            if isempty(plc.ads)
                value = struct('X', 0, 'Y', 0);
            else
                value = plc.ads.droppedSamples;
            end
        end

        %% PLC connection lifecycle
        function connectPLC(plc, app, src)
            if src.Value ~= "ON"
                plc.disconnectPLC();
                app.updateMachineStatus([], false);
                return;
            end

            try
                % Release a stale client before creating a complete ADS session.
                plc.disconnectPLC();
                NET.addAssembly(plc.dllPath);
                plc.client = TwinCAT.Ads.TcAdsClient();
                plc.client.Connect(plc.amsNetID, plc.adsPort);
                plc.ads = PlcAds(plc.client);
                plc.ads.initialize(false);

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
            % Keep ADS available until both axes have received their
            % power-off command (and any required position checkpoint has
            % completed). Disconnect remains best-effort so a PLC fault
            % cannot prevent the client and its handles from being released.
            if plc.connected && ~isempty(plc.ads) && ~isempty(plc.client)
                try
                    plc.ads.writeCommand('X', 'execute', false);
                    plc.ads.writeCommand('Y', 'execute', false);
                    plc.ads.writeCommand('X', 'halt');
                    plc.ads.writeCommand('Y', 'halt');
                    pause(0.05); % Let at least one PLC/status cycle observe stop.
                    plc.stopAndWait({'X', 'Y'}, 5);
                    plc.setPower({'X', 'Y'}, false);
                catch exception
                    warning('PLC:PowerOffBeforeDisconnect', ...
                        ['PLC power-off did not complete cleanly before ' ...
                        'disconnect: %s'], exception.message);
                end
            end
            % Clear facade state before releasing the detached ADS objects.
            plc.disconnecting = true;
            oldAds = plc.ads;
            oldClient = plc.client;
            plc.connected = false;
            plc.ads = [];
            plc.client = [];
            plc.isWorking = false;
            plc.activeJog = struct('X', false, 'Y', false);

            % PlcAds releases symbols first; Plc owns and closes the client.
            if ~isempty(oldAds)
                oldAds.releaseHandles();
            end
            if ~isempty(oldClient)
                try
                    oldClient.Disconnect();
                    oldClient.Dispose();
                catch
                end
            end
            plc.disconnecting = false;
        end

        function connectClientForTesting(plc, fakeClient)
            % Offline seam: use the same PlcAds implementation with buffers
            % represented by ordinary MATLAB arrays.
            plc.disconnectPLC();
            plc.client = fakeClient;
            plc.disconnecting = false;
            plc.ads = PlcAds(fakeClient);
            try
                plc.ads.initialize(true);
            catch exception
                plc.disconnectPLC();
                rethrow(exception);
            end
            plc.connected = true;
            plc.resetStreamingState();
        end

        %% PLC acquisition and status
        function [forceX, forceY, untaredX, untaredY, posX, posY, statuses] = fifoProcess(plc)
            % Read valid FIFO samples and derive untared force values.
            plc.requireConnection();
            [forceX, posX, plc.status.X] = plc.ads.readAxisSnapshot('X');
            [forceY, posY, plc.status.Y] = plc.ads.readAxisSnapshot('Y');
            untaredX = forceX - plc.status.X.tareOffset;
            untaredY = forceY - plc.status.Y.tareOffset;
            plc.isWorking = plc.status.X.working || plc.status.Y.working;
            statuses = plc.status;
        end

        function statuses = pollStatus(plc)
            % Poll status without consuming FIFO sample vectors.
            plc.requireConnection();
            plc.status.X = plc.ads.readAxisStatus('X');
            plc.status.Y = plc.ads.readAxisStatus('Y');
            plc.isWorking = plc.status.X.working || plc.status.Y.working;
            statuses = plc.status;
        end


        %% Machine commands and test control
        function accepted = SendCommands(plc, mode, xPos, xVel, yPos, yVel)
            % Both selected axes are fully prepared before either Execute
            % trigger is raised, preventing half-started biaxial commands.
            accepted = false;
            plc.requireConnection();
            if double(mode) ~= 2
                error('PLC:InvalidTrajectoryMode', ...
                    'Only PLC mode 2 uses basic scalar commands.');
            end

            % Reject commands before writing when a selected axis is unavailable.
            statuses = plc.pollStatus();
            activeX = ~isempty(xPos);
            activeY = ~isempty(yPos);
            if ~activeX && ~activeY
                return;
            end
            % Validate both selected commands before writing either axis.
            if activeX
                plc.requireAxisReady('X', statuses.X);
                configX = plc.ads.readAxisConfig('X');
                PlcCommandValidator.basic(xPos, xVel, configX);
            end
            if activeY
                plc.requireAxisReady('Y', statuses.Y);
                configY = plc.ads.readAxisConfig('Y');
                PlcCommandValidator.basic(yPos, yVel, configY);
            end
            if activeX
                plc.ads.writeBasicCommand('X', mode, xPos, xVel);
            end
            if activeY
                plc.ads.writeBasicCommand('Y', mode, yPos, yVel);
            end
            if activeX, plc.ads.pulseExecute('X'); end
            if activeY, plc.ads.pulseExecute('Y'); end
            accepted = true;
        end

        function axes = sendTestSequence(plc, commands)
            % Prepare for commands sending
            axes = plc.preflightTestSequence(commands);
            for index = 1:numel(axes)
                plc.ads.writeAxisTestCommand( ...
                    axes{index}, commands.(axes{index}));
            end
            % Biaxial tests use one PLC-owned start after both complete
            % commands are prepared. Single-axis tests retain their
            % individual Execute trigger.
            try
                if numel(axes) == 2
                    plc.ads.pulseBiaxialStart();
                else
                    plc.ads.pulseExecute(axes{1});
                end
            catch exception
                plc.recoverAmbiguousStart(axes);
                rethrow(exception);
            end
        end

        function [axes, statuses, configs] = preflightTestSequence(plc, commands)
            % Read-only validation used both before recording setup and
            % immediately before ADS command writes.
            plc.requireConnection();
            axes = {};
            for axisName = {'X', 'Y'}
                axis = axisName{1};
                if isfield(commands, axis) && ~isempty(commands.(axis))
                    axes{end + 1} = axis;
                end
            end
            if isempty(axes)
                error('PLC:NoAxes', ...
                    'No active axis command was provided.');
            end
            statuses = plc.pollStatus();
            configs = struct();
            for index = 1:numel(axes)
                axis = axes{index};
                plc.requireAxisReady(axis, statuses.(axis));
                configs.(axis) = plc.ads.readAxisConfig(axis);
                PlcCommandValidator.test( ...
                    commands.(axis), statuses.(axis), configs.(axis));
            end
            if numel(axes) == 2
                PlcCommandValidator.biaxial(commands.X, commands.Y);
            end
        end

        function jog(plc, axisName, pressed, velocity)
            axisName = upper(char(axisName));
            if ~any(strcmp(axisName, {'X', 'Y'}))
                error('PLC:InvalidAxes', ...
                    'Unknown axis selection: %s', axisName);
            end
            plc.requireConnection();
            if ~pressed
                plc.activeJog.(axisName) = false;
                plc.ads.writeCommand(axisName, 'execute', false);
                return;
            end
            statusNow = plc.ads.readAxisStatus(axisName);
            plc.requireAxisReady(axisName, statusNow);
            config = plc.ads.readAxisConfig(axisName);
            PlcCommandValidator.rate(velocity, config, 'Jog speed');
            plc.jogLeaseCounters.(axisName) = ...
                plc.jogLeaseCounters.(axisName) + uint32(1);
            plc.ads.writeJogLeaseCounter( ...
                axisName, plc.jogLeaseCounters.(axisName));
            plc.ads.writeJogCommand(axisName, velocity);
            try
                plc.ads.writeCommand(axisName, 'execute', true);
                plc.activeJog.(axisName) = true;
            catch exception
                plc.activeJog.(axisName) = false;
                try
                    plc.ads.writeCommand(axisName, 'halt');
                catch
                end
                rethrow(exception);
            end
        end

        function renewJogLeases(plc)
            % Call after each successful acquisition snapshot while a jog
            % button is held. If acquisition stops, the PLC lease expires.
            plc.requireConnection();
            for axisName = {'X', 'Y'}
                axis = axisName{1};
                if plc.activeJog.(axis)
                    plc.jogLeaseCounters.(axis) = ...
                        plc.jogLeaseCounters.(axis) + uint32(1);
                    plc.ads.writeJogLeaseCounter( ...
                        axis, plc.jogLeaseCounters.(axis));
                end
            end
        end

        function stop(plc, axes)
            plc.writeCommandForAxes(axes, 'halt');
        end

        function stopAndWait(plc, axes, timeoutSeconds)
            if nargin < 3
                timeoutSeconds = 5;
            end
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            statuses = plc.pollStatus();
            if plc.axesStopped(axes, statuses)
                return;
            end
            for index = 1:numel(axes)
                axis = axes{index};
                plc.activeJog.(axis) = false;
                plc.ads.writeCommand(axis, 'halt');
            end
            deadline = tic;
            while toc(deadline) < timeoutSeconds
                pause(0.05);
                drawnow limitrate;
                statuses = plc.pollStatus();
                if plc.axesStopped(axes, statuses)
                    return;
                end
            end
            error('PLC:StopTimeout', ...
                'Selected axes did not confirm stopped state in time.');
        end

        function resetErrors(plc, axes)
            plc.writeCommandForAxes(axes, 'reset');
        end

        function tare(plc, axes)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            statuses = plc.pollStatus();
            for index = 1:numel(axes)
                axis = axes{index};
                statusNow = statuses.(axis);
                if statusNow.working || statusNow.error
                    error('PLC:AxisUnavailable', ...
                        '%s axis is busy or in error.', axis);
                end
            end
            for index = 1:numel(axes)
                axis = axes{index};
                plc.ads.writeCommand(axis, 'tare');
            end
        end

        function moveToLowerLimit(plc, axes)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            statuses = plc.pollStatus();
            for index = 1:numel(axes)
                axis = axes{index};
                statusNow = statuses.(axis);
                if statusNow.working || statusNow.error
                    error('PLC:AxisUnavailable', ...
                        '%s axis is busy or in error.', axis);
                end
            end
            plc.ensurePowered(axes);
            for index = 1:numel(axes)
                axis = axes{index};
                plc.ads.writeCommand(axis, 'home');
            end
        end

        function savePosition(plc, axes)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            statuses = plc.pollStatus();
            for index = 1:numel(axes)
                axis = axes{index};
                plc.requireAxisReady(axis, statuses.(axis));
            end
            for index = 1:numel(axes)
                plc.ads.writeCommand(axes{index}, 'savePosition');
            end
        end

        function restorePosition(plc, axes, speeds)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            statuses = plc.pollStatus();
            for index = 1:numel(axes)
                axis = axes{index};
                speed = speeds.(axis);
                plc.requireAxisReady(axis, statuses.(axis));
                if ~statuses.(axis).savedPositionValid
                    error('PLC:NoSavedPosition', ...
                        '%s axis has no saved position.', axis);
                end
                if ~isfinite(speed) || speed <= 0
                    error('PLC:InvalidRestoreSpeed', ...
                        '%s restore speed must be positive.', axis);
                end
                config = plc.ads.readAxisConfig(axis);
                PlcCommandValidator.rate( ...
                    speed, config, 'Restore speed');
            end

            for index = 1:numel(axes)
                axis = axes{index};
                plc.ads.prepareRestore(axis, speeds.(axis));
            end
            for index = 1:numel(axes)
                plc.ads.writeCommand( ...
                    axes{index}, 'restorePosition');
            end
        end

        function setPower(plc, axes, enabled)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);

            waitForCheckpoint = false;
            checkpointBefore = uint32(0);
            if ~enabled
                statuses = plc.pollStatus();
                for index = 1:numel(axes)
                    axis = axes{index};
                    waitForCheckpoint = waitForCheckpoint || ...
                        (statuses.(axis).powered && statuses.(axis).homed);
                end
                if waitForCheckpoint
                    checkpoint = ...
                        plc.ads.readPersistentPositionCheckpoint();
                    checkpointBefore = checkpoint.counter;
                end
            end

            for index = 1:numel(axes)
                plc.ads.writeCommand( ...
                    axes{index}, 'power', logical(enabled));
            end

            % Do not let the operator cut controller power before TwinCAT has
            % written the last referenced coordinate to its boot-data file.
            if waitForCheckpoint
                deadline = tic;
                while toc(deadline) < 8
                    checkpoint = ...
                        plc.ads.readPersistentPositionCheckpoint();
                    if checkpoint.error
                        error('PLC:PersistentPositionSave', ...
                            ['Axis power is off, but the position checkpoint ' ...
                            'failed with ADS error 0x%08X. Do not switch off ' ...
                            'the controller; home again or repair persistent ' ...
                            'storage first.'], checkpoint.errorID);
                    end
                    if checkpoint.saved && ~checkpoint.busy && ...
                            checkpoint.counter ~= checkpointBefore
                        return;
                    end
                    pause(0.05);
                    drawnow limitrate;
                end
                error('PLC:PersistentPositionSaveTimeout', ...
                    ['Axis power is off, but the PLC did not confirm its ' ...
                    'position checkpoint within 8 seconds. Do not switch ' ...
                    'off the controller.']);
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
            PlcCommandValidator.axisConfig(axisCfg);
            plc.ads.writeAxisConfig(axisCfg, axisName);
        end

        function value = get.restartCounts(plc)
            if isempty(plc.ads)
                value = struct('X', 0, 'Y', 0);
            else
                value = plc.ads.restartCounts;
            end
        end

        function values = readAxisConfig(plc, axisName)
            % Capture the applied PLC settings in recording metadata.
            plc.requireConnection();
            values = plc.ads.readAxisConfig(axisName);
        end
    end

    %% Private PLC coordination helpers
    methods (Access = private)
        function ensureAxisPowered(plc, axisName)
            statusNow = plc.ads.readAxisStatus(axisName);
            if statusNow.powered
                return;
            end
            plc.ads.writeCommand(axisName, 'power', true);
            deadline = tic;
            while toc(deadline) < 5
                pause(0.05);
                drawnow limitrate;
                statusNow = plc.ads.readAxisStatus(axisName);
                if statusNow.error
                    error('PLC:PowerError', '%s', ...
                        PlcErrorCatalog.describe(axisName, ...
                        statusNow.errorCode, ...
                        statusNow.axisErrorID));
                end
                if statusNow.powered
                    return;
                end
            end
            error('PLC:PowerTimeout', ...
                '%s axis did not power on within 5 seconds.', axisName);
        end

        function requireAxisReady(~, axisName, statusNow)
            ready = statusNow.powered && statusNow.homed && ...
                ~statusNow.homing && statusNow.stopped && ...
                ~statusNow.working && ~statusNow.error;
            if ~ready
                error('PLC:AxisNotReady', ...
                    ['%s axis must be powered, homed, stopped, idle, ' ...
                    'and error-free.'], axisName);
            end
        end

        function recoverAmbiguousStart(plc, axes)
            % A transport exception cannot reveal whether the trigger write
            % reached TwinCAT. Halt every candidate and confirm fresh state.
            for index = 1:numel(axes)
                try
                    plc.ads.writeCommand(axes{index}, 'halt');
                catch
                end
            end
            deadline = tic;
            while toc(deadline) < 2
                try
                    statuses = plc.pollStatus();
                    if plc.axesStopped(axes, statuses)
                        return;
                    end
                catch
                end
                pause(0.05);
                drawnow limitrate;
            end
            warning('PLC:AmbiguousStartRecovery', ...
                ['A test trigger failed and stopped state could not be ' ...
                'confirmed. Treat all candidate axes as potentially moving.']);
        end

        function stopped = axesStopped(~, axes, statuses)
            stopped = true;
            for index = 1:numel(axes)
                statusNow = statuses.(axes{index});
                stopped = stopped && statusNow.stopped && ...
                    ~statusNow.working;
            end
        end

        function writeCommandForAxes(plc, axes, commandName)
            plc.requireConnection();
            axes = plc.normalizeAxes(axes);
            for index = 1:numel(axes)
                plc.ads.writeCommand(axes{index}, commandName);
            end
        end

        function axes = normalizeAxes(~, axes)
            if ischar(axes) || isstring(axes)
                value = char(axes);
                if strcmpi(value, 'Both')
                    axes = {'X', 'Y'};
                elseif strcmpi(value, 'X only') || ...
                        strcmpi(value, 'X')
                    axes = {'X'};
                elseif strcmpi(value, 'Y only') || ...
                        strcmpi(value, 'Y')
                    axes = {'Y'};
                else
                    error('PLC:InvalidAxes', ...
                        'Unknown axis selection: %s', value);
                end
            end
        end

        function requireConnection(plc)
            if ~plc.connected || plc.disconnecting || ...
                    isempty(plc.client) || isempty(plc.ads)
                error('PLC:Disconnected', 'PLC is disconnected.');
            end
        end

        function resetStreamingState(plc)
            if ~isempty(plc.ads)
                plc.ads.resetStreamingState();
            end
            plc.jogLeaseCounters = ...
                struct('X', uint32(0), 'Y', uint32(0));
            plc.activeJog = struct('X', false, 'Y', false);
        end

    end
end
