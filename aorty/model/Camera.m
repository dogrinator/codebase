classdef Camera < handle
    %CAMERA Owns the GigE camera and forwards frames to recording and preview.

    properties
        model Model

        % Camera interface
        cameraHW
        cameraSrc

        % Camera info variables
        latestFrame = [];
        camStartTime
        connected = false;
        errorHandler = []
    end

    methods
        function camera = Camera(model)
            camera.model = model;
        end

        function connectCamera(camera, app, src)
            if src.Value == "ON"
                try
                    camera.closeCam();

                    % Refresh the Image Acquisition Toolbox after a camera has been unplugged/reconnected
                    imaqreset;
                    hwInfo = imaqhwinfo('gige');
                    if isempty(hwInfo.DeviceInfo)
                        error('Camera:NotDetected', ...
                            ['No GigE Vision camera was detected. Check the ', ...
                             'camera power, Ethernet connection, and network settings.']);
                    end

                    % Search for camera id and connect to id
                    deviceID = hwInfo.DeviceInfo(1).DeviceID;
                    camera.cameraHW = videoinput('gige', deviceID, 'Mono8');
                    camera.cameraSrc = getselectedsource(camera.cameraHW);

                    % Trigger properties (just to be shure)
                    for sel = {'FrameStart','AcquisitionStart','FrameBurstStart'}
                        try
                            camera.cameraSrc.TriggerSelector = sel{1};
                            camera.cameraSrc.TriggerMode = 'Off';
                        catch
                        end
                    end

                    % Init camera com setup for better stability
                    if isprop(camera.cameraSrc,'PacketSize'),  camera.cameraSrc.PacketSize  = 8000; end
                    if isprop(camera.cameraSrc,'PacketDelay'), camera.cameraSrc.PacketDelay = 500;  end

                    % Trigger mandatory setup 
                    camera.cameraHW.FramesPerTrigger = 1;   % 1 frame per trigger
                    camera.cameraHW.TriggerRepeat = Inf; % repeat forever
                    triggerconfig(camera.cameraHW, 'immediate');

                    % Link fun. and get start time
                    camera.camStartTime = datetime('now');
                    camera.cameraHW.FramesAcquiredFcnCount = 1;
                    camera.cameraHW.FramesAcquiredFcn = @(s,ev) camera.acquireFrame(s);

                    % Flush camera and start aquisition
                    camera.latestFrame = [];
                    flushdata(camera.cameraHW);
                    start(camera.cameraHW);
                    camera.connected = true;
                    disp("Camera connected.");
                catch ME
                    camera.closeCam();
                    uialert(app.fig, getReport(ME), 'Camera Error');
                    src.Value = "OFF";
                    if ~isempty(camera.errorHandler)
                        camera.errorHandler(ME);
                    end
                end
            else
                camera.closeCam();
            end
        end

        function acquireFrame(camera, src)
            try
                % Check if camera exist and is working
                if isempty(src) || ~isvalid(src), return; end
                if src.FramesAvailable < 1,        return; end

                % Get img and time
                [frame, relativeTime] = getdata(src, 1);
                timeStamp = camera.camStartTime + seconds(relativeTime);

                % Link for recording
                camera.model.saveCameraFrame(frame, timeStamp);

                % Preview downsampling (Not needed on better pc but mi netebook is dying)
                camera.latestFrame = frame(1:3:end, 1:3:end);

            catch ME
                if contains(ME.message, 'deleted') || contains(ME.message, 'invalid')
                    return;
                end
                fprintf(2, 'acquireFrame error: %s\n', getReport(ME));
                if ~isempty(camera.errorHandler)
                    camera.errorHandler(ME);
                end
            end
        end

        function closeCam(camera)
            camera.latestFrame = [];

            % Safly disconnect and delete camera ewen if error stopped it
            if ~isempty(camera.cameraHW) && isvalid(camera.cameraHW)
                try
                    stop(camera.cameraHW);
                catch
                    warning("Camera:StopFailed", "Could not stop camera: %s", exception.message);
                end
                try
                    delete(camera.cameraHW);
                catch
                    warning("Camera:DeleteFailed", "Could not delete camera: %s", exception.message);
                end
            end
            % Final cleanup
            camera.cameraHW = [];
            camera.cameraSrc = [];
            camera.connected = false;
            disp("Camera disconnected");
        end
    end
end

