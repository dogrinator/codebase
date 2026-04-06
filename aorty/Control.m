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
        plcClient      % Native MATLAB ADS Client
        plcTimer       % Timer for reading sensors (Tenzos + Temp)
        amsNetID = '5.85.113.174.1.1';
        amsPort = 851;
        client
        adsListener
        notificationHandle

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
                    
                    % 3. THE TRIGGER RESET (Crucial for Basler)
                    % We cycle through all selectors to ensure the camera is in Freerun
                    selectors = {'FrameStart', 'AcquisitionStart', 'FrameBurstStart'};
                    for i = 1:length(selectors)
                        try
                            camSource.TriggerSelector = selectors{i};
                            camSource.TriggerMode = 'Off';
                        catch
                            % Some cameras don't support all selectors, just skip
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

    % Process Frame (Triggered automatically by Ethernet)
        function processFrame(controler, app, src)
            try
                % Grab the frame from the memory buffer
                frame = getdata(src, 1);

                % Add 1 frame to counter and reset framecount in long run
                controler.frameCount = controler.frameCount + 1;
                if controler.frameCount > 10000
                    controler.frameCount = 0; % Reset periodically
                end
        
                % Store the FULL quality frame in the model (for the real test data)
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

    % Settings Updates (settings can be added later, dinamicly is bad idea for performance '25s XD')
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
                src.ExposureTimeAbs = exposureValue; 
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
        function connectPLC(controler, app, src)
            disp("connectPLC called")
        
            persistent dllLoaded
        
            try
                import TwinCAT.Ads.*
        
                % Load DLL once
                if isempty(dllLoaded)
                    NET.addAssembly('C:\Program Files (x86)\Beckhoff\TwinCAT\Functions\TE14xx-ToolsForMatlabAndSimulink\TE140x\NET\TwinCAT.Ads.dll');
                    dllLoaded = true;
                end
        
                if src.Value == "ON"
                    % Connect
                    controler.client = TcAdsClient();
                    controler.client.Connect('5.85.113.174.1.1', 851);
        
                    % Event callback for typed notifications
                    controler.adsListener = addlistener( ...
                        controler.client, ...
                        'AdsNotificationEx', ...
                        @(s,e) controler.onNotification(app, e));
        
                    % Start with a simple PLC scalar first
                    % Replace MAIN.myTestInt with your test variable
                    controler.notificationHandle = controler.client.AddDeviceNotificationEx( ...
                        'MAIN.myTestInt', ...
                        AdsTransMode.OnChange, ...
                        100, ...
                        0, ...
                        [], ...
                        int32(0).GetType());
        
                    disp("PLC connected");
        
                else
                    % Disconnect
                    if ~isempty(controler.client)
                        if ~isempty(controler.notificationHandle)
                            controler.client.DeleteDeviceNotification(controler.notificationHandle);
                        end
        
                        if ~isempty(controler.adsListener)
                            delete(controler.adsListener);
                        end
        
                        controler.client.Dispose();
                        controler.client = [];
                        controler.notificationHandle = [];
                        controler.adsListener = [];
        
                        disp("PLC disconnected");
                    end
                end
        
            catch ME
                uialert(app.fig, ME.message, 'PLC Error');
                src.Value = "OFF";
            end
        end
            
        % 4. Samotný "Interrupt" (Callback funkcia)
        function onNotification(controler, app, event)
            % try
            %     % Dáta z PLC prídu ako event.Value
            %     % MATLAB ich automaticky mapuje na štruktúru
            %     plcData = event.Value;
            % 
            %     % Uložíme do modelu (fTenzo, fActualPos atď.)
            %     controler.model.saveData(plcData);
            % 
            %     % Aktualizujeme grafy (napr. každú 2. notifikáciu pre výkon)
            %     if mod(plcData.nSyncCounter, 2) == 0
            %         % Vykreslenie tenzometra na ľavý panel
            %         addpoints(app.FxLine, plcData.nSyncCounter, plcData.fTenzo);
            %         drawnow limitrate;
            %     end
            % catch
            %     % Ignorujeme chyby pri spracovaní počas behu
            % end
        end

    % Read data
        function updatePlcData(controler, app)
            % % This function runs in the background to read your 4 tenzos
            % if isempty(controler.plcClient) || ~isvalid(controler.plcClient)
            %     return;
            % end
            % 
            % try
            %     % --- OPTIMIZATION TIP ---
            %     % Instead of 4 separate reads, read them as one array if possible
            %     % For now, let's assume they are separate GVLs
            %     fx = read(controler.plcClient, 'GVL.fTenzo_Fx');
            %     fy = read(controler.plcClient, 'GVL.fTenzo_Fy');
            % 
            %     % Save to Model
            %     controler.model.saveTenzoX(fx);
            %     controler.model.saveTenzoy(fy);
            % 
            %     % Update GUI Plots
            %     % (We use 'animatedline' usually, but for now we update the axes)
            %     plot(app.FxAxes, controler.model.tenzoX, 'Color', 'g');
            %     plot(app.FyAxes, controler.model.tenzoY, 'Color', 'c');
            %     drawnow limitrate;
            % 
            % catch
            %     % Silently catch PLC timeouts to prevent GUI locking
            % end
        end

        function disconnectPLC(controler)
            disp("PLC Disconnected");
        end

    % % Motor Controls (Manual Move)
    %     function plcMove(controler, axis, direction)
    %         if isempty(controler.plcClient), return; end
    % 
    %         % Write to the PLC command variables
    %         % Assumes you have a 'bMove' variable in your PLC
    %         varName = sprintf('GVL.bMove%s_%s', axis, direction); 
    %         write(controler.plcClient, varName, true);
    % 
    %         % Note: You'll need a way to set them to false when button is released
    %     end
    end
end

