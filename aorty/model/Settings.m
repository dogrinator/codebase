classdef Settings < handle
    %SETTINGS Loads, saves, validates, and applies operator configuration.
    properties
        plc    Plc 
        camera Camera

        % Configuration directories
        hwPath
        appPath
        appInfoPath

        % Loaded configuration data
        hwConfig  = [];
        appConfig = [];
        activeHwConfigName = ''
        activeAppConfigName = ''
    end

    methods
        function settings = Settings(plc, camera)
            settings.plc = plc;
            settings.camera = camera;
            % Resolve configuration paths independently of the working folder.
            applicationRoot = fileparts(fileparts(mfilename('fullpath')));
            settings.hwPath = fullfile(applicationRoot, '.config', 'hwConfig');
            settings.appPath = fullfile(applicationRoot, '.config', 'appConfig');
            settings.appInfoPath = fullfile(applicationRoot, '.config', ...
                'appInfo.json');
        end

        %% Hardware configuration
        function configList = listHwConfigs(settings)
            configList = Settings.listJsonFiles(settings.hwPath);
        end

        function loadHwConfig(settings, filename)
            config = Settings.readJson(settings.hwPath, filename);
            Settings.validateHardwareConfig(config);
            settings.hwConfig = config;
            settings.activeHwConfigName = char(filename);
        end

        function saveHwConfig(settings, filename)
            Settings.validateHardwareConfig(settings.hwConfig);
            Settings.writeJson(settings.hwPath, filename, settings.hwConfig);
            settings.activeHwConfigName = char(filename);
        end

        function applyCameraConfig(settings)
            if ~isempty(settings.camera.cameraSrc) && ...
                    isvalid(settings.camera.cameraSrc) && ...
                    ~isempty(settings.hwConfig)
                settings.camera.cameraSrc.ExposureTimeAbs = settings.hwConfig.camera.exposureTimeAbs;
                if isfield(settings.hwConfig.camera, 'gainRaw') && ...
                        isprop(settings.camera.cameraSrc, 'GainRaw')
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
                PlcCommandValidator.axisConfig(settings.hwConfig.plc.xAxis);
                PlcCommandValidator.axisConfig(settings.hwConfig.plc.yAxis);
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
            config = Settings.readJson(settings.appPath, filename);
            settings.appConfig = settings.normalizeAppConfig(config);
            settings.activeAppConfigName = char(filename);
        end

        function saveAppConfig(settings, filename)
            Settings.writeJson( ...
                settings.appPath, filename, settings.appConfig);
            settings.activeAppConfigName = char(filename);
        end

        %% Last successfully applied templates
        function names = startupConfigNames(settings)
            names = settings.readAppInfo();
        end

        function root = testRoot(settings)
            names = settings.appInfoOrDefaults();
            root = names.testRoot;
        end

        function rememberHwConfig(settings)
            names = settings.appInfoOrDefaults();
            names.hwConfig = settings.activeHwConfigName;
            settings.writeAppInfo(names);
        end

        function rememberAppConfig(settings)
            names = settings.appInfoOrDefaults();
            names.appConfig = settings.activeAppConfigName;
            settings.writeAppInfo(names);
        end
    end

    methods (Access = private)
        function names = appInfoOrDefaults(settings)
            try
                names = settings.readAppInfo();
            catch
                names = struct( ...
                    'hwConfig', 'default', 'appConfig', 'default', ...
                    'testRoot', '');
            end
        end

        function names = readAppInfo(settings)
            names = struct('hwConfig', 'default', 'appConfig', 'default', ...
                'testRoot', '');
            if ~isfile(settings.appInfoPath)
                return;
            end
            stored = jsondecode(fileread(settings.appInfoPath));
            if isfield(stored, 'hwConfig')
                names.hwConfig = char(stored.hwConfig);
            end
            if isfield(stored, 'appConfig')
                names.appConfig = char(stored.appConfig);
            end
            if isfield(stored, 'testRoot')
                names.testRoot = char(stored.testRoot);
            end
        end

        function writeAppInfo(settings, names)
            [folder, filename] = fileparts(settings.appInfoPath);
            Settings.writeJson(folder, filename, names);
        end

        function config = normalizeAppConfig(settings, config)
            if isfield(config, 'schemaVersion')
                if ~isnumeric(config.schemaVersion) || ...
                        ~isscalar(config.schemaVersion) || ...
                        config.schemaVersion ~= 2
                    error('TestPreset:SchemaVersion', ...
                        'Application preset schemaVersion must be 2.');
                end
                if ~isfield(config.single, 'rupture')
                    config.single.rupture = struct( ...
                        'enabled', false, 'value', 10);
                end
                if strcmp(config.post.afterTest, 'Unload (force)')
                    config.post.afterTest = 'Unload to zero force';
                end
                return;
            end

            if isempty(settings.hwConfig)
                error('TestPreset:MissingHardwareConfig', ...
                    ['Load a hardware configuration before importing an ' ...
                    'unversioned application preset.']);
            end
            if ~isfield(config, 'pre') || ...
                    ~isfield(config.pre, 'cyclicForceTolerance') || ...
                    ~isfield(config.pre, 'preload') || ...
                    ~isfield(config.pre.preload, 'forceTolerance')
                error('TestPreset:LegacyToleranceMissing', ...
                    ['The unversioned preset does not contain both legacy ' ...
                    'pre-test tolerance fields.']);
            end
            cyclicTolerance = config.pre.cyclicForceTolerance;
            preloadTolerance = config.pre.preload.forceTolerance;
            if ~isequaln(cyclicTolerance, preloadTolerance)
                error('TestPreset:LegacyToleranceMismatch', ...
                    ['The legacy preload and pre-cycle tolerances must ' ...
                    'match before the preset can be migrated.']);
            end

            config.pre.forceTolerance = settings.newtonsToPercent( ...
                cyclicTolerance);
            config.pre = rmfield(config.pre, 'cyclicForceTolerance');
            config.pre.preload = rmfield( ...
                config.pre.preload, 'forceTolerance');
            config.single.forceTolerance = settings.newtonsToPercent( ...
                config.single.forceTolerance);
            config.cyclic.forceTolerance = settings.newtonsToPercent( ...
                config.cyclic.forceTolerance);
            config.single.rupture = struct( ...
                'enabled', false, 'value', 10);
            if strcmp(config.post.afterTest, 'Unload (force)')
                config.post.afterTest = 'Unload to zero force';
            end
            config.schemaVersion = 2;
        end

        function percent = newtonsToPercent(settings, tolerance)
            percent = tolerance;
            required = {'x', 'y'};
            if ~isstruct(tolerance) || ~isscalar(tolerance) || ...
                    ~all(isfield(tolerance, required))
                error('TestPreset:InvalidLegacyTolerance', ...
                    'Legacy tolerance must contain numeric x and y values.');
            end
            for item = {'x', 'y'}
                field = item{1};
                axisConfig = settings.hwConfig.plc.([field, 'Axis']);
                maxForce = double(axisConfig.fMaxForce);
                value = double(tolerance.(field));
                if ~isscalar(value) || ~isfinite(value) || value < 0 || ...
                        ~isfinite(maxForce) || maxForce <= 0
                    error('TestPreset:InvalidLegacyTolerance', ...
                        ['Legacy tolerance and configured maximum force ' ...
                        'must be finite and non-negative/positive.']);
                end
                percent.(field) = 100 * value / maxForce;
            end
        end
    end

    %% JSON file handling
    methods (Static, Access = private)
        function names = listJsonFiles(folder)
            files = dir(fullfile(folder, '*.json'));
            names = erase({files.name}, '.json');
        end

        function value = readJson(folder, name)
            filename = Settings.configFilename(folder, name);
            try
                value = jsondecode(fileread(filename));
            catch exception
                error('Settings:InvalidJson', ...
                    'Cannot read %s: %s', filename, exception.message);
            end
        end

        function writeJson(folder, name, value)
            filename = Settings.configFilename(folder, name);
            if ~isfolder(folder)
                error('Settings:WriteFailed', ...
                    'Configuration folder does not exist: %s', folder);
            end
            temporary = tempname(folder);
            temporaryCleanup = onCleanup( ...
                @() Settings.deleteIfPresent(temporary));
            fid = fopen(temporary, 'wb');
            if fid == -1
                error('Settings:WriteFailed', ...
                    'Could not create a temporary configuration file.');
            end
            closeCleanup = onCleanup(@() fclose(fid));
            payload = unicode2native( ...
                jsonencode(value, PrettyPrint=true), 'UTF-8');
            written = fwrite(fid, payload, 'uint8');
            if written ~= numel(payload)
                error('Settings:WriteFailed', ...
                    'Could not write %s.', filename);
            end
            clear closeCleanup;
            [moved, message] = movefile(temporary, filename, 'f');
            if ~moved
                error('Settings:WriteFailed', ...
                    'Could not replace %s: %s', filename, message);
            end
            clear temporaryCleanup;
        end

        function validateHardwareConfig(config)
            PlcCommandValidator.requireExactFields( ...
                config, {'plc', 'camera'}, 'hardware configuration');
            PlcCommandValidator.requireExactFields( ...
                config.plc, {'xAxis', 'yAxis'}, ...
                'hardware configuration.plc');
            PlcCommandValidator.axisConfig(config.plc.xAxis);
            PlcCommandValidator.axisConfig(config.plc.yAxis);
            if ~isstruct(config.camera) || ~isscalar(config.camera)
                error('Settings:InvalidHardwareConfig', ...
                    'hardware configuration.camera must be one object.');
            end
            required = {'exposureTimeAbs', ...
                'acquisitionFrameRateAbs'};
            optional = {'gainRaw'};
            names = fieldnames(config.camera);
            missing = setdiff(required, names, 'stable');
            unknown = setdiff(names, [required, optional], 'stable');
            if ~isempty(missing)
                error('Settings:InvalidHardwareConfig', ...
                    'Camera configuration is missing %s.', missing{1});
            end
            if ~isempty(unknown)
                error('Settings:InvalidHardwareConfig', ...
                    'Camera configuration contains unsupported field %s.', ...
                    unknown{1});
            end
            exposure = config.camera.exposureTimeAbs;
            frameRate = config.camera.acquisitionFrameRateAbs;
            if ~isnumeric(exposure) || ~isscalar(exposure) || ...
                    ~isfinite(exposure) || exposure <= 0 || ...
                    ~isnumeric(frameRate) || ~isscalar(frameRate) || ...
                    ~isfinite(frameRate) || frameRate <= 0
                error('Settings:InvalidHardwareConfig', ...
                    'Camera exposure and frame rate must be positive.');
            end
            if isfield(config.camera, 'gainRaw') && ...
                    (~isnumeric(config.camera.gainRaw) || ...
                    ~isscalar(config.camera.gainRaw) || ...
                    ~isfinite(config.camera.gainRaw) || ...
                    config.camera.gainRaw < 0)
                error('Settings:InvalidHardwareConfig', ...
                    'gainRaw must be a finite non-negative number.');
            end
        end

        function filename = configFilename(folder, name)
            if ~(ischar(name) || (isstring(name) && isscalar(name)))
                error('Settings:InvalidName', ...
                    'Configuration name must be one filename.');
            end
            name = char(name);
            if isempty(name) || ismember(name, {'.', '..'}) || ...
                    isempty(regexp(name, ...
                    '^[A-Za-z0-9][A-Za-z0-9 _.-]*$', 'once'))
                error('Settings:InvalidName', ...
                    ['Configuration name may contain letters, numbers, ' ...
                    'spaces, periods, underscores, and hyphens only.']);
            end
            filename = fullfile(folder, [name, '.json']);
        end

        function deleteIfPresent(filename)
            if isfile(filename)
                delete(filename);
            end
        end
    end
end
