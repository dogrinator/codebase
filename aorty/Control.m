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
                    % 1. Load .dll library from beckhoff
                    NET.addAssembly(controler.dllPath);
                    
                    % 2. Create client and connect
                    controler.client = TwinCAT.Ads.TcAdsClient();
                    % Choose AMS Net ID (851 is TwinCAT 3)
                    controler.client.Connect(controler.amsNetID, 851); 
                    
                    % 3. Setup and start timer
                    controler.plcTimer = timer(...
                        'ExecutionMode', 'fixedRate', ...
                        'Period', 0.1, ... 
                        'TimerFcn', @(~,~) controler.ReadCallback(app));
                    
                    start(controler.plcTimer);
                    controler.Connected = true;
                    disp("PLC Pripojené (Režim: Timer 10Hz)");
                
                % If something went wrong show error
                catch ME
                    uialert(app.fig, ME.message, 'PLC Connection Error');
                    src.Value = "OFF";
                    controler.Connected = false;
                end
            else
                controler.disconnectPLC();
            end
        end
    
    % Disconnect PLC
        function disconnectPLC(controler)
            % Stop and delete timer
            if ~isempty(controler.plcTimer) && isvalid(controler.plcTimer)
                stop(controler.plcTimer);
                delete(controler.plcTimer);
                controler.plcTimer = [];
            end
            
            % Disconect client
            if ~isempty(controler.client)
                controler.client.Disconnect();
                controler.client.Dispose();
                controler.client = [];
                disp("PLC disconnected");
            end
            
            controler.Connected = false;
        end
    
    % Read from Plc
        function ReadCallback(controler, app)
            % Read struct
            plcData = controler.client.ReadSymbol('MAIN.stSystemStatus', controler.client.GetType(), true);

            % Save actual state
            controler.isWorking = plcData.bWorking;
            
            % FIFO buffer
            currentHead = double(plcData.nBufferHead); 
            buffer = double(plcData.fTenzoBuffer);
            
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
            
            % 1. Check if PLC is occupied
            if controler.isWorking
                disp('PLC is currently working. Commands ignored.');
                return;
            end

           try
                % 2. Clean and format arrays
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
                
                % 3. Create Variable Handles
                hDist = controler.client.CreateVariableHandle('MAIN.stMoveCommand.fDistancesX');
                hVel  = controler.client.CreateVariableHandle('MAIN.stMoveCommand.fVelocitiesX');
                hTot  = controler.client.CreateVariableHandle('MAIN.stMoveCommand.nTotalStepsX');
                hMode = controler.client.CreateVariableHandle('MAIN.stMoveCommand.nMode');
                hExec = controler.client.CreateVariableHandle('MAIN.stMoveCommand.bExecute');
                hPwr  = controler.client.CreateVariableHandle('MAIN.stMoveCommand.bPower');

                % 4. Write data via WriteAny
                controler.client.WriteAny(hDist, netDistBuffer);
                controler.client.WriteAny(hVel, netVelBuffer);
                
                % INT v PLC is int16 in MATLAB
                controler.client.WriteAny(hTot, int16(length(myData)));
                controler.client.WriteAny(hMode, int16(Mode));
                
                % BOOL in PLC
                controler.client.WriteAny(hExec, true);
                controler.client.WriteAny(hPwr, true);
                
                % 5. Delete Handles
                controler.client.DeleteVariableHandle(hDist);
                controler.client.DeleteVariableHandle(hVel);
                controler.client.DeleteVariableHandle(hTot);
                controler.client.DeleteVariableHandle(hMode);
                controler.client.DeleteVariableHandle(hExec);
                controler.client.DeleteVariableHandle(hPwr);
                
                disp('Commands successfully sent to PLC.');
                
            catch ME
                % Error
                disp(['Write Error: ', ME.message]);
           end
        end

        % Power Enable 
        function powerCallback(controler, btn)
            if btn.Value
                btn.Text = 'ON';
                btn.BackgroundColor = [0.4 1 0.4];
                % Pošleme príkaz na zapnutie (uprav si SendPower metódu v kontroleri)
                controler.client.WriteSymbol('MAIN.stMoveCommand.bPower', true);
            else
                btn.Text = 'OFF';
                btn.BackgroundColor = [1 0.7 0.7];
                controler.client.WriteSymbol('MAIN.stMoveCommand.bPower', false);
            end
        end
    end
end
