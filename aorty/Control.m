classdef Control < handle
    % Control class is class that is responsible for whole system. In this
    % class PLC and camera is connected, controled and processed.
    % This class is also responsible for controlling view class and storing
    % data to model class

    properties
        % mandatory classes
        camera   Camera    % handle for camera
        plc      Plc       % handle for plc
        model    Model     % handle for storage
        settings Settings  % class for config

        plcReadTimer % Timer for reading sensors (Tenzos + Temp) and sending data
        displayTimer % Separate timer for GUI updates only

        xTenzoData = [];
        yTenzoData = [];
    end

    methods
        %% Init functions
        function controler = Control(model)
            controler.model = model;
            controler.camera = Camera(model);
            controler.plc = Plc(model);
            controler.settings = Settings(controler.plc, controler.camera);
        end

        function startTimers(controler, app)
            % Start timer
            controler.plcReadTimer = timer( ...
                'ExecutionMode', 'fixedRate', ...
                'Period', 0.5, ...
                'TimerFcn', @(~,~) controler.ReadCallback());
            start(controler.plcReadTimer);

            controler.displayTimer = timer( ...
                'ExecutionMode', 'fixedRate', ...
                'Period', 0.067, ...
                'TimerFcn', @(~,~) controler.updateDisplay(app));
            start(controler.displayTimer);
        end

        %% Main update loops
        function ReadCallback(controler)
            try
                % read data from plc
                if controler.plc.connected
                    % read data and append
                    [newXdata, newYdata] = controler.plc.fifoProcess();
                    controler.xTenzoData = [controler.xTenzoData, newXdata];
                    controler.yTenzoData = [controler.yTenzoData, newYdata];

                    % stop recording after test ended
                    if ~controler.plc.isWorking && controler.plc.model.isRecording
                        controler.endTest();
                    end
                end

            catch ME
                % Error
                stop(controler.plcReadTimer);
                fprintf('--- ADS READ ERROR ---\n');
                fprintf('Message: %s\n', ME.message);
                if isa(ME, 'NET.NetException')
                    fprintf('Inner Exception: %s\n', char(ME.ExceptionObject.Message));
                end
                fprintf('----------------------\n');
            end
        end

        function updateDisplay(controler, app)
            try
                % Plot camera frame
                if controler.camera.connected && ~isempty(controler.camera.latestFrame) && isvalid(app.cameraAxes)
                    app.camImageHandle.CData = controler.camera.latestFrame;
                    controler.camera.latestFrame = [];
                end
        
                % --- X channel ---
                if ~isempty(controler.xTenzoData) && controler.plc.connected
                    batch = controler.xTenzoData;        % snapshot the batch
                    controler.xTenzoData = [];           % drain immediately
        
                    numPts  = length(batch);
                    xData   = controler.plc.totalTimeX + controler.plc.ts * (1:numPts);
        
                    addpoints(app.fxLine, xData, batch);
                    controler.plc.model.saveTenzoX(batch);
        
                    controler.plc.totalTimeX = controler.plc.totalTimeX + controler.plc.ts * numPts; % advance FIRST
        
                    windowSize = 500 * controler.plc.ts;
                    if controler.plc.totalTimeX > windowSize
                        app.fxAxes.XLim = [controler.plc.totalTimeX - windowSize, controler.plc.totalTimeX];
                    else
                        app.fxAxes.XLim = [0, windowSize];
                    end
                end
        
                % --- Y channel ---
                if ~isempty(controler.yTenzoData) && controler.plc.connected
                    batch = controler.yTenzoData;        % snapshot the batch
                    controler.yTenzoData = [];           % drain immediately
        
                    numPts  = length(batch);
                    yData   = controler.plc.totalTimeY + controler.plc.ts * (1:numPts);
        
                    addpoints(app.fyLine, yData, batch);
                    controler.plc.model.saveTenzoY(batch);
        
                    controler.plc.totalTimeY = controler.plc.totalTimeY + controler.plc.ts * numPts; % advance FIRST
        
                    windowSize = 500 * controler.plc.ts;
                    if controler.plc.totalTimeY > windowSize
                        app.fyAxes.XLim = [controler.plc.totalTimeY - windowSize, controler.plc.totalTimeY];
                    else
                        app.fyAxes.XLim = [0, windowSize];
                    end
                end
        
                drawnow limitrate;
            catch ME
                % Error
                stop(controler.plcReadTimer);
                fprintf('--- Plot ERROR ---\n');
                fprintf('Message: %s\n', ME.message);
                if isa(ME, 'NET.NetException')
                    fprintf('Inner Exception: %s\n', char(ME.ExceptionObject.Message));
                end
                fprintf('----------------------\n');
            end
        end

        %% UI callbacks
        function panicStop(controler, btn)

            % Check if PLC is connected
            if ~controler.plc.connected
                disp('PLC is disconnected');
                return;
            end

            % Switch halt on
            if btn.Value
                btn.Text = 'Start';
                btn.BackgroundColor = [0.4 1 0.4];
                controler.plc.client.WriteAny(controler.plc.hHaltX, true);
                controler.plc.client.WriteAny(controler.plc.hHaltY, true);
            else
                btn.Text = 'Stop';
                btn.BackgroundColor = [1 0.7 0.7];
                controler.plc.client.WriteAny(controler.plc.hHaltX, false);
                controler.plc.client.WriteAny(controler.plc.hHaltY, false);
            end
        end

        %% Test handling
        function startTest(controler, mode, x, vx, y, vy)
            % choose folder path
            controler.model.selectedFolder = uigetdir('','Choose path');

            if controler.model.selectedFolder == 0
                disp('No file choosen')
                return
            end

            % Get camera dimensions before opening files for recording
            if ~isempty(controler.camera.cameraHW) && isvalid(controler.camera.cameraHW)
                vidRes = controler.camera.cameraHW.VideoResolution; % This property should give [width, height]
                controler.model.cameraFrameWidth = vidRes(1);
                controler.model.cameraFrameHeight = vidRes(2);
            else
                % In case app is runing without camera. To be able to record data
                controler.model.cameraFrameWidth = 1024;
                controler.model.cameraFrameHeight = 1024;
            end

            % start recording
            controler.model.recordIndex = 1;
            controler.model.isRecording = true;
            controler.model.openFilesRec(); % Open files for recording

            % send data to PLC
            controler.plc.SendCommands(mode, x, vx, y, vy)
        end

        function endTest(controler)
            if controler.model.isRecording % Only run if recording was active
                disp('--- Ending test and starting post-processing ---');
                controler.model.isRecording = false; % Ensure flag is off before closing files
                controler.model.closeFilesRec();

                % Pause camera acquisition to prevent buffer overflow
                camWasRunning = ~isempty(controler.camera.cameraHW) && isvalid(controler.camera.cameraHW) && ...
                    strcmp(controler.camera.cameraHW.Running, 'on');
                if camWasRunning
                    stop(controler.camera.cameraHW);
                    flushdata(controler.camera.cameraHW);
                end

                % Pause PLC timer so it doesn't keep adding data
                timerWasRunning = ~isempty(controler.plcReadTimer) && isvalid(controler.plcReadTimer) && ...
                    strcmp(controler.plcReadTimer.Running, 'on');
                if timerWasRunning
                    stop(controler.plcReadTimer);
                end

                controler.model.PostProcessData(controler.model.selectedFolder);

                % Restart camera for live preview
                if camWasRunning
                    start(controler.camera.cameraHW);
                end

                % Restart PLC timer
                if timerWasRunning
                    start(controler.plcReadTimer);
                end

                % Reset model properties for next test
                controler.model.recordIndex = 1;
                controler.model.cameraFrameWidth = 0;  % Reset dimensions
                controler.model.cameraFrameHeight = 0; % Reset dimensions
                disp('--- Test End and Post-Processing Complete ---');
            end
        end
    end
end
