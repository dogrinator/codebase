classdef FakeCameraHardware < handle
    properties
        VideoResolution = [2, 2]
        FlushCount = 0
        FailFlush = false
        FailStop = false
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
            if camera.FailStop
                error('FakeCamera:StopFailed', ...
                    'Injected camera stop failure.');
            end
        end
    end
end
