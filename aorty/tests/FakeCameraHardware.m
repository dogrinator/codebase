classdef FakeCameraHardware < handle
    properties
        VideoResolution = [2, 2]
        FlushCount = 0
        FailFlush = false
        FailStop = false
        FailDelete = false
        Probe = []
    end

    methods
        function flushdata(camera)
            if camera.FailFlush
                error('FakeCamera:FlushFailed', ...
                    'Injected camera flush failure.');
            end
            camera.FlushCount = camera.FlushCount + 1;
        end

        function stop(camera)
            if ~isempty(camera.Probe)
                camera.Probe.StopAttempted = true;
            end
            if camera.FailStop
                error('FakeCamera:StopFailed', ...
                    'Injected camera stop failure.');
            end
        end

        function delete(camera)
            if ~isempty(camera.Probe)
                camera.Probe.DeleteAttempted = true;
            end
            if camera.FailDelete
                error('FakeCamera:DeleteFailed', ...
                    'Injected camera delete failure.');
            end
        end
    end
end
