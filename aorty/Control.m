classdef Control < handle
    % Control class is class that is responsible for whole system. In this
    % class PLC and camera is connected, controled and processed.
    % This class is also responsible for controlling view class and storing
    % data to model class

    properties
        model             % handle for storage

        % camera
        cam
        frameCount = 0;   % Counter to track frames for plotting

        % PLC Properties
        plcTimer       % Timer for reading sensors (Tenzos + Temp) and sending data
        amsNetID = '5.85.113.174.1.1';
        dllPath = 'C:\Program Files (x86)\Beckhoff\TwinCAT\3.1\Components\Plc\LacBinaries\GAC_MSIL\TwinCAT.Ads\4.3.28.0__180016cd49e5e8c3\TwinCAT.Ads.dll';
        client
        % Handles for reciving
        hWorking
        hHead
        hBuffer
        hHalt
        % Handles for sending
        hDist, hVel, hTot, hMode, hExec, hPwr
        Connected = false;
        lastPlcHead = 1; % This variable remember last head of plc data
        totalTime = 0; % Number of samples from one reading
        isWorking = false; % PLC is ocupied
    end

    methods
        function controler = Control(model)
            controler.model = model;
        end

        %% Camera

        function connectCamera(controler, app, src)
            if src.Value == "ON"
                try
                    controler.cam = videoinput('gige', 1, 'Mono8');
                    camSource = getselectedsource(controler.cam);

                    % Trigger reset
                    for sel = {'FrameStart','AcquisitionStart','FrameBurstStart'}
                        try
                            camSource.TriggerSelector = sel{1};
                            camSource.TriggerMode = 'Off';
                        catch, end
                    end

                    % Network — lower delay on dedicated NIC
                    if isprop(camSource,'PacketSize'),  camSource.PacketSize  = 8000; end
                    if isprop(camSource,'PacketDelay'), camSource.PacketDelay = 500;  end

                    controler.cam.FramesPerTrigger      = 1;   % 1 frame per trigger
                    controler.cam.TriggerRepeat         = Inf; % repeat forever
                    triggerconfig(controler.cam, 'immediate');

                    % Callback every frame
                    controler.cam.FramesAcquiredFcnCount = 1;
                    controler.cam.FramesAcquiredFcn = ...
                        @(s,ev) controler.processFrame(app, s);

                    flushdata(controler.cam);
                    start(controler.cam);
                    disp("Camera connected.");
                catch ME
                    uialert(app.fig, getReport(ME), 'Camera Error');
                    src.Value = "OFF";
                end
            else
                controler.closeCam();
            end
        end

        % Process Frame
        function processFrame(controler, app, src)
            try
                % If buffer built up, skip stale frames and disp warning
                if src.FramesAvailable > 2
                    dropped = src.FramesAvailable;
                    flushdata(src);
                    fprintf('WARNING: Dropped %d stale frames\n', dropped);
                    return;
                end

                % Obtain frame
                raw = getdata(src, 1);

                % Filter impulz noise
                frame = medfilt2(raw, [3 3]);

                % Capture timestamp for this frame
                timeStamp = datetime('now');

                % Save frame
                controler.model.saveCameraFrame(frame, timeStamp);

                % Display every frame
                if isvalid(app.cameraAxes)
                    app.camImageHandle.CData = frame(1:3:end, 1:3:end);
                    drawnow limitrate;
                end
            catch
            end
        end

        % Settings Updates
        function updateExposure(controler, exposureValue)
            if ~isempty(controler.cam) && isvalid(controler.cam)
                src = getselectedsource(controler.cam);
                src.ExposureTimeAbs = exposureValue;
                disp(['Exposure set to: ', num2str(exposureValue)]);
            end
        end

        function updateGain(controler, gainValue)
            if ~isempty(controler.cam) && isvalid(controler.cam)
                src = getselectedsource(controler.cam);
                src.GainRaw = gainValue;
                disp(['Gain set to: ', num2str(gainValue)]);
            end
        end

        % Close camera port and erase cam
        function closeCam(controler)
            if ~isempty(controler.cam) && isvalid(controler.cam)
                stop(controler.cam);
                delete(controler.cam);
                controler.cam = [];
                disp("Camera disconnected")
            end
        end

        %% PLC
        % PLC Connection
        function connectPLC(controler, app, src)
            if src.Value == "ON"
                try
                    NET.addAssembly(controler.dllPath);
                    controler.client = TwinCAT.Ads.TcAdsClient();
                    controler.client.Connect(controler.amsNetID, 851);

                    % --- Create persistent handles ---
                    % For reading
                    controler.hWorking = int32(controler.client.CreateVariableHandle('MAIN.stSystemStatus.bWorking'));
                    controler.hHead    = int32(controler.client.CreateVariableHandle('MAIN.stSystemStatus.nBufferHead'));
                    controler.hBuffer  = int32(controler.client.CreateVariableHandle('MAIN.stSystemStatus.fTenzoBuffer'));

                    % For writing
                    controler.hDist = int32(controler.client.CreateVariableHandle('MAIN.stMoveCommand.fDistancesX'));
                    controler.hVel  = int32(controler.client.CreateVariableHandle('MAIN.stMoveCommand.fVelocitiesX'));
                    controler.hTot  = int32(controler.client.CreateVariableHandle('MAIN.stMoveCommand.nTotalStepsX'));
                    controler.hMode = int32(controler.client.CreateVariableHandle('MAIN.stMoveCommand.nMode'));
                    controler.hExec = int32(controler.client.CreateVariableHandle('MAIN.stMoveCommand.bExecute'));
                    controler.hPwr  = int32(controler.client.CreateVariableHandle('MAIN.stMoveCommand.bPower'));
                    controler.hHalt = int32(controler.client.CreateVariableHandle('MAIN.stMoveCommand.bHalt'));

                    % Start timer
                    controler.plcTimer = timer('ExecutionMode', 'fixedRate', 'Period', 0.5, ...
                        'TimerFcn', @(~,~) controler.ReadCallback(app));
                    start(controler.plcTimer);

                    controler.Connected = true;
                    disp("PLC connected.");
                catch ME
                    uialert(app.fig, ME.message, 'PLC Error');
                    src.Value = "OFF";
                end
            else
                controler.disconnectPLC();
            end
        end

        % Disconnect PLC
        function disconnectPLC(controler)
            if ~isempty(controler.plcTimer) && isvalid(controler.plcTimer)
                stop(controler.plcTimer);
                delete(controler.plcTimer);
            end

            if ~isempty(controler.client)
                try
                    % delete all handles
                    handles = {controler.hWorking, controler.hHead, controler.hBuffer, ...
                        controler.hDist, controler.hVel, controler.hTot, ...
                        controler.hMode, controler.hExec, controler.hPwr, controler.hHalt};

                    for i = 1:length(handles)
                        if ~isempty(handles{i})
                            controler.client.DeleteVariableHandle(handles{i});
                        end
                    end
                catch
                    % Ignor errors (No errors no problems XD)
                end
                controler.client.Disconnect();
                controler.client.Dispose();
                controler.client = [];
                disp("PLC Disconnected.");
            end
            controler.Connected = false;
        end

        % Read from Plc
        function ReadCallback(controler, app)
            % tic
            try
                % Read struct

                % Check if command is being processed
                isWorkingOut = controler.client.ReadAny(controler.hWorking, System.Type.GetType('System.Int32'));
                controler.isWorking = double(isWorkingOut);

                % Read where is head
                head_net = controler.client.ReadAny(controler.hHead, System.Type.GetType('System.Int32'));
                currentHead = double(head_net);

                % Prepare to read arrays
                lengths = NET.createArray('System.Int32', 1);
                lengths(1) = 500;

                % Read arrays
                buffer_net = controler.client.ReadAny(controler.hBuffer,System.Type.GetType('System.Single[]'), lengths);
                buffer = double(buffer_net);

                % Init vector
                newTenzoData = [];

                if currentHead > controler.lastPlcHead
                    % Read data from last to head
                    newTenzoData = buffer(controler.lastPlcHead : currentHead - 1);

                elseif currentHead < controler.lastPlcHead

                    part1 = buffer(controler.lastPlcHead : end);
                    part2 = buffer(1 : currentHead - 1);
                    newTenzoData = [part1, part2];
                end

                % Actualization of head
                controler.lastPlcHead = currentHead;

                Ts = 0.01; % Time interval of PLC

                % Plot data
                if ~isempty(newTenzoData)
                    % How many data came
                    numPoints = length(newTenzoData);

                    % Create x
                    xData = controler.totalTime + Ts*(1:numPoints);

                    % Plot data
                    addpoints(app.FxLine, xData, newTenzoData);

                    % Prepare for saving
                    controler.model.saveTenzoX(newTenzoData)

                    % Limit plots to show only last 500 values for performance
                    windowSize  = 500 * Ts;
                    if controler.totalTime > windowSize
                        app.FxAxes.XLim = [controler.totalTime - windowSize, controler.totalTime];
                    else
                        app.FxAxes.XLim = [0, windowSize];
                    end

                    % prepare for next data
                    controler.totalTime = controler.totalTime + Ts*numPoints;

                    drawnow limitrate;
                end

                % stop recording after test ended
                if ~controler.isWorking && controler.model.isRecording
                    controler.endTest(); % Call the new endTest method
                end

            catch ME
                % Error
                stop(controler.plcTimer);
                fprintf('--- ADS READ ERROR ---\n');
                fprintf('Message: %s\n', ME.message);
                if isa(ME, 'NET.NetException')
                    fprintf('Inner Exception: %s\n', char(ME.ExceptionObject.Message));
                end
                fprintf('----------------------\n');
            end
            % toc
        end


        % Send control data
        function SendCommands(controler,Mode,myData,myVels)

            % Check if PLC is occupied
            if controler.isWorking || ~controler.Connected
                disp('PLC is currently working or disconnected. Commands ignored.');
                return;
            end

            try
                % Clean and format arrays
                maxSteps = 100;
                distBuffer = zeros(1, maxSteps);
                velBuffer = zeros(1, maxSteps);

                % Add data to buffers
                distBuffer(1:length(myData)) = myData;
                velBuffer(1:length(myVels)) = myVels;

                % This is needed to bypas error with datatype
                netDistBuffer = NET.createArray('System.Double', maxSteps);
                netVelBuffer  = NET.createArray('System.Double', maxSteps);
                for i = 1:maxSteps
                    netDistBuffer(i) = distBuffer(i);
                    netVelBuffer(i)  = velBuffer(i);
                end

                % 1. Write data to plc
                controler.client.WriteAny(controler.hDist, netDistBuffer);
                controler.client.WriteAny(controler.hVel, netVelBuffer);
                controler.client.WriteAny(controler.hTot, int16(length(myData)));
                controler.client.WriteAny(controler.hMode, int16(Mode));

                % 2. Reset Execute
                controler.client.WriteAny(controler.hExec, false);

                % 3. Start
                controler.client.WriteAny(controler.hExec, true);
                controler.client.WriteAny(controler.hPwr, true);

                % set isWorking so user cannot doublesend data
                controler.isWorking = true;

                disp('Commands successfully sent to PLC.');

            catch ME
                % Error
                disp(['Write Error: ', ME.message]);
            end
        end

        % Panic stop when something broke
        function panicStop(controler, btn)

            % Check if PLC is connected
            if ~controler.Connected
                disp('PLC is disconnected');
                return;
            end

            % Switch halt on
            if btn.Value
                btn.Text = 'Start';
                btn.BackgroundColor = [0.4 1 0.4];
                controler.client.WriteAny(controler.hHalt, true);
            else
                btn.Text = 'Stop';
                btn.BackgroundColor = [1 0.7 0.7];
                controler.client.WriteAny(controler.hHalt, false);
            end
        end

        function endTest(controler)
            if controler.model.isRecording % Only run if recording was active
                disp('--- Ending test and starting post-processing ---');
                controler.model.isRecording = false; % Ensure flag is off before closing files
                controler.model.closeFilesRec();
                controler.model.PostProcessData(controler.model.selectedFolder);

                % Reset model properties for next test
                controler.model.recordIndex = 1;
                controler.totalTime = 0; % Reset total PLC time
                controler.model.cameraFrameWidth = 0; % Reset dimensions
                controler.model.cameraFrameHeight = 0; % Reset dimensions
                disp('--- Test End and Post-Processing Complete ---');
            end
        end

        function startTest(controler, mode, x, vx)
            % choose folder path
            controler.model.selectedFolder = uigetdir('','Choose path');

            if controler.model.selectedFolder == 0
                disp('No file choosen')
                return
            end

            % Get camera dimensions before opening files for recording
            if ~isempty(controler.cam) && isvalid(controler.cam)
                vidRes = controler.cam.VideoResolution; % This property should give [width, height]
                controler.model.cameraFrameWidth = vidRes(1);
                controler.model.cameraFrameHeight = vidRes(2);
            else
                % In case app is runing without camera. To be able to record data
                controler.model.cameraFrameWidth = 1024;
                controler.model.cameraFrameHeight = 1024;
            end

            % send data to PLC
            controler.SendCommands(mode, x, vx)

            % start recording
            controler.model.recordIndex = 1;
            controler.model.isRecording = true;
            controler.model.openFilesRec(); % Open files for recording

        end
    end
end
