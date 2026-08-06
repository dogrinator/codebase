classdef AppInfo
    %APPINFO Central application identity and acquisition timing.

    properties (Constant)
        VERSION = '0.1.0'
        PLC_SAMPLE_PERIOD_SECONDS = 0.01
        PLC_READ_PERIOD_SECONDS = 0.25
        RECORDING_WARMUP_SECONDS = 0.5
    end
end
