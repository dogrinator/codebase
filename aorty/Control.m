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
                        camSource.PacketSize = 9000; 
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
                        'TimerFcn', @(~,~) controler.comCallback(app));
                    
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
            end
            
            controler.Connected = false;
            disp("PLC disconnected");
        end
    
    % Communication Callback (TODO)
        function comCallback(controler, app)
            if ~controler.Connected || isempty(controler.client), return; end
            
            try
                % 1. ČÍTANIE DÁT (Z PLC do PC)
                % Pre jednoduchosť čítame celú štruktúru naraz
                % MATLAB .NET interface vie prečítať štruktúru ako objekt
                plcData = controler.client.ReadSymbol('GVL.stDataToPC', ...
                    controler.client.GetType(), true);
                
                % Uloženie do modelu
                controler.model.saveLivePoint(plcData.fTenzo, plcData.fActualPos);
                
                % Aktualizácia GUI
                if isvalid(app.FxAxes)
                    addpoints(app.FxLine, plcData.nSyncCounter, plcData.fTenzo);
                    drawnow limitrate;
                end
                
                % 2. ZÁPIS DÁT (Z PC do PLC)
                % Ak máš v modeli nejaké príkazy (napr. z GUI tlačidiel)
                if controler.model.needsUpdate
                    % Príklad zápisu jednej premennej (bool)
                    controler.client.WriteSymbol('GVL.bStartTest', controler.model.startCmd);
                    controler.model.needsUpdate = false;
                end
                
            catch ME
                % Ak nastane chyba (napr. strata spojenia), vypneme komunikáciu
                disp(['PLC Com Error: ', ME.message]);
                % controler.disconnectPLC(); % Voliteľné: automatické odpojenie pri chybe
            end
        end
    end
end
