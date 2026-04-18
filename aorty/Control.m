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
        % Handles for sending
        hDist, hVel, hTot, hMode, hExec, hPwr
        Connected = false;
        lastPlcHead = 1; % This variable remember last head of plc data
        totalSamples = 0; % Number of samples from one reading
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
                    % 1. Create the object
                    controler.cam = videoinput('gige', 1, 'Mono8');
                    
                    % 2. Get the source (hardware) handle
                    camSource = getselectedsource(controler.cam);
                    
                    % 3. THE TRIGGER RESET 
                    % We cycle through all selectors to ensure the camera is in Freerun
                    selectors = {'FrameStart', 'AcquisitionStart', 'FrameBurstStart'};
                    for i = 1:length(selectors)
                        try
                            camSource.TriggerSelector = selectors{i};
                            camSource.TriggerMode = 'Off';
                        catch
                            % if error skip
                        end
                    end
        
                    % 4. NETWORK STABILITY TEST
                    if isprop(camSource, 'PacketSize')
                        camSource.PacketSize = 2000; 
                    end
                    if isprop(camSource, 'PacketDelay')
                        camSource.PacketDelay = 2000; % Higher delay = more stability
                    end
        
                    % 5. Configure MATLAB side
                    controler.cam.FramesPerTrigger = Inf;
                    controler.cam.FramesAcquiredFcnCount = 5;
                    controler.cam.FramesAcquiredFcn = @(src, event) controler.processFrame(app, src);
                    
                    % 6. Clean the buffer and start
                    flushdata(controler.cam);
                    start(controler.cam);
                    
                    disp("--- Camera Foundation Stable ---");
                    disp(['Resolution: ', num2str(controler.cam.VideoResolution)]);
                    
                catch ME
                    report = getReport(ME);
                    uialert(app.fig, report, 'Camera Connection Error');
                    src.Value = "OFF";
                end
            else
                controler.closeCam();
            end
        end

    % Process Frame
        function processFrame(controler, app, src)
            try
                % Grab the frame from the memory buffer
                frame = getdata(src, 1);

                % Add 1 frame to counter and reset framecount in long run
                controler.frameCount = controler.frameCount + 1;
                if controler.frameCount > 10000
                    controler.frameCount = 0; % Reset periodically
                end
        
                % Store the FULL quality frame in the model 
                controler.model.saveCameraFrame(frame);
                
                % Update GUI every n-th frame (added at begining for performance)
                n = 2;
                if mod(controler.frameCount, n) == 0 && isvalid(app.cameraAxes)
                    
                    % --- DROP QUALITY FOR DISPLAY ---
                    % Take every 2nd pixel in both directions (1:2:end)
                    displayFrame = frame(1:2:end, 1:2:end); 
                    
                    % Update the image handle
                    app.camImageHandle.CData = displayFrame;
                    drawnow limitrate;
                end

            catch
                % ignore dropped frames in GUI
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
        
                    % Start timer
                    controler.plcTimer = timer('ExecutionMode', 'fixedRate', 'Period', 0.1, ...
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
                               controler.hMode, controler.hExec, controler.hPwr};
                    
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
            % Read struct
            isWorking_net = controler.client.ReadAny(controler.hWorking, System.Type.GetType('System.Boolean'));
            controler.isWorking = logical(isWorking_net);
    
            head_net = controler.client.ReadAny(controler.hHead, System.Type.GetType('System.Int32'));
            currentHead = double(head_net);
    
            buffer_net = controler.client.ReadAny(controler.hBuffer, System.Type.GetType('System.Single[]'));
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
            
            % Plot data
            if ~isempty(newTenzoData) && isvalid(app.FxAxes)
                % How many data came
                numPoints = length(newTenzoData);
                
                % Create x 
                xData = controler.totalSamples + (1:numPoints);
                
                % Plot data
                addpoints(app.FxLine, xData, newTenzoData);
                
                % prepare for next data
                controler.totalSamples = controler.totalSamples + numPoints;
                
                drawnow limitrate;
            end
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
                
                % Write data via WriteAny
                controler.client.WriteAny(controler.hDist, netDistBuffer);
                controler.client.WriteAny(controler.hVel, netVelBuffer);
                
                % INT v PLC is int16 in MATLAB
                controler.client.WriteAny(controler.hTot, int16(length(myData)));
                controler.client.WriteAny(controler.hMode, int16(Mode));
                
                % BOOL in PLC
                controler.client.WriteAny(controler.hExec, true);
                controler.client.WriteAny(controler.hPwr, true);
                
                disp('Commands successfully sent to PLC.');
                
            catch ME
                % Error
                disp(['Write Error: ', ME.message]);
           end
        end

        % Panic stop when something broke (TODO = how halt works)
        function panicStop(controler, btn)
            
            % Check if PLC is connected
            if ~controler.Connected
                disp('PLC is disconnected');
                return;
            end
            
            % Switch halt on
            if btn.Value
                btn.Text = 'Stop';
                btn.BackgroundColor = [0.4 1 0.4];
                controler.client.WriteSymbol('MAIN.stMoveCommand.bHalt', true);
            else
                btn.Text = 'Start';
                btn.BackgroundColor = [1 0.7 0.7];
                controler.client.WriteSymbol('MAIN.stMoveCommand.bHalt', false);
            end
        end
    end
end
