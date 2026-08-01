function tests = testGeneralTestDefinition
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
root = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(root));
testCase.TestData.example = fullfile(root, 'examples', ...
    'general_test_example.json');
end

function testValidMixedModeDefinition(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
verifyEqual(testCase, definition.schemaVersion, 1);
verifyTrue(testCase, isfield(definition, 'sourceFile'));
verifyEqual(testCase, definition.cyclic.forceTolerance.x, 0.1);
verifyEqual(testCase, lower(definition.cyclic.loadMode), 'force');
verifyEqual(testCase, lower(definition.cyclic.unloadMode), 'displacement');
verifyNotEmpty(testCase, GeneralTestDefinition.summary(definition));
end

function testSchemaVersionAndMalformedCounts(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.schemaVersion = 2;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:SchemaVersion');

definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.cyclic.loadValues.x = zeros(1, 51);
definition.cyclic.unloadValues.x = zeros(1, 51);
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:InvalidCycles');
end

function testNewToleranceAndHoldFieldsAreRequiredAndNonnegative(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.cyclic = rmfield(definition.cyclic, 'forceTolerance');
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:MissingField');

definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.preTest.preload.holdTime.x = -0.01;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:InvalidNonnegativeValue');

definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.preTest.cyclicForceTolerance.y = NaN;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:InvalidNumber');
end

function testPreTestToleranceEqualityUsesOnlyActiveAxes(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.preTest.preload.forceTolerance.x = 0.2;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:PreTestToleranceMismatch');

definition.axisMode = 'y';
verifyWarningFree(testCase, ...
    @() GeneralTestDefinition.validate(definition));
end

function testGeneralCommandMappingPreservesAxesAndDisplacementHolds(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.cyclic.loadMode = 'displacement';
definition.cyclic.unloadMode = 'displacement';
definition.cyclic.holdTime = struct('x', 0.31, 'y', 0.42);
definition.cyclic.forceTolerance = struct('x', 0.13, 'y', 0.24);
commands = TestCommandBuilder.fromGeneral(definition);
verifyEqual(testCase, commands.X.cyclicForceHoldTime, 0.31);
verifyEqual(testCase, commands.Y.cyclicForceHoldTime, 0.42);
verifyEqual(testCase, commands.X.cyclicForceTolerance, 0.13);
verifyEqual(testCase, commands.Y.cyclicForceTolerance, 0.24);
verifyEqual(testCase, commands.X.preloadHoldTime, 0.2);
verifyEqual(testCase, commands.X.preCycleHoldTime, 0.2);
end

function testFiftyCycleBoundaryAndPreTestLimit(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.cyclic.loadValues.x = zeros(1, 50);
definition.cyclic.unloadValues.x = zeros(1, 50);
definition.cyclic.loadValues.y = zeros(1, 50);
definition.cyclic.unloadValues.y = zeros(1, 50);
definition.preTest.cycles = 50;
verifyWarningFree(testCase, ...
    @() GeneralTestDefinition.validate(definition));

definition.preTest.cycles = 51;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:InvalidCount');

definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.axisMode = 'x';
definition.cyclic.loadValues.y = zeros(1, 51);
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:InvalidCycles');
end

function testRemovedForceDropFieldsAreRejected(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.cyclic.forceDropPercent = 10;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:UnsupportedField');

definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.testType = 'single';
definition.single = struct( ...
    'primaryMode', 'force', ...
    'primaryValue', struct('x', 5, 'y', 5), ...
    'secondaryMode', 'none', ...
    'secondaryValue', struct('x', 0, 'y', 0), ...
    'rate', struct('x', 1, 'y', 1), ...
    'forceTolerance', struct('x', 0.1, 'y', 0.1), ...
    'holdTime', struct('x', 0, 'y', 0), ...
    'forceDropThreshold', struct('x', 1, 'y', 1));
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:UnsupportedField');

definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.cyclic.forceHoldTime = struct('x', 0, 'y', 0);
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:UnsupportedField');
end

function testNaNRateAndCameraSettings(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.preTest.rate.x = NaN;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:InvalidNumber');

definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.camera.samplingPeriod = 0;
verifyWarningFree(testCase, ...
    @() GeneralTestDefinition.validate(definition));

definition.camera.samplingPeriod = -0.01;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:InvalidNumber');

definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.camera.includePrePost = 1;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:InvalidBoolean');

definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.camera.period = 0.1;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:UnsupportedField');
end

function testRatesMustBePositiveAndAreNotRounded(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.preTest.rate.x = -1;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:InvalidRate');

definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.cyclic.rate.y = 0;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:InvalidRate');
end

function testUnknownAndInactiveFieldsAreRejected(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.camera.typoSamplingPeriod = 0.1;
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:UnsupportedField');

definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.single = struct();
verifyError(testCase, @() GeneralTestDefinition.validate(definition), ...
    'GeneralTest:UnsupportedField');
end

function testSummaryDescribesSelectedPreTestPhases(testCase)
definition = GeneralTestDefinition.load(testCase.TestData.example);
definition.preTest.enabled = true;
definition.preTest.cyclic = false;
definition.preTest.preload.enabled = true;
summary = GeneralTestDefinition.summary(definition);
verifySubstring(testCase, summary, 'pre-test preload');
verifyFalse(testCase, contains(summary, ...
    'pre-test preload +'));

definition.preTest.cyclic = true;
summary = GeneralTestDefinition.summary(definition);
verifySubstring(testCase, summary, 'preload + 2 cycle(s)');
end
