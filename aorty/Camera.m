classdef Camera < handle
    % this class contains main functions to connect / disconnect to/from camera
    % This function also contains reciving frames from camera and settings and setup

    properties
        % mandatory classes
        model                  % model for saving frames

        % camera
        cameraHW
        latestFrame = [];       % Most recent frame for display
        camStartTime            % Start timer for visualization
        connected = false;
    end

    methods
        function camera = Camera(model)
            camera.model = model;
        end

        function connectCamera(camera, app, src)
            if src.Value == "ON"
                try
                    camera.cameraHW = videoinput('gige', 1, 'Mono8');
                    camSource = getselectedsource(camera.cameraHW);

                    % Trigger reset
                    for sel = {'FrameStart','AcquisitionStart','FrameBurstStart'}
                        try
                            camSource.TriggerSelector = sel{1};
                            camSource.TriggerMode = 'Off';
                        catch
                        end
                    end

                    % Network setup
                    if isprop(camSource,'PacketSize'),  camSource.PacketSize  = 8000; end
                    if isprop(camSource,'PacketDelay'), camSource.PacketDelay = 500;  end

                    camera.cameraHW.FramesPerTrigger = 1;   % 1 frame per trigger
                    camera.cameraHW.TriggerRepeat = Inf; % repeat forever
                    triggerconfig(camera.cameraHW, 'immediate');

                    % Save data
                    camera.camStartTime = datetime('now');
                    camera.cameraHW.FramesAcquiredFcnCount = 1;
                    camera.cameraHW.FramesAcquiredFcn = @(s,ev) camera.acquireFrame(s);

                    % Start display timer at fixed 15 Hz, independent of camera FPS.
                    camera.latestFrame = [];
                    camera.connected = true;

                    flushdata(camera.cameraHW);
                    start(camera.cameraHW);
                    disp("Camera connected.");
                catch ME
                    uialert(app.fig, getReport(ME), 'Camera Error');
                    src.Value = "OFF";
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

                [frame, relativeTime] = getdata(src, 1);
                timeStamp = camera.camStartTime + seconds(relativeTime);

                % Save
                camera.model.saveCameraFrame(frame, timeStamp);

                % Downsample
                camera.latestFrame = frame(1:3:end, 1:3:end);

            catch ME
                if contains(ME.message, 'deleted') || contains(ME.message, 'invalid')
                    return;
                end
                fprintf(2, 'acquireFrame error: %s\n', getReport(ME));
            end
        end

        % Settings Updates
        function updateExposure(camera, exposureValue)
            if ~isempty(camera.cameraHW) && isvalid(camera.cameraHW)
                src = getselectedsource(camera.cameraHW);
                src.ExposureTimeAbs = exposureValue;
                disp(['Exposure set to: ', num2str(exposureValue)]);
            end
        end

        function updateGain(camera, gainValue)
            if ~isempty(camera.cameraHW) && isvalid(camera.cameraHW)
                src = getselectedsource(camera.cameraHW);
                src.GainRaw = gainValue;
                disp(['Gain set to: ', num2str(gainValue)]);
            end
        end

        % Closing seq
        function closeCam(camera)
            camera.latestFrame = [];

            if ~isempty(camera.cameraHW) && isvalid(camera.cameraHW)
                stop(camera.cameraHW);
                delete(camera.cameraHW);
                camera.cameraHW = [];
                camera.connected = false;
                disp("Camera disconnected");
            end
        end
    end
end
