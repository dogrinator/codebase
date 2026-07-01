classdef Settings < handle

    properties
        % load mandatory structs for settings send/recive
        plc
        camera

        % help variables
        hwPath  = '.config/hwConfig'  % relative path to hardware config folder
        appPath = '.config/appConfig' % relative path to tests configs

        hwConfig  = []; % loaded hw config
        appConfig = []; % loaded test config
    end

    methods
        function settings = Settings(plc, camera)
            settings.plc = plc;
            settings.camera = camera;
        end

        %% PLC settings
        function configList = listHwConfigs(settings)
            % list all avalibe configs
            pattern = fullfile(settings.hwPath, "*.json");
            files = dir(pattern);
            configList = {files.name};
        end

        function loadHwConfig(settings, filename)
            fullFilename = fullfile( settings.hwPath, filename);
            txt = fileread(fullFilename);
            settings.hwConfig = jsondecode(txt);
        end

        function saveHwConfig(settings, filename)
            fullFilename = fullfile( settings.hwPath, filename);
            jsonTxt = jsonencode(settings.hwConfig);

            fid = fopen(fullFilename, 'w');
            
            if fid == -1
                error('Could not open file: %s', fullFilename);
            end

            fprintf(fid, '%s', jsonTxt);
            fclose(fid);
        end

        function applyCameraConfig(settings)
           % Settings Updates
            if ~isempty(settings.camera.cameraSrc) && isvalid(settings.camera.cameraSrc) && ~isempty(settings.hwConfig)
                settings.camera.cameraSrc.ExposureTimeAbs = settings.hwConfig.camera.exposureTimeAbs;
                settings.camera.cameraSrc.GainRaw = settings.hwConfig.camera.gainRaw;
                settings.camera.cameraSrc.AcquisitionFrameRateAbs = settings.hwConfig.camera.acquisitionFrameRateAbs;
                disp('Camera settings aplied');
            else
                disp('Camera disconnected or config not loaded');
            end
        end

        function applyPlcConfig(settings)
            settings.plc.writeAxisConfig(settings.hwConfig.plc.xAxis, 'X')
            settings.plc.writeAxisConfig(settings.hwConfig.plc.yAxis, "Y")
        end

        %% App settings
        function configList = listAppConfigs(settings)
            pattern = fullfile(settings.appPath, "*.json");

            files = dir(pattern);
        
            configList = {files.name};
        end

        function loadAppConfig(settings, filename)
            fullFilename = fullfile( settings.appPath, filename);
            txt = fileread(fullFilename);
            settings.appConfig = jsondecode(txt);
        end

        function saveAppConfig(settings, filename)
            fullFilename = fullfile(settings.appPath, filename);
        
            jsonTxt = jsonencode(settings.appConfig);

            fid = fopen(fullFilename, 'w');

            if fid == -1
                error('Could not open file: %s', fullFilename);
            end

            fprintf(fid, '%s', jsonTxt);
            fclose(fid);
        end

    end
end