classdef Settings < handle
    %SETTINGS Loads, saves, validates, and applies operator configuration.
    properties
        plc    Plc 
        camera Camera

        hwPath
        appPath

        hwConfig  = [];
        appConfig = [];
    end

    methods
        function settings = Settings(plc, camera)
            settings.plc = plc;
            settings.camera = camera;
            applicationRoot = fileparts(fileparts(mfilename('fullpath')));
            settings.hwPath = fullfile(applicationRoot, '.config', 'hwConfig');
            settings.appPath = fullfile(applicationRoot, '.config', 'appConfig');
        end

        %% Hardware configuration
        function configList = listHwConfigs(settings)
            configList = Settings.listJsonFiles(settings.hwPath);
        end

        function loadHwConfig(settings, filename)
            config = Settings.readJson(settings.hwPath, filename);
            Settings.validateHardwareConfig(config);
            settings.hwConfig = config;
        end

        function saveHwConfig(settings, filename)
            Settings.validateHardwareConfig(settings.hwConfig);
            Settings.writeJson( ...
                settings.hwPath, filename, settings.hwConfig);
        end

        function applyCameraConfig(settings)
            if ~isempty(settings.camera.cameraSrc) && ...
                    isvalid(settings.camera.cameraSrc) && ...
                    ~isempty(settings.hwConfig)
                if isfield(settings.hwConfig.camera, 'gainRaw') && ...
                        ~isprop(settings.camera.cameraSrc, 'GainRaw')
                    error('Camera:UnsupportedGainSetting', ...
                        ['This camera does not expose GainRaw. Remove ' ...
                        'gainRaw from the hardware configuration.']);
                end
                settings.camera.cameraSrc.ExposureTimeAbs = settings.hwConfig.camera.exposureTimeAbs;
                if isfield(settings.hwConfig.camera, 'gainRaw')
                    settings.camera.cameraSrc.GainRaw = ...
                        settings.hwConfig.camera.gainRaw;
                end
                settings.camera.cameraSrc.AcquisitionFrameRateAbs = settings.hwConfig.camera.acquisitionFrameRateAbs;
                settings.camera.cameraSrc.AcquisitionFrameRateEnable = 'True';
                disp('Camera settings applied.');
            else
                disp('Camera disconnected or configuration not loaded.');
            end
        end

        function applyPlcConfig(settings)
            if settings.plc.connected && ~isempty(settings.hwConfig)
                statuses = settings.plc.pollStatus();
                if statuses.X.working || statuses.Y.working
                    error('PLC:AxisUnavailable', ...
                        'Hardware settings can only be applied while both axes are idle.');
                end
                PlcCommandValidator.axisConfig( ...
                    settings.hwConfig.plc.xAxis);
                PlcCommandValidator.axisConfig( ...
                    settings.hwConfig.plc.yAxis);
                settings.plc.writeAxisConfig(settings.hwConfig.plc.xAxis, 'X')
                settings.plc.writeAxisConfig(settings.hwConfig.plc.yAxis, "Y")
                disp('PLC settings applied.');
            else
                disp('PLC disconnected or configuration not loaded.');
            end
        end

        %% Test presets
        function configList = listAppConfigs(settings)
            configList = Settings.listJsonFiles(settings.appPath);
        end

        function loadAppConfig(settings, filename)
            settings.appConfig = ...
                Settings.readJson(settings.appPath, filename);
        end

        function saveAppConfig(settings, filename)
            Settings.writeJson( ...
                settings.appPath, filename, settings.appConfig);
        end
    end

    methods (Static, Access = private)
        function names = listJsonFiles(folder)
            files = dir(fullfile(folder, '*.json'));
            names = erase({files.name}, '.json');
        end

        function value = readJson(folder, name)
            filename = fullfile(folder, char(string(name) + ".json"));
            try
                value = jsondecode(fileread(filename));
            catch exception
                error('Settings:InvalidJson', ...
                    'Cannot read %s: %s', filename, exception.message);
            end
        end

        function writeJson(folder, name, value)
            filename = fullfile(folder, char(string(name) + ".json"));
            fid = fopen(filename, 'w');
            if fid == -1
                error('Settings:WriteFailed', ...
                    'Could not open %s for writing.', filename);
            end
            cleanup = onCleanup(@() fclose(fid));
            written = fprintf(fid, '%s', ...
                jsonencode(value, PrettyPrint=true));
            if written < 0
                error('Settings:WriteFailed', ...
                    'Could not write %s.', filename);
            end
        end

        function validateHardwareConfig(config)
            PlcCommandValidator.requireExactFields( ...
                config, {'plc', 'camera'}, 'hardware configuration');
            PlcCommandValidator.requireExactFields( ...
                config.plc, {'xAxis', 'yAxis'}, ...
                'hardware configuration.plc');
            PlcCommandValidator.axisConfig(config.plc.xAxis);
            PlcCommandValidator.axisConfig(config.plc.yAxis);
            PlcCommandValidator.requireExactFields(config.camera, ...
                {'exposureTimeAbs', 'gainRaw', ...
                    'acquisitionFrameRateAbs'}, ...
                'hardware configuration.camera');
            cameraValues = [config.camera.exposureTimeAbs, ...
                config.camera.gainRaw, ...
                config.camera.acquisitionFrameRateAbs];
            if any(~isfinite(cameraValues)) || ...
                    config.camera.exposureTimeAbs <= 0 || ...
                    config.camera.gainRaw < 0 || ...
                    config.camera.acquisitionFrameRateAbs <= 0
                error('Settings:InvalidHardwareConfig', ...
                    ['Camera exposure and frame rate must be positive; ' ...
                    'gainRaw must be non-negative.']);
            end
        end
    end
end
