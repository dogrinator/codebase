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
        hWorking, hHead, hBuffer, hHalt
        % Handles for sending
        hDist, hVel, hTot, hMode, hExec, hPwr

        % Mandatory variables
        connected = false;
        lastPlcHead = -1;   % plc init head for reciving data
        totalTime = 0;      % Number of samples from one reading
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
                    % For reading
                    plc.hWorking = int32(plc.client.CreateVariableHandle('MAIN.stSystemStatus.bWorking'));
                    plc.hHead    = int32(plc.client.CreateVariableHandle('MAIN.stSystemStatus.nBufferHead'));
                    plc.hBuffer  = int32(plc.client.CreateVariableHandle('MAIN.stSystemStatus.fTenzoBuffer'));

                    % For writing
                    plc.hDist = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommand.fDistancesX'));
                    plc.hVel  = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommand.fVelocitiesX'));
                    plc.hTot  = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommand.nTotalStepsX'));
                    plc.hMode = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommand.nMode'));
                    plc.hExec = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommand.bExecute'));
                    plc.hPwr  = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommand.bPower'));
                    plc.hHalt = int32(plc.client.CreateVariableHandle('MAIN.stMoveCommand.bHalt'));


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
                    handles = {plc.hWorking, plc.hHead, plc.hBuffer, ...
                        plc.hDist, plc.hVel, plc.hTot, ...
                        plc.hMode, plc.hExec, plc.hPwr, plc.hHalt};

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

        function tenzoData = fifoProcess(plc)
            % Check if command is being processed
            isWorkingOut = plc.client.ReadAny(plc.hWorking, System.Type.GetType('System.Int32'));
            plc.isWorking = double(isWorkingOut);

            % Read where is head
            head_net = plc.client.ReadAny(plc.hHead, System.Type.GetType('System.Int32'));
            currentHead = double(head_net);

            % Prepare to read arrays
            lengths = NET.createArray('System.Int32', 1);
            lengths(1) = 500;

            % Read arrays
            buffer_net = plc.client.ReadAny(plc.hBuffer,System.Type.GetType('System.Single[]'), lengths);
            buffer = double(buffer_net);

            % Init vector
            tenzoData = [];

            if plc.lastPlcHead == -1
                plc.lastPlcHead = currentHead;
                return;
            end

            if currentHead > plc.lastPlcHead
                % Normal case: head advanced forward
                tenzoData = buffer(plc.lastPlcHead : currentHead - 1);

            elseif currentHead < plc.lastPlcHead
                % Ring buffer wrapped around
                part1 = buffer(plc.lastPlcHead : end);
                part2 = buffer(1 : currentHead - 1);
                tenzoData = [part1, part2];
            end

            % Actualization of head
            plc.lastPlcHead = currentHead;

        end

        % Send control data
        function SendCommands(plc,mode,xPos,xVel)

            % Check if PLC is occupied
            if plc.isWorking || ~plc.connected
                disp('PLC is currently working or disconnected. Commands ignored.');
                return;
            end

            try
                % Clean and format arrays
                maxSteps = 100;
                distBuffer = zeros(1, maxSteps);
                velBuffer = zeros(1, maxSteps);

                % Add data to buffers
                distBuffer(1:length(xPos)) = xPos;
                velBuffer(1:length(xVel)) = xVel;

                % This is needed to bypas error with datatype
                netDistBuffer = NET.createArray('System.Double', maxSteps);
                netVelBuffer  = NET.createArray('System.Double', maxSteps);
                for i = 1:maxSteps
                    netDistBuffer(i) = distBuffer(i);
                    netVelBuffer(i)  = velBuffer(i);
                end

                % 1. Write data to plc
                plc.client.WriteAny(plc.hDist, netDistBuffer);
                plc.client.WriteAny(plc.hVel, netVelBuffer);
                plc.client.WriteAny(plc.hTot, int16(length(xPos)));
                plc.client.WriteAny(plc.hMode, int16(mode));

                % 2. Reset Execute
                plc.client.WriteAny(plc.hExec, false);

                % 3. Start
                plc.client.WriteAny(plc.hExec, true);
                plc.client.WriteAny(plc.hPwr, true);

                % set isWorking so user cannot doublesend data
                plc.isWorking = true;

                disp('Commands successfully sent to PLC.');

            catch ME
                % Error
                disp(['Write Error: ', ME.message]);
            end
        end
    end
end
