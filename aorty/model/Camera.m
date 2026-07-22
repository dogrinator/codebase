classdef Camera < handle
    % this class contains main functions to connect / disconnect to/from camera
    % This function also contains reciving frames from camera and settings and setup

    properties
        % mandatory classes
        model Model            % model for saving frames

        % camera
        cameraHW               % videoinput obj
        cameraSrc              % camera settings

        latestFrame = [];      % Most recent frame for display
        camStartTime           % Start timer for visualization
        connected = false;
        recordingPeriod = 0;   % 0 saves every frame
        lastRecordingTime
        errorHandler = []
    end

    methods
        % Camera handles this operation.
        function camera = Camera(model)
            camera.model = model;
        end

        % connectCamera handles this operation.
        function connectCamera(camera, app, src)
            if src.Value == "ON"
                try
                    camera.closeCam();
                    camera.connected = false;
                    camera.cameraHW = videoinput('gige', 1, 'Mono8');
                    camera.cameraSrc = getselectedsource(camera.cameraHW);

                    % Trigger reset
                    for sel = {'FrameStart','AcquisitionStart','FrameBurstStart'}
                        try
                            camera.cameraSrc.TriggerSelector = sel{1};
                            camera.cameraSrc.TriggerMode = 'Off';
                        catch
                        end
                    end

                    % Network setup
                    if isprop(camera.cameraSrc,'PacketSize'),  camera.cameraSrc.PacketSize  = 8000; end
                    if isprop(camera.cameraSrc,'PacketDelay'), camera.cameraSrc.PacketDelay = 500;  end

                    camera.cameraHW.FramesPerTrigger = 1;   % 1 frame per trigger
                    camera.cameraHW.TriggerRepeat = Inf; % repeat forever
                    triggerconfig(camera.cameraHW, 'immediate');

                    % Save data
                    camera.camStartTime = datetime('now');
                    camera.cameraHW.FramesAcquiredFcnCount = 1;
                    camera.cameraHW.FramesAcquiredFcn = @(s,ev) camera.acquireFrame(s);

                    % Start display timer at fixed 15 Hz, independent of camera FPS.
                    camera.latestFrame = [];
                    flushdata(camera.cameraHW);
                    start(camera.cameraHW);
                    camera.connected = true;
                    disp("Camera connected.");
                catch ME
                    camera.closeCam();
                    camera.connected = false;
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

        % Saving frame
        function acquireFrame(camera, src)
            try
                % Guard against callbacks firing after delete(cam)
                if isempty(src) || ~isvalid(src), return; end
                if src.FramesAvailable < 1,        return; end

                % get new frame
                [frame, relativeTime] = getdata(src, 1);
                timeStamp = camera.camStartTime + seconds(relativeTime);

                % Save
                saveFrame = camera.recordingPeriod <= 0 || isempty(camera.lastRecordingTime) || ...
                    seconds(timeStamp - camera.lastRecordingTime) >= camera.recordingPeriod;
                if saveFrame
                    camera.model.saveCameraFrame(frame, timeStamp);
                    camera.lastRecordingTime = timeStamp;
                end

                % Downsample
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

        % Closing seq
        function closeCam(camera)
            camera.latestFrame = [];
            camera.lastRecordingTime = [];

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

