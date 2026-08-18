classdef Camera < handle
    %CAMERA Owns the GigE camera and forwards frames to recording and preview.

    properties
        recordingSession RecordingSession

        % Image Acquisition Toolbox objects
        cameraHW
        cameraSrc

        % Acquisition and preview state
        latestFrame = [];
        camStartTime
        connected = false;
        errorHandler = []
    end

    methods
        %% Connection and acquisition
        function camera = Camera(recordingSession)
            camera.recordingSession = recordingSession;
        end

        function connectCamera(camera, app, src)
            if src.Value == "ON"
                try
                    camera.closeCam();

                    % Refresh hardware discovery after a camera reconnect.
                    imaqreset;
                    hwInfo = imaqhwinfo('gige');
                    if isempty(hwInfo.DeviceInfo)
                        error('Camera:NotDetected', ...
                            ['No GigE Vision camera was detected. Check the ', ...
                             'camera power, Ethernet connection, and network settings.']);
                    end

                    % Use the first detected GigE camera.
                    deviceID = hwInfo.DeviceInfo(1).DeviceID;
                    camera.cameraHW = videoinput('gige', deviceID, 'Mono8');
                    camera.cameraSrc = getselectedsource(camera.cameraHW);

                    % Disable device-side triggering modes when supported.
                    for sel = {'FrameStart','AcquisitionStart','FrameBurstStart'}
                        try
                            camera.cameraSrc.TriggerSelector = sel{1};
                            camera.cameraSrc.TriggerMode = 'Off';
                        catch
                        end
                    end

                    % Tune packet transport when the source exposes these controls.
                    if isprop(camera.cameraSrc,'PacketSize'),  camera.cameraSrc.PacketSize  = 8000; end
                    if isprop(camera.cameraSrc,'PacketDelay'), camera.cameraSrc.PacketDelay = 500;  end

                    % Acquire one frame per repeated immediate trigger.
                    camera.cameraHW.FramesPerTrigger = 1;
                    camera.cameraHW.TriggerRepeat = Inf;
                    triggerconfig(camera.cameraHW, 'immediate');

                    % Anchor relative frame times and register the callback.
                    camera.camStartTime = datetime('now');
                    camera.cameraHW.FramesAcquiredFcnCount = 1;
                    camera.cameraHW.FramesAcquiredFcn = @(s,ev) camera.acquireFrame(s);

                    % Start with an empty queue so preview and recording are current.
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
                % A callback may arrive while the camera is being released.
                if isempty(src) || ~isvalid(src), return; end
                if src.FramesAvailable < 1,        return; end

                % Convert the source-relative frame time to an absolute time.
                [frame, relativeTime] = getdata(src, 1);
                timeStamp = camera.camStartTime + seconds(relativeTime);

                camera.recordingSession.saveCameraFrame(frame, timeStamp);

                % Downsample preview only; recording retains the full frame.
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

        function discardQueuedFrames(camera)
            % Discard frames acquired while recording files were prepared.
            if ~camera.connected || isempty(camera.cameraHW) || ~isvalid(camera.cameraHW)
                error('Camera:NotConnected', ...
                    'Cannot prepare recording while the camera is disconnected.');
            end
            flushdata(camera.cameraHW);
            camera.latestFrame = [];
        end

        function closeCam(camera)
            camera.latestFrame = [];

            % Attempt both cleanup steps even after an acquisition error.
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
            % Clear state even when the hardware object was already invalid.
            camera.cameraHW = [];
            camera.cameraSrc = [];
            camera.connected = false;
            disp("Camera disconnected");
        end
    end
end
