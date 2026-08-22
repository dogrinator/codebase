classdef TestCommandBuilder
    %TESTCOMMANDBUILDER Converts UI and General Test definitions to PLC commands.

    methods (Static)
        %% Public command construction
        function commands = fromPreset(config, testType, hwConfig)
            if nargin < 3 || isempty(hwConfig)
                error('Control:MissingHardwareConfig', ...
                    ['A hardware configuration is required to convert ' ...
                    'preset tolerance percentages.']);
            end
            axes = TestCommandBuilder.axesForMode(config.system.axisMode);
            commands = struct('X', [], 'Y', []);
            postMode = TestCommandBuilder.postMode(config.post.afterTest);

            for index = 1:numel(axes)
                axis = axes{index};
                field = lower(axis);
                command = TestCommandBuilder.emptyCommand();
                command.postTestMode = postMode;

                switch lower(char(testType))
                    case 'pre'
                        command = TestCommandBuilder.applyPreTest( ...
                            command, config.pre, field, true, ...
                            TestCommandBuilder.percentTolerance( ...
                            config.pre.forceTolerance.(field), ...
                            hwConfig, field));
                        command.preTestOnly = true;
                    case 'single'
                        command = TestCommandBuilder.applyPreTest( ...
                            command, config.pre, field, ...
                            logical(config.single.includePre), ...
                            TestCommandBuilder.percentTolerance( ...
                            config.pre.forceTolerance.(field), ...
                            hwConfig, field));
                        command.testRate = config.single.rate.(field);
                        command.singleForceTolerance = ...
                            TestCommandBuilder.percentTolerance( ...
                            config.single.forceTolerance.(field), ...
                            hwConfig, field);
                        command.singleForceHoldTime = ...
                            config.single.holdTime.(field);
                        command.stop1Mode = TestCommandBuilder.controlMode( ...
                            config.single.primaryMode, false);
                        command.stop1Value = ...
                            config.single.primary.(field);
                        if config.single.rupture.enabled
                            command.stop2Mode = 3;
                            command.stop2Value = config.single.rupture.value;
                        else
                            command.stop2Mode = TestCommandBuilder.controlMode( ...
                                config.single.secondaryMode, true);
                            command.stop2Value = ...
                                config.single.secondary.(field);
                        end
                    case 'cyclic'
                        command = TestCommandBuilder.applyPreTest( ...
                            command, config.pre, field, ...
                            logical(config.cyclic.includePre), ...
                            TestCommandBuilder.percentTolerance( ...
                            config.pre.forceTolerance.(field), ...
                            hwConfig, field));
                        command.testRate = config.cyclic.rate.(field);
                        command.cyclicForceTolerance = ...
                            TestCommandBuilder.percentTolerance( ...
                            config.cyclic.forceTolerance.(field), ...
                            hwConfig, field);
                        command.cyclicForceHoldTime = ...
                            config.cyclic.holdTime.(field);
                        command.cycleCount = config.cyclic.cycles;
                        command.loadMode = TestCommandBuilder.controlMode( ...
                            config.cyclic.loadMode, false);
                        command.unloadMode = TestCommandBuilder.controlMode( ...
                            config.cyclic.unloadMode, false);
                        command.loadValues = repmat( ...
                            config.cyclic.load.(field), ...
                            1, command.cycleCount);
                        command.unloadValues = repmat( ...
                            config.cyclic.unload.(field), ...
                            1, command.cycleCount);
                    otherwise
                        error('Control:InvalidTestType', ...
                            'Unsupported test type: %s.', testType);
                end
                commands.(axis) = command;
            end
        end

        function commands = fromGeneral(definition)
            GeneralTestDefinition.validate(definition);
            axes = TestCommandBuilder.axesForMode(definition.axisMode);
            commands = struct('X', [], 'Y', []);

            for index = 1:numel(axes)
                axis = axes{index};
                field = lower(axis);
                command = TestCommandBuilder.emptyCommand();
                preTolerance = command.preTestForceTolerance;
                if definition.preTest.enabled
                    preTolerance = TestCommandBuilder.preTestTolerance( ...
                        definition.preTest, field);
                end
                command = TestCommandBuilder.applyPreTest(command, ...
                    definition.preTest, field, ...
                    definition.preTest.enabled, ...
                    preTolerance);
                command.postTestMode = ...
                    TestCommandBuilder.generalPostMode(definition.postTest);

                if strcmpi(definition.testType, 'single')
                    value = definition.single;
                    command.testRate = value.rate.(field);
                    command.singleForceTolerance = ...
                        value.forceTolerance.(field);
                    command.singleForceHoldTime = value.holdTime.(field);
                    command.stop1Mode = TestCommandBuilder.controlMode( ...
                        value.primaryMode, false);
                    command.stop1Value = value.primaryValue.(field);
                    command.stop2Mode = TestCommandBuilder.controlMode( ...
                        value.secondaryMode, true);
                    command.stop2Value = value.secondaryValue.(field);
                else
                    value = definition.cyclic;
                    command.testRate = value.rate.(field);
                    command.cyclicForceTolerance = ...
                        value.forceTolerance.(field);
                    command.cyclicForceHoldTime = value.holdTime.(field);
                    command.cycleCount = numel(value.loadValues.(field));
                    command.loadMode = TestCommandBuilder.controlMode( ...
                        value.loadMode, false);
                    command.unloadMode = TestCommandBuilder.controlMode( ...
                        value.unloadMode, false);
                    command.loadValues = ...
                        double(value.loadValues.(field)(:))';
                    command.unloadValues = ...
                        double(value.unloadValues.(field)(:))';
                end
                commands.(axis) = command;
            end
        end

        function axes = axesForMode(mode)
            switch lower(strtrim(char(mode)))
                case {'x only', 'x'}
                    axes = {'X'};
                case {'y only', 'y'}
                    axes = {'Y'};
                case 'both'
                    axes = {'X', 'Y'};
                otherwise
                    error('Control:InvalidAxisMode', ...
                        'Unsupported axis mode: %s.', char(mode));
            end
        end
    end

    methods (Static, Access = private)
        %% Command mapping helpers
        function command = applyPreTest( ...
                command, pre, field, enabled, tolerance)
            command.includePreTest = logical(enabled);
            if ~enabled
                return;
            end
            cycles = pre.cycles;
            if ~pre.cyclic
                cycles = 0;
            end
            command.preCycleCount = cycles;
            command.preloadEnabled = logical(pre.preload.enabled);
            command.preloadValue = pre.preload.value.(field);
            command.preCycleLoadValue = pre.load.(field);
            command.preUnloadValue = pre.unload.(field);
            command.preUnloadToStart = logical(pre.unloadToStart);
            command.preTestRate = pre.rate.(field);
            command.preTestForceTolerance = tolerance;
            command.preloadHoldTime = pre.preload.holdTime.(field);
            command.preCycleHoldTime = pre.holdTime.(field);
        end

        function command = emptyCommand()
            command = struct( ...
                'includePreTest', false, 'preTestOnly', false, ...
                'preCycleCount', 1, 'preloadEnabled', false, ...
                'preloadValue', 0, 'preCycleLoadValue', 0, ...
                'preUnloadValue', 0, 'preUnloadToStart', false, ...
                'preTestRate', 1, 'preTestForceTolerance', 0.1, ...
                'preloadHoldTime', 0, 'preCycleHoldTime', 0, ...
                'testRate', 1, ...
                'singleForceTolerance', 0.1, ...
                'singleForceHoldTime', 0, ...
                'cyclicForceTolerance', 0.1, ...
                'cyclicForceHoldTime', 0, ...
                'cycleCount', 0, 'loadMode', 1, 'loadValues', [], ...
                'unloadMode', 1, 'unloadValues', [], ...
                'stop1Mode', 1, 'stop1Value', 0, ...
                'stop2Mode', 0, 'stop2Value', 0, ...
                'postTestMode', 0);
        end

        function tolerance = preTestTolerance(pre, field)
            preloadEnabled = logical(pre.preload.enabled);
            cyclicEnabled = logical(pre.cyclic);
            preloadTolerance = pre.preload.forceTolerance.(field);
            cyclicTolerance = pre.cyclicForceTolerance.(field);
            if preloadEnabled && cyclicEnabled && ...
                    ~isequal(preloadTolerance, cyclicTolerance)
                error('Control:PreTestToleranceMismatch', ...
                    ['%s-axis preload tolerance (%g N) must equal the ' ...
                    'pre-cycle tolerance (%g N) when both phases run.'], ...
                    upper(field), preloadTolerance, cyclicTolerance);
            end
            if preloadEnabled
                tolerance = preloadTolerance;
            else
                tolerance = cyclicTolerance;
            end
        end

        function tolerance = percentTolerance(percent, ~, field)
            percent = double(percent);
            if ~isscalar(percent) || ~isfinite(percent) || ...
                    percent < 0 || percent > 100
                error('Control:InvalidTolerancePercent', ...
                    'Tolerance must be from 0 to 100%% for the %s axis.', ...
                    upper(field));
            end
            % Negative command tolerances identify UI percentages to the PLC.
            % Positive values remain absolute newtons for General Test JSON.
            tolerance = -max(percent, eps);
        end

        function mode = controlMode(value, allowNone)
            value = lower(strtrim(char(value)));
            if strcmp(value, 'displacement')
                mode = 1;
            elseif strcmp(value, 'force')
                mode = 2;
            elseif allowNone && strcmp(value, 'none')
                mode = 0;
            else
                error('Control:InvalidMode', ...
                    'Unsupported control mode: %s.', value);
            end
        end

        function mode = postMode(value)
            switch char(value)
                case 'Return to saved position'
                    mode = 1;
                case 'Return to start position'
                    mode = 2;
                case 'Return to pre-test final position'
                    mode = 3;
                case {'Unload to zero force', 'Unload (force)'}
                    mode = 4;
                otherwise
                    mode = 0;
            end
        end

        function mode = generalPostMode(value)
            switch lower(char(value))
                case 'saved'
                    mode = 1;
                case 'sequence_start'
                    mode = 2;
                case 'pretest_final'
                    mode = 3;
                case 'zero_force'
                    mode = 4;
                otherwise
                    mode = 0;
            end
        end
    end
end
