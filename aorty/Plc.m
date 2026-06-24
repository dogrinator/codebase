classdef Plc <handle
    % This class contains main functions to connect/disconnect to/from plc
    % This class also contains main functions for settings and to send/recive data

    properties
        % mandatory class
        model

        % PLC inicialization
        amsNetID = '5.85.113.174.1.1';
        dllPath = 'C:\Program Files (x86)\Beckhoff\TwinCAT\3.1\Components\Plc\LacBinaries\GAC_MSIL\TwinCAT.Ads\4.3.28.0__180016cd49e5e8c3\TwinCAT.Ads.dll';
        client

        % Handles for reciving
        hWorkingX, hHeadX, hBufferX, hHaltX
        hWorkingY, hHeadY, hBufferY, hHaltY
        % Handles for sending
        hDistX, hVelX, hTotX, hModeX, hExecX, hPwrX
        hDistY, hVelY, hTotY, hModeY, hExecY, hPwrY

        % Mandatory variables
        connected = false;
        lastPlcHeadX, lastPlcHeadY = -1;   % plc init head for reciving data
        totalTimeX, totalTimeY = 0;      % Number of samples from one reading
        isWorking = false;  % PLC is ocupied
        ts = 0.01           % plc dt for 1 loop

        % Settings variables TODO
    end

    methods
        function plc = Plc(model)
            plc.model = model;
        end

        % PLC Connection
        function connectPLC(plc, app, src)
            if src.Value == "ON"
                try
                    NET.addAssembly(plc.dllPath);
                    plc.client = TwinCAT.Ads.TcAdsClient();
                    plc.client.Connect(plc.amsNetID, 851);

                    % --- Create persistent handles ---
                    % For reading X axis
                    plc.hWorkingX = int32(plc.client.CreateVariableHandle('MAIN.stSystemStatusX.bWorking'));
                    plc.hHeadX    = int32(plc.client.CreateVariableHandle('MAIN.stSystemStatusX.nBufferHead'));
                    plc.hBufferX  = int32(plc.client.CreateVariableHandle('MAIN.stSystemStatusX.fTenzoBuffer'));

                    % For writing X axis
                    plc.hDistX = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandX.fDistances'));
                    plc.hVelX  = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandX.fVelocities'));
                    plc.hTotX  = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandX.nTotalSteps'));
                    plc.hModeX = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandX.nMode'));
                    plc.hExecX = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandX.bExecute'));
                    plc.hPwrX  = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandX.bPower'));
                    plc.hHaltX = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandX.bHalt'));

                    % For reading Y axis
                    plc.hWorkingY = int32(plc.client.CreateVariableHandle('MAIN.stSystemStatusY.bWorking'));
                    plc.hHeadY    = int32(plc.client.CreateVariableHandle('MAIN.stSystemStatusY.nBufferHead'));
                    plc.hBufferY  = int32(plc.client.CreateVariableHandle('MAIN.stSystemStatusY.fTenzoBuffer'));

                    % For writing Y axis
                    plc.hDistY = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandY.fDistances'));
                    plc.hVelY  = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandY.fVelocities'));
                    plc.hTotY  = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandY.nTotalSteps'));
                    plc.hModeY = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandY.nMode'));
                    plc.hExecY = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandY.bExecute'));
                    plc.hPwrY  = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandY.bPower'));
                    plc.hHaltY = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommandY.bHalt'));

                    % Plc connected flags
                    plc.connected = true;
                    disp("PLC connected.");
                catch ME
                    uialert(app.fig, ME.message, 'PLC Error');
                    src.Value = "OFF";
                end
            else
                plc.disconnectPLC();
            end
        end

        % Disconnect PLC
        function disconnectPLC(plc)
            if ~isempty(plc.client)
                try
                    % delete all handles
                    handles = {plc.hWorkingX, plc.hHeadX, plc.hBufferX, ...
                        plc.hDistX, plc.hVelX, plc.hTotX, ...
                        plc.hModeX, plc.hExecX, plc.hPwrX, plc.hHaltX, ...
                        plc.hWorkingY, plc.hHeadY, plc.hBufferY, ...
                        plc.hDistY, plc.hVelY, plc.hTotY, ...
                        plc.hModeY, plc.hExecY, plc.hPwrY, plc.hHaltY};

                    for i = 1:length(handles)
                        if ~isempty(handles{i})
                            plc.client.DeleteVariableHandle(handles{i});
                        end
                    end
                catch
                    % Ignor errors (No errors no problems XD) TODO
                end
                plc.client.Disconnect();
                plc.client.Dispose();
                plc.client = [];
                disp("PLC Disconnected.");
            end
            plc.connected = false;
        end

        function [tenzoDataX, tenzoDataY] = fifoProcess(plc)
            % Check if command is being processed
            isWorkingOutX = plc.client.ReadAny(plc.hWorkingX, System.Type.GetType('System.Int32'));
            isWorkingOutY = plc.client.ReadAny(plc.hWorkingY, System.Type.GetType('System.Int32'));
            plc.isWorking = double(isWorkingOutX) || double(isWorkingOutY);

            % Read where is head
            head_netX = plc.client.ReadAny(plc.hHeadX, System.Type.GetType('System.Int32'));
            currentHeadX = double(head_netX);
            head_netY = plc.client.ReadAny(plc.hHeadY, System.Type.GetType('System.Int32'));
            currentHeadY = double(head_netY);

            % Prepare to read arrays
            lengths = NET.createArray('System.Int32', 1);
            lengths(1) = 150;

            % Read arrays
            buffer_netX = plc.client.ReadAny(plc.hBufferX,System.Type.GetType('System.Single[]'), lengths);
            bufferX = double(buffer_netX);
            buffer_netY = plc.client.ReadAny(plc.hBufferY,System.Type.GetType('System.Single[]'), lengths);
            bufferY = double(buffer_netY);

            % Init vector
            tenzoDataX = [];
            tenzoDataY = [];

            if plc.lastPlcHeadX == -1
                plc.lastPlcHeadX = currentHeadX;
            else
                if currentHeadX > plc.lastPlcHeadX
                    % Normal case: head advanced forward
                    tenzoDataX = bufferX(plc.lastPlcHeadX : currentHeadX - 1);
                elseif currentHeadX < plc.lastPlcHeadX
                    % Ring buffer wrapped around
                    part1 = bufferX(plc.lastPlcHeadX : end);
                    part2 = bufferX(1 : currentHeadX - 1);
                    tenzoDataX = [part1, part2];
                end
                % Actualization of head
                plc.lastPlcHeadX = currentHeadX;
            end

            % Y axis handling
            if plc.lastPlcHeadY == -1
                plc.lastPlcHeadY = currentHeadY;
            else
                if currentHeadY > plc.lastPlcHeadY
                    % Normal case: head advanced forward
                    tenzoDataY = bufferY(plc.lastPlcHeadY : currentHeadY - 1);
                elseif currentHeadY < plc.lastPlcHeadY
                    % Ring buffer wrapped around
                    part1 = bufferY(plc.lastPlcHeadY : end);
                    part2 = bufferY(1 : currentHeadY - 1);
                    tenzoDataY = [part1, part2];
                end
                % Actualization of head
                plc.lastPlcHeadY = currentHeadY;
            end
        end


        % Send control data
        function SendCommands(plc,mode,xPos,xVel,yPos,yVel)

            % Check if PLC is occupied
            if plc.isWorking || ~plc.connected
                disp('PLC is currently working or disconnected. Commands ignored.');
                return;
            end

            try
                % Clean and format arrays for X and Y
                maxSteps = 100;
                distBufferX = zeros(1, maxSteps);
                velBufferX  = zeros(1, maxSteps);
                distBufferY = zeros(1, maxSteps);
                velBufferY  = zeros(1, maxSteps);

                % Add data to buffers (ensure lengths do not exceed maxSteps)
                nX = min(length(xPos), maxSteps);
                mX = min(length(xVel), maxSteps);
                nY = min(length(yPos), maxSteps);
                mY = min(length(yVel), maxSteps);

                distBufferX(1:nX) = xPos(1:nX);
                velBufferX(1:mX)  = xVel(1:mX);
                distBufferY(1:nY) = yPos(1:nY);
                velBufferY(1:mY)  = yVel(1:mY);

                % Create .NET arrays (System.Double) and copy data
                netDistBufferX = NET.createArray('System.Double', maxSteps);
                netVelBufferX  = NET.createArray('System.Double', maxSteps);
                netDistBufferY = NET.createArray('System.Double', maxSteps);
                netVelBufferY  = NET.createArray('System.Double', maxSteps);
                for i = 1:maxSteps
                    netDistBufferX(i) = distBufferX(i);
                    netVelBufferX(i)  = velBufferX(i);
                    netDistBufferY(i) = distBufferY(i);
                    netVelBufferY(i)  = velBufferY(i);
                end

                % 1. Write data to PLC for X axis
                plc.client.WriteAny(plc.hDistX, netDistBufferX);
                plc.client.WriteAny(plc.hVelX, netVelBufferX);
                plc.client.WriteAny(plc.hTotX, int16(nX));
                plc.client.WriteAny(plc.hModeX, int16(mode));

                % 1b. Write data to PLC for Y axis
                plc.client.WriteAny(plc.hDistY, netDistBufferY);
                plc.client.WriteAny(plc.hVelY, netVelBufferY);
                plc.client.WriteAny(plc.hTotY, int16(nY));
                plc.client.WriteAny(plc.hModeY, int16(mode));

                % 2. Reset Execute for both axes
                plc.client.WriteAny(plc.hExecX, false);
                plc.client.WriteAny(plc.hExecY, false);

                % 3. Start both axes
                plc.client.WriteAny(plc.hExecX, true);
                plc.client.WriteAny(plc.hPwrX, true);
                plc.client.WriteAny(plc.hExecY, true);
                plc.client.WriteAny(plc.hPwrY, true);

                % set isWorking so user cannot double-send data
                plc.isWorking = true;

                disp('Commands successfully sent to PLC.');

            catch ME
                % Error
                disp(['Write Error: ', ME.message]);
            end
        end
    end
end
