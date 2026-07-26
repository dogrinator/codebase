classdef GeneralTestDefinition
    % Loads and validates the complete, versioned General Test JSON format.

    methods (Static)
        function definition = load(filename)
            if ~(ischar(filename) || (isstring(filename) && isscalar(filename)))
                error('GeneralTest:InvalidFile', 'Select one General Test JSON file.');
            end
            filename = char(filename);
            if ~isfile(filename)
                error('GeneralTest:InvalidFile', 'General Test file does not exist: %s', filename);
            end
            try
                definition = jsondecode(fileread(filename));
            catch exception
                error('GeneralTest:InvalidJson', 'The General Test JSON cannot be read: %s', ...
                    exception.message);
            end
            GeneralTestDefinition.validate(definition);
            definition.sourceFile = filename;
        end

        function validate(definition)
            GeneralTestDefinition.requireFields(definition, ...
                {'schemaVersion', 'axisMode', 'testType', 'preTest', ...
                'postTest', 'camera'}, 'root');
            if ~isscalar(definition.schemaVersion) || definition.schemaVersion ~= 1
                error('GeneralTest:SchemaVersion', ...
                    'schemaVersion must be 1.');
            end
            axisMode = GeneralTestDefinition.textChoice(definition.axisMode, ...
                {'x', 'y', 'both'}, 'axisMode');
            testType = GeneralTestDefinition.textChoice(definition.testType, ...
                {'single', 'cyclic'}, 'testType');

            GeneralTestDefinition.validatePreTest(definition.preTest);
            if ~isfield(definition, testType)
                error('GeneralTest:MissingField', ...
                    'The selected testType requires a "%s" object.', testType);
            end
            if strcmp(testType, 'single')
                GeneralTestDefinition.validateSingle(definition.single);
            else
                GeneralTestDefinition.validateCyclic(definition.cyclic, axisMode);
            end

            GeneralTestDefinition.textChoice(definition.postTest, ...
                {'stay', 'saved', 'sequence_start', 'pretest_final', ...
                'zero_force'}, 'postTest');
            GeneralTestDefinition.requireFields(definition.camera, ...
                {'enabled', 'period'}, 'camera');
            GeneralTestDefinition.booleanValue(definition.camera.enabled, ...
                'camera.enabled');
            GeneralTestDefinition.nonnegativeScalar(definition.camera.period, ...
                'camera.period');
            if definition.camera.enabled && definition.camera.period <= 0
                error('GeneralTest:InvalidCamera', ...
                    'camera.period must be positive when the camera is enabled.');
            end
        end

        function text = summary(definition)
            axisMode = upper(char(definition.axisMode));
            testType = char(definition.testType);
            if strcmpi(testType, 'cyclic')
                cycleCount = GeneralTestDefinition.cycleCount( ...
                    definition.cyclic, lower(char(definition.axisMode)));
                detail = sprintf('%d variable cycle(s)', cycleCount);
            else
                detail = sprintf('%s endpoint', ...
                    char(definition.single.primaryMode));
            end
            if definition.preTest.enabled
                pre = sprintf('pre-test %d cycle(s)', definition.preTest.cycles);
            else
                pre = 'no pre-test';
            end
            text = sprintf('Schema 1 | %s axis | %s (%s) | %s | post: %s', ...
                axisMode, testType, detail, pre, char(definition.postTest));
        end
    end

    methods (Static, Access = private)
        function validatePreTest(value)
            GeneralTestDefinition.requireFields(value, ...
                {'enabled', 'cyclic', 'cycles', 'rate', 'holdTime', ...
                'preload', 'load', 'unload', 'unloadToStart'}, 'preTest');
            GeneralTestDefinition.booleanValue(value.enabled, 'preTest.enabled');
            GeneralTestDefinition.booleanValue(value.cyclic, 'preTest.cyclic');
            GeneralTestDefinition.booleanValue(value.unloadToStart, ...
                'preTest.unloadToStart');
            GeneralTestDefinition.integerRange(value.cycles, 1, 100, ...
                'preTest.cycles');
            GeneralTestDefinition.axisScalar(value.rate, 'preTest.rate', true);
            GeneralTestDefinition.axisScalar(value.holdTime, ...
                'preTest.holdTime', false);
            GeneralTestDefinition.axisScalar(value.load, 'preTest.load', false);
            GeneralTestDefinition.axisScalar(value.unload, ...
                'preTest.unload', false);
            GeneralTestDefinition.requireFields(value.preload, ...
                {'enabled', 'value'}, 'preTest.preload');
            GeneralTestDefinition.booleanValue(value.preload.enabled, ...
                'preTest.preload.enabled');
            GeneralTestDefinition.axisScalar(value.preload.value, ...
                'preTest.preload.value', false);
        end

        function validateSingle(value)
            GeneralTestDefinition.requireFields(value, ...
                {'primaryMode', 'primaryValue', 'secondaryMode', ...
                'secondaryValue', 'rate', 'holdTime'}, 'single');
            GeneralTestDefinition.textChoice(value.primaryMode, ...
                {'displacement', 'force'}, 'single.primaryMode');
            GeneralTestDefinition.textChoice(value.secondaryMode, ...
                {'none', 'displacement', 'force'}, 'single.secondaryMode');
            GeneralTestDefinition.axisScalar(value.primaryValue, ...
                'single.primaryValue', false);
            GeneralTestDefinition.axisScalar(value.secondaryValue, ...
                'single.secondaryValue', false);
            GeneralTestDefinition.axisScalar(value.rate, 'single.rate', true);
            GeneralTestDefinition.axisScalar(value.holdTime, ...
                'single.holdTime', false);
            GeneralTestDefinition.validateOptionalForceDrop(value, 'single');
        end

        function validateCyclic(value, axisMode)
            GeneralTestDefinition.requireFields(value, ...
                {'loadMode', 'unloadMode', 'rate', 'holdTime', ...
                'loadValues', 'unloadValues'}, 'cyclic');
            GeneralTestDefinition.textChoice(value.loadMode, ...
                {'displacement', 'force'}, 'cyclic.loadMode');
            GeneralTestDefinition.textChoice(value.unloadMode, ...
                {'displacement', 'force'}, 'cyclic.unloadMode');
            GeneralTestDefinition.axisScalar(value.rate, 'cyclic.rate', true);
            GeneralTestDefinition.axisScalar(value.holdTime, ...
                'cyclic.holdTime', false);
            GeneralTestDefinition.axisArrays(value.loadValues, ...
                'cyclic.loadValues');
            GeneralTestDefinition.axisArrays(value.unloadValues, ...
                'cyclic.unloadValues');
            GeneralTestDefinition.validateOptionalForceDrop(value, 'cyclic');
            active = {'x', 'y'};
            if ~strcmp(axisMode, 'both'), active = {axisMode}; end
            count = [];
            for index = 1:numel(active)
                axis = active{index};
                loadCount = numel(value.loadValues.(axis));
                unloadCount = numel(value.unloadValues.(axis));
                if loadCount < 1 || loadCount > 100 || loadCount ~= unloadCount
                    error('GeneralTest:InvalidCycles', ...
                        ['Active-axis load/unload arrays must have matching ' ...
                        'lengths from 1 to 100.']);
                end
                if isempty(count), count = loadCount; end
                if count ~= loadCount
                    error('GeneralTest:InvalidCycles', ...
                        'X and Y active-axis arrays must have matching lengths.');
                end
            end
        end

        function count = cycleCount(value, axisMode)
            if strcmp(axisMode, 'y')
                count = numel(value.loadValues.y);
            else
                count = numel(value.loadValues.x);
            end
        end

        function axisScalar(value, path, mustBeNonzero)
            GeneralTestDefinition.requireFields(value, {'x', 'y'}, path);
            for axis = {'x', 'y'}
                number = value.(axis{1});
                if ~isnumeric(number) || ~isscalar(number) || ~isfinite(number)
                    error('GeneralTest:InvalidNumber', ...
                        '%s.%s must be a finite number.', path, axis{1});
                end
                if mustBeNonzero && number == 0
                    error('GeneralTest:InvalidRate', ...
                        '%s.%s must be non-zero.', path, axis{1});
                end
                if contains(path, 'holdTime') && number < 0
                    error('GeneralTest:InvalidHold', ...
                        '%s.%s must be non-negative.', path, axis{1});
                end
            end
        end

        function axisArrays(value, path)
            GeneralTestDefinition.requireFields(value, {'x', 'y'}, path);
            for axis = {'x', 'y'}
                numbers = value.(axis{1});
                if ~isnumeric(numbers) || any(~isfinite(numbers(:)))
                    error('GeneralTest:InvalidArray', ...
                        '%s.%s must contain only finite numbers.', path, axis{1});
                end
            end
        end

        function number = nonnegativeScalar(number, path)
            if ~isnumeric(number) || ~isscalar(number) || ...
                    ~isfinite(number) || number < 0
                error('GeneralTest:InvalidNumber', ...
                    '%s must be a finite non-negative number.', path);
            end
        end

        function validateOptionalForceDrop(value, path)
            if isfield(value, 'forceDropPercent')
                percent = value.forceDropPercent;
                if ~isnumeric(percent) || ~isscalar(percent) || ...
                        ~isfinite(percent) || percent < 0 || percent >= 100
                    error('GeneralTest:InvalidForceDrop', ...
                        '%s.forceDropPercent must be from 0 up to, but not including, 100.', ...
                        path);
                end
            end
            if isfield(value, 'forceDropThreshold')
                GeneralTestDefinition.axisScalar(value.forceDropThreshold, ...
                    [path, '.forceDropThreshold'], false);
                if value.forceDropThreshold.x < 0 || ...
                        value.forceDropThreshold.y < 0
                    error('GeneralTest:InvalidForceDrop', ...
                        '%s.forceDropThreshold values must be non-negative.', path);
                end
            end
        end

        function booleanValue(value, path)
            if ~(islogical(value) && isscalar(value))
                error('GeneralTest:InvalidBoolean', '%s must be true or false.', path);
            end
        end

        function integerRange(value, lowerBound, upperBound, path)
            if ~isnumeric(value) || ~isscalar(value) || ~isfinite(value) || ...
                    fix(value) ~= value || value < lowerBound || value > upperBound
                error('GeneralTest:InvalidCount', ...
                    '%s must be an integer from %d to %d.', ...
                    path, lowerBound, upperBound);
            end
        end

        function result = textChoice(value, choices, path)
            if ~(ischar(value) || (isstring(value) && isscalar(value)))
                error('GeneralTest:InvalidChoice', '%s must be text.', path);
            end
            result = lower(char(value));
            if ~ismember(result, choices)
                error('GeneralTest:InvalidChoice', ...
                    '%s must be one of: %s.', path, strjoin(choices, ', '));
            end
        end

        function requireFields(value, fields, path)
            if ~isstruct(value) || ~isscalar(value)
                error('GeneralTest:InvalidObject', '%s must be an object.', path);
            end
            for index = 1:numel(fields)
                if ~isfield(value, fields{index})
                    error('GeneralTest:MissingField', ...
                        '%s is missing "%s".', path, fields{index});
                end
            end
        end
    end
end
