classdef Settings < handle

    %SETTINGS Application component.
    properties
        % load mandatory structs for settings send/recive
        plc    Plc 
        camera Camera

        % help variables
        hwPath
        appPath

        hwConfig  = []; % loaded hw config
        appConfig = []; % loaded test config
    end

    methods
        % Settings handles this operation.
        function settings = Settings(plc, camera)
            settings.plc = plc;
            settings.camera = camera;
            applicationRoot = fileparts(fileparts(mfilename('fullpath')));
            settings.hwPath = fullfile(applicationRoot, '.config', 'hwConfig');
            settings.appPath = fullfile(applicationRoot, '.config', 'appConfig');
        end

        %% PLC settings
        function configList = listHwConfigs(settings)
            % list all avalibe configs
            pattern = fullfile(settings.hwPath, "*.json");
            files = dir(pattern);
            configList = erase({files.name}, ".json");
        end

        % loadHwConfig handles this operation.
        function loadHwConfig(settings, filename)
            filename = filename + ".json";
            fullFilename = fullfile( settings.hwPath, filename);
            txt = fileread(fullFilename);
            settings.hwConfig = jsondecode(txt);
            settings.normalizeHwConfig();
        end

        % saveHwConfig handles this operation.
        function saveHwConfig(settings, filename)
            filename = filename + ".json";
            fullFilename = fullfile( settings.hwPath, filename);
            jsonTxt = jsonencode(settings.hwConfig, PrettyPrint=true);
            fid = fopen(fullFilename, 'w');
            
            if fid == -1
                error('Could not open file: %s', fullFilename);
            end

            fprintf(fid, '%s', jsonTxt);
            fclose(fid);
        end

        % applyCameraConfig handles this operation.
        function applyCameraConfig(settings)
           % Settings Updates
            if ~isempty(settings.camera.cameraSrc) && isvalid(settings.camera.cameraSrc) && ~isempty(settings.hwConfig)
                settings.camera.cameraSrc.ExposureTimeAbs = settings.hwConfig.camera.exposureTimeAbs;
                % settings.camera.cameraSrc.GainRaw = settings.hwConfig.camera.gainRaw;
                settings.camera.cameraSrc.AcquisitionFrameRateAbs = settings.hwConfig.camera.acquisitionFrameRateAbs;
                settings.camera.cameraSrc.AcquisitionFrameRateEnable = 'True';
                disp('Camera settings aplied');
            else
                disp('Camera disconnected or config not loaded');
            end
        end

        % applyPlcConfig handles this operation.
        function applyPlcConfig(settings)
            if settings.plc.connected && ~isempty(settings.hwConfig)
                settings.plc.writeAxisConfig(settings.hwConfig.plc.xAxis, 'X')
                settings.plc.writeAxisConfig(settings.hwConfig.plc.yAxis, "Y")
                disp('Plc settings aplied');
            else
                disp('Plc disconnected or config not loaded');
            end
        end

        function normalizeHwConfig(settings)
            if isempty(settings.hwConfig) || ~isfield(settings.hwConfig, 'plc')
                return;
            end
            for axisName = {'xAxis', 'yAxis'}
                name = axisName{1};
                if ~isfield(settings.hwConfig.plc, name)
                    continue;
                end
                axisCfg = settings.hwConfig.plc.(name);
                if ~isfield(axisCfg, 'fTenzoOffset')
                    axisCfg.fTenzoOffset = 0;
                end
                if ~isfield(axisCfg, 'fForceReliefDistance')
                    axisCfg.fForceReliefDistance = 1.0;
                end
                if ~isfield(axisCfg, 'fForceReliefVelocity')
                    axisCfg.fForceReliefVelocity = 1.0;
                end
                if isfield(axisCfg, 'fMaxPosition')
                    axisCfg = rmfield(axisCfg, 'fMaxPosition');
                end
                settings.hwConfig.plc.(name) = axisCfg;
            end
        end

        %% App settings
        function configList = listAppConfigs(settings)
            pattern = fullfile(settings.appPath, "*.json");
            files = dir(pattern);
            configList = erase({files.name}, ".json");
        end

        % loadAppConfig handles this operation.
        function loadAppConfig(settings, filename)
            filename = filename + ".json";
            fullFilename = fullfile( settings.appPath, filename);
            txt = fileread(fullFilename);
            settings.appConfig = jsondecode(txt);
        end

        % saveAppConfig handles this operation.
        function saveAppConfig(settings, filename)
            filename = filename + ".json";
            fullFilename = fullfile(settings.appPath, filename);
            jsonTxt = jsonencode(settings.appConfig, PrettyPrint=true);
            fid = fopen(fullFilename, 'w');

            if fid == -1
                error('Could not open file: %s', fullFilename);
            end

            fprintf(fid, '%s', jsonTxt);
            fclose(fid);
        end

    end
end
