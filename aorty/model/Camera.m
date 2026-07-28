classdef Camera < handle
    %CAMERA Owns the GigE camera and forwards frames to recording and preview.

    properties
        model Model

        cameraHW
        cameraSrc

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

                    % Refresh the Image Acquisition Toolbox after a camera
                    % has been unplugged/reconnected. Without this, the
                    % gige adaptor can keep a stale device list.
                    imaqreset;
                    hwInfo = imaqhwinfo('gige');
                    if isempty(hwInfo.DeviceInfo)
                        error('Camera:NotDetected', ...
                            ['No GigE Vision camera was detected. Check the ', ...
                             'camera power, Ethernet connection, and network settings.']);
                    end

                    % Do not assume that the first camera always has ID 1.
                    deviceID = hwInfo.DeviceInfo(1).DeviceID;
                    camera.cameraHW = videoinput('gige', deviceID, 'Mono8');
                    camera.cameraSrc = getselectedsource(camera.cameraHW);

                    % Trigger properties differ between camera firmware
                    % versions, so unsupported selectors are skipped.
                    for sel = {'FrameStart','AcquisitionStart','FrameBurstStart'}
                        try
                            camera.cameraSrc.TriggerSelector = sel{1};
                            camera.cameraSrc.TriggerMode = 'Off';
                        catch
                        end
                    end

                    if isprop(camera.cameraSrc,'PacketSize'),  camera.cameraSrc.PacketSize  = 8000; end
                    if isprop(camera.cameraSrc,'PacketDelay'), camera.cameraSrc.PacketDelay = 500;  end

                    camera.cameraHW.FramesPerTrigger = 1;   % 1 frame per trigger
                    camera.cameraHW.TriggerRepeat = Inf; % repeat forever
                    triggerconfig(camera.cameraHW, 'immediate');

                    camera.camStartTime = datetime('now');
                    camera.cameraHW.FramesAcquiredFcnCount = 1;
                    camera.cameraHW.FramesAcquiredFcn = @(s,ev) camera.acquireFrame(s);

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
                % A final callback may arrive while shutdown deletes the
                % videoinput object.
                if isempty(src) || ~isvalid(src), return; end
                if src.FramesAvailable < 1,        return; end

                [frame, relativeTime] = getdata(src, 1);
                timeStamp = camera.camStartTime + seconds(relativeTime);

                camera.model.saveCameraFrame(frame, timeStamp);

                % Preview downsampling does not affect recorded frames.
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

            if ~isempty(camera.cameraHW) && isvalid(camera.cameraHW)
                try
                    stop(camera.cameraHW);
                catch
                end
                try
                    delete(camera.cameraHW);
                catch
                end
            end
            camera.cameraHW = [];
            camera.cameraSrc = [];
            camera.connected = false;
            disp("Camera disconnected");
        end
    end
end

